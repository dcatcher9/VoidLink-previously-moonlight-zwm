#import "relative_touch_test_doubles.h"
#import "RelativeTouchHandler.h"
#import <UIKit/UIGestureRecognizerSubclass.h>
#include <Limelight.h>

@implementation StreamView
- (NSUInteger)hostInputGeneration { return self.gate.generation; }
- (BOOL)hostInputAllowed { return self.gate.allowed; }
- (BOOL)hostTouchInputAllowed { return self.gate.allowed; }
- (void)performHostInputForGeneration:(NSUInteger)generation action:(dispatch_block_t)action {
    [self.gate performForGeneration:generation action:action];
}
- (void)performHostInput:(dispatch_block_t)action { [self.gate perform:action]; }
@end
@implementation TemporarySettings @end
@implementation OnScreenControls
+ (NSMutableSet *)touchesCapturedByOnScreenControls {
    static NSMutableSet *touches; static dispatch_once_t once;
    dispatch_once(&once, ^{ touches = [NSMutableSet set]; });
    return touches;
}
@end
@implementation UITouchUtil
+ (NSSet *)touchesIn:(UIView *)view from:(UIEvent *)event {
    return [event.allTouches filteredSetUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(UITouch *touch, NSDictionary *bindings) {
        return touch.view == view;
    }]];
}
+ (CGVector)vectorOf:(UITouch *)touch in:(UIView *)view {
    CGPoint p = [touch locationInView:view], q = [touch previousLocationInView:view];
    return CGVectorMake(p.x - q.x, p.y - q.y);
}
@end
@implementation TouchPadGestureHandler
static BOOL ctrl;
+ (BOOL)ctrlDown { return ctrl; }
+ (void)setCtrlDown:(BOOL)value { ctrl = value; }
+ (void)handleGestureIn:(UIView *)view with:(UIEvent *)event {}
+ (void)startInertialScroll {}
@end
@implementation CommandManager
+ (NSDictionary *)keyboardButtonMappings { return @{@"CTRL": @0x11}; }
@end

@interface FakeTouch : UITouch
@property (nonatomic, weak) UIView *sourceView;
@property (nonatomic) CGPoint point;
@property (nonatomic) CGPoint previous;
@end
@implementation FakeTouch
- (UIView *)view { return self.sourceView; }
- (CGPoint)locationInView:(UIView *)view { return self.point; }
- (CGPoint)previousLocationInView:(UIView *)view { return self.previous; }
@end
@interface FakeEvent : UIEvent
@property (nonatomic, strong) NSSet *suppliedTouches;
@end
@implementation FakeEvent
- (NSSet *)allTouches { return self.suppliedTouches; }
@end
@interface RelativeTouchHandler (TestEntry)
- (void)mouseRightClick;
@end

