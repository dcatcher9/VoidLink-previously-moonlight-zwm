#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <VideoToolbox/VideoToolbox.h>
#import "Frame.h"
#import "SunlightDecoderRecovery.h"
#include <Limelight.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

// Actual production methods are inserted unchanged by the runner. Only the
// UIKit surface, interpolator and queue mutations are controlled boundaries.
#define Log(...) do {} while (0)
enum { RENDER_AVSB, RENDER_METAL };
@interface UIColor : NSObject
@property(readonly) CGColorRef CGColor;
+ (instancetype)blackColor;
@end
@implementation UIColor
+ (instancetype)blackColor { return [self new]; }
- (CGColorRef)CGColor { return CGColorGetConstantColor(kCGColorBlack); }
@end

@interface PresentationView : NSObject
@property CGRect bounds;
@property CALayer *layer;
@end
@implementation PresentationView @end

@interface TemporarySettings : NSObject
@property NSNumber *interpolationMaximumDimension;
@property NSNumber *interpolationMaximumPixelCount;
@property NSNumber *frameQueueSize;
@end
@implementation TemporarySettings @end
@interface DataManager : NSObject
- (TemporarySettings *)getSettings;
@end
@implementation DataManager
- (TemporarySettings *)getSettings { abort(); }
@end

enum { PLOT_HOST_FRAMETIME };
@interface ImGuiPlots : NSObject
@property NSMutableArray<NSNumber *> *hostFrameTimes;
+ (instancetype)sharedInstance;
- (void)observeFloat:(int)plotId value:(CFTimeInterval)value;
@end
@implementation ImGuiPlots
+ (instancetype)sharedInstance {
    static ImGuiPlots *plots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ plots = [self new]; plots.hostFrameTimes = [NSMutableArray array]; });
    return plots;
}
- (void)observeFloat:(int)plotId value:(CFTimeInterval)value {
    if (plotId == PLOT_HOST_FRAMETIME) [self.hostFrameTimes addObject:@(value)];
}
@end

static unsigned requestedIDRs;
void LiRequestIdrFrame(void) { requestedIDRs++; }
@interface FailedPresentationLayer : AVSampleBufferDisplayLayer
@property BOOL failed;
@property NSUInteger flushes;
@end
@implementation FailedPresentationLayer
- (AVQueuedSampleBufferRenderingStatus)status {
    return self.failed ? AVQueuedSampleBufferRenderingStatusFailed : AVQueuedSampleBufferRenderingStatusRendering;
}
- (void)flushAndRemoveImage { self.flushes++; self.failed = NO; }
@end

static unsigned createdInterpolators;
@interface FrameInterpolator : NSObject
@property BOOL isEnabled;
@property(copy) void (^transientHUDHandler)(NSString *);
@property NSUInteger resets;
- (instancetype)initWithMaximumDimension:(NSInteger)dimension maximumPixelCount:(NSInteger)count;
- (void)reset;
@end
@implementation FrameInterpolator
- (instancetype)initWithMaximumDimension:(NSInteger)dimension maximumPixelCount:(NSInteger)count {
    (void)dimension; (void)count;
    self = [super init];
    if (self) createdInterpolators++;
    return self;
}
- (void)reset { self.resets++; }
@end

@interface PresentationQueue : NSObject
@property int highWaterMark;
@property NSUInteger clears;
- (void)clear;
@end
@implementation PresentationQueue
- (void)clear { self.clears++; }
@end

@protocol ConnectionCallbacks <NSObject>
- (void)updateTransientHUDText:(NSString *)text;
@end
@interface PresentationSink : NSObject <ConnectionCallbacks>
@property NSUInteger deliveries;
@property NSString *lastText;
@end
@implementation PresentationSink
- (void)updateTransientHUDText:(NSString *)text { self.deliveries++; self.lastText = text; }
@end

