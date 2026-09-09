#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "Plot.h"
#import "ConnectionLifecycle.h"
#include <Limelight.h>
#include <stdatomic.h>

#define Log(...) do {} while (0)
@interface BandwidthTracker : NSObject
- (instancetype)initWithWindowSeconds:(int)seconds bucketIntervalMs:(int)milliseconds;
- (void)addBytes:(int)bytes;
@end
@implementation BandwidthTracker
- (instancetype)initWithWindowSeconds:(int)seconds bucketIntervalMs:(int)milliseconds { return [super init]; }
- (void)addBytes:(int)bytes {}
@end
@interface VideoDecoderRenderer : NSObject
@property NSString *backendDescription;
@property dispatch_semaphore_t statsEntered, releaseStats;
@property NSUInteger setups, statReads;
- (void)setupWithVideoFormat:(int)format width:(int)width height:(int)height frameRate:(int)rate fullRange:(BOOL)range request10BitCodec:(BOOL)tenBit;
- (uint64_t)renderedInterpolatedFrameCount;
- (void)getAllStats:(video_stats_t *)stats;
- (int)submitDecodeBuffer:(unsigned char *)data length:(int)length bufferType:(int)type decodeUnit:(PDECODE_UNIT)unit decodeStartTime:(CFTimeInterval)time;
@end
@implementation VideoDecoderRenderer
- (void)setupWithVideoFormat:(int)format width:(int)width height:(int)height frameRate:(int)rate fullRange:(BOOL)range request10BitCodec:(BOOL)tenBit { self.setups++; }
- (uint64_t)renderedInterpolatedFrameCount { return 4; }
- (void)getAllStats:(video_stats_t *)stats {
    self.statReads++;
    if (self.statsEntered) dispatch_semaphore_signal(self.statsEntered);
    if (self.releaseStats) dispatch_semaphore_wait(self.releaseStats, DISPATCH_TIME_FOREVER);
    if (self.backendDescription) stats->renderingBackendString = self.backendDescription;
}
- (int)submitDecodeBuffer:(unsigned char *)data length:(int)length bufferType:(int)type decodeUnit:(PDECODE_UNIT)unit decodeStartTime:(CFTimeInterval)time {
    if (type == BUFFER_TYPE_PICDATA) free(data);
    return DR_OK;
}
@end

static VideoDecoderRenderer *renderer;
static BandwidthTracker *bwTracker;
static NSLock *videoStatsLock;
static video_stats_t currentVideoStats, lastVideoStats;
static int lastFrameNumber, activeVideoFormat;
static uint64_t lastRenderedInterpolatedFrameCount;
static bool fullColorRange, request10BitCodec;
// SUNLIGHT_ACTUAL_STATS_CALLBACKS

@interface Connection : NSObject {
@public
    ConnectionLifecycle *_lifecycle;
    VideoDecoderRenderer *_sessionRenderer;
}
- (BOOL)getVideoStats:(video_stats_t *)stats;
@end
@implementation Connection
// SUNLIGHT_ACTUAL_STATS_GETTER
@end

