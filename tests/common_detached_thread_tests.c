#include "Limelight-internal.h"
#include <errno.h>
#include <time.h>
#include <stdatomic.h>

// Exercise the production Darwin implementation and real pthreads. Interpose
// only allocation accounting, failure injection and a completion-order latch.
// The worker may finish ThreadProc (including freeing its platform context)
// before pthread_create returns to production, deterministically reproducing
// the immediate-completion boundary without replacing ThreadProc or detaching.
static void* platformAllocate(size_t size);
static void platformFree(void* pointer);
static int observedPthreadCreate(pthread_t* thread, const pthread_attr_t* attributes,
                                 void* (*entry)(void*), void* context);
static int observedPthreadDetach(pthread_t thread);
#define malloc platformAllocate
#define free platformFree
#define pthread_create observedPthreadCreate
#define pthread_detach observedPthreadDetach
#include "../moonlight-common/moonlight-common-c/src/Platform.c"
#undef malloc
#undef free
#undef pthread_create
#undef pthread_detach

static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t condition = PTHREAD_COND_INITIALIZER;
static atomic_uint checks;
static unsigned allocations, releases, creates, detaches, completed, callbacks;
static unsigned failAllocation;
static bool failCreate, finishBeforeCreateReturns, entryStarted, releaseEntry;
static void* liveAllocation;
static int detachResult;

