#import <UIKit/UIKit.h>
#import "ExternalDisplayCoordinator.h"
#import "ExternalDisplayViewController.h"
#import "metal_view_lifecycle_tests.h"
#import "sbs_calibration_tests.h"
#import "frame_queue_tests.h"
#include <stdio.h>
#include <stdlib.h>

static NSUInteger testCount;
static NSUInteger failureCount;
static UIWindow *primaryTestWindow;

#define CHECK(condition, message) do { \
    if (!(condition)) { \
        [NSException raise:@"ExternalDisplayAssertion" format:@"%s:%d: %@", __FILE__, __LINE__, (message)]; \
    } \
} while (0)

@interface ExternalDisplayTestContext : NSObject
@property(nonatomic, strong) ExternalDisplayCoordinator *coordinator;
@property(nonatomic, strong) NSMutableArray<UIWindow *> *windows;
@property(nonatomic, strong) UIView *phoneHost;
@end

@implementation ExternalDisplayTestContext
- (instancetype)init {
    self = [super init];
    if (self) {
        _coordinator = [[ExternalDisplayCoordinator alloc] init];
        _windows = [NSMutableArray array];
        _phoneHost = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 240)];
        [primaryTestWindow.rootViewController.view addSubview:_phoneHost];
    }
    return self;
}

- (UIWindow *)newWindow {
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 640, 360)];
    window.rootViewController = [[ExternalDisplayViewController alloc] init];
    [self.windows addObject:window];
    return window;
}

- (UIView *)newPhoneView {
    UIView *view = [[UIView alloc] initWithFrame:self.phoneHost.bounds];
    [self.phoneHost addSubview:view];
    return view;
}

- (void)cleanUp {
    [self.coordinator clearRenderView];
    for (UIWindow *window in self.windows) {
        [self.coordinator unregisterWindow:window];
        window.hidden = YES;
    }
    [self.phoneHost removeFromSuperview];
}
@end

static UIView *ContentHost(UIWindow *window) {
    return ((ExternalDisplayViewController *)window.rootViewController).contentHostView;
}

static BOOL ContainsVisibleReadinessLabel(UIView *view) {
    if (view.hidden || view.alpha <= 0) return NO;
    if ([view isKindOfClass:UILabel.class] &&
        [((UILabel *)view).text isEqualToString:NSLocalizedString(@"Sunlight ready", nil)]) return YES;
    for (UIView *child in view.subviews) {
        if (ContainsVisibleReadinessLabel(child)) return YES;
    }
    return NO;
}

static void RunTest(NSString *name, void (^body)(ExternalDisplayTestContext *)) {
    @autoreleasepool {
        testCount++;
        ExternalDisplayTestContext *context = [[ExternalDisplayTestContext alloc] init];
        @try {
            body(context);
            printf("PASS: %s\n", name.UTF8String);
        } @catch (NSException *exception) {
            failureCount++;
            printf("FAIL: %s — %s\n", name.UTF8String, exception.reason.UTF8String);
        } @finally {
            [context cleanUp];
        }
        fflush(stdout);
    }
}

static void FinishTestsAfterCheckingDeferredReplacement(void) {
    // Return to the main queue before checking, so an accidental deferred clear
    // has a chance to execute. Nested run loops cannot drain the main queue
    // while the current main-queue block is still running.
    testCount++;
    ExternalDisplayTestContext *context = [[ExternalDisplayTestContext alloc] init];
    UIWindow *window = [context newWindow];
    UIView *first = [context newPhoneView];
    UIView *replacement = [context newPhoneView];
    [context.coordinator registerWindow:window];
    [context.coordinator setRenderView:first];
    [context.coordinator clearRenderView];
    [context.coordinator setRenderView:replacement];
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            CHECK(replacement.superview == ContentHost(window), @"Deferred work must not remove the replacement");
            CHECK([context.coordinator isPresentingView:replacement], @"Replacement must still be presented next main-queue turn");
            printf("PASS: replacement survives the next main-queue turn\n");
        } @catch (NSException *exception) {
            failureCount++;
            printf("FAIL: replacement survives the next main-queue turn — %s\n", exception.reason.UTF8String);
        } @finally {
            [context cleanUp];
        }
        printf("EXTERNAL_DISPLAY_TESTS_RESULT: %s %lu tests, %lu failures\n",
               failureCount ? "FAIL" : "PASS", (unsigned long)testCount, (unsigned long)failureCount);
        fflush(stdout);
        fflush(stderr);
        exit(failureCount ? EXIT_FAILURE : EXIT_SUCCESS);
    });
}

