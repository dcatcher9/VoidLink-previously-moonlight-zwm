#import "ConnectionLifecycle.h"
#include <stdatomic.h>

// Compile the actual production coordinator. Semaphores hold the fake C engine
// at specific lifecycle boundaries; assertions never depend on source text.
@interface SessionProbe : NSObject {
@public
    atomic_int cleanups, interrupts, prepares, starts, stops, teardowns;
    atomic_bool interrupted;
}
@end
@implementation SessionProbe @end

static void Require(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); abort(); }
}
static void Wait(dispatch_semaphore_t semaphore) {
    Require(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0,
            "timed out waiting for lifecycle boundary");
}
static void StillWaiting(dispatch_semaphore_t semaphore) {
    Require(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC)) != 0,
            "successor crossed predecessor teardown boundary");
}
static void WaitUntil(BOOL (^predicate)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!predicate() && deadline.timeIntervalSinceNow > 0) [NSThread sleepForTimeInterval:0.001];
    Require(predicate(), "timed out waiting for session ownership change");
}
static ConnectionLifecycle *MakeSession(SessionProbe *probe) {
    return [[ConnectionLifecycle alloc] initWithCleanup:^{
        atomic_fetch_add(&probe->cleanups, 1);
    } interrupt:^{
        atomic_fetch_add(&probe->interrupts, 1);
        atomic_store(&probe->interrupted, true);
    }];
}
static void RunSession(ConnectionLifecycle *lifecycle, SessionProbe *probe,
                       dispatch_block_t prepareHook, int (^startHook)(void),
                       dispatch_block_t stopHook, dispatch_block_t teardownHook) {
    [lifecycle runWithContext:probe prepare:^{
        atomic_fetch_add(&probe->prepares, 1);
        Require([ConnectionLifecycle activeContext] == probe, "prepare must hold session ownership");
        if (prepareHook) prepareHook();
    } start:^int{
        atomic_fetch_add(&probe->starts, 1);
        return startHook ? startHook() : 0;
    } stop:^{
        atomic_fetch_add(&probe->stops, 1);
        Require([ConnectionLifecycle activeContext] == probe, "stop must target its own session");
        if (stopHook) stopHook();
    } teardown:^{
        atomic_fetch_add(&probe->teardowns, 1);
        Require([ConnectionLifecycle activeContext] == probe, "globals must remain owned through teardown");
        if (teardownHook) teardownHook();
    }];
}
static void StopAndWait(ConnectionLifecycle *lifecycle, SessionProbe *probe) {
    [lifecycle cancel];
    WaitUntil(^BOOL{ return [ConnectionLifecycle activeContext] != probe; });
    Require(atomic_load(&probe->cleanups) == 1, "decoder must clean up exactly once");
}
static void Pass(const char *name) { printf("PASS %s\n", name); }

static void TestNoOwner(void) {
    Require([ConnectionLifecycle activeContext] == nil, "no active context before first allocation");
    Require(![ConnectionLifecycle reassertActiveCancellation], "no cancellation without an owner");
    [ConnectionLifecycle cleanupActiveDecoder];
    Pass("safe callbacks without an owner");
}

static void TestUnrunRelease(void) {
    SessionProbe *probe = [SessionProbe new];
    @autoreleasepool {
        ConnectionLifecycle *session = MakeSession(probe);
        Require(session != nil, "session allocated");
    }
    Require(atomic_load(&probe->cleanups) == 1, "never-queued decoder must be released");
    Require(atomic_load(&probe->interrupts) == 0, "unstarted destruction must not interrupt C");
    Pass("never-queued decoder release");
}

static void TestCancelBeforeRun(void) {
    SessionProbe *probe = [SessionProbe new];
    ConnectionLifecycle *session = MakeSession(probe);
    [session cancel];
    [session cancel];
    RunSession(session, probe, nil, nil, nil, nil);
    Require(atomic_load(&probe->prepares) == 0 && atomic_load(&probe->starts) == 0,
            "cancelled session must not publish or enter C");
    Require(atomic_load(&probe->cleanups) == 1 && atomic_load(&probe->stops) == 0,
            "cancel before C setup must clean only its own decoder");
    Pass("cancel before ownership claim");
}

