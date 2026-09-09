//
//  FrameQueue.h
//  Moonlight
//
//  Created by Andy Grundman.
//  Ported to VoidLink by Acaki.
//  Copyright (c) 2025 Moonlight Stream. All rights reserved.
//
//  Modified by True砖家 since 2026/8/12.
//  Copyright © 2026 True砖家 on Bilibili. All rights reserved.
//
//


#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

#import "Frame.h"
#import "FloatBuffer.h"

NS_ASSUME_NONNULL_BEGIN

@interface FrameQueue : NSObject

@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic) FloatBuffer *frameDropMetrics;
@property (nonatomic) int highWaterMark;
@property (nonatomic, readonly) int maxCapacity;
@property (atomic) BOOL paused;
- (void)dequeueWithTimeout:(CFTimeInterval)timeout
                completion:(void (^)(Frame *frame))completion;
// Waiting ends with nil when this owner is stopped or replaced.
- (void)dequeueWithTimeout:(CFTimeInterval)timeout
                    owner:(id)owner
               completion:(void (^)(Frame * _Nullable frame))completion;

+ (instancetype)sharedInstance;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (BOOL)isEmpty;
- (void)clear;
- (int)enqueue:(Frame *)frame;
- (int)enqueue:(Frame *)frame withSlackSize:(int)slack;
// Rejects callbacks from a replaced/stopped session without changing its successor.
// Returns one dropped frame on rejection, leaving current queue metrics untouched.
- (int)enqueue:(Frame *)frame withSlackSize:(int)slack owner:(id)owner;
- (nullable Frame *)dequeue;
- (nullable Frame *)dequeueWithTimeoutSync:(CFTimeInterval)timeout;
- (nullable Frame *)dequeueWithTimeoutSync:(CFTimeInterval)timeout owner:(id)owner;
// Captures the current queue owner and never consumes a replacement's frames.
- (nullable Frame *)dequeueWithTimeoutSync:(CFTimeInterval)timeout untilCancelled:(BOOL (^)(void))isCancelled;
- (CFTimeInterval)estimatedFramerate;
- (int)currentSoftCap;
- (void)waitForEnqueue;
- (void)waitForEnqueueUntilCancelled:(BOOL (^)(void))isCancelled;
// Metal may start before the decoder owns an active queue. Wait through pause.
- (void)waitForActiveEnqueueUntilCancelled:(BOOL (^)(void))isCancelled;
// Records a decoded image discarded before enqueue (e.g. interpolation backlog).
- (void)recordDroppedFrameForOwner:(id)owner;
- (void)startForOwner:(id)owner;
- (void)stopForOwner:(id)owner;

@end

NS_ASSUME_NONNULL_END