static void require(bool conditionValue, const char* message) {
    if (!conditionValue) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
    atomic_fetch_add_explicit(&checks, 1, memory_order_relaxed);
}
static void waitUntil(bool* value) {
    struct timespec deadline;
    require(clock_gettime(CLOCK_REALTIME, &deadline) == 0, "read condition deadline");
    deadline.tv_sec += 10;
    while (!*value) {
        int error = pthread_cond_timedwait(&condition, &mutex, &deadline);
        require(error == 0, "real pthread completed before the condition deadline");
    }
}
static void waitCompleted(unsigned target) {
    struct timespec deadline;
    require(clock_gettime(CLOCK_REALTIME, &deadline) == 0, "read completion deadline");
    deadline.tv_sec += 10;
    while (completed < target) {
        int error = pthread_cond_timedwait(&condition, &mutex, &deadline);
        require(error == 0, "production ThreadProc returned before the deadline");
    }
}
static void* platformAllocate(size_t size) {
    pthread_mutex_lock(&mutex);
    allocations++;
    if (failAllocation == allocations) { pthread_mutex_unlock(&mutex); return NULL; }
    require(liveAllocation == NULL, "serialized platform context allocation");
    liveAllocation = malloc(size);
    require(liveAllocation != NULL, "real context allocation succeeds");
    void* pointer = liveAllocation;
    pthread_mutex_unlock(&mutex);
    return pointer;
}
static void platformFree(void* pointer) {
    if (!pointer) return;
    pthread_mutex_lock(&mutex);
    require(pointer == liveAllocation, "platform frees exactly its own context, never caller payload");
    liveAllocation = NULL; releases++;
    free(pointer);
    pthread_mutex_unlock(&mutex);
}
typedef struct {
    void* (*entry)(void*);
    void* context;
} REAL_THREAD_START;
static void recordThreadCompletion(void* unused) {
    (void)unused;
    pthread_mutex_lock(&mutex);
    completed++;
    pthread_cond_broadcast(&condition);
    pthread_mutex_unlock(&mutex);
}
static void* realThreadStart(void* opaque) {
    REAL_THREAD_START start = *(REAL_THREAD_START*)opaque;
    free(opaque);
    void* result;
    // Also observe a client entry that calls pthread_exit() instead of returning.
    pthread_cleanup_push(recordThreadCompletion, NULL);
    result = start.entry(start.context);
    pthread_cleanup_pop(1);
    return result;
}
static int observedPthreadCreate(pthread_t* thread, const pthread_attr_t* attributes,
                                 void* (*entry)(void*), void* context) {
    pthread_mutex_lock(&mutex);
    creates++;
    bool injectedFailure = failCreate, immediate = finishBeforeCreateReturns;
    unsigned target = completed + 1;
    pthread_mutex_unlock(&mutex);
    if (injectedFailure) return EAGAIN;
    REAL_THREAD_START* start = malloc(sizeof(*start));
    require(start != NULL, "fixture start record allocation");
    *start = (REAL_THREAD_START){entry, context};
    int error = pthread_create(thread, attributes, realThreadStart, start);
    if (error != 0) free(start);
    if (error == 0 && immediate) {
        pthread_mutex_lock(&mutex);
        waitCompleted(target);
        pthread_mutex_unlock(&mutex);
    }
    return error;
}
static int observedPthreadDetach(pthread_t thread) {
    int result = pthread_detach(thread);
    pthread_mutex_lock(&mutex);
    detaches++; detachResult = result;
    pthread_mutex_unlock(&mutex);
    return result;
}
static void resetCase(void) {
    // No production thread remains active at this point. The fixture never
    // changes or sanitizes the common library's unrelated activeThreads logic.
    pthread_mutex_lock(&mutex);
    require(liveAllocation == NULL && activeThreads == 0, "previous platform lifetime is balanced");
    allocations = releases = creates = detaches = completed = callbacks = 0;
    failAllocation = 0; failCreate = finishBeforeCreateReturns = entryStarted = releaseEntry = false;
    detachResult = -1;
    pthread_mutex_unlock(&mutex);
}
static void immediateEntry(void* opaque) {
    const int* token = opaque;
    require(*token == 0x12345678, "caller context reaches the real Darwin worker intact");
    char name[64] = {0};
    require(pthread_getname_np(pthread_self(), name, sizeof(name)) == 0 && strcmp(name, "DetachedTest") == 0,
            "production Darwin thread naming is retained");
    pthread_mutex_lock(&mutex);
    require(liveAllocation == NULL && releases == 1, "trampoline context is freed before calling client code");
    callbacks++;
    pthread_mutex_unlock(&mutex);
}
static void freeingEntry(void* opaque) {
    require(*(int*)opaque == 42, "detached callback receives its independently owned payload");
    free(opaque);
    pthread_mutex_lock(&mutex); callbacks++; pthread_mutex_unlock(&mutex);
}
static void gatedEntry(void* opaque) {
    PLT_THREAD* joinable = opaque;
    pthread_mutex_lock(&mutex);
    require(liveAllocation == NULL && releases == 1, "running entry does not retain platform trampoline storage");
    entryStarted = true;
    pthread_cond_broadcast(&condition);
    waitUntil(&releaseEntry);
    if (joinable) require(PltIsThreadInterrupted(joinable), "existing interrupt flag is visible after synchronized release");
    callbacks++;
    pthread_mutex_unlock(&mutex);
}
static void exitingEntry(void* opaque) {
    require(*(int*)opaque == 42, "exiting callback receives its separately owned payload");
    free(opaque);
    pthread_mutex_lock(&mutex);
    require(liveAllocation == NULL && releases == 1, "pthread_exit cannot leak the already-freed trampoline");
    callbacks++;
    pthread_mutex_unlock(&mutex);
    pthread_exit(NULL);
}
int main(void) {
    require(sizeof(PLT_THREAD) >= sizeof(pthread_t), "test uses the real Darwin pthread platform");
    const int token = 0x12345678;
    for (unsigned iteration = 0; iteration < 256; iteration++) {
        resetCase(); finishBeforeCreateReturns = true;
        require(PltCreateThreadDetached("DetachedTest", immediateEntry, (void*)&token) == 0,
                "detached API succeeds when its worker finishes before creation returns");
        require(callbacks == 1 && allocations == 1 && releases == 1 && liveAllocation == NULL,
                "immediate worker releases platform context exactly once");
        require(detaches == 1 && detachResult == 0 && activeThreads == 0,
                "platform performs exactly one successful native detach after immediate completion");
    }
    resetCase(); finishBeforeCreateReturns = true;
    int* owned = malloc(sizeof(*owned)); require(owned != NULL, "caller payload allocation"); *owned = 42;
    require(PltCreateThreadDetached("OwnedPayload", freeingEntry, owned) == 0 && callbacks == 1 && releases == 1,
            "callback may free caller payload while platform separately frees its context");
    resetCase(); failAllocation = 1;
    require(PltCreateThreadDetached("NoMemory", immediateEntry, (void*)&token) != 0 && creates == 0 && releases == 0 && callbacks == 0,
            "allocation failure starts nothing and leaves caller context untouched");
    resetCase(); failCreate = true;
    require(PltCreateThreadDetached("NoThread", immediateEntry, (void*)&token) == EAGAIN && releases == 1 && callbacks == 0 && detaches == 0,
            "pthread creation failure releases context and never detaches an invalid thread");
    resetCase();
    require(PltCreateThreadDetached("Delayed", gatedEntry, NULL) == 0, "detached API returns while callback is still running");
    pthread_mutex_lock(&mutex); waitUntil(&entryStarted);
    require(detaches == 1 && detachResult == 0 && releases == 1 && liveAllocation == NULL,
            "running detached worker has already released its platform context");
    releaseEntry = true; pthread_cond_broadcast(&condition); waitCompleted(1); pthread_mutex_unlock(&mutex);
    require(releases == 1 && callbacks == 1, "delayed detached callback finishes without a second context release");
    resetCase();
    PLT_THREAD thread;
    require(PltCreateThread("Joinable", gatedEntry, &thread, &thread) == 0, "existing joinable API still creates a real thread");
    pthread_mutex_lock(&mutex); waitUntil(&entryStarted);
    require(!PltIsThreadInterrupted(&thread) && detaches == 0 && activeThreads == 1, "joinable handle remains owned by caller");
    PltInterruptThread(&thread); releaseEntry = true; pthread_cond_broadcast(&condition); pthread_mutex_unlock(&mutex);
    PltJoinThread(&thread);
    require(callbacks == 1 && releases == 1 && activeThreads == 0 && detaches == 0, "join consumes handle after actual worker completion");
    resetCase();
    require(PltCreateThread("LegacyDetach", gatedEntry, NULL, &thread) == 0, "legacy explicit detach API still creates a thread");
    PltDetachThread(&thread);
    pthread_mutex_lock(&mutex); waitUntil(&entryStarted); releaseEntry = true; pthread_cond_broadcast(&condition); waitCompleted(1); pthread_mutex_unlock(&mutex);
    require(detaches == 1 && detachResult == 0 && releases == 1 && activeThreads == 0, "legacy explicit native detach remains balanced");
    resetCase();
    finishBeforeCreateReturns = true;
    owned = malloc(sizeof(*owned)); require(owned != NULL, "exiting callback payload allocation"); *owned = 42;
    require(PltCreateThreadDetached("ExitingEntry", exitingEntry, owned) == 0,
            "detached entry may call pthread_exit before creation returns");
    require(callbacks == 1 && releases == 1 && completed == 1 && liveAllocation == NULL &&
            detaches == 1 && detachResult == 0 && activeThreads == 0,
            "early thread exit releases each ownership layer and detaches exactly once");
    resetCase();
    printf("COMMON_DETACHED_THREAD_TESTS_RESULT: PASS %u checks (256 forced immediate completions)\n", atomic_load_explicit(&checks, memory_order_relaxed));
    return 0;
}