@interface VideoDecoderRenderer : NSObject {
@public
    id<ConnectionCallbacks> _callbacks;
    PresentationView *_view;
    AVSampleBufferDisplayLayer *_displayLayer;
    atomic_bool _cleanupRequested, _appInBackground;
    BOOL _hasLastDecodedFramePTS;
    CFTimeInterval _lastDecodedFramePTS;
    _Atomic(float) _streamAspectRatio;
    int _renderingBackend;
    CMVideoFormatDescriptionRef _formatDesc, _formatDescImageBuffer;
    SunlightDecoderRecovery _decoderRecovery;
    dispatch_queue_t _vtq;
    id _displayLink;
    TemporarySettings *_presentationSettings;
    FrameInterpolator *_frameInterpolator;
    BOOL _frameInterpolationPaused, _activatedForStreaming, _needRequeuing;
    int32_t _queueSize;
    PresentationQueue *_frameQueue;
    NSUInteger _invalidations, _displayRestarts;
    BOOL _lastRestartEnabled;
}
- (FrameInterpolator *)newFrameInterpolatorWithMaximumDimension:(NSInteger)dimension maximumPixelCount:(NSInteger)count;
- (void)setRequeuingRequired:(BOOL)required;
- (void)checkDisplayLayer;
- (void)recordIncomingFrameTiming:(Frame *)frame;
- (void)updateDisplayLayerLayout;
- (void)startOrRestartFrameInterpolation;
- (void)stopFrameInterpolation;
- (void)invalidateDecompressionSession;
- (void)restartDisplayLinkForInterpolationEnabled:(BOOL)enabled;
- (Frame *)frameForDecodedImage:(CVImageBufferRef)imageBuffer
             formatDescription:(CMVideoFormatDescriptionRef)formatDescription
                     timestamp:(CMTime)timestamp duration:(CMTime)duration
                   frameNumber:(int)frameNumber frameType:(int)frameType status:(OSStatus *)status;
@end
@implementation VideoDecoderRenderer
- (instancetype)init {
    self = [super init];
    if (self) {
        _view = [PresentationView new];
        _view.layer = [CALayer layer];
        _view.bounds = CGRectMake(0, 0, 2622, 1206);
        _vtq = dispatch_queue_create("decoder-presentation-tests", DISPATCH_QUEUE_SERIAL);
        _frameQueue = [PresentationQueue new];
        _displayLink = [NSObject new];
        _presentationSettings = [TemporarySettings new];
        _presentationSettings.interpolationMaximumDimension = @1920;
        _presentationSettings.interpolationMaximumPixelCount = @2073600;
        _presentationSettings.frameQueueSize = @2;
        _decoderRecovery = SunlightDecoderRecoveryInitial();
        atomic_init(&_cleanupRequested, false);
        atomic_init(&_streamAspectRatio, 16.0f / 9);
    }
    return self;
}
- (void)dealloc {
    if (_formatDesc) CFRelease(_formatDesc);
    if (_formatDescImageBuffer) CFRelease(_formatDescImageBuffer);
}
- (void)invalidateDecompressionSession {
    _invalidations++;
    SunlightDecoderRecoveryInvalidate(&_decoderRecovery);
}
- (void)restartDisplayLinkForInterpolationEnabled:(BOOL)enabled {
    _displayRestarts++; _lastRestartEnabled = enabled;
}
// SUNLIGHT_ACTUAL_DECODER_PRESENTATION_METHODS
@end