static unsigned checks;
static void Require(BOOL condition, const char *message) {
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); abort(); }
}
static void Wait(dispatch_semaphore_t signal) {
    Require(dispatch_semaphore_wait(signal, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0,
            "reach controlled statistics ownership boundary");
}
static Connection *StartConnection(VideoDecoderRenderer *presentation) {
    Connection *connection = [Connection new];
    connection->_sessionRenderer = presentation;
    connection->_lifecycle = [[ConnectionLifecycle alloc] initWithCleanup:^{} interrupt:^{}];
    [connection->_lifecycle runWithContext:connection prepare:^{ renderer = presentation; }
                                    start:^int{ return 0; } stop:^{} teardown:^{}];
    return connection;
}
static void StopConnection(Connection *connection) {
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    [connection->_lifecycle cancelWithCompletion:^{ dispatch_semaphore_signal(finished); }];
    Wait(finished);
}

static void TestResetReleasesOwnedStrings(void) {
    __weak NSString *currentLabel;
    __weak NSString *lastLabel;
    @autoreleasepool {
        NSMutableString *a = [[NSMutableString alloc] initWithString:@"Current rendering label"];
        NSMutableString *b = [[NSMutableString alloc] initWithString:@"Last rendering label"];
        currentLabel = a; lastLabel = b;
        currentVideoStats.renderingBackendString = a;
        lastVideoStats.renderingBackendString = b;
    }
    @autoreleasepool { Require(currentLabel != nil && lastLabel != nil, "statistics structs retain their ARC string fields"); }
    renderer = [VideoDecoderRenderer new];
    @autoreleasepool { DrDecoderSetup(VIDEO_FORMAT_H264, 1920, 1080, 60, NULL, 0); }
    @autoreleasepool { Require(currentLabel == nil && lastLabel == nil,
            "actual decoder setup releases both previous statistics strings through typed zero assignment"); }
    @autoreleasepool { Require(currentVideoStats.totalFrames == 0 && lastVideoStats.endTime == 0 && renderer.setups == 1,
            "new decoder resets scalar statistics and initializes its renderer exactly once"); }
}

static void TestRolloverAndSnapshotOwnership(void) {
    Connection *connection = StartConnection([VideoDecoderRenderer new]);
    __weak NSString *discardedWindow;
    __weak NSString *copiedWindow;
    __weak NSString *oldDestination;
    @autoreleasepool {
        NSMutableString *old = [[NSMutableString alloc] initWithString:@"Discarded window"];
        NSMutableString *next = [[NSMutableString alloc] initWithString:@"Window copied into snapshot"];
        discardedWindow = old; copiedWindow = next;
        lastVideoStats.renderingBackendString = old;
        currentVideoStats.renderingBackendString = next;
    }
    currentVideoStats.startTime = CACurrentMediaTime() - 2;
    currentVideoStats.totalFrames = 60;
    lastFrameNumber = 1;
    DECODE_UNIT unit = {0};
    unit.fullLength = 1;
    unit.frameNumber = 2;
    @autoreleasepool { Require(DrSubmitDecodeUnit(&unit) == DR_OK, "actual decode submission rolls a completed statistics window"); }
    @autoreleasepool { Require(discardedWindow == nil && copiedWindow != nil && currentVideoStats.renderingBackendString == nil &&
            lastVideoStats.totalFrames == 60 && currentVideoStats.totalFrames == 1,
            "window rollover releases replaced storage and retains the completed ARC-managed label"); }
    video_stats_t output = {0};
    @autoreleasepool {
        NSMutableString *old = [[NSMutableString alloc] initWithString:@"Prior caller snapshot"];
        oldDestination = old;
        output.renderingBackendString = old;
    }
    @autoreleasepool { Require([connection getVideoStats:&output], "current session returns its complete snapshot"); }
    @autoreleasepool { Require(oldDestination == nil && output.renderingBackendString == copiedWindow && output.totalFrames == 60,
            "typed output assignment releases caller's previous string and retains the new snapshot"); }
    lastVideoStats = (video_stats_t){0};
    @autoreleasepool { Require(copiedWindow != nil && [output.renderingBackendString isEqualToString:@"Window copied into snapshot"],
            "caller snapshot remains valid after the source window is cleared"); }
    output = (video_stats_t){0};
    @autoreleasepool { Require(copiedWindow == nil, "clearing final caller snapshot releases the retained string"); }
    @autoreleasepool { Require(![connection getVideoStats:&output] && ![connection getVideoStats:NULL],
            "missing completed window and null destination are reported without access"); }
    StopConnection(connection);
}

static void TestSnapshotCannotCrossSessionHandoff(void) {
    VideoDecoderRenderer *oldRenderer = [VideoDecoderRenderer new];
    oldRenderer.backendDescription = @"Old Metal renderer";
    oldRenderer.statsEntered = dispatch_semaphore_create(0);
    oldRenderer.releaseStats = dispatch_semaphore_create(0);
    Connection *old = StartConnection(oldRenderer);
    lastVideoStats.endTime = 1;
    dispatch_semaphore_t readFinished = dispatch_semaphore_create(0);
    dispatch_semaphore_t oldFinished = dispatch_semaphore_create(0);
    dispatch_semaphore_t nextStarted = dispatch_semaphore_create(0);
    __block video_stats_t snapshot = {0};
    __block BOOL available = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        available = [old getVideoStats:&snapshot];
        dispatch_semaphore_signal(readFinished);
    });
    Wait(oldRenderer.statsEntered);
    // Cancellation must run independently because snapshot enrichment holds
    // lifecycle ownership until it has finished reading its original renderer.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [old->_lifecycle cancelWithCompletion:^{ dispatch_semaphore_signal(oldFinished); }];
    });
    VideoDecoderRenderer *nextRenderer = [VideoDecoderRenderer new];
    nextRenderer.backendDescription = @"New AVSB renderer";
    __block Connection *next;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        next = StartConnection(nextRenderer);
        dispatch_semaphore_signal(nextStarted);
    });
    @autoreleasepool { Require(dispatch_semaphore_wait(nextStarted, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_MSEC)) != 0,
            "successor cannot publish its renderer while the previous statistics snapshot is being enriched"); }
    dispatch_semaphore_signal(oldRenderer.releaseStats);
    Wait(readFinished); Wait(oldFinished); Wait(nextStarted);
    @autoreleasepool { Require(available && [snapshot.renderingBackendString isEqualToString:@"Old Metal renderer"] && nextRenderer.statReads == 0,
            "completed old snapshot retains its original renderer metadata across reconnect"); }
    @autoreleasepool { Require(![old getVideoStats:&snapshot] && nextRenderer.statReads == 0,
            "retired statistics reader cannot read or overwrite successor renderer information"); }
    @autoreleasepool { Require([next getVideoStats:&snapshot] && [snapshot.renderingBackendString isEqualToString:@"New AVSB renderer"],
            "successor independently enriches its own current snapshot"); }
    StopConnection(next);
}

int main(void) {
    @autoreleasepool {
        videoStatsLock = [NSLock new];
        TestResetReleasesOwnedStrings();
        TestRolloverAndSnapshotOwnership();
        TestSnapshotCannotCrossSessionHandoff();
        currentVideoStats = (video_stats_t){0};
        lastVideoStats = (video_stats_t){0};
        printf("VIDEO_STATS_OWNERSHIP_TESTS_RESULT: PASS (%u checks)\n", checks);
    }
    return 0;
}
