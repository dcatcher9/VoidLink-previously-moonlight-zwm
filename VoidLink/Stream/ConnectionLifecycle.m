#import "ConnectionLifecycle.h"

static NSCondition *sessionCondition;
static NSLock *engineLock;
static ConnectionLifecycle *sessionOwner;
static uint64_t nextSessionToken;

@interface ConnectionLifecycle ()
- (void)cleanupDecoderOnce;
- (void)finishSession;
- (void)deliverStopCompletionsIfReady;
@end

@implementation ConnectionLifecycle {
    BOOL _cancelled;
    BOOL _runRequested;
    BOOL _engineEntered;
    BOOL _finishing;
    BOOL _terminationClaimed;
    BOOL _retired;
    BOOL _cleanupFinished;
    BOOL _finished;
    NSMutableArray<dispatch_block_t> *_stopCompletions;
    dispatch_block_t _cleanup;
    dispatch_block_t _interrupt;
    dispatch_block_t _stop;
    dispatch_block_t _teardown;
    id _context;
}

- (instancetype)initWithCleanup:(dispatch_block_t)cleanup interrupt:(dispatch_block_t)interrupt {
    self = [super init];
    if (self) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            sessionCondition = [NSCondition new];
            engineLock = [NSLock new];
        });
        [sessionCondition lock];
        _sessionToken = ++nextSessionToken;
        [sessionCondition unlock];
        _cleanup = [cleanup copy];
        _interrupt = [interrupt copy];
        _stopCompletions = [NSMutableArray array];
    }
    return self;
}

- (void)dealloc {
    // An allocated Connection that was never queued still owns a decoder.
    if (_cleanup) _cleanup();
}

- (BOOL)isCurrentOwner {
    [sessionCondition lock];
    BOOL isOwner = sessionOwner == self;
    [sessionCondition unlock];
    return isOwner;
}

- (void)performIfCurrentOwner:(dispatch_block_t)action {
    [sessionCondition lock];
    @try {
        if (sessionOwner == self && !_cancelled && !_finishing) action();
    } @finally {
        [sessionCondition unlock];
    }
}

+ (id)activeContext {
    [sessionCondition lock];
    id context = sessionOwner ? sessionOwner->_context : nil;
    [sessionCondition unlock];
    return context;
}

+ (BOOL)claimTerminationForSessionToken:(uint64_t)token capture:(void (^)(id))capture {
    [sessionCondition lock];
    ConnectionLifecycle *owner = sessionOwner;
    BOOL accepted = owner && token != 0 && owner.sessionToken == token &&
        !owner->_cancelled && !owner->_finishing && !owner->_terminationClaimed;
    @try {
        if (accepted) {
            owner->_terminationClaimed = YES;
            capture(owner->_context);
        }
    } @finally {
        [sessionCondition unlock];
    }
    return accepted;
}

+ (BOOL)reassertActiveCancellation {
    [sessionCondition lock];
    ConnectionLifecycle *owner = sessionOwner;
    BOOL cancelled = owner && owner->_cancelled;
    if (cancelled) owner->_interrupt();
    [sessionCondition unlock];
    return cancelled;
}

+ (void)cleanupActiveDecoder {
    [sessionCondition lock];
    ConnectionLifecycle *owner = sessionOwner;
    [sessionCondition unlock];
    [owner cleanupDecoderOnce];
}

- (void)cleanupDecoderOnce {
    [sessionCondition lock];
    dispatch_block_t cleanup = _cleanup;
    _cleanup = nil;
    [sessionCondition unlock];
    if (cleanup) {
        cleanup();
        [sessionCondition lock];
        _cleanupFinished = YES;
        [sessionCondition unlock];
        [self deliverStopCompletionsIfReady];
    }
}

- (void)deliverStopCompletionsIfReady {
    [sessionCondition lock];
    NSArray<dispatch_block_t> *completions = nil;
    if (_retired && _cleanupFinished) {
        _finished = YES;
        completions = [_stopCompletions copy];
        [_stopCompletions removeAllObjects];
    }
    [sessionCondition unlock];
    for (dispatch_block_t completion in completions) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), completion);
    }
}

- (void)cancelWithCompletion:(dispatch_block_t)completion {
    [sessionCondition lock];
    BOOL finished = _finished;
    if (!finished) [_stopCompletions addObject:[completion copy]];
    [sessionCondition unlock];
    if (finished) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), completion);
    }
    [self cancel];
}

- (void)cancel {
    [sessionCondition lock];
    if (_cancelled) {
        [sessionCondition unlock];
        return;
    }
    _cancelled = YES;
    BOOL ownsSession = sessionOwner == self;
    if (!ownsSession) _retired = YES;
    if (ownsSession) {
        // Owner identity cannot change while this interrupt is issued, so a
        // retiring connection can never interrupt a newer C session.
        _interrupt();
    }
    [sessionCondition broadcast];
    [sessionCondition unlock];

    if (ownsSession) {
        // Never stop C synchronously from one of its callbacks. The engine lock
        // also waits for start to return before invoking stop.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [engineLock lock];
            [self finishSession];
            [engineLock unlock];
        });
    } else {
        // Unstarted/waiting connections own only their own decoder. They must
        // not call the global C stop or change the current owner's globals.
        [self cleanupDecoderOnce];
        [self deliverStopCompletionsIfReady];
    }
}

- (void)runWithContext:(id)context
              prepare:(dispatch_block_t)prepare
                start:(int (^)(void))start
                 stop:(dispatch_block_t)stop
             teardown:(dispatch_block_t)teardown {
    [sessionCondition lock];
    if (_runRequested) {
        [sessionCondition unlock];
        return;
    }
    _runRequested = YES;
    while (sessionOwner && !_cancelled) [sessionCondition wait];
    if (_cancelled) {
        [sessionCondition unlock];
        [self cleanupDecoderOnce];
        return;
    }
    sessionOwner = self;
    _context = context;
    _stop = [stop copy];
    _teardown = [teardown copy];
    [sessionCondition unlock];

    [engineLock lock];
    [sessionCondition lock];
    BOOL mayStart = sessionOwner == self && !_cancelled;
    [sessionCondition unlock];
    if (mayStart) {
        prepare();
        [sessionCondition lock];
        mayStart = !_cancelled;
        if (mayStart) _engineEntered = YES;
        [sessionCondition unlock];
    }
    if (!mayStart) {
        [self finishSession];
        [engineLock unlock];
        return;
    }

    int result = start();
    [sessionCondition lock];
    BOOL shouldFinish = result != 0 || _cancelled;
    [sessionCondition unlock];
    if (shouldFinish) [self finishSession];
    [engineLock unlock];
}

// Must run with engineLock held. Ownership remains assigned until all C work
// and renderer cleanup have completed; queued stale finish calls become no-ops.
- (void)finishSession {
    [sessionCondition lock];
    if (sessionOwner != self) {
        [sessionCondition unlock];
        return;
    }
    BOOL entered = _engineEntered;
    _finishing = YES;
    dispatch_block_t stop = _stop;
    dispatch_block_t teardown = _teardown;
    [sessionCondition unlock];

    if (entered && stop) stop();
    [self cleanupDecoderOnce];
    if (teardown) teardown();

    [sessionCondition lock];
    _context = nil;
    _stop = nil;
    _teardown = nil;
    sessionOwner = nil;
    _retired = YES;
    [sessionCondition broadcast];
    [sessionCondition unlock];
    [self deliverStopCompletionsIfReady];
}
@end
