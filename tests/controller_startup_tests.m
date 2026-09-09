#import <Foundation/Foundation.h>
#import <Limelight.h>

static NSMutableArray<dispatch_block_t> *pending;
static void FixtureAfter(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t callback) {
    (void)when; (void)queue; [pending addObject:[callback copy]];
}
@interface VoidController : NSObject
@property VoidController *mergedWithController;
@end
@implementation VoidController @end
@interface StartupConfig : NSObject
@property int gyroMode;
@end
@implementation StartupConfig @end
@interface ControllerSupport : NSObject {
@public
    BOOL _hostInputConnected, _localControlPadEnabled;
    VoidController *_oscController;
    NSMutableDictionary *_voidControllers;
    StartupConfig *_streamConfig;
    int _gyroMode;
}
@property NSUInteger gyroApplications;
- (void)connectionEstablished;
- (BOOL)psGyroEnabledInSetting;
- (void)updateFinished:(VoidController *)controller;
- (void)setButtonFlag:(VoidController *)controller flags:(int)flag;
- (void)clearButtonFlag:(VoidController *)controller flags:(int)flag;
- (void)applyGyroModeSetting;
@end
static ControllerSupport *VLSharedControllerSupport;
@implementation ControllerSupport
- (instancetype)init { self = [super init]; if (self) { _voidControllers = [NSMutableDictionary dictionary]; _streamConfig = [StartupConfig new]; _streamConfig.gyroMode = 2; } return self; }
- (BOOL)psGyroEnabledInSetting { return NO; }
- (void)updateFinished:(VoidController *)controller { (void)controller; }
- (void)setButtonFlag:(VoidController *)controller flags:(int)flag { (void)controller; (void)flag; }
- (void)clearButtonFlag:(VoidController *)controller flags:(int)flag { (void)controller; (void)flag; }
- (void)applyGyroModeSetting { self.gyroApplications++; }
#define dispatch_after FixtureAfter
#include "controller_startup.inc"
#undef dispatch_after
@end
static unsigned checks;
static void Check(BOOL okay, NSString *message) { checks++; if (!okay) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); } }
static void RunPending(void) { NSArray *blocks = [pending copy]; [pending removeAllObjects]; for (dispatch_block_t block in blocks) block(); }
int main(void) { @autoreleasepool {
    pending = [NSMutableArray array];
    ControllerSupport *active = [ControllerSupport new]; VLSharedControllerSupport = active;
    [active connectionEstablished]; Check(pending.count == 1 && active->_hostInputConnected, @"Established controller schedules delayed gyro setup");
    RunPending(); Check(active.gyroApplications == 1 && active->_gyroMode == 2, @"Current connected controller applies its gyro preference");
    ControllerSupport *retired = [ControllerSupport new]; VLSharedControllerSupport = retired;
    [retired connectionEstablished]; retired->_hostInputConnected = NO;
    RunPending(); Check(retired.gyroApplications == 0, @"Cleanup invalidates queued gyro setup even before a successor exists");
    ControllerSupport *superseded = [ControllerSupport new]; VLSharedControllerSupport = superseded;
    [superseded connectionEstablished]; VLSharedControllerSupport = active;
    RunPending(); Check(superseded.gyroApplications == 0 && active.gyroApplications == 1, @"Old delayed setup cannot change shared motion after another controller takes ownership");
    printf("Controller startup: %u checks passed\n", checks);
} return 0; }
