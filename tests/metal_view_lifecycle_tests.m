#import "metal_view_lifecycle_tests.h"
#import "MetalView.h"
#include <unistd.h>

/// Owns no decoder, Metal device, drawable, or GPU command queue. Its gate lets
/// the main-thread tests move the real view while one wait/render pair is live.
@interface GatedMetalViewDelegate : NSObject <MetalViewDelegate>
@property(nonatomic, readonly) NSUInteger waitCount;
@property(nonatomic, readonly) NSUInteger renderCount;
@property(nonatomic, readonly) NSUInteger maximumConcurrentPairs;
@property(nonatomic, readonly) BOOL hasPairingError;
@property(nonatomic, readonly) NSSet<NSThread *> *workers;
- (BOOL)waitForWaitCount:(NSUInteger)count timeout:(NSTimeInterval)timeout;
- (BOOL)waitForRenderCount:(NSUInteger)count timeout:(NSTimeInterval)timeout;
- (void)allowOnePair;
- (void)releaseAllWaits;
@end

@implementation GatedMetalViewDelegate {
    NSCondition *_gate;
    NSUInteger _permits;
    NSUInteger _waitCount;
    NSUInteger _renderCount;
    NSUInteger _activePairs;
    NSUInteger _maximumConcurrentPairs;
    BOOL _released;
    BOOL _hasPairingError;
    NSMutableSet<NSThread *> *_workers;
    NSMapTable<NSThread *, NSNumber *> *_openPairsByWorker;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _gate = [[NSCondition alloc] init];
        _workers = [NSMutableSet set];
        _openPairsByWorker = [NSMapTable strongToStrongObjectsMapTable];
    }
    return self;
}

- (void)drawableResize:(CGSize)size {}

- (void)waitToRenderTo:(CAMetalLayer *)layer {
    [_gate lock];
    NSThread *worker = NSThread.currentThread;
    [_workers addObject:worker];
    NSUInteger openPairs = [[_openPairsByWorker objectForKey:worker] unsignedIntegerValue];
    _hasPairingError |= openPairs != 0 || worker.isMainThread;
    [_openPairsByWorker setObject:@(openPairs + 1) forKey:worker];
    _waitCount++;
    _activePairs++;
    _maximumConcurrentPairs = MAX(_maximumConcurrentPairs, _activePairs);
    [_gate broadcast];
    while (_permits == 0 && !_released) {
        [_gate wait];
    }
    if (_permits > 0) _permits--;
    [_gate unlock];
}

- (void)renderTo:(CAMetalLayer *)layer {
    [_gate lock];
    NSThread *worker = NSThread.currentThread;
    NSUInteger openPairs = [[_openPairsByWorker objectForKey:worker] unsignedIntegerValue];
    _hasPairingError |= openPairs != 1 || _activePairs == 0;
    if (openPairs > 0) [_openPairsByWorker setObject:@(openPairs - 1) forKey:worker];
    if (_activePairs > 0) _activePairs--;
    _renderCount++;
    [_gate broadcast];
    [_gate unlock];
}

- (BOOL)waitForWaitCount:(NSUInteger)count timeout:(NSTimeInterval)timeout {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    [_gate lock];
    while (_waitCount < count && [deadline timeIntervalSinceNow] > 0) {
        [_gate waitUntilDate:deadline];
    }
    BOOL reached = _waitCount >= count;
    [_gate unlock];
    return reached;
}

- (BOOL)waitForRenderCount:(NSUInteger)count timeout:(NSTimeInterval)timeout {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    [_gate lock];
    while (_renderCount < count && [deadline timeIntervalSinceNow] > 0) {
        [_gate waitUntilDate:deadline];
    }
    BOOL reached = _renderCount >= count;
    [_gate unlock];
    return reached;
}

- (void)allowOnePair {
    [_gate lock];
    _permits++;
    [_gate broadcast];
    [_gate unlock];
}

- (void)releaseAllWaits {
    [_gate lock];
    _released = YES;
    [_gate broadcast];
    [_gate unlock];
}

- (NSUInteger)waitCount { [_gate lock]; NSUInteger value = _waitCount; [_gate unlock]; return value; }
- (NSUInteger)renderCount { [_gate lock]; NSUInteger value = _renderCount; [_gate unlock]; return value; }
- (NSUInteger)maximumConcurrentPairs { [_gate lock]; NSUInteger value = _maximumConcurrentPairs; [_gate unlock]; return value; }
- (BOOL)hasPairingError { [_gate lock]; BOOL value = _hasPairingError; [_gate unlock]; return value; }
- (NSSet<NSThread *> *)workers { [_gate lock]; NSSet *value = [_workers copy]; [_gate unlock]; return value; }
@end

