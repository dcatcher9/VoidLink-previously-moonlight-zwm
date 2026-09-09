#import <UIKit/UIKit.h>
#import <Limelight.h>
#import "SunlightControlPadView.h"

static NSUInteger checks;
static void Expect(BOOL passed, NSString *message) {
    if (!passed) {
        printf("CONTROL_PAD_TESTS_RESULT: FAIL %s\n", message.UTF8String);
        fflush(stdout);
        exit(1);
    }
    checks++;
}
// Exercises UIControl's public tracking entry points without injecting any
// device events. Production controls receive real UIKit touches in the app.
@interface PadTestTouch : UITouch
@property CGPoint point;
@end
@implementation PadTestTouch
- (CGPoint)locationInView:(UIView *)view { return self.point; }
@end

static UIControl *Control(SunlightControlPadView *pad, NSString *name) {
    NSString *identifier = [@"sunlight.controlPad." stringByAppendingString:name];
    for (UIView *child in pad.subviews) {
        if ([child.accessibilityIdentifier isEqualToString:identifier]) return (UIControl *)child;
    }
    Expect(NO, [@"Missing control: " stringByAppendingString:name]);
    return nil;
}
static PadTestTouch *Touch(CGFloat x, CGFloat y) {
    PadTestTouch *touch = [[PadTestTouch alloc] init];
    touch.point = CGPointMake(x, y);
    return touch;
}
static void Save(UIView *view, NSString *name) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor colorWithRed:9.0/255 green:17.0/255 blue:22.0/255 alpha:1] setFill];
        UIRectFill(view.bounds);
        [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES];
    }];
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    [UIImagePNGRepresentation(image) writeToFile:[documents stringByAppendingPathComponent:name] atomically:YES];
}

