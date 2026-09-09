#import <Foundation/Foundation.h>
#import "StreamConfiguration.h"

static int checks;
#define Check(c) do { checks++; if (!(c)) { NSLog(@"FAIL line %d: %s", __LINE__, #c); exit(1); } } while (0)
#define DS_EFFECT_PAYLOAD_SIZE 10

@interface UIView : NSObject @end
@implementation UIView @end
@interface TestTimer : NSObject
@property int stops;
- (void)invalidate;
- (void)clean;
@end
@implementation TestTimer
- (void)invalidate { self.stops++; }
- (void)clean { self.stops++; }
@end
@interface SceneDelegate : NSObject
+ (void)clearExternalDisplayRenderView:(UIView *)view;
@end
@implementation SceneDelegate
+ (void)clearExternalDisplayRenderView:(UIView *)view {}
@end
@interface TemporaryHost : NSObject
@property NSString *uuid;
@end
@implementation TemporaryHost @end
@interface TemporaryApp : NSObject
@property NSString *id;
@property TemporaryHost *host;
@end
@implementation TemporaryApp @end
@interface Navigation : NSObject
@property id topViewController;
@end
@implementation Navigation @end
@interface StreamManager : NSObject
@property(copy) dispatch_block_t completion;
- (void)stopStreamWithCompletion:(dispatch_block_t)completion;
@end
@implementation StreamManager
- (void)stopStreamWithCompletion:(dispatch_block_t)completion { self.completion = completion; }
@end
@interface ControllerSupport : NSObject
@property int deliveries;
@property NSData *left, *right;
- (void)rumble:(unsigned short)n lowFreqMotor:(unsigned short)l highFreqMotor:(unsigned short)h;
- (void)rumbleTriggers:(uint16_t)n leftTrigger:(uint16_t)l rightTrigger:(uint16_t)r;
- (void)setMotionEventState:(uint16_t)n motionType:(uint8_t)t reportRateHz:(uint16_t)h;
- (void)setControllerLed:(uint16_t)n r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b;
- (void)setAdaptiveTriggers:(uint16_t)n eventFlags:(uint8_t)f typeLeft:(uint8_t)l typeRight:(uint8_t)r left:(const uint8_t *)left right:(const uint8_t *)right;
@end
@implementation ControllerSupport
- (void)delivered { Check(NSThread.isMainThread); self.deliveries++; }
- (void)rumble:(unsigned short)n lowFreqMotor:(unsigned short)l highFreqMotor:(unsigned short)h { [self delivered]; }
- (void)rumbleTriggers:(uint16_t)n leftTrigger:(uint16_t)l rightTrigger:(uint16_t)r { [self delivered]; }
- (void)setMotionEventState:(uint16_t)n motionType:(uint8_t)t reportRateHz:(uint16_t)h { [self delivered]; }
- (void)setControllerLed:(uint16_t)n r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b { [self delivered]; }
- (void)setAdaptiveTriggers:(uint16_t)n eventFlags:(uint8_t)f typeLeft:(uint8_t)l typeRight:(uint8_t)r left:(const uint8_t *)left right:(const uint8_t *)right {
    [self delivered]; self.left = [NSData dataWithBytes:left length:10]; self.right = [NSData dataWithBytes:right length:10];
}
@end
@class MainFrameViewController;
@interface StreamFrameViewController : NSObject {
@public
    BOOL _isEndingStream, _externalDisplayRoutingReady;
    TestTimer *_statsUpdateTimer, *_inactivityTimer, *safeTimer;
    dispatch_block_t _delayedRemoveExtScreen;
    UIView *_externalDisplayRenderViewRequest;
    ControllerSupport *_controllerSupport;
}
@property StreamConfiguration *streamConfig;
@property StreamManager *streamMan;
@property Navigation *navigation;
@property(weak) MainFrameViewController *main;
@property int stops;
- (void)returnToMainFrame;
- (void)stopMicrophoneCapture;
- (void)retireStreamPresentation;
@end
@interface MainFrameViewController : NSObject {
@public
    StreamFrameViewController *streamFrameViewController;
    TemporaryApp *launchedApp;
    NSUInteger _streamLaunchGeneration;
}
@property Navigation *navigationController;
@property TemporaryApp *quitTarget;
@property NSString *quitSession;
- (void)quitApp:(TemporaryApp *)app expectedHostSessionId:(NSString *)session;
- (void)disconnectAndQuitStreamFromController:(StreamFrameViewController *)controller;
@end
@implementation StreamFrameViewController
- (void)returnToMainFrame { self.navigation.topViewController = self.main; [self retireStreamPresentation]; }
- (void)stopMicrophoneCapture { self.stops++; }
// ACTUAL_STREAM_CALLBACK_METHODS
@end
@implementation MainFrameViewController
- (void)quitApp:(TemporaryApp *)app expectedHostSessionId:(NSString *)session { self.quitTarget = app; self.quitSession = session; }
// ACTUAL_MAIN_QUIT_METHOD
@end