static void RequireMetalLifecycle(BOOL condition, NSString *message) {
    if (!condition) [NSException raise:@"MetalViewLifecycleAssertion" format:@"%@", message];
}

static UIWindow *NewMetalTestWindow(void) {
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 640, 360)];
    window.rootViewController = [[UIViewController alloc] init];
    window.hidden = NO;
    [window layoutIfNeeded];
    return window;
}

static void RequireSingleWorker(GatedMetalViewDelegate *delegate, NSThread *originalWorker) {
    RequireMetalLifecycle(delegate.workers.count == 1 && [delegate.workers containsObject:originalWorker],
                          @"Window changes must retain the original worker identity");
    RequireMetalLifecycle(delegate.maximumConcurrentPairs == 1,
                          @"A view must never have two concurrent wait/render pairs");
    RequireMetalLifecycle(!delegate.hasPairingError,
                          @"Every render must pair with its worker's preceding wait");
}

BOOL SunlightTestMetalViewReparenting(UIWindow *primaryWindow, NSString **failure) {
    GatedMetalViewDelegate *delegate = [[GatedMetalViewDelegate alloc] init];
    MetalView *view = [[MetalView alloc] initWithFrame:CGRectMake(0, 0, 160, 90)];
    view.delegate = delegate;
    UIWindow *externalWindow = NewMetalTestWindow();
    UIView *phoneHost = primaryWindow.rootViewController.view;
    UIView *externalHost = externalWindow.rootViewController.view;
    @try {
        [phoneHost addSubview:view];
        RequireMetalLifecycle([delegate waitForWaitCount:1 timeout:2], @"Initial attachment must start its worker");
        NSThread *originalWorker = delegate.workers.anyObject;

        // Direct reparenting exercises UIKit's temporary removal callbacks while
        // an acquired pair remains deliberately blocked in the delegate.
        for (NSUInteger move = 0; move < 8; move++) {
            NSUInteger priorWaits = delegate.waitCount;
            NSUInteger priorRenders = delegate.renderCount;
            UIView *destination = move % 2 == 0 ? externalHost : phoneHost;
            [destination addSubview:view];
            RequireMetalLifecycle(view.window == destination.window, @"Reparenting must use the destination window");
            [delegate allowOnePair];
            RequireMetalLifecycle([delegate waitForRenderCount:priorRenders + 1 timeout:2], @"Worker must finish its in-flight pair after reparenting");
            RequireMetalLifecycle([delegate waitForWaitCount:priorWaits + 1 timeout:2], @"Original worker must resume after reparenting");
            RequireSingleWorker(delegate, originalWorker);
        }

        // A detached view may complete its in-flight pair, but must wait for a
        // window before asking the delegate for another frame.
        for (NSUInteger detach = 0; detach < 4; detach++) {
            NSUInteger priorWaits = delegate.waitCount;
            NSUInteger priorRenders = delegate.renderCount;
            [view removeFromSuperview];
            RequireMetalLifecycle(view.window == nil, @"Detached test interval must have no window");
            [delegate allowOnePair];
            RequireMetalLifecycle([delegate waitForRenderCount:priorRenders + 1 timeout:2], @"Detached view may finish the in-flight pair");
            RequireMetalLifecycle(![delegate waitForWaitCount:priorWaits + 1 timeout:0.04], @"Detached view must not start another wait/render pair");
            [externalHost addSubview:view];
            RequireMetalLifecycle([delegate waitForWaitCount:priorWaits + 1 timeout:2], @"Reattaching must resume the waiting original worker");
            RequireSingleWorker(delegate, originalWorker);
        }
        return YES;
    } @catch (NSException *exception) {
        if (failure) *failure = exception.reason;
        return NO;
    } @finally {
        [delegate releaseAllWaits];
        [view shutdown];
        [view removeFromSuperview];
        externalWindow.hidden = YES;
    }
}

