#import <Foundation/Foundation.h>
#import "HapticContext.h"

static unsigned checks;
static void Check(BOOL okay, NSString *message) {
    checks++;
    if (!okay) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
@interface FixturePlayer : NSObject
@property NSUInteger starts, stops, cancels, updates;
@end
@implementation FixturePlayer
- (BOOL)startAtTime:(NSTimeInterval)time error:(NSError **)error { (void)time; (void)error; self.starts++; return YES; }
- (BOOL)stopAtTime:(NSTimeInterval)time error:(NSError **)error { (void)time; (void)error; self.stops++; return YES; }
- (BOOL)cancelAndReturnError:(NSError **)error { (void)error; self.cancels++; return YES; }
- (BOOL)sendParameters:(NSArray *)parameters atTime:(NSTimeInterval)time error:(NSError **)error { (void)parameters; (void)time; (void)error; self.updates++; return YES; }
@end
@interface FixtureEngine : NSObject
@property NSMutableArray<FixturePlayer *> *players;
@property (copy) void (^stoppedHandler)(CHHapticEngineStoppedReason);
@property (copy) dispatch_block_t resetHandler;
@property (copy) dispatch_block_t callbackDuringStop;
@property NSUInteger starts, stops;
@end
@implementation FixtureEngine
- (instancetype)init { self = [super init]; if (self) self.players = [NSMutableArray array]; return self; }
- (id<CHHapticPatternPlayer>)createPlayerWithPattern:(CHHapticPattern *)pattern error:(NSError **)error {
    (void)pattern; (void)error; FixturePlayer *player = [FixturePlayer new]; [self.players addObject:player]; return (id)player;
}
- (BOOL)startAndReturnError:(NSError **)error { (void)error; self.starts++; return YES; }
- (void)stopWithCompletionHandler:(void (^)(NSError *))completion { self.stops++; if (self.callbackDuringStop) self.callbackDuringStop(); if (completion) completion(nil); }
@end
@interface HapticContext (Testing)
- (void)installEngineCallbacks;
@end
static HapticContext *Context(FixtureEngine **engine) {
    HapticContext *context = [HapticContext new];
    *engine = [FixtureEngine new];
    [context setValue:*engine forKey:@"hapticEngine"];
    [context installEngineCallbacks];
    return context;
}
// A queue barrier observes completed effects without exposing a test-only
// production API or invoking hardware. CoreHaptics endpoints are the sole doubles.
static void Drain(HapticContext *context) {
    dispatch_queue_t queue = [context valueForKey:@"hapticQueue"];
    dispatch_sync(queue, ^{});
}
int main(void) { @autoreleasepool {
    FixtureEngine *engine;
    HapticContext *context = Context(&engine);
    [context setMotorAmplitude:65535];
    [context setAuthoredAmplitude:0.5 sharpness:0.2 transientStrength:0];
    Drain(context);
    Check(engine.players.count == 2, @"Ordinary and authored haptics retain separate players");
    Check(engine.players[0].starts == 1 && engine.players[1].starts == 1, @"Both haptic effects start");
    [context setMotorAmplitude:32000]; [context setAuthoredAmplitude:0.3 sharpness:0.8 transientStrength:0];
    [context setMotorAmplitude:0]; [context setAuthoredAmplitude:0 sharpness:0 transientStrength:0];
    Drain(context);
    Check(engine.players[0].starts == 1 && engine.players[1].starts == 1, @"Amplitude updates reuse the running players");
    Check(engine.players[0].stops == 1 && engine.players[1].stops == 1, @"Zero stops both ordinary and authored effects");
    dispatch_block_t queuedReset = engine.resetHandler;
    void (^queuedStop)(CHHapticEngineStoppedReason) = engine.stoppedHandler;
    engine.callbackDuringStop = queuedReset;
    [context cleanup];
    Check(engine.stops == 1 && engine.players[0].cancels == 1 && engine.players[1].cancels == 1, @"Cleanup drains and cancels each player and stops the engine once");
    engine.resetHandler(); engine.stoppedHandler(CHHapticEngineStoppedReasonAudioSessionInterrupt);
    queuedReset(); queuedStop(CHHapticEngineStoppedReasonAudioSessionInterrupt);
    [context setMotorAmplitude:65535]; [context setAuthoredAmplitude:1 sharpness:1 transientStrength:1];
    [context cleanup]; Drain(context);
    Check(engine.starts == 0 && engine.stops == 1 && engine.players.count == 2, @"Late callbacks and effects cannot restart a cleaned engine");

    FixtureEngine *resetEngine;
    HapticContext *resetContext = Context(&resetEngine);
    [resetContext setMotorAmplitude:1]; Drain(resetContext);
    resetEngine.resetHandler(); Drain(resetContext);
    [resetContext setMotorAmplitude:1]; Drain(resetContext);
    Check(resetEngine.starts == 1 && resetEngine.players.count == 2, @"A live engine reset restarts and rebuilds the effect player");
    [resetContext cleanup];

    FixtureEngine *racingEngine;
    HapticContext *racingContext = Context(&racingEngine);
    dispatch_block_t racingReset = racingEngine.resetHandler;
    dispatch_group_t group = dispatch_group_create();
    for (NSUInteger i = 0; i < 300; i++) {
        dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            [racingContext setMotorAmplitude:(unsigned short)(i * 200)];
            [racingContext setAuthoredAmplitude:0.2 sharpness:0.5 transientStrength:0];
            if (i % 17 == 0) racingReset();
        });
    }
    [racingContext cleanup];
    Check(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0, @"Concurrent effects and reset callbacks do not block cleanup");
    Drain(racingContext); [racingContext cleanup];
    Check(racingEngine.stops == 1, @"Concurrent teardown stops the engine exactly once");
    printf("Haptic context: %u checks passed (300 concurrent effect batches)\n", checks);
} return 0; }