static void TestCancelDuringPrepare(void) {
    SessionProbe *probe = [SessionProbe new];
    ConnectionLifecycle *session = MakeSession(probe);
    RunSession(session, probe, ^{ [session cancel]; }, nil, nil, nil);
    Require(atomic_load(&probe->prepares) == 1 && atomic_load(&probe->starts) == 0,
            "cancel during preparation must prevent C entry");
    Require(atomic_load(&probe->stops) == 0 && atomic_load(&probe->cleanups) == 1 &&
            atomic_load(&probe->teardowns) == 1, "prepared decoder and globals must retire without C stop");
    Require([ConnectionLifecycle activeContext] == nil, "cancelled preparation relinquishes ownership");
    Pass("cancel between decoder activation and C entry");
}

static void TestFailureWithoutCommonCleanup(void) {
    SessionProbe *probe = [SessionProbe new];
    ConnectionLifecycle *session = MakeSession(probe);
    RunSession(session, probe, nil, ^int{ return -1; }, nil, nil);
    [session cancel];
    Require(atomic_load(&probe->stops) == 1 && atomic_load(&probe->cleanups) == 1 &&
            atomic_load(&probe->teardowns) == 1, "failed startup before video setup needs fallback cleanup");
    Require(atomic_load(&probe->interrupts) == 0, "stop after retired failure cannot interrupt another owner");
    Pass("failure before common video setup");
}

static void TestCommonCleanupOnlyOnce(void) {
    SessionProbe *probe = [SessionProbe new];
    ConnectionLifecycle *session = MakeSession(probe);
    RunSession(session, probe, nil, ^int{
        [ConnectionLifecycle cleanupActiveDecoder];
        return -1;
    }, ^{ [ConnectionLifecycle cleanupActiveDecoder]; }, nil);
    Require(atomic_load(&probe->cleanups) == 1, "common cleanup and fallback must share one decoder claim");
    Pass("common cleanup and fallback exactly once");
}

static void TestRetainsOwnerAfterStartup(void) {
    SessionProbe *probe = [SessionProbe new];
    ConnectionLifecycle *session = MakeSession(probe);
    RunSession(session, probe, nil, nil, nil, nil);
    Require([session isCurrentOwner] && [ConnectionLifecycle activeContext] == probe,
            "successful C start must retain ownership after main returns");
    Require(atomic_load(&probe->cleanups) == 0, "running decoder remains live");
    RunSession(session, probe, nil, nil, nil, nil);
    Require(atomic_load(&probe->starts) == 1, "duplicate run must not start a second C session");
    StopAndWait(session, probe);
    Require(atomic_load(&probe->stops) == 1 && atomic_load(&probe->teardowns) == 1,
            "normal stop retires exactly once");
    Pass("ownership spans the full running session");
}

static void TestCancellationAcrossCommonReset(void) {
    SessionProbe *probe = [SessionProbe new];
    ConnectionLifecycle *session = MakeSession(probe);
    dispatch_semaphore_t entered = dispatch_semaphore_create(0);
    dispatch_semaphore_t allowReset = dispatch_semaphore_create(0);
    dispatch_semaphore_t returned = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RunSession(session, probe, nil, ^int{
            dispatch_semaphore_signal(entered);
            Wait(allowReset);
            // The actual C implementation resets this after Connection's final
            // caller-side cancellation check, before its first stage callback.
            atomic_store(&probe->interrupted, false);
            Require([ConnectionLifecycle reassertActiveCancellation], "stage must see canceled active owner");
            Require(atomic_load(&probe->interrupted), "first stage must restore interruption after C reset");
            return -1;
        }, nil, nil);
        dispatch_semaphore_signal(returned);
    });
    Wait(entered);
    [session cancel];
    Require(atomic_load(&probe->interrupted), "stop interrupts blocked C startup promptly");
    dispatch_semaphore_signal(allowReset);
    Wait(returned);
    Require(atomic_load(&probe->interrupts) == 2 && atomic_load(&probe->cleanups) == 1,
            "reset handshake and fallback cleanup must both run");
    Require([ConnectionLifecycle activeContext] == nil, "canceled C startup releases the owner");
    Pass("cancellation survives the C interrupt reset");
}

