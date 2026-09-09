#import <Foundation/Foundation.h>
#import "ConnectionLifecycle.h"
#include <stdatomic.h>
#include <stdint.h>

// The runner inserts Connection.m's exact playback gate and owner-interrupt
// code. SDL queue depth is controlled; lifecycle ownership/teardown is real.
static unsigned audioDevice = 1;
static int audioFrameSize = 100;
// SUNLIGHT_ACTUAL_AUDIO_STOP_STATE
static atomic_uint queuedBytes, queueReads, samplesQueued, interrupts;
static atomic_bool stopDuringQuery;
static dispatch_semaphore_t readEntered;
static void ArStop(void);
static uint32_t SDL_GetQueuedAudioSize(unsigned device) {
    (void)device;
    atomic_fetch_add(&queueReads, 1);
    if (readEntered) dispatch_semaphore_signal(readEntered);
    if (atomic_exchange(&stopDuringQuery, false)) ArStop();
    return atomic_load(&queuedBytes);
}
static void LiInterruptConnection(void) {
    if (!atomic_load(&audioRendererStopping)) abort();
    atomic_fetch_add(&interrupts, 1);
}
// SUNLIGHT_ACTUAL_AUDIO_GATE

static unsigned checks;
static void Require(BOOL condition, const char *message) {
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); abort(); }
}
static void Wait(dispatch_semaphore_t signal) {
    Require(dispatch_semaphore_wait(signal, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0,
            "reach controlled audio/lifecycle boundary");
}
static void StillWaiting(dispatch_semaphore_t signal) {
    Require(dispatch_semaphore_wait(signal, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_MSEC)) != 0,
            "operation remains blocked at its intended boundary");
}
static ConnectionLifecycle *Lifecycle(dispatch_block_t cleanup) {
    return [[ConnectionLifecycle alloc] initWithCleanup:cleanup interrupt:^{
        // SUNLIGHT_ACTUAL_OWNER_INTERRUPT
    }];
}
static void SimulateAudioCallback(void) {
    if (WaitForSdlAudioQueueCapacity()) atomic_fetch_add(&samplesQueued, 1);
}

static void TestQueueCapacity(void) {
    readEntered = nil;
    ArStop();
    atomic_store(&queueReads, 0);
    atomic_store(&queuedBytes, 0);
    Require(!WaitForSdlAudioQueueCapacity() && atomic_load(&queueReads) == 0,
            "retired playback never accesses SDL even when capacity is available");
    PrepareAudioPlayback();
    Require(WaitForSdlAudioQueueCapacity(), "active playback accepts available capacity");
    atomic_store(&queuedBytes, 1000);
    Require(WaitForSdlAudioQueueCapacity(), "existing ten-frame backpressure threshold is retained");

    atomic_store(&queuedBytes, 1100);
    readEntered = dispatch_semaphore_create(0);
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    __block BOOL admitted = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        admitted = WaitForSdlAudioQueueCapacity();
        dispatch_semaphore_signal(finished);
    });
    Wait(readEntered);
    StillWaiting(finished);
    atomic_store(&queuedBytes, 500);
    Wait(finished);
    Require(admitted, "normal playback resumes when SDL drains without cancelling its session");
    readEntered = nil;

    atomic_store(&stopDuringQuery, true);
    atomic_store(&queuedBytes, 0);
    Require(!WaitForSdlAudioQueueCapacity(), "stop during the capacity query prevents an additional queued sample");
    PrepareAudioPlayback();
    audioFrameSize = 0;
    Require(!WaitForSdlAudioQueueCapacity(), "uninitialized frame size cannot divide by zero");
    audioFrameSize = 100;
    audioDevice = 0;
    Require(!WaitForSdlAudioQueueCapacity(), "uninitialized device cannot enter a wait");
    audioDevice = 1;
    ArStop();
}

static void TestCommonStopUnblocksStalledAudio(void) {
    PrepareAudioPlayback();
    atomic_store(&queuedBytes, 1100);
    atomic_store(&samplesQueued, 0);
    readEntered = dispatch_semaphore_create(0);
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        SimulateAudioCallback();
        dispatch_semaphore_signal(finished);
    });
    Wait(readEntered);
    StillWaiting(finished);
    CFAbsoluteTime began = CFAbsoluteTimeGetCurrent();
    ArStop(); // Common invokes this audio stop callback before joining its decoder.
    Require(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC)) == 0,
            "stalled SDL queue exits promptly when common stops audio");
    Require(CFAbsoluteTimeGetCurrent() - began < 0.25 && atomic_load(&samplesQueued) == 0,
            "teardown completes without waiting for stalled audio to drain or enqueuing more data");
    readEntered = nil;
}