static NSMutableArray<NSString *> *events;
static int cases;
static void Require(BOOL okay, const char *message) {
    if (!okay) { fprintf(stderr, "RELATIVE_TOUCH_TESTS_RESULT: FAIL %s\n", message); fflush(stderr); exit(1); }
}
static void Pass(const char *name) { ++cases; printf("PASS %s\n", name); fflush(stdout); }
static void Record(NSString *event) { @synchronized(events) { [events addObject:event]; } }
static NSArray *Snapshot(void) { @synchronized(events) { return [events copy]; } }
static void Clear(void) { @synchronized(events) { [events removeAllObjects]; } }
int LiSendMouseButtonEvent(char action, int button) {
    Record([NSString stringWithFormat:@"%d:%@", button, action == BUTTON_ACTION_PRESS ? @"down" : @"up"]);
    return 0;
}
int LiSendMouseMoveEvent(short x, short y) { Record(@"move"); return 0; }
int LiSendKeyboardEvent(short key, char action, char mods) { Record(@"key"); return 0; }
static void Pump(NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (end.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:MIN(0.005, end.timeIntervalSinceNow)]];
    }
}
static void WaitFor(BOOL (^predicate)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!predicate() && end.timeIntervalSinceNow > 0) Pump(0.002);
    Require(predicate(), "asynchronous mouse delivery timed out");
}
static NSUInteger Count(NSString *value) { return [Snapshot() filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF == %@", value]].count; }
static FakeTouch *Touch(StreamView *view, CGFloat x) {
    FakeTouch *touch = [FakeTouch new]; touch.sourceView = view;
    touch.point = touch.previous = CGPointMake(x, 80); return touch;
}
static FakeEvent *Event(NSSet *touches) { FakeEvent *event = [FakeEvent new]; event.suppliedTouches = touches; return event; }
static RelativeTouchHandler *Handler(StreamView **outView) {
    StreamView *view = [[StreamView alloc] initWithFrame:CGRectMake(0, 0, 400, 800)];
    view.streamFrameTopLayerView = [UIView new];
    view.gate = [SunlightInputGate new];
    [view.gate setConnected:YES cancellation:^{}];
    TemporarySettings *settings = [TemporarySettings new];
    settings.singleTapSensitivity = @3; settings.relativeTouchSlideThreshold = @2; settings.mousePointerVelocityFactor = @1;
    RelativeTouchHandler *handler = [[RelativeTouchHandler alloc] initWithView:view andSettings:settings];
    // UIKit action delivery is deliberately driven in both legal orders below;
    // recognizer touch/state code itself remains the real production class.
    [handler.mouseRightClickTapRecognizer removeTarget:nil action:NULL];
    *outView = view;
    Clear(); return handler;
}
static void SingleTap(void) {
    StreamView *view; RelativeTouchHandler *handler = Handler(&view);
    NSSet *touches = [NSSet setWithObject:Touch(view, 100)]; FakeEvent *event = Event(touches);
    [handler touchesBegan:touches withEvent:event];
    [handler touchesEnded:touches withEvent:event];
    WaitFor(^BOOL{ return Count(@"1:up") == 1; });
    Require([Snapshot() isEqualToArray:@[@"1:down", @"1:up"]], "single tap did not produce exactly one left click");
    Pass("stationary single tap produces only one left click");
}
static void RightTap(BOOL actionBeforeTouchUp, BOOL sequentialFingers) {
    StreamView *view; RelativeTouchHandler *handler = Handler(&view);
    FakeTouch *first = Touch(view, 100), *second = Touch(view, 130);
    NSSet *one = [NSSet setWithObject:first], *both = [NSSet setWithObjects:first, second, nil];
    FakeEvent *event = Event(both);
    CustomTapGestureRecognizer *recognizer = handler.mouseRightClickTapRecognizer;
    Require(!recognizer.cancelsTouchesInView, "right-click recognizer cancels its own pending action");
    if (sequentialFingers) {
        [handler touchesBegan:one withEvent:Event(one)];
        [recognizer touchesBegan:one withEvent:Event(one)];
        [handler touchesBegan:[NSSet setWithObject:second] withEvent:event];
    } else [handler touchesBegan:both withEvent:event];
    [recognizer touchesBegan:both withEvent:event];
    [recognizer touchesEnded:both withEvent:event];
    Require(recognizer.state == UIGestureRecognizerStateRecognized, "two-finger quick tap was not recognized");
    if (actionBeforeTouchUp) [handler mouseRightClick];
    [handler touchesEnded:both withEvent:event];
    if (!actionBeforeTouchUp) [handler mouseRightClick];
    WaitFor(^BOOL{ return Count(@"3:up") == 1; });
    Pump(0.23);
    Require([Snapshot() isEqualToArray:@[@"3:down", @"3:up"]], "two-finger tap produced an extra left click or wrong right click");
    Pass(actionBeforeTouchUp ? "right-click action before finger-up sends only right click" : "right-click action after finger-up sends only right click");
}
static void Drag(void) {
    StreamView *view; RelativeTouchHandler *handler = Handler(&view);
    NSSet *first = [NSSet setWithObject:Touch(view, 100)];
    [handler touchesBegan:first withEvent:Event(first)];
    [handler touchesEnded:first withEvent:Event(first)];
    WaitFor(^BOOL{ return Count(@"1:down") == 1; });
    FakeTouch *held = Touch(view, 101); NSSet *second = [NSSet setWithObject:held];
    [handler touchesBegan:second withEvent:Event(second)];
    held.previous = held.point; held.point = CGPointMake(120, 80);
    [handler touchesMoved:second withEvent:Event(second)];
    Pump(0.02);
    held.previous = held.point; held.point = CGPointMake(150, 80);
    [handler touchesMoved:second withEvent:Event(second)];
    Pump(0.24);
    Require(Count(@"move") > 0 && Count(@"1:up") == 0, "second tap did not hold the mouse button through dragging");
    [handler touchesEnded:second withEvent:Event(second)];
    Pump(0.12);
    Require(Count(@"1:down") == 1 && Count(@"1:up") == 1 && Count(@"3:down") == 0, "drag release synthesized an extra click or left a held button");
    Pass("double-tap hold drags and releases without an extra click");
}
static void CancelPendingTap(void) {
    StreamView *view; RelativeTouchHandler *handler = Handler(&view);
    NSSet *touches = [NSSet setWithObject:Touch(view, 100)];
    [handler touchesBegan:touches withEvent:Event(touches)];
    // Prevent the async send crossing this boundary until cancellation has
    // changed the actual gate generation. No scheduler timing assumption.
    [view.gate perform:^{
        [handler touchesEnded:touches withEvent:Event(touches)];
        [view.gate setBlocked:YES cancellation:^{ [handler cancelHostTouches]; }];
    }];
    [view.gate setBlocked:NO cancellation:^{}];
    Pump(0.28);
    Require(Count(@"1:down") == 0 && Count(@"3:down") == 0, "opening/closing controls revived a queued tap");
    Pass("panel cancellation rejects a pending tap after closing");
}
static void OldFinger(void) {
    StreamView *view; RelativeTouchHandler *handler = Handler(&view);
    FakeTouch *old = Touch(view, 100); NSSet *touches = [NSSet setWithObject:old];
    [handler touchesBegan:touches withEvent:Event(touches)];
    [view.gate setBlocked:YES cancellation:^{ [handler cancelHostTouches]; }];
    [view.gate setBlocked:NO cancellation:^{}]; Clear();
    old.previous = old.point; old.point = CGPointMake(180, 80);
    [handler touchesMoved:touches withEvent:Event(touches)];
    [handler touchesEnded:touches withEvent:Event(touches)];
    Pump(0.28);
    Require(Snapshot().count == 0, "cancelled old finger reactivated after controls closed");
    NSSet *fresh = [NSSet setWithObject:Touch(view, 110)];
    [handler touchesBegan:fresh withEvent:Event(fresh)];
    [handler touchesEnded:fresh withEvent:Event(fresh)];
    WaitFor(^BOOL{ return Count(@"1:up") == 1; });
    Require(Count(@"1:down") == 1, "fresh touch was not accepted after cancellation");
    Pass("old finger stays cancelled after closing; fresh touch works");
}
static void PillExclusion(void) {
    StreamView *view; RelativeTouchHandler *handler = Handler(&view);
    UIView *pill = [UIView new]; FakeTouch *touch = Touch(view, 100); touch.sourceView = pill;
    id<UIGestureRecognizerDelegate> delegate = handler.mouseRightClickTapRecognizer.delegate;
    Require(![delegate gestureRecognizer:handler.mouseRightClickTapRecognizer shouldReceiveTouch:touch], "ancestor recognizer accepted a pill touch");
    touch.sourceView = view;
    Require([delegate gestureRecognizer:handler.mouseRightClickTapRecognizer shouldReceiveTouch:touch], "recognizer rejected a stream touch");
    [view.gate setBlocked:YES cancellation:^{ [handler cancelHostTouches]; }];
    Require(![delegate gestureRecognizer:handler.mouseRightClickTapRecognizer shouldReceiveTouch:touch], "blocked recognizer accepted touch");
    Pass("ancestor recognizer rejects pill and blocked stream touches");
}
@interface TestDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation TestDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new]; [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{
        events = [NSMutableArray array];
        SingleTap(); RightTap(YES, YES); RightTap(NO, YES); RightTap(YES, NO);
        Drag(); CancelPendingTap(); OldFinger(); PillExclusion();
        printf("RELATIVE_TOUCH_TESTS_RESULT: PASS %d cases\n", cases); fflush(stdout); exit(0);
    });
    return YES;
}
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(TestDelegate.class)); } }