static void TestSuccessorWaitsForTeardown(void) {
    SessionProbe *oldProbe = [SessionProbe new], *newProbe = [SessionProbe new];
    ConnectionLifecycle *oldSession = MakeSession(oldProbe), *newSession = MakeSession(newProbe);
    dispatch_semaphore_t stopping = dispatch_semaphore_create(0), allowStop = dispatch_semaphore_create(0);
    dispatch_semaphore_t newPrepared = dispatch_semaphore_create(0), newReturned = dispatch_semaphore_create(0);
    __block atomic_int published;
    atomic_init(&published, 0);
    RunSession(oldSession, oldProbe, ^{ atomic_store(&published, 1); }, nil, ^{
        dispatch_semaphore_signal(stopping);
        Wait(allowStop);
        Require(atomic_load(&published) == 1, "new decoder must not replace old globals during C stop");
    }, ^{ atomic_store(&published, 0); });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RunSession(newSession, newProbe, ^{
            Require(atomic_load(&published) == 0 && atomic_load(&oldProbe->cleanups) == 1,
                    "successor publication follows old decoder cleanup and global teardown");
            atomic_store(&published, 2);
            dispatch_semaphore_signal(newPrepared);
        }, nil, nil, ^{ atomic_store(&published, 0); });
        dispatch_semaphore_signal(newReturned);
    });
    StillWaiting(newPrepared);
    [oldSession cancel];
    Wait(stopping);
    StillWaiting(newPrepared);
    dispatch_semaphore_signal(allowStop);
    Wait(newPrepared);
    Wait(newReturned);
    [oldSession cancel];
    [oldSession performIfCurrentOwner:^{ atomic_store(&published, 99); }];
    Require(atomic_load(&published) == 2 && atomic_load(&newProbe->interrupts) == 0 &&
            atomic_load(&newProbe->cleanups) == 0, "retired owner actions cannot touch the successor");
    StopAndWait(newSession, newProbe);
    Pass("successor waits through stop, decoder cleanup and global teardown");
}

static void TestCancelWaitingSuccessor(void) {
    SessionProbe *oldProbe = [SessionProbe new], *newProbe = [SessionProbe new];
    ConnectionLifecycle *oldSession = MakeSession(oldProbe), *newSession = MakeSession(newProbe);
    RunSession(oldSession, oldProbe, nil, nil, nil, nil);
    dispatch_semaphore_t waiting = dispatch_semaphore_create(0), returned = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        dispatch_semaphore_signal(waiting);
        RunSession(newSession, newProbe, nil, nil, nil, nil);
        dispatch_semaphore_signal(returned);
    });
    Wait(waiting);
    StillWaiting(returned);
    [newSession cancel];
    Wait(returned);
    Require([ConnectionLifecycle activeContext] == oldProbe && atomic_load(&oldProbe->interrupts) == 0 &&
            atomic_load(&oldProbe->cleanups) == 0, "canceling a waiter must leave current C/decoder untouched");
    Require(atomic_load(&newProbe->cleanups) == 1 && atomic_load(&newProbe->starts) == 0 &&
            atomic_load(&newProbe->interrupts) == 0, "waiter cleans locally without entering or interrupting C");
    StopAndWait(oldSession, oldProbe);
    Pass("cancel waiting successor without interrupting current session");
}

static void TestConcurrentRepeatedStop(void) {
    SessionProbe *probe = [SessionProbe new];
    ConnectionLifecycle *session = MakeSession(probe);
    RunSession(session, probe, nil, nil, nil, nil);
    dispatch_group_t requests = dispatch_group_create();
    for (int index = 0; index < 64; index++) {
        dispatch_group_async(requests, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [session cancel];
        });
    }
    Require(dispatch_group_wait(requests, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0,
            "concurrent cancellation requests must return");
    WaitUntil(^BOOL{ return [ConnectionLifecycle activeContext] != probe; });
    Require(atomic_load(&probe->interrupts) == 1 && atomic_load(&probe->stops) == 1 &&
            atomic_load(&probe->teardowns) == 1 && atomic_load(&probe->cleanups) == 1,
            "concurrent repeated stop must interrupt/stop/clean/retire exactly once");
    Pass("64 concurrent repeated stop requests");
}

static void TestExternalActionOwnership(void) {
    SessionProbe *probe = [SessionProbe new];
    ConnectionLifecycle *session = MakeSession(probe);
    RunSession(session, probe, nil, nil, nil, nil);
    dispatch_semaphore_t inAction = dispatch_semaphore_create(0), allowAction = dispatch_semaphore_create(0);
    dispatch_semaphore_t cancelled = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [session performIfCurrentOwner:^{
            dispatch_semaphore_signal(inAction);
            Wait(allowAction);
        }];
    });
    Wait(inAction);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [session cancel];
        dispatch_semaphore_signal(cancelled);
    });
    StillWaiting(cancelled);
    dispatch_semaphore_signal(allowAction);
    Wait(cancelled);
    WaitUntil(^BOOL{ return [ConnectionLifecycle activeContext] != probe; });
    [session performIfCurrentOwner:^{ Require(NO, "retired audio action must not execute"); }];
    Pass("external action and ownership change remain atomic");
}