static void FinishTestsAfterBackgroundModeNotification(void) {
    testCount++;
    ExternalDisplayTestContext *context = [[ExternalDisplayTestContext alloc] init];
    UIWindow *window = [context newWindow];
    [context.coordinator registerWindow:window];
    [context.coordinator setValue:[NSValue valueWithCGSize:CGSizeMake(3840,1080)] forKey:@"lastModeSize"];
    __block NSUInteger changes = 0;
    __block BOOL callbackOnMain = YES;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SunlightExternalDisplayChangedNotification object:context.coordinator queue:nil usingBlock:^(NSNotification *note) {
        changes++; callbackOnMain &= NSThread.isMainThread;
    }];
    UIScreen *screen = window.screen;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:UIScreenModeDidChangeNotification object:screen];
        // Enqueued after the production handler's main-thread hop.
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                CHECK(changes == 1 && callbackOnMain, @"Background mode notification must resample and notify on main");
                printf("PASS: mode notifications from background are serialized on main\n");
            } @catch (NSException *exception) {
                failureCount++;
                printf("FAIL: background mode notification — %s\n", exception.reason.UTF8String);
            } @finally {
                [NSNotificationCenter.defaultCenter removeObserver:observer];
                [context cleanUp];
            }
            FinishTestsAfterCheckingDeferredReplacement();
        });
    });
}

