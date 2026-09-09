#import "frame_queue_tests.h"
#import "FrameQueue.h"
#include <Limelight.h>

static void RequireQueue(BOOL condition, NSString *message) {
    if (!condition) [NSException raise:@"FrameQueueAssertion" format:@"%@", message];
}

static Frame *QueueTestFrame(int number, int type) {
    return [[Frame alloc] initWithPixelBufffer:NULL frameNumber:number frameType:type
                                         pts:CMTimeMake(number * 1500, 90000)];
}

void SunlightRunFrameQueueTests(void (^run)(NSString *name, void (^body)(void))) {
    run(@"FrameQueue empty waits do not consume historical dequeue notifications", ^{
        FrameQueue *queue = FrameQueue.sharedInstance;
        NSObject *owner = [NSObject new];
        [queue startForOwner:owner];
        @try {
            for (int number = 0; number < 256; number++) {
                [queue enqueue:QueueTestFrame(number, FRAME_TYPE_IDR)];
                RequireQueue(queue.dequeue.frameNumber == number, @"Each frame must be consumed directly");
            }
            CFTimeInterval began = CACurrentMediaTime();
            __block int cancellationChecks = 0;
            [queue waitForEnqueueUntilCancelled:^BOOL{ return ++cancellationChecks == 3; }];
            RequireQueue(CACurrentMediaTime() - began >= 0.15,
                         @"An empty queue must sleep between cancellation checks instead of draining historical permits");
        } @finally {
            [queue stopForOwner:owner];
        }
    });

    run(@"FrameQueue clear discards wakeups for frames it removes", ^{
        FrameQueue *queue = FrameQueue.sharedInstance;
        NSObject *owner = [NSObject new];
        [queue startForOwner:owner];
        @try {
            for (int number = 0; number < queue.maxCapacity; number++) {
                [queue enqueue:QueueTestFrame(number, FRAME_TYPE_IDR)];
            }
            [queue clear];
            CFTimeInterval began = CACurrentMediaTime();
            __block int cancellationChecks = 0;
            [queue waitForEnqueueUntilCancelled:^BOOL{ return ++cancellationChecks == 3; }];
            RequireQueue(CACurrentMediaTime() - began >= 0.15,
                         @"Removed frames must not cause immediate wakeups in the next empty wait");
        } @finally {
            [queue stopForOwner:owner];
        }
    });

    run(@"FrameQueue wakes for a new frame after its previous queue is drained", ^{
        FrameQueue *queue = FrameQueue.sharedInstance;
        NSObject *owner = [NSObject new];
        [queue startForOwner:owner];
        dispatch_semaphore_t entered = dispatch_semaphore_create(0);
        dispatch_semaphore_t finished = dispatch_semaphore_create(0);
        for (int number = 0; number < 32; number++) {
            [queue enqueue:QueueTestFrame(number, FRAME_TYPE_IDR)];
            (void)queue.dequeue;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool {
                __block BOOL firstCheck = YES;
                [queue waitForEnqueueUntilCancelled:^BOOL{
                    if (firstCheck) {
                        firstCheck = NO;
                        dispatch_semaphore_signal(entered);
                    }
                    return NO;
                }];
                dispatch_semaphore_signal(finished);
            }
        });
        @try {
            RequireQueue(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0,
                         @"Consumer must enter its empty wait");
            [queue enqueue:QueueTestFrame(99, FRAME_TYPE_IDR)];
            RequireQueue(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0,
                         @"New enqueue must wake the waiting consumer");
            RequireQueue(queue.dequeue.frameNumber == 99, @"Wakeup must leave the new frame available to dequeue");
        } @finally {
            [queue stopForOwner:owner];
        }
    });

    run(@"FrameQueue bounds an IDR burst and retains newest frames in order", ^{
        FrameQueue *queue = FrameQueue.sharedInstance;
        NSObject *owner = [NSObject new];
        [queue startForOwner:owner];
        @try {
            int capacity = queue.maxCapacity;
            int drops = 0;
            for (int number = 0; number < capacity * 3; number++) {
                drops += [queue enqueue:QueueTestFrame(number, FRAME_TYPE_IDR)];
                RequireQueue(queue.count <= (NSUInteger)capacity, @"IDR bypass must not overflow the ring's allocation");
            }
            RequireQueue(drops == capacity * 2, @"Evicted presentation frames must be included in drop metrics");
            for (int number = capacity * 2; number < capacity * 3; number++) {
                Frame *frame = queue.dequeue;
                RequireQueue(frame && frame.frameNumber == number, @"Full-ring replacement must preserve chronological order");
            }
            RequireQueue(queue.isEmpty && !queue.dequeue, @"Drained ring must be empty without duplicate or null entries");
        } @finally {
            [queue stopForOwner:owner];
        }
    });

    run(@"FrameQueue bounds a mixed burst when the oldest frame is an IDR", ^{
        FrameQueue *queue = FrameQueue.sharedInstance;
        NSObject *owner = [NSObject new];
        int originalHighWaterMark = queue.highWaterMark;
        [queue startForOwner:owner];
        @try {
            queue.highWaterMark = queue.maxCapacity;
            for (int number = 0; number < queue.maxCapacity; number++) {
                [queue enqueue:QueueTestFrame(number, FRAME_TYPE_IDR)];
            }
            RequireQueue([queue enqueue:QueueTestFrame(100, FRAME_TYPE_PFRAME)] == 1, @"First full-queue delta frame should be dropped");
            RequireQueue([queue enqueue:QueueTestFrame(101, FRAME_TYPE_PFRAME)] == 1, @"Next delta frame must evict once even with an IDR at the head");
            RequireQueue(queue.count == (NSUInteger)queue.maxCapacity, @"IDR preservation must not bypass the hard capacity");
            Frame *last = nil;
            while (!queue.isEmpty) last = queue.dequeue;
            RequireQueue(last.frameNumber == 101, @"Newest accepted frame must be retained");
        } @finally {
            queue.highWaterMark = originalHighWaterMark;
            [queue stopForOwner:owner];
        }
    });

    run(@"FrameQueue empty wait cancels without stopping the current queue", ^{
        FrameQueue *queue = FrameQueue.sharedInstance;
        NSObject *owner = [NSObject new];
        [queue startForOwner:owner];
        dispatch_semaphore_t entered = dispatch_semaphore_create(0);
        dispatch_semaphore_t cancel = dispatch_semaphore_create(0);
        dispatch_semaphore_t finished = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool {
                BOOL __block firstCheck = YES;
                [queue waitForEnqueueUntilCancelled:^BOOL{
                    if (firstCheck) {
                        firstCheck = NO;
                        dispatch_semaphore_signal(entered);
                    }
                    return dispatch_semaphore_wait(cancel, DISPATCH_TIME_NOW) == 0;
                }];
                dispatch_semaphore_signal(finished);
            }
        });
        @try {
            RequireQueue(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0,
                         @"Consumer must enter the empty wait");
            RequireQueue(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_MSEC)) != 0,
                         @"Empty active queue should wait before cancellation");
            dispatch_semaphore_signal(cancel);
            RequireQueue(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0,
                         @"A cancelled renderer must leave the wait even while the shared queue stays active");
            RequireQueue(!queue.paused, @"Cancelling one consumer must preserve the queue's current session");
        } @finally {
            dispatch_semaphore_signal(cancel);
            [queue stopForOwner:owner];
        }
    });

    run(@"FrameQueue ignores a stale owner's stop after session replacement", ^{
        FrameQueue *queue = FrameQueue.sharedInstance;
        NSObject *oldOwner = [NSObject new];
        NSObject *newOwner = [NSObject new];
        [queue startForOwner:oldOwner];
        [queue startForOwner:newOwner];
        @try {
            [queue enqueue:QueueTestFrame(42, FRAME_TYPE_IDR)];
            [queue stopForOwner:oldOwner];
            RequireQueue(!queue.paused && queue.dequeue.frameNumber == 42,
                         @"Old teardown must not pause or clear the replacement session");
        } @finally {
            [queue stopForOwner:newOwner];
        }
    });

    run(@"FrameQueue rejects late frames from a replaced or stopped owner", ^{
        FrameQueue *queue = FrameQueue.sharedInstance;
        NSObject *oldOwner = [NSObject new];
        NSObject *newOwner = [NSObject new];
        [queue startForOwner:oldOwner];
        RequireQueue([queue enqueue:QueueTestFrame(10, FRAME_TYPE_IDR) withSlackSize:3 owner:oldOwner] == 0,
                     @"Original owner must enqueue while active");
        [queue startForOwner:newOwner];
        @try {
            RequireQueue(queue.isEmpty, @"Replacement must discard the previous session's frames");
            RequireQueue([queue enqueue:QueueTestFrame(42, FRAME_TYPE_IDR) withSlackSize:3 owner:newOwner] == 0,
                         @"Current owner must enqueue into the replacement queue");
            FloatBuffer *metrics = queue.frameDropMetrics;
            int metricCount = metrics.count;
            RequireQueue([queue enqueue:QueueTestFrame(11, FRAME_TYPE_IDR) withSlackSize:3 owner:oldOwner] == 1,
                         @"A late old-owner callback must report its frame rejected");
            RequireQueue(queue.count == 1 && queue.frameDropMetrics == metrics && metrics.count == metricCount,
                         @"Rejected old frames must leave current queue contents and metrics unchanged");
            RequireQueue([queue enqueue:QueueTestFrame(43, FRAME_TYPE_IDR) withSlackSize:3 owner:newOwner] == 0,
                         @"Current owner must still enqueue after a stale callback");
            RequireQueue(queue.dequeue.frameNumber == 42 && queue.dequeue.frameNumber == 43 && queue.isEmpty,
                         @"Only current-owner frames may reach the consumer, in their original order");
            [queue stopForOwner:newOwner];
            RequireQueue([queue enqueue:QueueTestFrame(44, FRAME_TYPE_IDR) withSlackSize:3 owner:newOwner] == 1
                         && queue.isEmpty && queue.frameDropMetrics.count == 0,
                         @"A callback after stop must not refill the paused queue");
        } @finally {
            [queue stopForOwner:newOwner];
        }
    });

    run(@"FrameQueue pending old-owner dequeue cannot consume a replacement frame", ^{
        FrameQueue *queue = FrameQueue.sharedInstance;
        NSObject *oldOwner = [NSObject new];
        NSObject *newOwner = [NSObject new];
        dispatch_semaphore_t entered = dispatch_semaphore_create(0);
        dispatch_semaphore_t finished = dispatch_semaphore_create(0);
        __block Frame *oldFrame = nil;
        [queue startForOwner:oldOwner];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            dispatch_semaphore_signal(entered);
            oldFrame = [queue dequeueWithTimeoutSync:1 owner:oldOwner];
            dispatch_semaphore_signal(finished);
        });
        @try {
            RequireQueue(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0,
                         @"Old consumer must start its dequeue");
            RequireQueue(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC)) != 0,
                         @"Old consumer must remain pending on its empty active queue");
            [queue startForOwner:newOwner];
            [queue enqueue:QueueTestFrame(42, FRAME_TYPE_IDR) withSlackSize:3 owner:newOwner];
            RequireQueue(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC)) == 0,
                         @"Replacement must end the old wait before its timeout");
            RequireQueue(oldFrame == nil && queue.count == 1,
                         @"Old consumer must return nil and leave the successor's frame queued");
            Frame *currentFrame = [queue dequeueWithTimeoutSync:0 owner:newOwner];
            RequireQueue(currentFrame.frameNumber == 42 && queue.isEmpty,
                         @"Current consumer must receive its frame even with a zero timeout");
            [queue stopForOwner:newOwner];
            RequireQueue([queue dequeueWithTimeoutSync:1 owner:newOwner] == nil,
                         @"Stopped consumers must leave immediately without taking another frame");
        } @finally {
            [queue stopForOwner:newOwner];
        }
    });

    run(@"FrameQueue active wait sleeps while paused and resumes for the first frame", ^{
        FrameQueue *queue = FrameQueue.sharedInstance;
        NSObject *owner = [NSObject new];
        [queue startForOwner:owner];
        [queue stopForOwner:owner];
        // Discard the intentional stop wakeup before measuring a paused wait.
        [queue clear];
        CFTimeInterval began = CACurrentMediaTime();
        __block int checks = 0;
        [queue waitForActiveEnqueueUntilCancelled:^BOOL{ return ++checks == 3; }];
        RequireQueue(CACurrentMediaTime() - began >= 0.15 && queue.paused,
                     @"Paused startup/retirement must sleep instead of repeatedly invoking the Metal loop");
        dispatch_semaphore_t entered = dispatch_semaphore_create(0), finished = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            __block BOOL first = YES;
            [queue waitForActiveEnqueueUntilCancelled:^BOOL{
                if (first) { first = NO; dispatch_semaphore_signal(entered); }
                return NO;
            }];
            dispatch_semaphore_signal(finished);
        });
        @try {
            RequireQueue(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0,
                         @"Consumer enters the paused wait");
            RequireQueue(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_MSEC)) != 0,
                         @"Paused queue does not appear ready");
            [queue startForOwner:owner];
            [queue enqueue:QueueTestFrame(80, FRAME_TYPE_IDR) withSlackSize:3 owner:owner];
            RequireQueue(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0,
                         @"First active frame wakes the waiting Metal consumer");
            RequireQueue([queue dequeueWithTimeoutSync:0 untilCancelled:^BOOL{ return NO; }].frameNumber == 80,
                         @"Active wait leaves the first image available");
        } @finally { [queue stopForOwner:owner]; }
    });

    run(@"FrameQueue timed dequeue sleeps and checks cancellation before consuming", ^{
        FrameQueue *queue = FrameQueue.sharedInstance;
        NSObject *owner = [NSObject new];
        [queue startForOwner:owner];
        @try {
            CFTimeInterval began = CACurrentMediaTime();
            __block int checks = 0;
            Frame *frame = [queue dequeueWithTimeoutSync:5 untilCancelled:^BOOL{ return ++checks == 3; }];
            RequireQueue(frame == nil && CACurrentMediaTime() - began >= 0.15 && checks == 3,
                         @"Timed consumer uses bounded semaphore waits instead of 100-microsecond polling");
            [queue enqueue:QueueTestFrame(90, FRAME_TYPE_IDR) withSlackSize:3 owner:owner];
            RequireQueue([queue dequeueWithTimeoutSync:0 untilCancelled:^BOOL{ return YES; }] == nil && queue.count == 1,
                         @"Renderer cancellation leaves a ready image untouched");
            RequireQueue([queue dequeueWithTimeoutSync:0 untilCancelled:^BOOL{ return NO; }].frameNumber == 90,
                         @"Current uncancelled consumer can still receive the image");
        } @finally { [queue stopForOwner:owner]; }
    });

    run(@"FrameQueue Metal timed wait captures owner before session replacement", ^{
        FrameQueue *queue = FrameQueue.sharedInstance;
        NSObject *oldOwner = [NSObject new], *newOwner = [NSObject new];
        [queue startForOwner:oldOwner];
        dispatch_semaphore_t entered = dispatch_semaphore_create(0), finished = dispatch_semaphore_create(0);
        __block Frame *result;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            __block BOOL first = YES;
            result = [queue dequeueWithTimeoutSync:5 untilCancelled:^BOOL{
                if (first) { first = NO; dispatch_semaphore_signal(entered); }
                return NO;
            }];
            dispatch_semaphore_signal(finished);
        });
        @try {
            RequireQueue(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0,
                         @"Metal consumer has captured its original queue owner");
            [queue startForOwner:newOwner];
            [queue enqueue:QueueTestFrame(91, FRAME_TYPE_IDR) withSlackSize:3 owner:newOwner];
            RequireQueue(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0,
                         @"Changing owner wakes or expires the old bounded wait");
            RequireQueue(result == nil && queue.count == 1,
                         @"Old Metal consumer does not take the successor's frame");
            RequireQueue([queue dequeueWithTimeoutSync:0 owner:newOwner].frameNumber == 91,
                         @"Successor receives its intact first frame");
        } @finally { [queue stopForOwner:newOwner]; }
    });

    run(@"FrameQueue interpolation drops count only for the active owner", ^{
        FrameQueue *queue = FrameQueue.sharedInstance;
        NSObject *oldOwner = [NSObject new], *newOwner = [NSObject new];
        [queue startForOwner:oldOwner];
        [queue recordDroppedFrameForOwner:oldOwner];
        RequireQueue(queue.frameDropMetrics.count == 1 && queue.frameDropMetrics.averageValue == 1,
                     @"Pre-enqueue interpolation drop appears in actual queue drop statistics");
        [queue startForOwner:newOwner];
        @try {
            [queue recordDroppedFrameForOwner:oldOwner];
            RequireQueue(queue.frameDropMetrics.count == 0 && queue.isEmpty,
                         @"Late interpolation rejection does not change a successor's metrics");
            [queue recordDroppedFrameForOwner:newOwner];
            RequireQueue(queue.frameDropMetrics.count == 1 && queue.isEmpty,
                         @"Drop accounting must not manufacture a presentation frame");
            [queue stopForOwner:newOwner];
            [queue recordDroppedFrameForOwner:newOwner];
            RequireQueue(queue.frameDropMetrics.count == 0, @"Stopped owner cannot add delayed drop statistics");
        } @finally { [queue stopForOwner:newOwner]; }
    });

}
