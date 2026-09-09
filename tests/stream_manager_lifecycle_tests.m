#import "stream_manager_lifecycle_doubles.h"
#import "StreamManager.h"
#include <Limelight.h>

@interface ManagerTestState : NSObject <ConnectionCallbacks>
@property (atomic) NSInteger cryptoCalls;
@property (atomic) NSInteger rendererInitializations;
@property (atomic) NSInteger connectionInitializations;
@property (atomic) NSInteger connectionStarts;
@property (atomic) NSInteger connectionStops;
@property (atomic) NSInteger failures;
@property BOOL resume;
@property BOOL failServerInfo;
@property BOOL glassesOutput;
@property BOOL decoderUsesMetal;
@property BOOL transportIsStereo;
@property BOOL emitsStats;
@property TemporarySettings *frozenPresentation;
@property TemporarySettings *globalPresentation;
@property TemporarySettings *rendererPresentation;
@property TemporarySettings *connectionPresentation;
@property BOOL hostSessionSupported;
@property BOOL deliberateReconnect;
@property NSInteger activeSessionResponses;
@property NSInteger resumeAttempts;
@property (copy) NSString *sessionToken;
@property (copy) NSString *runningApp;
@property (copy) NSString *resumeError;
@property (copy) dispatch_block_t stopCompletion;
@property BOOL delayStopCompletion;
@property NSMutableArray<NSString *> *requests;
@property (copy) void (^cryptoHook)(void);
@property (copy) void (^requestHook)(NSString *path);
@property (copy) void (^rendererHook)(void);
@end
@implementation ManagerTestState
- (id)init { if ((self = [super init])) { _requests = [NSMutableArray new]; _sessionToken = @"17"; _runningApp = @"1"; } return self; }
- (void)launchFailed:(NSString *)message { self.failures++; }
@end
static ManagerTestState *currentState;