static void TestLifecycleRetainsOwnershipThroughAudioJoin(void) {
    atomic_store(&queuedBytes, 1100);
    atomic_store(&samplesQueued, 0);
    atomic_store(&interrupts, 0);
    readEntered = dispatch_semaphore_create(0);
    dispatch_semaphore_t audioFinished = dispatch_semaphore_create(0);
    dispatch_semaphore_t cleanupEntered = dispatch_semaphore_create(0);
    dispatch_semaphore_t releaseCleanup = dispatch_semaphore_create(0);
    dispatch_semaphore_t successorPrepared = dispatch_semaphore_create(0);
    dispatch_semaphore_t oldFinished = dispatch_semaphore_create(0);
    dispatch_semaphore_t nextFinished = dispatch_semaphore_create(0);
    NSObject *oldContext = [NSObject new], *nextContext = [NSObject new];
    __block BOOL callbackJoined = NO;
    ConnectionLifecycle *old = Lifecycle(^{
        // ArCleanup may destroy device/buffer storage only after common has
        // joined the old decoder callback. Hold this boundary to race reconnect.
        Require(callbackJoined, "audio callback has exited before device/buffer cleanup");
        dispatch_semaphore_signal(cleanupEntered);
        Wait(releaseCleanup);
    });
    [old runWithContext:oldContext prepare:^{
        PrepareAudioPlayback();
    } start:^int{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            SimulateAudioCallback();
            dispatch_semaphore_signal(audioFinished);
        });
        return 0;
    } stop:^{
        ArStop();
        Wait(audioFinished);
        callbackJoined = YES;
    } teardown:^{}];
    Wait(readEntered);

    ConnectionLifecycle *successor = Lifecycle(^{});
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [successor runWithContext:nextContext prepare:^{
            PrepareAudioPlayback();
            atomic_store(&queuedBytes, 0);
            dispatch_semaphore_signal(successorPrepared);
        } start:^int{ return 0; } stop:^{ ArStop(); } teardown:^{}];
    });
    StillWaiting(successorPrepared);
    [old cancelWithCompletion:^{ dispatch_semaphore_signal(oldFinished); }];
    Wait(cleanupEntered);
    Require(atomic_load(&interrupts) == 1 && atomic_load(&samplesQueued) == 0 &&
            atomic_load(&audioRendererStopping),
            "owner interrupt stops the stalled callback before C teardown and retains stopped state");
    StillWaiting(successorPrepared);
    dispatch_semaphore_signal(releaseCleanup);
    Wait(oldFinished);
    Wait(successorPrepared);
    Require([ConnectionLifecycle activeContext] == nextContext && WaitForSdlAudioQueueCapacity(),
            "successor resets its own playback only after predecessor audio cleanup finishes");
    for (int i = 0; i < 64; i++) [old cancel];
    Require(atomic_load(&interrupts) == 1 && WaitForSdlAudioQueueCapacity(),
            "repeated old cancellation cannot stop successor playback");
    [successor cancelWithCompletion:^{ dispatch_semaphore_signal(nextFinished); }];
    Wait(nextFinished);
    Require(atomic_load(&audioRendererStopping) && atomic_load(&interrupts) == 2,
            "successor termination independently retires its audio gate");
    readEntered = nil;
}

static void TestUnstartedCancellationDoesNotStopCurrentAudio(void) {
    NSObject *context = [NSObject new];
    ConnectionLifecycle *current = Lifecycle(^{});
    [current runWithContext:context prepare:^{ PrepareAudioPlayback(); atomic_store(&queuedBytes, 0); }
                     start:^int{ return 0; } stop:^{ ArStop(); } teardown:^{}];
    ConnectionLifecycle *unstarted = Lifecycle(^{});
    dispatch_semaphore_t discarded = dispatch_semaphore_create(0), finished = dispatch_semaphore_create(0);
    unsigned before = atomic_load(&interrupts);
    [unstarted cancelWithCompletion:^{ dispatch_semaphore_signal(discarded); }];
    Wait(discarded);
    Require(atomic_load(&interrupts) == before && WaitForSdlAudioQueueCapacity(),
            "cancelling an allocated but unstarted connection does not alter current playback");
    [current cancelWithCompletion:^{ dispatch_semaphore_signal(finished); }];
    Wait(finished);
}

int main(void) {
    @autoreleasepool {
        TestQueueCapacity();
        TestCommonStopUnblocksStalledAudio();
        TestLifecycleRetainsOwnershipThroughAudioJoin();
        TestUnstartedCancellationDoesNotStopCurrentAudio();
        printf("AUDIO_PLAYBACK_LIFECYCLE_TESTS_RESULT: PASS (%u checks)\n", checks);
    }
    return 0;
}