static unsigned checks;
static void check(BOOL condition, const char *message) {
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); abort(); }
}
static CVPixelBufferRef pixelBuffer(size_t width, size_t height) {
    CVPixelBufferRef result = NULL;
    check(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, NULL, &result) == noErr,
          "create actual decoded pixel buffer");
    return result;
}
static CMVideoFormatDescriptionRef descriptionFor(CVPixelBufferRef image) {
    CMVideoFormatDescriptionRef result = NULL;
    check(CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, image, &result) == noErr,
          "create actual frame format metadata");
    return result;
}
static void drain(VideoDecoderRenderer *renderer) { dispatch_sync(renderer->_vtq, ^{}); }
static void waitForPresentation(dispatch_semaphore_t signal) {
    check(dispatch_semaphore_wait(signal, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0,
          "reach controlled presentation boundary");
}

static void testOwnedFrames(void) {
    VideoDecoderRenderer *renderer = [VideoDecoderRenderer new];
    renderer->_renderingBackend = RENDER_METAL;
    CVPixelBufferRef first = pixelBuffer(64, 32);
    CMVideoFormatDescriptionRef firstFormat = descriptionFor(first);
    CMTime pts = CMTimeMake(123456, 90000), duration = CMTimeMake(1500, 90000);
    OSStatus status = -1;
    Frame *metal = [renderer frameForDecodedImage:first formatDescription:firstFormat timestamp:pts duration:duration
                                     frameNumber:42 frameType:1 status:&status];
    check(metal && status == noErr && metal.sampleBuffer == NULL && metal.pixelBuffer == first && metal.formatDesc == firstFormat,
          "Metal handoff owns the actual image and its matching description without a sample-buffer copy");
    CFRelease(firstFormat);
    CVPixelBufferRelease(first);
    // The callback's borrowed references are gone before the presentation queue
    // reads the frame, as happens during an IDR/format switch or retirement.
    __block Frame *queuedFrame;
    dispatch_async(renderer->_vtq, ^{ queuedFrame = metal; });
    drain(renderer);
    check(queuedFrame.width == 64 && queuedFrame.height == 32 &&
          CMVideoFormatDescriptionGetDimensions(queuedFrame.formatDesc).width == 64 &&
          CMTimeCompare(queuedFrame.pts90, pts) == 0 && queuedFrame.frameNumber == 42,
          "queued frame remains valid after the decode callback releases its references");

    CVPixelBufferRef second = pixelBuffer(128, 64);
    CMVideoFormatDescriptionRef secondFormat = descriptionFor(second);
    Frame *later = [renderer frameForDecodedImage:second formatDescription:secondFormat timestamp:CMTimeAdd(pts, duration)
                                       duration:duration frameNumber:43 frameType:1 status:&status];
    check(CMVideoFormatDescriptionGetDimensions(later.formatDesc).width == 128 &&
          CMVideoFormatDescriptionGetDimensions(queuedFrame.formatDesc).width == 64,
          "later format change cannot replace an earlier queued frame's metadata");

    renderer->_renderingBackend = RENDER_AVSB;
    Frame *sample = [renderer frameForDecodedImage:second formatDescription:secondFormat timestamp:pts duration:duration
                                      frameNumber:44 frameType:1 status:&status];
    check(sample && status == noErr && sample.sampleBuffer && !sample.pixelBuffer && sample.imageBuffer == second,
          "AVSB handoff packages the same decoded image with an owned sample buffer");
    check(CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sample.sampleBuffer), pts) == 0 &&
          CMTimeCompare(CMSampleBufferGetDuration(sample.sampleBuffer), duration) == 0 &&
          CMTIME_IS_INVALID(CMSampleBufferGetDecodeTimeStamp(sample.sampleBuffer)),
          "decoded sample timing keeps presentation/duration and has no compressed decode timestamp");
    CMVideoFormatDescriptionRef cached = renderer->_formatDescImageBuffer;
    Frame *sameFormat = [renderer frameForDecodedImage:second formatDescription:secondFormat timestamp:pts duration:kCMTimeInvalid
                                          frameNumber:45 frameType:0 status:&status];
    check(sameFormat && renderer->_formatDescImageBuffer == cached, "AVSB reuses matching image format metadata");
    CVPixelBufferRef third = pixelBuffer(32, 16);
    Frame *changedFormat = [renderer frameForDecodedImage:third formatDescription:NULL timestamp:pts duration:duration
                                             frameNumber:46 frameType:1 status:&status];
    check(changedFormat && renderer->_formatDescImageBuffer != cached &&
          CMVideoFormatDescriptionGetDimensions(renderer->_formatDescImageBuffer).width == 32 &&
          CMVideoFormatDescriptionGetDimensions(CMSampleBufferGetFormatDescription(sample.sampleBuffer)).width == 128,
          "AVSB replaces its cache on size change while pending samples retain their own format");
    CFRelease(secondFormat); CVPixelBufferRelease(second); CVPixelBufferRelease(third);
    check(CVPixelBufferGetWidth(sample.imageBuffer) == 128 && CVPixelBufferGetWidth(changedFormat.imageBuffer) == 32,
          "AVSB frames own decoded images after callback storage is released");
    check([renderer frameForDecodedImage:NULL formatDescription:NULL timestamp:pts duration:duration
                            frameNumber:47 frameType:0 status:&status] == nil && status == kVTVideoDecoderBadDataErr,
          "missing decoded image reports a recovery error rather than an empty frame");
}