@implementation UIView @end
@implementation TestFrameQueue
- (void)clear {}
@end
@implementation VideoDecoderRenderer
- (void)setRequeuingRequired:(BOOL)required { self.needRequeuing = required; }
- (id)initWithView:(UIView *)view callbacks:(id<ConnectionCallbacks>)callbacks streamAspectRatio:(float)aspect {
    return [self initWithView:view callbacks:callbacks streamAspectRatio:aspect presentationSettings:nil];
}
- (id)initWithView:(UIView *)view callbacks:(id<ConnectionCallbacks>)callbacks streamAspectRatio:(float)aspect presentationSettings:(TemporarySettings *)settings {
    if ((self = [super init])) {
        currentState.rendererInitializations++;
        currentState.rendererPresentation = settings;
        if (currentState.rendererHook) currentState.rendererHook();
    }
    return self;
}
- (void)cleanup {}
@end
@implementation BandwidthTracker @end
@implementation Connection {
    ManagerTestState *_state;
}
- (id)initWithConfig:(StreamConfiguration *)config renderer:(VideoDecoderRenderer *)renderer connectionCallbacks:(id<ConnectionCallbacks>)callbacks {
    if ((self = [super init])) {
        _state = currentState;
        _state.connectionInitializations++;
        _state.decoderUsesMetal = renderer.stereoPresentation;
        _state.transportIsStereo = config.isStereoStream;
        _state.connectionPresentation = config.presentationSettings;
    }
    return self;
}
- (void)main { _state.connectionStarts++; }
- (void)terminate { _state.connectionStops++; }
- (void)terminateWithCompletion:(dispatch_block_t)completion {
    if (_state.delayStopCompletion) _state.stopCompletion = completion;
    else completion();
}
- (BOOL)getVideoStats:(video_stats_t *)stats {
    if (!_state.emitsStats) return NO;
    *stats = (video_stats_t){0};
    stats->totalFrames = 60;
    stats->networkDroppedFrames = 10;
    stats->endTime = 1;
    stats->renderingBackendString = @"AVSampleBuffer";
    return YES;
}
- (BandwidthTracker *)getBwTracker { return nil; }
- (NSString *)getActiveCodecName { return @"test"; }
@end
@implementation CryptoManager
+ (void)generateKeyPairUsingSSL {
    currentState.cryptoCalls++;
    if (currentState.cryptoHook) currentState.cryptoHook();
}
@end
@implementation HttpManager {
    ManagerTestState *_state;
}
- (id)initWithAddress:(NSString *)address httpsPort:(unsigned short)port serverCert:(NSData *)cert {
    if ((self = [super init])) _state = currentState;
    return self;
}
- (NSURLRequest *)newServerInfoRequest:(BOOL)fastFail { return [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://fixture.invalid/serverinfo"]]; }
- (NSURLRequest *)newHttpServerInfoRequest { return [self newServerInfoRequest:NO]; }
- (NSURLRequest *)newLaunchOrResumeRequest:(NSString *)verb config:(StreamConfiguration *)config {
    return [NSURLRequest requestWithURL:[NSURL URLWithString:[@"https://fixture.invalid/" stringByAppendingString:verb]]];
}
- (void)executeRequestSynchronously:(HttpRequest *)request {
    NSString *path = request.request.URL.path;
    @synchronized (_state) { [_state.requests addObject:path]; }
    if (_state.requestHook) _state.requestHook(path);
    NSString *xml;
    if ([path isEqualToString:@"/serverinfo"]) {
        xml = _state.failServerInfo ? @"<root status_code=\"500\" status_message=\"fixture failure\"/>" :
            [NSString stringWithFormat:@"<root status_code=\"200\"><PairStatus>1</PairStatus><appversion>7.1.431.0</appversion><state>SUNSHINE_SERVER_%@</state><currentgame>%@</currentgame><ServerCodecModeSupport>1</ServerCodecModeSupport>%@</root>", _state.resume ? @"BUSY" : @"FREE", _state.runningApp,
                _state.hostSessionSupported ? [NSString stringWithFormat:@"<hostsessionid>%@</hostsessionid>", _state.sessionToken] : @""];
    } else {
        if ([path isEqualToString:@"/resume"]) _state.resumeAttempts++;
        if ([path isEqualToString:@"/resume"] &&
            (_state.resumeError != nil || _state.resumeAttempts <= _state.activeSessionResponses)) {
            xml = [NSString stringWithFormat:@"<root status_code=\"503\" status_message=\"%@\"/>", _state.resumeError ?: @"Another streaming session is already active"];
        } else {
            xml = [NSString stringWithFormat:@"<root status_code=\"200\"><gamesession>1</gamesession><resume>1</resume><sessionUrl0>rtsp://fixture.invalid:48010</sessionUrl0>%@</root>",
                _state.hostSessionSupported ? [NSString stringWithFormat:@"<hostsessionid>%@</hostsessionid>", _state.sessionToken] : @""];
        }
    }
    [request.response populateWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
}
@end
@implementation ServerInfoResponse @end
@implementation Utils
+ (NSData *)randomBytes:(NSInteger)length { return [NSMutableData dataWithLength:length]; }
@end
@implementation TemporarySettings @end
@implementation DataManager
- (TemporarySettings *)getSettings { return currentState.globalPresentation; }
@end
@implementation LocalizationHelper
+ (NSString *)localizedStringForKey:(NSString *)key, ... { return key; }
@end
@implementation PublicUtils
+ (NSString *)onScreenRuntimeStats { return @""; }
@end
bool LiGetEstimatedRttInfo(uint32_t *rtt, uint32_t *variance) { return false; }

static void Require(BOOL condition, NSString *message) {
    if (!condition) [NSException raise:@"ManagerLifecycleAssertion" format:@"%@", message];
}
static void Wait(dispatch_semaphore_t semaphore) {
    Require(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0,
            @"Timed out waiting for controlled lifecycle boundary");
}
static void PumpUntil(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!condition() && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    }
    Require(condition(), @"Main-queue continuation did not complete");
}
static void DrainMain(void) {
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    PumpUntil(^BOOL{ return drained; });
}
static StreamManager *NewManager(void) {
    StreamConfiguration *config = [StreamConfiguration new];
    config.appID = @"1";
    config.host = @"fixture.invalid";
    config.width = config.logicalWidth = 1920;
    config.height = config.logicalHeight = 1080;
    config.frameRate = 60;
    config.glassesOutputEnabled = currentState.glassesOutput;
    config.presentationSettings = currentState.frozenPresentation;
    config.reconnectRetainedSession = currentState.deliberateReconnect;
    if (currentState.deliberateReconnect && currentState.hostSessionSupported) config.expectedHostSessionId = @"17";
    return [[StreamManager alloc] initWithConfig:config renderView:[UIView new] connectionCallbacks:currentState];
}
static void ExpectNoConnection(void) {
    DrainMain();
    Require(currentState.rendererInitializations == 0 && currentState.connectionInitializations == 0,
            @"Cancelled startup must never create decoder or Connection");
    Require(currentState.failures == 0, @"Cancelled startup must not report a late failure");
}
static void StopDuringRequest(NSString *path, BOOL resume, BOOL failResponse) {
    currentState.resume = resume;
    currentState.failServerInfo = failResponse;
    dispatch_semaphore_t entered = dispatch_semaphore_create(0);
    dispatch_semaphore_t release = dispatch_semaphore_create(0);
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    currentState.requestHook = ^(NSString *requestPath) {
        if ([path isEqualToString:requestPath]) {
            dispatch_semaphore_signal(entered);
            Wait(release);
        }
    };
    StreamManager *manager = NewManager();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [manager main];
        dispatch_semaphore_signal(finished);
    });
    Wait(entered);
    [manager stopStream];
    dispatch_semaphore_signal(release);
    Wait(finished);
    ExpectNoConnection();
    Require(currentState.requests.count == ([path isEqualToString:@"/serverinfo"] ? 1u : 2u),
            @"Cancelled request completion must not issue another startup request");
}
static NSUInteger testCount;
static void Run(NSString *name, void (^body)(void)) {
    @autoreleasepool {
        currentState = [ManagerTestState new];
        body();
        testCount++;
        printf("PASS: %s\n", name.UTF8String);
        currentState = nil;
    }
}
int main(void) {
    @autoreleasepool {
        Run(@"stop before main prevents crypto, HTTP and decoder startup", ^{
            StreamManager *manager = NewManager();
            [manager stopStream];
            [manager main];
            Require(manager.isCancelled && currentState.cryptoCalls == 0 && currentState.requests.count == 0,
                    @"stopStream must cancel the operation before any startup work");
            ExpectNoConnection();
        });
        Run(@"NSOperation cancellation uses the same terminal startup state", ^{
            StreamManager *manager = NewManager();
            [manager cancel];
            [manager main];
            Require(currentState.cryptoCalls == 0, @"Operation cancellation must prevent startup");
            ExpectNoConnection();
        });
        Run(@"stop during crypto prevents the serverinfo request", ^{
            dispatch_semaphore_t entered = dispatch_semaphore_create(0), release = dispatch_semaphore_create(0), finished = dispatch_semaphore_create(0);
            currentState.cryptoHook = ^{ dispatch_semaphore_signal(entered); Wait(release); };
            StreamManager *manager = NewManager();
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [manager main]; dispatch_semaphore_signal(finished); });
            Wait(entered);
            [manager stopStream];
            dispatch_semaphore_signal(release);
            Wait(finished);
            Require(currentState.requests.count == 0, @"Crypto completion must recheck cancellation");
            ExpectNoConnection();
        });
        Run(@"stop during serverinfo prevents host launch", ^{ StopDuringRequest(@"/serverinfo", NO, NO); });
        Run(@"stop during failed serverinfo suppresses stale failure", ^{ StopDuringRequest(@"/serverinfo", NO, YES); });
        Run(@"stop during launch prevents connection publication", ^{ StopDuringRequest(@"/launch", NO, NO); });
        Run(@"stop during resume prevents connection publication", ^{ StopDuringRequest(@"/resume", YES, NO); });
        Run(@"stop before the main continuation prevents renderer creation", ^{
            StreamManager *manager = NewManager();
            [manager main];
            Require(currentState.requests.count == 2, @"HTTP startup must have finished before this stop");
            [manager stopStream];
            ExpectNoConnection();
        });
        Run(@"normal startup connects once and repeated stop terminates once", ^{
            StreamManager *manager = NewManager();
            [manager main];
            PumpUntil(^BOOL{ return currentState.connectionStarts == 1; });
            Require(currentState.rendererInitializations == 1 && currentState.connectionInitializations == 1,
                    @"Normal startup must publish exactly one decoder and connection");
            [manager stopStream];
            [manager stopStream];
            Require(manager.isCancelled && currentState.connectionStops == 1, @"Terminal stop must be idempotent");
        });
        Run(@"a real startup error still reaches the active callback", ^{
            currentState.failServerInfo = YES;
            StreamManager *manager = NewManager();
            [manager main];
            Require(currentState.failures == 1 && currentState.rendererInitializations == 0,
                    @"Cancellation guard must preserve error reporting for active startup");
            [manager stopStream];
        });
        Run(@"2D glasses set Metal presentation before connection creation and retain mono transport", ^{
            currentState.glassesOutput = YES;
            StreamManager *manager = NewManager();
            [manager main];
            PumpUntil(^BOOL{ return currentState.connectionStarts == 1; });
            Require(currentState.decoderUsesMetal && !currentState.transportIsStereo,
                    @"Glasses output must configure the decoder before Connection without enabling host conversion");
            [manager stopStream];
        });
        for (NSInteger pacing = FramePacingModeOff; pacing <= FramePacingModeInterpolation; pacing++) {
            Run([NSString stringWithFormat:@"negotiated pacing %ld reaches decoder and connection despite different global defaults", (long)pacing], ^{
                currentState.frozenPresentation = [TemporarySettings new];
                currentState.frozenPresentation.framePacingMode = @(pacing);
                currentState.globalPresentation = [TemporarySettings new];
                currentState.globalPresentation.framePacingMode = @(pacing == FramePacingModeOff ? FramePacingModeQueue : FramePacingModeOff);
                currentState.emitsStats = YES;
                StreamManager *manager = NewManager();
                [manager main];
                PumpUntil(^BOOL{ return currentState.connectionStarts == 1; });
                Require(currentState.rendererPresentation == currentState.frozenPresentation &&
                        currentState.connectionPresentation == currentState.frozenPresentation,
                        @"The actual manager must pass one captured snapshot to both initialization boundaries");
                currentState.globalPresentation.framePacingMode = @((pacing + 1) % 4);
                NSString *stats = [manager getStatsOverlayText:0];
                BOOL queue = pacing == FramePacingModeQueue || pacing == FramePacingModeInterpolation;
                Require([stats containsString:@"Frames buffered"] == queue,
                        @"Stats must use the same negotiated pacing even after global defaults change");
                NSString *compactStats = [manager getStatsOverlayText:1];
                Require([compactStats isEqualToString:pacing == FramePacingModeInterpolation ? @"simplifiedOsdTextWithInterpolation" : @"simplifiedOsdText"],
                        @"Interpolation stats must follow this PC snapshot rather than the global default");
                [manager stopStream];
            });
        }
        Run(@"legacy nil snapshot retains global stats fallback and Metal still forces queue", ^{
            currentState.globalPresentation = [TemporarySettings new];
            currentState.globalPresentation.framePacingMode = @(FramePacingModeQueue);
            currentState.emitsStats = YES;
            StreamManager *manager = NewManager();
            [manager main];
            PumpUntil(^BOOL{ return currentState.connectionStarts == 1; });
            Require(currentState.rendererPresentation == nil && [[manager getStatsOverlayText:0] containsString:@"Frames buffered"],
                    @"Legacy callers must retain nil and resolve their original global fallback");
            [manager stopStream];
            currentState.connectionStarts = 0;
            currentState.globalPresentation.framePacingMode = @(FramePacingModeOff);
            currentState.glassesOutput = YES;
            manager = NewManager();
            [manager main];
            PumpUntil(^BOOL{ return currentState.connectionStarts == 1; });
            Require([[manager getStatsOverlayText:0] containsString:@"Frames buffered"],
                    @"Metal presentation must keep queue statistics even with a legacy Off fallback");
            [manager stopStream];
        });
        Run(@"stop completion with no published connection is asynchronous on main", ^{
            StreamManager *manager = NewManager();
            __block BOOL completed = NO;
            [manager stopStreamWithCompletion:^{ Require(NSThread.isMainThread, @"completion must run on main"); completed = YES; }];
            Require(!completed && manager.isCancelled, @"stop completion must never reenter its caller");
            PumpUntil(^BOOL{ return completed; });
            [manager main];
            ExpectNoConnection();
        });
        Run(@"published connection completion waits for its cleanup boundary", ^{
            currentState.delayStopCompletion = YES;
            StreamManager *manager = NewManager();
            [manager main];
            PumpUntil(^BOOL{ return currentState.connectionStarts == 1; });
            __block BOOL completed = NO;
            [manager stopStreamWithCompletion:^{ Require(NSThread.isMainThread, @"completion must run on main"); completed = YES; }];
            DrainMain();
            Require(!completed && currentState.stopCompletion != nil, @"engine must complete cleanup first");
            currentState.stopCompletion();
            currentState.stopCompletion = nil;
            PumpUntil(^BOOL{ return completed; });
            currentState.delayStopCompletion = NO;
            completed = NO;
            [manager stopStreamWithCompletion:^{ completed = YES; }];
            PumpUntil(^BOOL{ return completed; });
            Require(currentState.connectionStops == 1, @"repeated completion must not restart teardown");
        });
        Run(@"deliberate reconnect retries exact active-session refusal with fresh identity", ^{
            currentState.resume = currentState.hostSessionSupported = currentState.deliberateReconnect = YES;
            currentState.activeSessionResponses = 1;
            StreamManager *manager = NewManager();
            [manager main];
            PumpUntil(^BOOL{ return currentState.connectionStarts == 1; });
            Require(currentState.failures == 0 && currentState.resumeAttempts == 2 &&
                    [currentState.requests isEqual:@[@"/serverinfo", @"/resume", @"/serverinfo", @"/resume"]],
                    @"only successful, revalidated reconnect may publish the new connection");
            [manager stopStream];
        });
        Run(@"ordinary resume does not retry active-session refusal", ^{
            currentState.resume = currentState.hostSessionSupported = YES;
            currentState.activeSessionResponses = 1;
            StreamManager *manager = NewManager();
            [manager main];
            Require(currentState.failures == 1 && currentState.resumeAttempts == 1 && currentState.requests.count == 2,
                    @"an ordinary connection must report the competing active session");
            [manager stopStream];
        });
        Run(@"other 503 responses remain terminal on deliberate reconnect", ^{
            currentState.resume = currentState.hostSessionSupported = currentState.deliberateReconnect = YES;
            currentState.resumeError = @"Another streaming handshake is already pending";
            StreamManager *manager = NewManager();
            [manager main];
            Require(currentState.failures == 1 && currentState.resumeAttempts == 1,
                    @"pending handshakes must never be blindly retried");
            [manager stopStream];
        });
        Run(@"changed token between retries rejects before another resume", ^{
            currentState.resume = currentState.hostSessionSupported = currentState.deliberateReconnect = YES;
            currentState.activeSessionResponses = 1;
            currentState.requestHook = ^(NSString *path) {
                if ([path isEqualToString:@"/serverinfo"] && currentState.resumeAttempts == 1) currentState.sessionToken = @"18";
            };
            StreamManager *manager = NewManager();
            [manager main];
            Require(currentState.failures == 1 && currentState.resumeAttempts == 1 && currentState.requests.count == 3,
                    @"new session must never receive the stale reconnect");
            [manager stopStream];
        });
        Run(@"changed app between retries rejects before another resume", ^{
            currentState.resume = currentState.hostSessionSupported = currentState.deliberateReconnect = YES;
            currentState.activeSessionResponses = 1;
            currentState.requestHook = ^(NSString *path) {
                if ([path isEqualToString:@"/serverinfo"] && currentState.resumeAttempts == 1) currentState.runningApp = @"2";
            };
            StreamManager *manager = NewManager();
            [manager main];
            Require(currentState.failures == 1 && currentState.resumeAttempts == 1,
                    @"new app must never receive the stale reconnect");
            [manager stopStream];
        });
        Run(@"idle retained reconnect never launches a replacement session", ^{
            currentState.hostSessionSupported = currentState.deliberateReconnect = YES;
            StreamManager *manager = NewManager();
            [manager main];
            Require(currentState.failures == 1 && [currentState.requests isEqual:@[@"/serverinfo"]],
                    @"ended app session must not silently become a new launch");
            [manager stopStream];
        });
        Run(@"cancellation wakes reconnect backoff without another request", ^{
            currentState.resume = currentState.hostSessionSupported = currentState.deliberateReconnect = YES;
            currentState.activeSessionResponses = 1;
            StreamManager *manager = NewManager();
            currentState.requestHook = ^(NSString *path) {
                if ([path isEqualToString:@"/resume"]) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [manager stopStream]; });
                }
            };
            [manager main];
            Require(manager.isCancelled && currentState.requests.count == 2, @"backoff must stop before retry after cancellation");
            ExpectNoConnection();
        });
        Run(@"active-session retry budget is finite", ^{
            currentState.resume = currentState.hostSessionSupported = currentState.deliberateReconnect = YES;
            currentState.activeSessionResponses = 20;
            StreamManager *manager = NewManager();
            [manager main];
            Require(currentState.failures == 1 && currentState.resumeAttempts == 7 && currentState.requests.count == 14,
                    @"initial request plus six revalidated retries must terminate clearly");
            [manager stopStream];
        });
        printf("StreamManager lifecycle: %lu production-flow tests passed\n", (unsigned long)testCount);
    }
    return 0;
}
