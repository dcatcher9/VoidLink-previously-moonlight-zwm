#include "Limelight-internal.h"

// Include the exact production translation unit so its static dispatch shim is
// exercised directly. Only thread creation/delivery and allocation are controlled.
static void* testAllocate(size_t size);
static void testFree(void* allocation);
#define malloc testAllocate
#define free testFree
#include "../moonlight-common/moonlight-common-c/src/Connection.c"
#undef malloc
#undef free

typedef struct {
    ThreadEntry entry;
    void* context;
    bool detached;
    bool pending;
} PENDING_THREAD;
typedef struct {
    int callback;
    int error;
    uint64_t token;
} DELIVERY;

static PENDING_THREAD threads[16];
static DELIVERY deliveries[16];
static void* allocation;
static int allocatedCount, freedCount, threadCount, detachCount, deliveryCount;
static int loggedCount;
static bool failAllocation, failThreadCreation, invokeEntryBeforeCreateReturns;
static int threadCreationDepth;
static uint64_t currentToken;
static int acceptedTerminations;
static void beginSession(ConnListenerConnectionTerminated legacy,
                         ConnListenerConnectionTerminatedWithSession sessionCallback, uint64_t token);

static void require(bool condition, const char* message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static void record(int callback, int error, uint64_t token) {
    require(deliveryCount < 16, "delivery capacity");
    deliveries[deliveryCount++] = (DELIVERY){ callback, error, token };
}
static void legacyA(int error) { record(1, error, 0); }
static void legacyB(int error) { record(2, error, 0); }
static void withSessionA(int error, uint64_t token) { record(3, error, token); }
static void withSessionB(int error, uint64_t token) { record(4, error, token); }
static void matchingSession(int error, uint64_t token) {
    record(5, error, token);
    if (token == currentToken) acceptedTerminations++;
}
static void stopLegacy(int error) {
    require(allocation == NULL, "payload must be freed before legacy callback");
    LiStopConnection();
    record(6, error, 0);
}
static void stopWithSession(int error, uint64_t token) {
    require(allocation == NULL, "payload must be freed before session callback");
    LiStopConnection();
    record(7, error, token);
}
static void stopAndReplaceSession(int error, uint64_t token) {
    require(threadCreationDepth == 1, "entry must run before detached creation returns");
    require(allocation == NULL, "payload must be freed before immediate stop and replacement");
    LiStopConnection();
    record(8, error, token);
    // Model the successor's start snapshots while the predecessor's dispatcher
    // is still on the stack. Its return must not touch successor session state.
    beginSession(legacyB, withSessionB, token + 1);
    invokeEntryBeforeCreateReturns = false;
}
static void testLog(const char* format, ...) {
    (void)format;
    loggedCount++;
}

// The fixture tracks two pending payloads for delayed predecessor/successor
// delivery. All allocations still use real malloc/free (and ASan when enabled).
static void* liveAllocations[16];
static void* testAllocate(size_t size) {
    if (failAllocation) return NULL;
    void* result = malloc(size);
    require(result != NULL && allocatedCount < 16, "fixture allocation");
    liveAllocations[allocatedCount++] = result;
    allocation = result;
    return result;
}
static void testFree(void* value) {
    if (value == NULL) return;
    bool found = false;
    for (int index = 0; index < allocatedCount; index++) {
        if (liveAllocations[index] == value) {
            liveAllocations[index] = NULL;
            found = true;
            break;
        }
    }
    require(found, "payload must be freed exactly once");
    freedCount++;
    if (allocation == value) allocation = NULL;
    free(value);
}
int PltCreateThreadDetached(const char* name, ThreadEntry entry, void* context) {
    require(strcmp(name, "AsyncTerm") == 0 && context != NULL, "termination thread owns a payload");
    if (failThreadCreation) return -12;
    require(threadCount < 16, "thread capacity");
    PENDING_THREAD* pending = &threads[threadCount++];
    *pending = (PENDING_THREAD){ entry, context, true, true };
    detachCount++;
    threadCreationDepth++;
    if (invokeEntryBeforeCreateReturns) {
        pending->pending = false;
        entry(context);
        // Ownership already passed to entry. Do not read or free its context.
    }
    threadCreationDepth--;
    return 0;
}
void PltJoinThread(PLT_THREAD* thread) {
    (void)thread;
    require(false, "termination callback must never be joined during reentrant stop");
}
static void deliver(int index) {
    PENDING_THREAD* pending = &threads[index];
    require(pending->pending && pending->detached, "deliver one detached thread");
    pending->pending = false;
    pending->entry(pending->context);
}

// These stream implementations are unreachable with fixture stage STAGE_NONE;
// the actual public LiStopConnection() body is retained for reentrant-stop tests.
#define STOP_STUB(name) void name(void) { require(false, "unexpected C stream teardown"); }
STOP_STUB(destroyMicrophoneStream)
int stopInputStream(void) { require(false, "unexpected input stream teardown"); return -1; }
STOP_STUB(stopAudioStream)
STOP_STUB(stopVideoStream)
int stopControlStream(void) { require(false, "unexpected control stream teardown"); return -1; }
STOP_STUB(destroyInputStream)
STOP_STUB(destroyVideoStream)
STOP_STUB(destroyControlStream)
STOP_STUB(destroyAudioStream)
STOP_STUB(cleanupPlatform)

static void beginSession(ConnListenerConnectionTerminated legacy,
                         ConnListenerConnectionTerminatedWithSession sessionCallback, uint64_t token) {
    LiInitializeConnectionCallbacks(&ListenerCallbacks);
    ListenerCallbacks.logMessage = testLog;
    ListenerCallbacks.connectionTerminatedWithSession = sessionCallback;
    ListenerCallbacks.connectionSessionId = token;
    originalTerminationCallback = legacy;
    originalTerminationCallbackWithSession = sessionCallback;
    originalTerminationSessionId = token;
    alreadyTerminated = false;
    ConnectionInterrupted = false;
    stage = STAGE_NONE;
    currentToken = token;
}
static void reset(void) {
    require(allocatedCount == freedCount, "all detached payloads must be released");
    require(threadCreationDepth == 0, "all detached creation calls must have returned");
    memset(threads, 0, sizeof(threads));
    memset(deliveries, 0, sizeof(deliveries));
    memset(liveAllocations, 0, sizeof(liveAllocations));
    allocation = NULL;
    allocatedCount = freedCount = threadCount = detachCount = deliveryCount = loggedCount = 0;
    acceptedTerminations = 0;
    failAllocation = failThreadCreation = invokeEntryBeforeCreateReturns = false;
}
static void pass(const char* name) { printf("PASS %s\n", name); reset(); }

int main(void) {
    CONNECTION_LISTENER_CALLBACKS callbacks;
    memset(&callbacks, 0xFF, sizeof(callbacks));
    LiInitializeConnectionCallbacks(&callbacks);
    require(callbacks.connectionTerminated == NULL && callbacks.connectionTerminatedWithSession == NULL &&
            callbacks.connectionSessionId == 0, "initializer defaults to legacy callback behavior");
    pass("callback initializer clears optional session API");

    beginSession(legacyA, withSessionA, UINT64_C(0xFEDCBA9876543210));
    ClInternalConnectionTerminated(-101);
    require(deliveryCount == 0 && detachCount == 1, "delivery must remain asynchronous");
    deliver(0);
    require(deliveryCount == 1 && deliveries[0].callback == 3 && deliveries[0].error == -101 &&
            deliveries[0].token == UINT64_C(0xFEDCBA9876543210), "optional callback replaces legacy with full token");
    pass("session callback replaces legacy and preserves 64-bit token");

    beginSession(legacyA, withSessionA, 12);
    ListenerCallbacks.connectionTerminatedWithSession = withSessionB;
    ListenerCallbacks.connectionSessionId = 99;
    ClInternalConnectionTerminated(-103);
    deliver(0);
    require(deliveries[0].callback == 3 && deliveries[0].token == 12 && deliveries[0].error == -103,
            "dispatcher must use immutable start snapshots, not mutable listener fields");
    pass("start snapshots survive listener callback and session ID mutation");

    beginSession(legacyA, NULL, 0);
    ClInternalConnectionTerminated(-102);
    deliver(0);
    require(deliveryCount == 1 && deliveries[0].callback == 1 && deliveries[0].error == -102,
            "legacy callers must retain error callback behavior");
    pass("legacy callback remains supported");

    beginSession(legacyA, withSessionA, 11);
    ClInternalConnectionTerminated(-111);
    LiStopConnection();
    beginSession(legacyB, withSessionB, 22);
    ClInternalConnectionTerminated(-222);
    deliver(1);
    deliver(0);
    require(deliveries[0].callback == 4 && deliveries[0].error == -222 && deliveries[0].token == 22 &&
            deliveries[1].callback == 3 && deliveries[1].error == -111 && deliveries[1].token == 11,
            "delayed old payload must retain its own callback, error and token");
    pass("delayed predecessor survives successor callback/error overwrite");

    beginSession(legacyA, matchingSession, 31);
    ClInternalConnectionTerminated(-301);
    LiStopConnection();
    beginSession(legacyA, matchingSession, 32);
    deliver(0);
    require(acceptedTerminations == 0 && deliveries[0].token == 31 && !ConnectionInterrupted,
            "same client trampoline can reject an old token without stopping current session");
    ClInternalConnectionTerminated(-302);
    deliver(1);
    require(acceptedTerminations == 1 && deliveries[1].token == 32,
            "current token remains deliverable after rejecting old callback");
    pass("same callback distinguishes predecessor from active successor");

    beginSession(legacyA, NULL, 0);
    ClInternalConnectionTerminated(-401);
    LiStopConnection();
    beginSession(legacyB, NULL, 0);
    ClInternalConnectionTerminated(-402);
    deliver(0);
    deliver(1);
    require(deliveries[0].callback == 1 && deliveries[0].error == -401 &&
            deliveries[1].callback == 2 && deliveries[1].error == -402,
            "legacy callback pointer and error are also per-thread snapshots");
    pass("legacy delayed delivery retains original callback and error");

    beginSession(stopLegacy, NULL, 0);
    ClInternalConnectionTerminated(0);
    deliver(0);
    require(ConnectionInterrupted && deliveries[0].callback == 6, "legacy callback may stop synchronously");
    pass("synchronous stop inside legacy callback");

    beginSession(legacyA, stopWithSession, 51);
    ClInternalConnectionTerminated(0);
    deliver(0);
    require(ConnectionInterrupted && deliveries[0].callback == 7 && deliveries[0].token == 51,
            "session callback may stop synchronously");
    pass("synchronous stop inside session callback");

    beginSession(stopLegacy, NULL, 0);
    invokeEntryBeforeCreateReturns = true;
    ClInternalConnectionTerminated(-501);
    require(ConnectionInterrupted && deliveryCount == 1 && deliveries[0].callback == 6 &&
            allocatedCount == 1 && freedCount == 1 && !threads[0].pending,
            "legacy callback can finish reentrant stop before detached creation returns");
    pass("immediate detached entry supports legacy synchronous stop");

    beginSession(legacyA, stopAndReplaceSession, 52);
    invokeEntryBeforeCreateReturns = true;
    ClInternalConnectionTerminated(-502);
    require(deliveryCount == 1 && deliveries[0].callback == 8 && deliveries[0].error == -502 &&
            deliveries[0].token == 52 && allocatedCount == 1 && freedCount == 1 &&
            currentToken == 53 && !ConnectionInterrupted && !alreadyTerminated,
            "predecessor return must preserve successor state after immediate stop/replacement");
    ClInternalConnectionTerminated(-503);
    deliver(1);
    require(deliveryCount == 2 && deliveries[1].callback == 4 && deliveries[1].error == -503 &&
            deliveries[1].token == 53 && allocatedCount == 2 && freedCount == 2,
            "successor can still schedule and release its own termination payload");
    pass("immediate detached entry stops and replaces session before create returns");

    beginSession(legacyA, withSessionA, 61);
    failAllocation = true;
    ClInternalConnectionTerminated(-601);
    require(threadCount == 0 && detachCount == 0 && allocatedCount == 0 && loggedCount == 1,
            "allocation failure must not create or detach a thread");
    pass("allocation failure has no thread or payload leak");

    beginSession(legacyA, withSessionA, 71);
    failThreadCreation = true;
    ClInternalConnectionTerminated(-701);
    require(allocatedCount == 1 && freedCount == 1 && detachCount == 0 && loggedCount == 1,
            "thread failure must free payload and never detach an invalid handle");
    pass("thread creation failure frees payload without detaching");

    beginSession(legacyA, withSessionA, 81);
    LiInterruptConnection();
    ClInternalConnectionTerminated(-801);
    require(allocatedCount == 0 && threadCount == 0, "interrupted session must suppress callback scheduling");
    pass("interrupted session does not schedule termination");

    beginSession(legacyA, withSessionA, 91);
    ClInternalConnectionTerminated(-901);
    ClInternalConnectionTerminated(-902);
    deliver(0);
    require(allocatedCount == 1 && detachCount == 1 && deliveryCount == 1 && deliveries[0].error == -901,
            "repeated termination keeps one payload and original error");
    pass("repeated termination schedules once");
    puts("PASS: 15 actual common-C termination cases");
    return 0;
}