static void testLayoutPreservesDecodeState(void) {
    VideoDecoderRenderer *renderer = [VideoDecoderRenderer new];
    CVPixelBufferRef image = pixelBuffer(64, 32);
    renderer->_formatDesc = descriptionFor(image);
    renderer->_formatDescImageBuffer = descriptionFor(image);
    CVPixelBufferRelease(image);
    CMVideoFormatDescriptionRef compressed = renderer->_formatDesc, decoded = renderer->_formatDescImageBuffer;
    SunlightDecoderRecoveryDecodedIDR(&renderer->_decoderRecovery);
    [renderer updateDisplayLayerLayout];
    check(renderer->_displayLayer.hidden && renderer->_view.layer.sublayers.count == 1,
          "initial layout creates one hidden loading layer");
    renderer->_displayLayer.hidden = NO;
    renderer->_view.bounds = CGRectMake(0, 0, 1920, 1080);
    [renderer updateDisplayLayerLayout];
    check(renderer->_formatDesc == compressed && renderer->_formatDescImageBuffer == decoded &&
          !renderer->_decoderRecovery.awaitingIDR && renderer->_invalidations == 0,
          "screen relayout preserves compressed/image metadata and recovered decoder state");
    check(!renderer->_displayLayer.hidden && renderer->_view.layer.sublayers.count == 1 &&
          fabs(renderer->_displayLayer.bounds.size.width - 1920) < 0.001 &&
          fabs(renderer->_displayLayer.bounds.size.height - 1080) < 0.001,
          "screen relayout moves the visible picture without hiding it or creating another consumer");
    FailedPresentationLayer *failed = [FailedPresentationLayer new];
    failed.failed = YES;
    renderer->_displayLayer = failed;
    [renderer checkDisplayLayer];
    check(failed.flushes == 1 && requestedIDRs == 0 && renderer->_invalidations == 0 &&
          renderer->_formatDesc == compressed && renderer->_formatDescImageBuffer == decoded,
          "failed AVSB presentation flushes without resetting healthy decode references or requesting another IDR");
    [renderer checkDisplayLayer];
    check(failed.flushes == 1, "healthy presentation does not repeatedly flush");
    CGRect previousBounds = renderer->_displayLayer.bounds;
    renderer->_cleanupRequested = true;
    renderer->_view.bounds = CGRectMake(0, 0, 640, 360);
    [renderer updateDisplayLayerLayout];
    check(CGRectEqualToRect(renderer->_displayLayer.bounds, previousBounds),
          "a queued layout request cannot modify a retired renderer");
}

static void testInterpolationRetirement(void) {
    VideoDecoderRenderer *renderer = [VideoDecoderRenderer new];
    renderer->_renderingBackend = RENDER_AVSB;
    [renderer startOrRestartFrameInterpolation]; drain(renderer);
    check(createdInterpolators == 0 && renderer->_frameQueue.clears == 0,
          "an unactivated decoder cannot modify the singleton presentation queue");
    renderer->_activatedForStreaming = YES;
    [renderer startOrRestartFrameInterpolation]; drain(renderer);
    check(createdInterpolators == 1 && renderer->_frameInterpolator.isEnabled && renderer->_queueSize == 8 &&
          renderer->_frameQueue.highWaterMark == 8 && renderer->_frameQueue.clears == 1 && renderer->_lastRestartEnabled,
          "active interpolation restart configures its queue and presentation cadence");
    check(renderer->_invalidations == 1 && renderer->_decoderRecovery.awaitingIDR && !renderer->_decoderRecovery.requestSent,
          "interpolation restart arms the existing coalesced decode recovery path");
    FrameInterpolator *previous = renderer->_frameInterpolator;
    [renderer stopFrameInterpolation]; drain(renderer);
    check(renderer->_frameInterpolator == nil && previous.resets == 1 && renderer->_queueSize == 2 &&
          renderer->_frameQueue.highWaterMark == 2 && renderer->_frameQueue.clears == 2 && !renderer->_lastRestartEnabled,
          "active stop restores the negotiated normal queue and retires its interpolator");

    dispatch_semaphore_t entered = dispatch_semaphore_create(0), release = dispatch_semaphore_create(0);
    dispatch_async(renderer->_vtq, ^{ dispatch_semaphore_signal(entered); dispatch_semaphore_wait(release, DISPATCH_TIME_FOREVER); });
    waitForPresentation(entered);
    [renderer startOrRestartFrameInterpolation];
    [renderer stopFrameInterpolation];
    @synchronized(renderer) { renderer->_cleanupRequested = true; }
    // Model the queue already being transferred to a successor while the old
    // renderer's deferred tasks are still awaiting their serial dispatch turn.
    renderer->_frameQueue.highWaterMark = 5;
    dispatch_semaphore_signal(release); drain(renderer);
    check(createdInterpolators == 1 && renderer->_frameQueue.clears == 2 && renderer->_frameQueue.highWaterMark == 5 &&
          renderer->_invalidations == 2 && renderer->_displayRestarts == 2,
          "queued old interpolation start/stop cannot reconfigure or clear the successor's queue");
}

