#import <Foundation/Foundation.h>
#import <Limelight.h>
#define TARGET_OS_TV 0
#include "stage_names.inc"

static int checks, creations, cleanups, starts, sends;
static NSMutableArray<dispatch_block_t> *pending;
static BOOL allowed = YES;
static id activeOwner;
static void Require(BOOL okay, const char *message) {
    checks++;
    if (!okay) { fprintf(stderr, "FAIL %s\n", message); abort(); }
}
static void Schedule(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t action) {
    (void)when; (void)queue;
    [pending addObject:[action copy]];
}
@interface Connection : NSObject
- (void)performMicrophoneInput:(dispatch_block_t)action;
@end
@implementation Connection
- (void)performMicrophoneInput:(dispatch_block_t)action { if (activeOwner == self) action(); }
@end
@interface ConnectionLifecycle : NSObject
+ (id)activeContext;
@end
@implementation ConnectionLifecycle
+ (id)activeContext { return activeOwner; }
@end
@interface Settings : NSObject
@property BOOL useBuiltinMic;
@property NSNumber *micVolume;
@property BOOL redirectMic;
@end
@implementation Settings @end
@interface MicHandler : NSObject
@property(copy) void (^packet)(NSData *);
@property BOOL closed;
+ (BOOL)permissionGranted;
+ (void)setVolume:(float)volume;
- (instancetype)initWithUseBuiltinMic:(BOOL)builtin sendPacket:(void (^)(NSData *))send;
- (void)startTapping;
- (void)clean;
@end
@implementation MicHandler
+ (BOOL)permissionGranted { return allowed; }
+ (void)setVolume:(float)volume { (void)volume; }
- (instancetype)initWithUseBuiltinMic:(BOOL)builtin sendPacket:(void (^)(NSData *))send {
    (void)builtin;
    if ((self = [super init])) { creations++; self.packet = send; }
    return self;
}
- (void)startTapping { if (!self.closed) starts++; }
- (void)clean { if (!self.closed) { self.closed = YES; cleanups++; } }
@end
int sendMicrophoneOpusData(const unsigned char *data, int length) {
    Require(data != NULL && length > 0, "forwarded packet is valid"); sends++; return length;
}
@interface StreamFrameViewController : NSObject {
@public
    BOOL _microphoneCaptureStopped, _micStreamInitialized, _isEndingStream;
    NSUInteger _microphoneGeneration;
    Settings *_streamConfig, *_settings;
    MicHandler *micHandler;
}
- (void)stopMicrophoneCapture;
- (void)stageComplete:(const char *)name;
@end
@implementation StreamFrameViewController
#define dispatch_after Schedule
#include "stream_microphone_methods.inc"
#undef dispatch_after
@end
static StreamFrameViewController *Frame(void) {
    StreamFrameViewController *frame = [StreamFrameViewController new];
    frame->_settings = [Settings new]; frame->_settings.micVolume = @1;
    frame->_streamConfig = [Settings new]; frame->_streamConfig.redirectMic = YES;
    return frame;
}
static void RunPending(void) {
    NSArray *copy = pending.copy; [pending removeAllObjects];
    for (dispatch_block_t action in copy) action();
}
int main(void) {
    @autoreleasepool {
        pending = [NSMutableArray new]; activeOwner = [Connection new];
        StreamFrameViewController *f = Frame();
        [f stageComplete:NULL]; [f stageComplete:LiGetStageName(STAGE_INPUT_STREAM_START)];
        Require(pending.count == 0, "unrelated/null stages cannot start mic");
        [f stageComplete:LiGetStageName(STAGE_MIC_STREAM_START)];
        Require(pending.count == 1 && creations == 0, "published stage schedules capture");
        RunPending();
        Require(creations == 1 && starts == 1 && f->_micStreamInitialized, "published stage starts capture");
        [f stageComplete:LiGetStageName(STAGE_VIDEO_STREAM_START)];
        Require(f->_micStreamInitialized, "other stage cannot clear established microphone");
        f->micHandler.packet([@"opus" dataUsingEncoding:NSUTF8StringEncoding]);
        Require(sends == 1, "active connection receives packet");
        void (^oldPacket)(NSData *) = f->micHandler.packet;
        activeOwner = [Connection new];
        oldPacket([@"late" dataUsingEncoding:NSUTF8StringEncoding]);
        Require(sends == 1, "old owner packet cannot enter successor");
        [f stopMicrophoneCapture]; [f stopMicrophoneCapture];
        Require(cleanups == 1 && f->micHandler == nil && !f->_micStreamInitialized, "idempotent producer retirement");
        f = Frame(); [f stageComplete:LiGetStageName(STAGE_MIC_STREAM_START)];
        [f stopMicrophoneCapture]; RunPending();
        Require(creations == 1, "disconnect invalidates queued start");
        f = Frame(); [f stageComplete:LiGetStageName(STAGE_MIC_STREAM_START)];
        activeOwner = [Connection new]; RunPending();
        Require(creations == 1, "replaced owner cannot start capture");
        f = Frame(); [f stageComplete:LiGetStageName(STAGE_MIC_STREAM_START)];
        [f stageComplete:LiGetStageName(STAGE_MIC_STREAM_START)]; RunPending();
        Require(creations == 2, "duplicate stage invalidates older start");
        [f stopMicrophoneCapture];
        f = Frame(); [f stageComplete:LiGetStageName(STAGE_MIC_STREAM_START)];
        [f stageComplete:LiGetStageName(STAGE_MIC_STREAM_UNSUPPORTED_OR_UNINITIALIZED)]; RunPending();
        Require(creations == 2 && !f->_micStreamInitialized, "unsupported transport invalidates capture");
        [f stageComplete:LiGetStageName(STAGE_MIC_STREAM_START)];
        Require(pending.count == 0, "retired controller cannot be revived by stage callback");
        f = Frame(); [f stageComplete:LiGetStageName(STAGE_MIC_STREAM_START)]; allowed = NO; RunPending();
        Require(creations == 2, "permission is checked at actual capture start"); allowed = YES;
        f = Frame(); [f stageComplete:LiGetStageName(STAGE_MIC_STREAM_START)]; f->_streamConfig.redirectMic = NO; RunPending();
        Require(creations == 2, "disabled forwarding cannot start pending capture");
        f = Frame(); [f stageComplete:LiGetStageName(STAGE_MIC_STREAM_START)]; f->_isEndingStream = YES; RunPending();
        Require(creations == 2, "ending session cannot start pending capture");
        printf("PASS microphone stage/ownership: %d checks\n", checks);
    }
}