@interface PadTestAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation PadTestAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UIViewController alloc] init];
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{ [self runTests]; });
    return YES;
}
- (void)runTests {
    SunlightControlPadView *pad = [[SunlightControlPadView alloc] initWithFrame:CGRectMake(0, 0, 361, 390)];
    [self.window.rootViewController.view addSubview:pad];
    NSArray<NSString *> *names = @[@"a", @"b", @"x", @"y", @"up", @"down", @"left", @"right", @"back", @"menu", @"leftShoulder", @"rightShoulder", @"leftTrigger", @"rightTrigger", @"leftStick", @"rightStick"];
    const CGSize sizes[] = {{284,304}, {320,304}, {361,390}, {560,184}, {724,204}, {900,500}};
    for (NSUInteger index = 0; index < sizeof(sizes)/sizeof(*sizes); index++) {
        pad.frame = (CGRect){CGPointZero, sizes[index]};
        [pad setNeedsLayout];
        [pad layoutIfNeeded];
        NSMutableArray<UIControl *> *controls = [NSMutableArray array];
        for (NSString *name in names) {
            UIControl *control = Control(pad, name);
            Expect(CGRectGetWidth(control.bounds) >= 44 && CGRectGetHeight(control.bounds) >= 44, [@"44pt target: " stringByAppendingString:name]);
            Expect(CGRectContainsRect(pad.bounds, control.frame), [NSString stringWithFormat:@"Contained target: %@ %@ inside %@", name, NSStringFromCGRect(control.frame), NSStringFromCGRect(pad.bounds)]);
            Expect(control.isAccessibilityElement && control.accessibilityLabel.length > 0, [@"Accessible target: " stringByAppendingString:name]);
            for (UIControl *other in controls) {
                CGRect intersection = CGRectIntersection(control.frame, other.frame);
                Expect(CGRectIsNull(intersection) || CGRectGetWidth(intersection) == 0 || CGRectGetHeight(intersection) == 0, @"Independent controls never overlap");
            }
            [controls addObject:control];
        }
        if (index == 2) Save(pad, @"control-pad-portrait.png");
        if (index == 4) Save(pad, @"control-pad-landscape.png");
        if (index == 5) Save(pad, @"control-pad-tablet.png");
    }
    __block int held = 0;
    __block NSUInteger downs = 0, ups = 0, leftChanges = 0, rightChanges = 0;
    __block CGPoint left = CGPointZero, right = CGPointZero;
    __block float leftTrigger = 0, rightTrigger = 0;
    pad.buttonChangedHandler = ^(int flag, BOOL down) {
        Expect(flag != 0, @"Triggers never emit button flag zero");
        if (down) { held |= flag; downs++; }
        else { held &= ~flag; ups++; }
    };
    pad.leftStickChangedHandler = ^(CGPoint value) { left = value; leftChanges++; };
    pad.rightStickChangedHandler = ^(CGPoint value) { right = value; rightChanges++; };
    pad.leftTriggerChangedHandler = ^(float value) { leftTrigger = value; };
    pad.rightTriggerChangedHandler = ^(float value) { rightTrigger = value; };
    PadTestTouch *buttonTouch = Touch(22, 22);
    UIControl *a = Control(pad, @"a"), *up = Control(pad, @"up");
    Expect([a beginTrackingWithTouch:buttonTouch withEvent:nil], @"A begins");
    Expect([up beginTrackingWithTouch:Touch(22,22) withEvent:nil], @"D-pad begins independently");
    Expect(held == (A_FLAG | UP_FLAG), @"Independent simultaneous buttons");
    [a endTrackingWithTouch:buttonTouch withEvent:nil];
    Expect(held == UP_FLAG, @"Releasing one button preserves another");
    [pad releaseAllControls];
    Expect(held == 0, @"Release all clears held flags");
    NSUInteger priorUps = ups;
    [pad releaseAllControls];
    Expect(ups == priorUps, @"Release all is idempotent");
    Expect(![up continueTrackingWithTouch:buttonTouch withEvent:nil] && held == 0, @"Old touch cannot reactivate after release all");
    [a beginTrackingWithTouch:buttonTouch withEvent:nil];
    buttonTouch.point = CGPointMake(-1, 22);
    Expect(![a continueTrackingWithTouch:buttonTouch withEvent:nil] && held == 0, @"Moving off releases a button");
    buttonTouch.point = CGPointMake(22, 22);
    Expect(![a continueTrackingWithTouch:buttonTouch withEvent:nil] && held == 0, @"Moving back inside requires a fresh touch");
    [a beginTrackingWithTouch:buttonTouch withEvent:nil];
    [a cancelTrackingWithEvent:nil];
    Expect(held == 0, @"Cancellation releases without another press");
    UIControl *ls = Control(pad, @"leftStick"), *rs = Control(pad, @"rightStick");
    PadTestTouch *stickTouch = Touch(82,52);
    [ls beginTrackingWithTouch:stickTouch withEvent:nil];
    [rs beginTrackingWithTouch:Touch(52,22) withEvent:nil];
    Expect(left.x == 1 && left.y == 0 && right.x == 0 && right.y == 1, @"Both sticks track independently with up-positive Y");
    stickTouch.point = CGPointMake(103,1);
    [ls continueTrackingWithTouch:stickTouch withEvent:nil];
    Expect(fabs(hypot(left.x,left.y)-1) < 0.000001, @"Diagonal stick clamps to unit circle");
    stickTouch.point = CGPointMake(-1,52);
    Expect(![ls continueTrackingWithTouch:stickTouch withEvent:nil] && CGPointEqualToPoint(left,CGPointZero), @"Moving off releases stick");
    Expect(right.y == 1, @"Other stick stays held");
    [pad releaseAllControls];
    Expect(CGPointEqualToPoint(right,CGPointZero), @"Release all centers both sticks");
    [ls beginTrackingWithTouch:Touch(53,52) withEvent:nil];
    Expect(CGPointEqualToPoint(left,CGPointZero), @"Center dead zone removes tiny movements");
    [Control(pad,@"leftTrigger") beginTrackingWithTouch:buttonTouch withEvent:nil];
    [Control(pad,@"rightTrigger") beginTrackingWithTouch:buttonTouch withEvent:nil];
    Expect(leftTrigger == 1 && rightTrigger == 1 && held == 0, @"Both trigger channels independent of buttons");
    [pad releaseAllControls];
    Expect(leftTrigger == 0 && rightTrigger == 0, @"Release all resets triggers");
    [a beginTrackingWithTouch:buttonTouch withEvent:nil];
    pad.hidden = YES;
    pad.hidden = NO;
    Expect(held == 0 && ![a continueTrackingWithTouch:buttonTouch withEvent:nil], @"Hide/show retires active touches");
    [a beginTrackingWithTouch:buttonTouch withEvent:nil];
    pad.userInteractionEnabled = NO;
    pad.userInteractionEnabled = YES;
    Expect(held == 0 && ![a continueTrackingWithTouch:buttonTouch withEvent:nil], @"Disable/enable retires active touches");
    [a beginTrackingWithTouch:buttonTouch withEvent:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    Expect(held == 0, @"Background releases held input");
    [a beginTrackingWithTouch:buttonTouch withEvent:nil];
    [pad removeFromSuperview];
    Expect(held == 0, @"Removal releases held input");
    Expect([a accessibilityActivate] && held == 0 && downs == ups, @"Accessible button emits a balanced press and release");
    Expect(leftChanges >= 2 && rightChanges >= 2, @"Stick release callbacks delivered");
    printf("CONTROL_PAD_TESTS_RESULT: PASS %lu checks\n", (unsigned long)checks);
    fflush(stdout);
    exit(0);
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(PadTestAppDelegate.class));
    }
}