BOOL SunlightTestMetalViewTerminalShutdown(UIWindow *primaryWindow, NSString **failure) {
    GatedMetalViewDelegate *delegate = [[GatedMetalViewDelegate alloc] init];
    MetalView *view = [[MetalView alloc] initWithFrame:CGRectMake(0, 0, 160, 90)];
    view.delegate = delegate;
    UIWindow *externalWindow = NewMetalTestWindow();
    @try {
        [primaryWindow.rootViewController.view addSubview:view];
        RequireMetalLifecycle([delegate waitForWaitCount:1 timeout:2], @"Initial attachment must reach its first wait");
        NSThread *originalWorker = delegate.workers.anyObject;

        // Keep the old worker blocked so shutdown exercises its bounded timeout.
        // Reattaching during this interval must not create a replacement worker.
        CFTimeInterval started = CACurrentMediaTime();
        [view shutdown];
        RequireMetalLifecycle(CACurrentMediaTime() - started < 2.0, @"Shutdown must remain bounded while the delegate is blocked");
        for (NSUInteger move = 0; move < 4; move++) {
            [view removeFromSuperview];
            UIView *destination = move % 2 == 0 ? externalWindow.rootViewController.view : primaryWindow.rootViewController.view;
            [destination addSubview:view];
        }
        RequireMetalLifecycle(![delegate waitForWaitCount:2 timeout:0.04], @"Terminal shutdown must prohibit a replacement while its worker exits");
        RequireSingleWorker(delegate, originalWorker);
        [delegate allowOnePair];
        RequireMetalLifecycle([delegate waitForRenderCount:1 timeout:2], @"Old worker must finish its already acquired pair");
        CFTimeInterval deadline = CACurrentMediaTime() + 2.0;
        while (!originalWorker.isFinished && CACurrentMediaTime() < deadline) usleep(1000);
        RequireMetalLifecycle(originalWorker.isFinished, @"Original worker must terminate after its blocked pair is released");
        [view removeFromSuperview];
        [externalWindow.rootViewController.view addSubview:view];
        RequireMetalLifecycle(![delegate waitForWaitCount:2 timeout:0.04], @"Reattachment after the old worker exits must still not restart it");
        RequireSingleWorker(delegate, originalWorker);
        return YES;
    } @catch (NSException *exception) {
        if (failure) *failure = exception.reason;
        return NO;
    } @finally {
        [delegate releaseAllWaits];
        [view shutdown];
        [view removeFromSuperview];
        externalWindow.hidden = YES;
    }
}

BOOL SunlightTestMetalViewPause(UIWindow *primaryWindow, NSString **failure) {
    GatedMetalViewDelegate *delegate = [[GatedMetalViewDelegate alloc] init];
    MetalView *view = [[MetalView alloc] initWithFrame:CGRectMake(0, 0, 160, 90)];
    view.delegate = delegate;
    UIWindow *externalWindow = NewMetalTestWindow();
    @try {
        [primaryWindow.rootViewController.view addSubview:view];
        RequireMetalLifecycle([delegate waitForWaitCount:1 timeout:2], @"Initial worker must acquire a pair");
        NSThread *originalWorker = delegate.workers.anyObject;
        view.renderingPaused = YES;
        [delegate allowOnePair];
        RequireMetalLifecycle([delegate waitForRenderCount:1 timeout:2], @"Pause must finish its already acquired pair");
        RequireMetalLifecycle(![delegate waitForWaitCount:2 timeout:0.08], @"Paused worker must block instead of spinning through the delegate");

        [externalWindow.rootViewController.view addSubview:view];
        RequireMetalLifecycle(![delegate waitForWaitCount:2 timeout:0.08], @"Reparenting must preserve the pause");
        view.renderingPaused = NO;
        RequireMetalLifecycle([delegate waitForWaitCount:2 timeout:2], @"Resume must wake the original worker");
        RequireSingleWorker(delegate, originalWorker);

        view.renderingPaused = YES;
        [delegate allowOnePair];
        RequireMetalLifecycle([delegate waitForRenderCount:2 timeout:2], @"Second pause must balance the active pair");
        [view shutdown];
        RequireMetalLifecycle(originalWorker.isFinished, @"Shutdown must wake a worker blocked by pause");
        view.renderingPaused = NO;
        RequireMetalLifecycle(![delegate waitForWaitCount:3 timeout:0.08], @"Resume after terminal shutdown must not restart rendering");
        return YES;
    } @catch (NSException *exception) {
        if (failure) *failure = exception.reason;
        return NO;
    } @finally {
        [delegate releaseAllWaits];
        [view shutdown];
        [view removeFromSuperview];
        externalWindow.hidden = YES;
    }
}
