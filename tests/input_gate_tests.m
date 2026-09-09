#import "SunlightInputGate.h"

// Exercises the production admission/cancellation mechanism. UIKit gesture
// recognition and hardware event delivery still require the app/device checks.
static int cases;
static void Require(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL %s\n", message); abort(); }
}
static void Pass(const char *name) { ++cases; printf("PASS %s\n", name); }
static void Wait(dispatch_semaphore_t event) {
    Require(dispatch_semaphore_wait(event, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0,
            "timed out waiting for controlled input delivery");
}
static SunlightInputGate *Connected(void) {
    SunlightInputGate *gate = [SunlightInputGate new];
    [gate setConnected:YES cancellation:^{ abort(); }];
    return gate;
}
int main(void) { @autoreleasepool {
    SunlightInputGate *gate = [SunlightInputGate new];
    __block int sends = 0, cancels = 0;
    dispatch_block_t send = ^{ ++sends; };
    dispatch_block_t cancel = ^{ ++cancels; };
    [gate perform:send];
    [gate performForGeneration:gate.generation action:send];
    Require(sends == 0 && !gate.allowed, "unconnected view sent host input");
    Pass("no input before the stream connection is accepted");

    NSUInteger unconnected = gate.generation;
    [gate setConnected:YES cancellation:cancel];
    [gate performForGeneration:unconnected action:send];
    [gate perform:send];
    Require(sends == 1 && cancels == 0, "connection admitted stale work or cancelled new session");
    Pass("connection begins a fresh input generation");

    NSUInteger beforePanel = gate.generation;
    __weak SunlightInputGate *presentedGate = gate;
    [gate setBlocked:YES cancellation:^{
        ++cancels;
        Require(!presentedGate.allowed, "gate must block before cancellation runs");
        [presentedGate perform:send];
    }];
    [gate perform:send];
    [gate performForGeneration:beforePanel action:send];
    Require(sends == 1 && cancels == 1, "panel allowed input or skipped release");
    Pass("opening controls blocks input before releasing held state");

    NSUInteger whilePanel = gate.generation;
    [gate setBlocked:YES cancellation:cancel];
    Require(gate.generation == whilePanel && cancels == 1, "repeated UI updates cancelled twice");
    Pass("repeated panel presentation is idempotent");

    [gate setBlocked:NO cancellation:cancel];
    [gate performForGeneration:beforePanel action:send];
    [gate performForGeneration:whilePanel action:send];
    [gate performForGeneration:gate.generation action:send];
    Require(sends == 2 && cancels == 1, "closing controls revived a queued old gesture");
    Pass("closing controls cannot revive pre-panel clicks or scrolling");

    NSUInteger collapsed = gate.generation;
    [gate setBlocked:NO cancellation:cancel];
    [gate setConnected:YES cancellation:cancel];
    Require(gate.generation == collapsed && cancels == 1, "unchanged layout interrupted current input");
    Pass("unchanged collapsed state preserves active input generation");

    NSMutableArray<NSString *> *events = [NSMutableArray array];
    [gate perform:^{ [events addObject:@"down"]; }];
    NSUInteger held = gate.generation;
    [gate cancelCurrentInput:^{ [events addObject:@"release"]; }];
    [gate performForGeneration:held action:^{ [events addObject:@"late-down"]; }];
    Require([events isEqualToArray:@[@"down", @"release"]], "cancel synthesized a click or revived old held input");
    Pass("touch mode cancellation releases held state without a new click");

    [gate setBlocked:YES cancellation:cancel];
    int oldCancels = cancels;
    [gate cancelCurrentInput:cancel];
    Require(cancels == oldCancels, "blocked touch cancellation repeated remote releases");
    Pass("blocked touch cancellation only invalidates pending work");

    [gate setBlocked:NO cancellation:cancel];
    NSUInteger connectedGeneration = gate.generation;
    [gate setConnected:NO cancellation:cancel];
    [gate perform:send];
    [gate setConnected:YES cancellation:cancel];
    [gate performForGeneration:connectedGeneration action:send];
    Require(sends == 2, "disconnect/reconnect admitted old session work");
    Pass("disconnect and reconnect reject old session work");

    [gate invalidateWithCancellation:cancel];
    oldCancels = cancels;
    NSUInteger terminal = gate.generation;
    [gate setConnected:YES cancellation:cancel];
    [gate setBlocked:NO cancellation:cancel];
    [gate cancelCurrentInput:cancel];
    [gate invalidateWithCancellation:cancel];
    [gate perform:send];
    Require(sends == 2 && cancels == oldCancels && gate.generation == terminal && !gate.allowed,
            "retired view reactivated or cancelled twice");
    Pass("cleanup permanently retires the stream input gate");

    gate = Connected();
    [gate perform:^{ [gate perform:send]; }];
    Require(sends == 3, "nested final-delivery wrappers failed");
    Pass("nested delivery wrappers are safe");

    // Hold an accepted send inside the actual monitor while another thread
    // opens controls. The release must occur after that send, never before it.
    gate = Connected();
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    dispatch_semaphore_t entered = dispatch_semaphore_create(0);
    dispatch_semaphore_t finishSend = dispatch_semaphore_create(0);
    dispatch_semaphore_t transitionStarted = dispatch_semaphore_create(0);
    dispatch_semaphore_t transitioned = dispatch_semaphore_create(0);
    NSMutableArray *order = [NSMutableArray array];
    SunlightInputGate *concurrentGate = gate;
    dispatch_async(queue, ^{
        [concurrentGate perform:^{
            [order addObject:@"send-begin"];
            dispatch_semaphore_signal(entered);
            Wait(finishSend);
            [order addObject:@"send-end"];
        }];
    });
    Wait(entered);
    dispatch_async(queue, ^{
        dispatch_semaphore_signal(transitionStarted);
        [concurrentGate setBlocked:YES cancellation:^{ [order addObject:@"release"]; }];
        dispatch_semaphore_signal(transitioned);
    });
    Wait(transitionStarted);
    Require(dispatch_semaphore_wait(transitioned, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC)) != 0,
            "cancellation crossed an in-flight delivery");
    dispatch_semaphore_signal(finishSend);
    Wait(transitioned);
    Require([order isEqualToArray:@[@"send-begin", @"send-end", @"release"]],
            "accepted delivery raced its cancellation release");
    Pass("concurrent panel opening waits for accepted delivery before release");

    NSUInteger retiredGeneration = gate.generation;
    dispatch_semaphore_t queuedReady = dispatch_semaphore_create(0);
    dispatch_semaphore_t releaseQueued = dispatch_semaphore_create(0);
    dispatch_semaphore_t queuedDone = dispatch_semaphore_create(0);
    dispatch_async(queue, ^{
        dispatch_semaphore_signal(queuedReady);
        Wait(releaseQueued);
        [concurrentGate performForGeneration:retiredGeneration action:^{ [order addObject:@"stale"]; }];
        dispatch_semaphore_signal(queuedDone);
    });
    Wait(queuedReady);
    [gate setBlocked:NO cancellation:^{ abort(); }];
    dispatch_semaphore_signal(releaseQueued);
    Wait(queuedDone);
    Require(order.count == 3, "delayed worker crossed the panel generation boundary");
    Pass("delayed worker is rejected after panel closes");

    printf("PASS %d input gate cases\n", cases);
    return 0;
} }
