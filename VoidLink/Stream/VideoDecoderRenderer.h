//
//  VideoDecoderRenderer.h
//  Moonlight
//
//  Created by Cameron Gutman on 10/18/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import AVFoundation;

#import "ConnectionCallbacks.h"
#import "FrameQueue.h"
#import "Plot.h"

#include "Limelight.h"

@class TemporarySettings;

@interface VideoDecoderRenderer : NSObject

@property (atomic, readonly) PlotMetrics decodeMetrics;
@property (atomic, readonly) PlotMetrics frameQueueMetrics;
@property (atomic, assign) bool needRequeuing;
@property (nonatomic, strong) FrameQueue* frameQueue;
@property (atomic, readonly) int32_t queueSize;

@property (nonatomic, strong, readonly) AVSampleBufferDisplayLayer *displayLayer;
// Glasses output (including 2D) uses one Metal consumer for independent eye layout.
// Configure before setupWithVideoFormat: so decoder pacing matches the connection.
@property (nonatomic) BOOL stereoPresentation;

- (id)initWithView:(UIView*)view callbacks:(id<ConnectionCallbacks>)callbacks streamAspectRatio:(float)aspectRatio;
// A resolved connection snapshot keeps per-PC pacing/backend choices independent
// of subsequent global-default edits. Nil preserves the legacy initializer.
- (id)initWithView:(UIView*)view callbacks:(id<ConnectionCallbacks>)callbacks
 streamAspectRatio:(float)aspectRatio presentationSettings:(TemporarySettings * _Nullable)settings;
// Called only after Connection owns the process-wide streaming session.
- (void)activateForStreaming;

- (void)setupWithVideoFormat:(int)videoFormat width:(int)videoWidth height:(int)videoHeight frameRate:(int)frameRate fullRange:(BOOL)fullRange request10BitCodec:(BOOL)enableHdr;

- (void)renderFrame:(Frame *)frame atTime:(CMTime)targetTime;
// Retires main-thread display callbacks before common tears down its video queue.
- (void)stop;
- (void)cleanup;
- (void)setHdrMode:(BOOL)enabled;
- (void)safeCopyMetricsTo:(PlotMetrics *)dst from:(PlotMetrics *)src;
- (void)getAllStats:(video_stats_t *)stats;
- (uint64_t)renderedInterpolatedFrameCount;
// Clears only this active renderer's presentation queue, never a successor's.
- (void)setRequeuingRequired:(BOOL)required;
- (void)resetFramePacing;
// Called after the stream controller resolves whether PiP remains active.
- (void)setDecodingPausedForBackground:(BOOL)paused;

- (int)submitDecodeBuffer:(unsigned char *)data
                   length:(int)length
               bufferType:(int)bufferType
               decodeUnit:(PDECODE_UNIT)du
          decodeStartTime:(CFTimeInterval)decodeStartTime;

- (OSStatus)decodeFrameWithSampleBuffer:(CMSampleBufferRef)sampleBuffer
                            frameNumber:(int)frameNumber
                              frameType:(int)frameType
                        decodeStartTime:(CFTimeInterval)decodeStartTime;

- (void)invalidateDecompressionSession;
+ (void)setFrameInterpolationEnabled:(bool)enabled;
+ (void)startOrRestartFrameInterpolation;
+ (void)stopFrameInterpolation;

@end