static void TestQueuedOldStopCannotRetireSuccessor(void) {
    // A canceled start performs inline cleanup and also has an async stop queued
    // behind the engine lock. Repeated handoffs exercise either lock ordering:
    // the stale stop must be harmless even when the successor claims first.
    for (int iteration = 0; iteration < 100; iteration++) {
        @autoreleasepool {
            SessionProbe *oldProbe = [SessionProbe new], *newProbe = [SessionProbe new];
            ConnectionLifecycle *oldSession = MakeSession(oldProbe), *newSession = MakeSession(newProbe);
            dispatch_semaphore_t entered = dispatch_semaphore_create(0), allowReturn = dispatch_semaphore_create(0);
            dispatch_semaphore_t oldReturned = dispatch_semaphore_create(0), newReturned = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                RunSession(oldSession, oldProbe, nil, ^int{
                    dispatch_semaphore_signal(entered);
                    Wait(allowReturn);
                    return -1;
                }, nil, nil);
                dispatch_semaphore_signal(oldReturned);
            });
            Wait(entered);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                RunSession(newSession, newProbe, nil, nil, nil, nil);
                dispatch_semaphore_signal(newReturned);
            });
            [oldSession cancel];
            dispatch_semaphore_signal(allowReturn);
            Wait(oldReturned);
            Wait(newReturned);
            Require([ConnectionLifecycle activeContext] == newProbe && atomic_load(&newProbe->stops) == 0 &&
                    atomic_load(&newProbe->cleanups) == 0, "queued old stop must not retire new session");
            StopAndWait(newSession, newProbe);
            Require(atomic_load(&oldProbe->stops) == 1 && atomic_load(&oldProbe->cleanups) == 1,
                    "old inline and queued cleanup must not run twice");
        }
    }
    Pass("100 canceled-start handoffs with a stale queued stop");
}

static void TestDelayedTerminationToken(void) {
    SessionProbe *oldProbe = [SessionProbe new], *newProbe = [SessionProbe new];
    ConnectionLifecycle *oldSession = MakeSession(oldProbe), *newSession = MakeSession(newProbe);
    Require(oldSession.sessionToken != 0 && newSession.sessionToken != oldSession.sessionToken,
            "each connection must receive a distinct nonzero local token");
    RunSession(oldSession, oldProbe, nil, nil, nil, nil);
    StopAndWait(oldSession, oldProbe);
    RunSession(newSession, newProbe, nil, nil, nil, nil);
    __block id captured = nil;
    Require(![ConnectionLifecycle claimTerminationForSessionToken:oldSession.sessionToken capture:^(id context) {
        captured = context;
    }], "a detached old termination must be rejected after successor startup");
    Require(captured == nil && [newSession isCurrentOwner] && atomic_load(&newProbe->interrupts) == 0,
            "rejecting the stale event must not touch the successor");
    Require([ConnectionLifecycle claimTerminationForSessionToken:newSession.sessionToken capture:^(id context) {
        captured = context;
    }] && captured == newProbe, "a current termination must capture its own instance");
    Require(![ConnectionLifecycle claimTerminationForSessionToken:newSession.sessionToken capture:^(id context) {
        (void)context;
        abort();
    }], "termination delivery is claimed at most once");
    StopAndWait(newSession, newProbe);
    Pass("detached termination tokens reject stale sessions and capture current sink once");
}

static void TestCapturedTerminationRemainsInstanceOwned(void) {
    SessionProbe *oldProbe = [SessionProbe new], *newProbe = [SessionProbe new];
    ConnectionLifecycle *oldSession = MakeSession(oldProbe), *newSession = MakeSession(newProbe);
    RunSession(oldSession, oldProbe, nil, nil, nil, nil);
    __block SessionProbe *captured;
    Require([ConnectionLifecycle claimTerminationForSessionToken:oldSession.sessionToken capture:^(id context) {
        captured = context;
    }], "current event accepted before cancellation");
    StopAndWait(oldSession, oldProbe);
    RunSession(newSession, newProbe, nil, nil, nil, nil);
    // Delivery outside the capture lock may cancel the original connection.
    // It must use the captured instance rather than the new activeContext.
    Require(captured == oldProbe, "captured callback sink retains its original identity");
    [oldSession cancel];
    Require([newSession isCurrentOwner] && atomic_load(&newProbe->interrupts) == 0,
            "late instance-owned cancellation cannot interrupt a successor");
    StopAndWait(newSession, newProbe);
    Pass("captured termination remains instance-owned across a subsequent handoff");
}