static void testPresentationOwnerCallbacks(void) {
    VideoDecoderRenderer *renderer = [VideoDecoderRenderer new];
    PresentationSink *original = [PresentationSink new];
    renderer->_callbacks = original;
    FrameInterpolator *first = [renderer newFrameInterpolatorWithMaximumDimension:1920 maximumPixelCount:2073600];
    renderer->_frameInterpolator = first;
    first.transientHUDHandler(@"Running");
    check(original.deliveries == 1 && [original.lastText isEqualToString:@"Running"],
          "interpolator HUD targets its original renderer's callback sink");
    renderer->_frameInterpolator = [renderer newFrameInterpolatorWithMaximumDimension:1280 maximumPixelCount:921600];
    first.transientHUDHandler(nil);
    check(original.deliveries == 1, "delayed old-interpolator clear cannot erase replacement HUD text");
    renderer->_frameInterpolator.transientHUDHandler(@"New");
    check(original.deliveries == 2, "current interpolator still delivers its HUD");
    renderer->_cleanupRequested = true;
    renderer->_frameInterpolator.transientHUDHandler(@"Late");
    check(original.deliveries == 2, "retired decoder cannot deliver a delayed HUD into a later session");

    VideoDecoderRenderer *resize = [VideoDecoderRenderer new];
    resize->_queueSize = 2;
    [resize setRequeuingRequired:YES];
    check(resize->_frameQueue.clears == 0 && !resize->_needRequeuing,
          "deferred pre-activation resize cannot clear another renderer's queue");
    resize->_activatedForStreaming = YES;
    [resize setRequeuingRequired:YES];
    check(resize->_frameQueue.clears == 1 && resize->_needRequeuing,
          "active resize clears its own queue and requests refill");
    resize->_needRequeuing = NO;
    resize->_cleanupRequested = true;
    [resize setRequeuingRequired:YES];
    check(resize->_frameQueue.clears == 1 && !resize->_needRequeuing,
          "delayed retired resize does not clear a successor queue");
}

static Frame *timingFrame(int64_t ticks) {
    return [[Frame alloc] initWithPixelBufffer:NULL frameNumber:1 frameType:0 pts:CMTimeMake(ticks, 90000)];
}
static void testIncomingFrameTiming(void) {
    VideoDecoderRenderer *first = [VideoDecoderRenderer new];
    NSMutableArray<NSNumber *> *times = ImGuiPlots.sharedInstance.hostFrameTimes;
    [times removeAllObjects];
    [first recordIncomingFrameTiming:timingFrame(0)];
    [first recordIncomingFrameTiming:timingFrame(1500)];
    [first recordIncomingFrameTiming:timingFrame(3000)];
    check(times.count == 2 && fabs(times.lastObject.doubleValue - 1000.0 / 60) < 0.001,
          "incoming timing records normal cadence including a zero-origin first image");
    VideoDecoderRenderer *successor = [VideoDecoderRenderer new];
    [successor recordIncomingFrameTiming:timingFrame(0)];
    check(times.count == 2, "new decoder starts an independent timing baseline without a negative cross-session sample");
    [successor recordIncomingFrameTiming:timingFrame(750)];
    check(times.count == 3 && fabs(times.lastObject.doubleValue - 1000.0 / 120) < 0.001,
          "successor cadence is measured from its own incoming frames");
    [successor recordIncomingFrameTiming:timingFrame(400)];
    check(times.count == 3, "timestamp regression rebases without manufacturing a negative interval");
    successor->_appInBackground = true;
    [successor recordIncomingFrameTiming:timingFrame(90000)];
    successor->_appInBackground = false;
    [successor recordIncomingFrameTiming:timingFrame(180000)];
    check(times.count == 3, "background interval is not reported as a foreground host-frame stall");
    [successor recordIncomingFrameTiming:timingFrame(180750)];
    check(times.count == 4 && fabs(times.lastObject.doubleValue - 1000.0 / 120) < 0.001,
          "foreground cadence resumes after one fresh timing baseline");
}

int main(void) {
    @autoreleasepool {
        testOwnedFrames();
        testLayoutPreservesDecodeState();
        testInterpolationRetirement();
        testPresentationOwnerCallbacks();
        testIncomingFrameTiming();
        printf("DECODER_PRESENTATION_TESTS_RESULT: PASS (%u checks)\n", checks);
    }
    return 0;
}