static MainFrameViewController *Browser(void) {
    MainFrameViewController *main = [MainFrameViewController new];
    main->launchedApp = [TemporaryApp new]; main->launchedApp.id = @"app-a";
    main->launchedApp.host = [TemporaryHost new]; main->launchedApp.host.uuid = @"pc-a";
    StreamFrameViewController *stream = [StreamFrameViewController new];
    stream.streamConfig = [StreamConfiguration new]; stream.streamConfig.appID = @"app-a";
    stream.streamConfig.hostUUID = @"pc-a"; stream.streamConfig.hostSessionId = @"777";
    stream.streamMan = [StreamManager new]; stream.main = main;
    main->streamFrameViewController = stream;
    main.navigationController = [Navigation new]; stream.navigation = main.navigationController;
    main.navigationController.topViewController = stream;
    return main;
}

static void Drain(void) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]]; }
static void Feedback(StreamFrameViewController *stream) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        uint8_t left[10], right[10]; memset(left, 12, 10); memset(right, 34, 10);
        [stream rumble:0 lowFreqMotor:100 highFreqMotor:200];
        [stream rumbleTriggers:0 leftTrigger:100 rightTrigger:200];
        [stream setMotionEventState:0 motionType:1 reportRateHz:60];
        [stream setControllerLed:0 r:1 g:2 b:3];
        [stream setAdaptiveTriggers:0 eventFlags:3 typeLeft:1 typeRight:1 left:left right:right];
        memset(left, 99, 10); memset(right, 99, 10);
        dispatch_semaphore_signal(done);
    });
    Check(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0);
}

int main(void) { @autoreleasepool {
    MainFrameViewController *main = Browser(); StreamFrameViewController *stream = main->streamFrameViewController;
    TemporaryApp *original = main->launchedApp;
    [main disconnectAndQuitStreamFromController:stream];
    Check(main.quitTarget == nil && stream.stops == 1);
    main->launchedApp = [TemporaryApp new]; main->launchedApp.id = @"app-b";
    stream.streamConfig.hostSessionId = @"888";
    stream.streamMan.completion();
    Check(main.quitTarget == original && [main.quitSession isEqual:@"777"]);
    main = Browser(); stream = main->streamFrameViewController;
    [main disconnectAndQuitStreamFromController:stream];
    main->_streamLaunchGeneration++;
    stream.streamMan.completion();
    Check(main.quitTarget == nil);
    main = Browser(); stream = main->streamFrameViewController;
    stream.streamConfig.hostUUID = @"different-pc";
    [main disconnectAndQuitStreamFromController:stream];
    Check(stream.streamMan.completion == nil && stream.stops == 0);
    main = Browser(); stream = main->streamFrameViewController;
    [main disconnectAndQuitStreamFromController:[StreamFrameViewController new]];
    Check(stream.streamMan.completion == nil);

    stream->_controllerSupport = [ControllerSupport new];
    Feedback(stream); Check(stream->_controllerSupport.deliveries == 0);
    Drain(); Check(stream->_controllerSupport.deliveries == 5);
    Check(((const uint8_t *)stream->_controllerSupport.left.bytes)[0] == 12);
    Check(((const uint8_t *)stream->_controllerSupport.right.bytes)[0] == 34);
    Feedback(stream);
    TestTimer *stats = [TestTimer new], *inactivity = [TestTimer new], *dummy = [TestTimer new];
    stream->_statsUpdateTimer = stats; stream->_inactivityTimer = inactivity; stream->safeTimer = dummy;
    stream->_delayedRemoveExtScreen = dispatch_block_create(0, ^{});
    dispatch_block_t oldResize = stream->_delayedRemoveExtScreen;
    [stream retireStreamPresentation];
    Check(stats.stops == 1 && inactivity.stops == 1 && dummy.stops == 1);
    Check(stream->_statsUpdateTimer == nil && stream->_inactivityTimer == nil && stream->safeTimer == nil);
    Check(stream->_delayedRemoveExtScreen == nil && dispatch_block_testcancel(oldResize));
    Drain(); Check(stream->_controllerSupport.deliveries == 5);
    [stream retireStreamPresentation];
    Check(stats.stops == 1 && inactivity.stops == 1 && dummy.stops == 1);
    NSLog(@"PASS %d controller ownership checks", checks);
} return 0; }