static void TestConcurrentTerminationClaims(void) {
    SessionProbe *probe = [SessionProbe new];
    ConnectionLifecycle *session = MakeSession(probe);
    RunSession(session, probe, nil, nil, nil, nil);
    __block atomic_int claims;
    atomic_init(&claims, 0);
    dispatch_group_t group = dispatch_group_create();
    for (int i = 0; i < 64; i++) {
        dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [ConnectionLifecycle claimTerminationForSessionToken:session.sessionToken capture:^(id context) {
                Require(context == probe, "concurrent claim must preserve context identity");
                atomic_fetch_add(&claims, 1);
            }];
        });
    }
    Require(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0,
            "concurrent termination claims timed out");
    Require(atomic_load(&claims) == 1, "only one concurrent termination may be delivered");
    StopAndWait(session, probe);
    Require(![ConnectionLifecycle claimTerminationForSessionToken:session.sessionToken capture:^(id context) {
        (void)context;
        abort();
    }], "stopped session cannot claim a callback");
    Pass("64 concurrent termination claims deliver once and stop rejects further claims");
}

static void TestCompletionAfterFullTeardown(void) {
    SessionProbe *probe = [SessionProbe new];
    ConnectionLifecycle *session = MakeSession(probe);
    dispatch_semaphore_t stopping = dispatch_semaphore_create(0), allowStop = dispatch_semaphore_create(0);
    dispatch_semaphore_t tearingDown = dispatch_semaphore_create(0), allowTeardown = dispatch_semaphore_create(0);
    dispatch_semaphore_t completed = dispatch_semaphore_create(0);
    RunSession(session, probe, nil, nil, ^{ dispatch_semaphore_signal(stopping); Wait(allowStop); },
               ^{ dispatch_semaphore_signal(tearingDown); Wait(allowTeardown); });
    [session cancelWithCompletion:^{
        Require(![session isCurrentOwner] && atomic_load(&probe->cleanups) == 1 && atomic_load(&probe->teardowns) == 1,
                "completion must follow engine, decoder and owner teardown");
        dispatch_semaphore_signal(completed);
    }];
    Wait(stopping);
    StillWaiting(completed);
    dispatch_semaphore_signal(allowStop);
    Wait(tearingDown);
    StillWaiting(completed);
    dispatch_semaphore_signal(allowTeardown);
    Wait(completed);
    [session cancelWithCompletion:^{ dispatch_semaphore_signal(completed); }];
    Wait(completed);
    Require(atomic_load(&probe->stops) == 1, "already-stopped completion must not repeat C teardown");
    Pass("stop completion waits for decoder and full ownership teardown, including repeated calls");
}

static void TestCompletionDuringUnstartedCleanup(void) {
    dispatch_semaphore_t cleaning = dispatch_semaphore_create(0), allowCleanup = dispatch_semaphore_create(0);
    dispatch_semaphore_t completed = dispatch_semaphore_create(0), cancelled = dispatch_semaphore_create(0);
    ConnectionLifecycle *session = [[ConnectionLifecycle alloc] initWithCleanup:^{
        dispatch_semaphore_signal(cleaning); Wait(allowCleanup);
    } interrupt:^{ abort(); }];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [session cancel];
        dispatch_semaphore_signal(cancelled);
    });
    Wait(cleaning);
    // The cleanup block has already been claimed, but has not finished.
    [session cancelWithCompletion:^{ dispatch_semaphore_signal(completed); }];
    StillWaiting(completed);
    dispatch_semaphore_signal(allowCleanup);
    Wait(cancelled);
    Wait(completed);
    Pass("completion observes in-flight cleanup of a never-started decoder");
}

int main(void) {
    @autoreleasepool {
        TestNoOwner();
        TestCompletionAfterFullTeardown();
        TestCompletionDuringUnstartedCleanup();
        TestUnrunRelease();
        TestCancelBeforeRun();
        TestCancelDuringPrepare();
        TestFailureWithoutCommonCleanup();
        TestCommonCleanupOnlyOnce();
        TestRetainsOwnerAfterStartup();
        TestCancellationAcrossCommonReset();
        TestSuccessorWaitsForTeardown();
        TestCancelWaitingSuccessor();
        TestConcurrentRepeatedStop();
        TestExternalActionOwnership();
        TestQueuedOldStopCannotRetireSuccessor();
        TestDelayedTerminationToken();
        TestCapturedTerminationRemainsInstanceOwned();
        TestConcurrentTerminationClaims();
        puts("PASS: 18 Connection lifecycle cases");
    }
    return 0;
}