static void RunExternalDisplayTests(void) {
    CHECK(NSThread.isMainThread, @"UIKit tests require the main thread");
    printf("External roles: legacy=%s modern=%s equal=%s\n",
           UIWindowSceneSessionRoleExternalDisplay.UTF8String,
           UIWindowSceneSessionRoleExternalDisplayNonInteractive.UTF8String,
           [UIWindowSceneSessionRoleExternalDisplay isEqualToString:UIWindowSceneSessionRoleExternalDisplayNonInteractive] ? "YES" : "NO");

    RunTest(@"registration immediately shows standalone readiness", ^(ExternalDisplayTestContext *t) {
        CHECK(t.coordinator.enabled, @"External output must default to enabled");
        CHECK(!t.coordinator.isAvailable, @"No window means no external output");
        UIWindow *window = [t newWindow];
        [t.coordinator registerWindow:window];
        CHECK(t.coordinator.externalWindow == window, @"Registered window must become active");
        CHECK(t.coordinator.isAvailable, @"Registered output must be available");
        CHECK(!window.hidden, @"Readiness window must be visible without any stream");
        CHECK(ContentHost(window).hidden, @"Empty content host must leave readiness visible");
        CHECK(ContainsVisibleReadinessLabel(window.rootViewController.view), @"Readiness text must be visible");
        CHECK(primaryTestWindow.isKeyWindow, @"External output must preserve the phone key window");
        CHECK(t.coordinator.externalScreen == window.screen, @"Output screen must come from its window");
    });

    RunTest(@"view requested before display stays on phone until registration", ^(ExternalDisplayTestContext *t) {
        UIView *view = [t newPhoneView];
        [t.coordinator setRenderView:view];
        CHECK(view.superview == t.phoneHost, @"Pending output must not detach phone content");
        CHECK(![t.coordinator isPresentingView:view], @"Pending view is not externally presented");
        CHECK(t.coordinator.hasRenderViewRequest, @"Pending source ownership must be recognized without a display");
        [t.coordinator clearRenderView];
        CHECK(!t.coordinator.hasRenderViewRequest, @"Clear must release a pending request without a display");
        CHECK(view.superview == t.phoneHost, @"Clearing a pending request must leave phone-owned content attached");
        [t.coordinator setRenderView:view];
        UIWindow *window = [t newWindow];
        [t.coordinator registerWindow:window];
        CHECK(view.superview == ContentHost(window), @"Registration must attach the pending view");
        CHECK([t.coordinator isPresentingView:view], @"Attached view must be reported as presented");
        CHECK(CGRectEqualToRect(view.frame, ContentHost(window).bounds), @"Pending content must be sized before return");
    });

    RunTest(@"display requested before view immediately presents content", ^(ExternalDisplayTestContext *t) {
        UIWindow *window = [t newWindow];
        [t.coordinator registerWindow:window];
        UIView *view = [t newPhoneView];
        [t.coordinator setRenderView:view];
        CHECK(view.superview == ContentHost(window), @"Stream must move into the active content host");
        CHECK(!ContentHost(window).hidden, @"Content host must be visible");
        CHECK(!ContainsVisibleReadinessLabel(window.rootViewController.view), @"Readiness must give way to content");
    });

    RunTest(@"clear is synchronous and cannot remove its replacement", ^(ExternalDisplayTestContext *t) {
        UIWindow *window = [t newWindow];
        [t.coordinator registerWindow:window];
        UIView *first = [t newPhoneView];
        UIView *replacement = [t newPhoneView];
        [t.coordinator setRenderView:first];
        [t.coordinator clearRenderView];
        CHECK(first.superview == nil, @"Clear must detach the old view synchronously");
        CHECK(ContainsVisibleReadinessLabel(window.rootViewController.view), @"Clear must immediately restore readiness");
        [t.coordinator setRenderView:replacement];
        CHECK(replacement.superview == ContentHost(window), @"Earlier clear must never detach a replacement");
        CHECK([t.coordinator isPresentingView:replacement], @"Replacement must remain the active view");
    });

    RunTest(@"unplug preserves pending content for phone fallback and reconnect", ^(ExternalDisplayTestContext *t) {
        UIWindow *firstWindow = [t newWindow];
        UIView *view = [t newPhoneView];
        [t.coordinator registerWindow:firstWindow];
        [t.coordinator setRenderView:view];
        [t.coordinator unregisterWindow:firstWindow];
        CHECK(!t.coordinator.isAvailable, @"Last disconnect must remove output availability");
        CHECK(t.coordinator.externalWindow == nil, @"Last disconnect must release the active window");
        CHECK(view.superview == nil, @"Disconnected host must release presented content");
        [t.phoneHost addSubview:view];
        UIWindow *replacementWindow = [t newWindow];
        [t.coordinator registerWindow:replacementWindow];
        CHECK(view.superview == ContentHost(replacementWindow), @"Reconnect must use the pending presentation request");
    });

    RunTest(@"retiring stream cannot clear a newer pending or visible request", ^(ExternalDisplayTestContext *t) {
        UIView *old = [t newPhoneView];
        UIView *current = [t newPhoneView];
        [t.coordinator setRenderView:old];
        [t.coordinator setRenderView:current];
        [t.coordinator clearRenderView:old];
        CHECK(t.coordinator.hasRenderViewRequest, @"Stale cleanup must preserve a newer pending request");
        UIWindow *window = [t newWindow];
        [t.coordinator registerWindow:window];
        CHECK([t.coordinator isPresentingView:current], @"Preserved request must appear when display connects");
        [t.coordinator clearRenderView:old];
        CHECK([t.coordinator isPresentingView:current], @"Stale cleanup must preserve visible replacement");
        [t.coordinator clearRenderView:current];
        CHECK(!t.coordinator.hasRenderViewRequest, @"Matching owner must be able to release its request");
        CHECK(ContainsVisibleReadinessLabel(window.rootViewController.view), @"Matching cleanup restores readiness");
    });

    RunTest(@"matching cleanup releases pending content without stealing phone view", ^(ExternalDisplayTestContext *t) {
        UIView *view = [t newPhoneView];
        [t.coordinator setRenderView:view];
        [t.coordinator clearRenderView:view];
        CHECK(!t.coordinator.hasRenderViewRequest, @"Matching pending request must be released");
        CHECK(view.superview == t.phoneHost, @"Release must not detach a phone-owned view");
        UIWindow *window = [t newWindow];
        [t.coordinator registerWindow:window];
        CHECK(ContainsVisibleReadinessLabel(window.rootViewController.view), @"Cancelled request cannot reappear after connection");
    });

    RunTest(@"repeated register and set do not emit duplicate changes", ^(ExternalDisplayTestContext *t) {
        __block NSUInteger changes = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:@"SunlightExternalDisplayChanged" object:nil queue:nil usingBlock:^(NSNotification *note) {
            changes++;
        }];
        @try {
            UIWindow *window = [t newWindow];
            UIView *view = [t newPhoneView];
            [t.coordinator registerWindow:window];
            CHECK(changes > 0, @"First registration must announce changed output");
            NSUInteger afterRegistration = changes;
            [t.coordinator registerWindow:window];
            CHECK(changes == afterRegistration, @"Repeated registration must be idempotent");
            [t.coordinator setRenderView:view];
            NSUInteger afterPresentation = changes;
            [t.coordinator setRenderView:view];
            CHECK(changes == afterPresentation, @"Repeated presentation must not emit another change");
            [t.coordinator windowDidUpdate:window];
            CHECK(changes == afterPresentation, @"Unchanged geometry must not emit another change");
        } @finally {
            [NSNotificationCenter.defaultCenter removeObserver:observer];
        }
    });

    RunTest(@"mode-only notification resamples current output and ignores duplicate or stale events", ^(ExternalDisplayTestContext *t) {
        UIWindow *window = [t newWindow];
        [t.coordinator registerWindow:window];
        __block NSUInteger changes = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:SunlightExternalDisplayChangedNotification object:t.coordinator queue:nil usingBlock:^(NSNotification *note) { changes++; }];
        @try {
            // Seed the prior-mode cache to simulate a hardware mode change;
            // the real window canvas and all coordinator methods stay intact.
            [t.coordinator setValue:[NSValue valueWithCGSize:CGSizeMake(3840,1080)] forKey:@"lastModeSize"];
            [NSNotificationCenter.defaultCenter postNotificationName:UIScreenModeDidChangeNotification object:window.screen];
            CHECK(changes == 1, @"Mode-only notification must reach windowDidUpdate without a scene-coordinate callback");
            [NSNotificationCenter.defaultCenter postNotificationName:UIScreenModeDidChangeNotification object:window.screen];
            CHECK(changes == 1, @"Unchanged repeated mode notification must be idempotent");
            [NSNotificationCenter.defaultCenter postNotificationName:UIScreenModeDidChangeNotification object:[NSObject new]];
            CHECK(changes == 1, @"A different screen identity must be ignored");
            [t.coordinator unregisterWindow:window];
            NSUInteger afterRemoval = changes;
            [NSNotificationCenter.defaultCenter postNotificationName:UIScreenModeDidChangeNotification object:window.screen];
            CHECK(changes == afterRemoval, @"Retired-screen notification must not recreate output");
        } @finally { [NSNotificationCenter.defaultCenter removeObserver:observer]; }
    });

    RunTest(@"disabled output preserves phone ownership and resumes pending view", ^(ExternalDisplayTestContext *t) {
        t.coordinator.enabled = NO;
        UIWindow *window = [t newWindow];
        UIView *view = [t newPhoneView];
        [t.coordinator registerWindow:window];
        [t.coordinator setRenderView:view];
        CHECK(window.hidden, @"Disabled output window must be hidden");
        CHECK(view.superview == t.phoneHost, @"Disabled output must preserve phone content");
        t.coordinator.enabled = YES;
        CHECK(!window.hidden, @"Enabling output must show its window");
        CHECK(view.superview == ContentHost(window), @"Enabling output must attach pending content");
        t.coordinator.enabled = NO;
        CHECK(view.superview == nil, @"Disabling output must detach content held by its host");
        [t.phoneHost addSubview:view];
        [t.coordinator clearRenderView];
        CHECK(view.superview == t.phoneHost, @"Clearing a pending view must not detach phone-owned content");
    });

    RunTest(@"nonactive and stale disconnects cannot clear active output", ^(ExternalDisplayTestContext *t) {
        UIWindow *firstWindow = [t newWindow];
        UIWindow *secondWindow = [t newWindow];
        UIWindow *neverRegistered = [t newWindow];
        UIView *view = [t newPhoneView];
        [t.coordinator registerWindow:firstWindow];
        [t.coordinator registerWindow:secondWindow];
        [t.coordinator setRenderView:view];
        CHECK(t.coordinator.externalWindow == firstWindow, @"First registered window retains preference");
        [t.coordinator unregisterWindow:neverRegistered];
        [t.coordinator unregisterWindow:secondWindow];
        [t.coordinator unregisterWindow:secondWindow];
        CHECK(t.coordinator.externalWindow == firstWindow, @"Unrelated disconnects must preserve the active window");
        CHECK(view.superview == ContentHost(firstWindow), @"Unrelated disconnects must preserve active content");
    });

    RunTest(@"active disconnect falls through to next registered window", ^(ExternalDisplayTestContext *t) {
        UIWindow *firstWindow = [t newWindow];
        UIWindow *secondWindow = [t newWindow];
        UIView *view = [t newPhoneView];
        [t.coordinator registerWindow:firstWindow];
        [t.coordinator registerWindow:secondWindow];
        [t.coordinator setRenderView:view];
        [t.coordinator unregisterWindow:firstWindow];
        CHECK(t.coordinator.externalWindow == secondWindow, @"Remaining registered window must become active");
        CHECK(view.superview == ContentHost(secondWindow), @"Pending content must follow the active output");
        [t.coordinator unregisterWindow:firstWindow];
        CHECK(view.superview == ContentHost(secondWindow), @"Late old disconnect must not touch replacement output");
    });

    RunTest(@"resize lays out content before posting output notification", ^(ExternalDisplayTestContext *t) {
        UIWindow *window = [t newWindow];
        UIView *view = [t newPhoneView];
        [t.coordinator registerWindow:window];
        [t.coordinator setRenderView:view];
        __block NSUInteger changes = 0;
        __block BOOL observedFinishedLayout = YES;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:@"SunlightExternalDisplayChanged" object:nil queue:nil usingBlock:^(NSNotification *note) {
            changes++;
            observedFinishedLayout &= CGRectEqualToRect(view.frame, ContentHost(window).bounds);
            observedFinishedLayout &= CGRectEqualToRect(ContentHost(window).bounds, window.rootViewController.view.bounds);
        }];
        @try {
            window.frame = CGRectMake(0, 0, 1000, 500);
            [t.coordinator windowDidUpdate:window];
            CHECK(CGRectEqualToRect(view.frame, ContentHost(window).bounds), @"Render view must fill resized content host");
            CHECK(CGRectEqualToRect(window.rootViewController.view.bounds, window.bounds), @"Root content must match resized window");
            CHECK(changes > 0, @"Changed output geometry must be announced");
            CHECK(observedFinishedLayout, @"Notifications must be delivered after geometry is updated");
        } @finally {
            [NSNotificationCenter.defaultCenter removeObserver:observer];
        }
    });

    RunTest(@"readiness renders at 1920 by 1080 for visual review", ^(ExternalDisplayTestContext *t) {
        ExternalDisplayViewController *controller = [[ExternalDisplayViewController alloc] init];
        [controller loadViewIfNeeded];
        controller.view.frame = CGRectMake(0, 0, 1920, 1080);
        [controller.view setNeedsLayout];
        [controller.view layoutIfNeeded];
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 1;
        format.opaque = YES;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:controller.view.bounds.size format:format];
        UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [controller.view.layer renderInContext:context.CGContext];
        }];
        NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/readiness-1920x1080.png"];
        CHECK([UIImagePNGRepresentation(image) writeToFile:path atomically:YES], @"Readiness preview must be saved");
        CHECK(CGImageGetWidth(image.CGImage) == 1920 && CGImageGetHeight(image.CGImage) == 1080, @"Preview must preserve exact output pixels");
    });

    RunTest(@"MetalView retains one worker across moves and detached intervals", ^(ExternalDisplayTestContext *t) {
        NSString *failure = nil;
        CHECK(SunlightTestMetalViewReparenting(primaryTestWindow, &failure), failure);
    });

    RunTest(@"MetalView terminal shutdown cannot restart on reattachment", ^(ExternalDisplayTestContext *t) {
        NSString *failure = nil;
        CHECK(SunlightTestMetalViewTerminalShutdown(primaryTestWindow, &failure), failure);
    });

    RunTest(@"MetalView pause blocks across reparenting and resumes one worker", ^(ExternalDisplayTestContext *t) {
        NSString *failure = nil;
        CHECK(SunlightTestMetalViewPause(primaryTestWindow, &failure), failure);
    });

    SunlightRunFrameQueueTests(^(NSString *name, void (^body)(void)) {
        RunTest(name, ^(ExternalDisplayTestContext *t) { body(); });
    });

    SunlightRunSBSCalibrationTests(primaryTestWindow, ^(NSString *name, void (^body)(void)) {
        RunTest(name, ^(ExternalDisplayTestContext *t) { body(); });
    });

    FinishTestsAfterBackgroundModeNotification();
}

@interface ExternalDisplayTestsAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation ExternalDisplayTestsAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UIViewController alloc] init];
    self.window.rootViewController.view.backgroundColor = UIColor.blackColor;
    [self.window makeKeyAndVisible];
    primaryTestWindow = self.window;
    dispatch_async(dispatch_get_main_queue(), ^{ RunExternalDisplayTests(); });
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(ExternalDisplayTestsAppDelegate.class));
    }
}
