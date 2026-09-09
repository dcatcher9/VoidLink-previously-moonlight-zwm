#import "sbs_calibration_tests.h"
#import "ExternalDisplayCoordinator.h"
#import "ExternalDisplayViewController.h"
#import "SBSCalibrationView.h"
#import "SunlightGlassesModePolicy.h"
#include <stdio.h>

// These doubles change only display capability reports. Unrelated screen calls
// forward to the real simulator screen so the window/content host remain UIKit.
@interface CalibrationModeDouble : NSProxy
@property(nonatomic) CGSize pixelSize;
@property(nonatomic, strong) UIScreenMode *backingMode;
@end

@implementation CalibrationModeDouble
- (CGSize)size { return self.pixelSize; }
- (CGFloat)pixelAspectRatio { return 1.0; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector { return [self.backingMode methodSignatureForSelector:selector]; }
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:self.backingMode]; }
@end

@interface CalibrationScreenDouble : NSProxy
@property(nonatomic, strong) UIScreen *backingScreen;
@property(nonatomic, strong) CalibrationModeDouble *mode;
@property(nonatomic) CGFloat reportedScale;
@end

@implementation CalibrationScreenDouble
- (UIScreenMode *)currentMode { return (UIScreenMode *)self.mode; }
- (UIScreenMode *)preferredMode { return (UIScreenMode *)self.mode; }
- (NSArray<UIScreenMode *> *)availableModes { return @[(UIScreenMode *)self.mode]; }
- (CGFloat)scale { return self.reportedScale; }
- (CGFloat)nativeScale { return self.reportedScale; }
- (CGRect)nativeBounds { return (CGRect){CGPointZero, self.mode.pixelSize}; }
- (CGRect)bounds { return CGRectMake(0, 0, self.mode.pixelSize.width / self.reportedScale, self.mode.pixelSize.height / self.reportedScale); }
- (NSInteger)maximumFramesPerSecond { return 60; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector { return [self.backingScreen methodSignatureForSelector:selector]; }
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:self.backingScreen]; }
@end

@interface CalibrationWindow : UIWindow
@property(nonatomic, strong) CalibrationScreenDouble *reportedScreen;
@property(nonatomic) BOOL useReportedScreen;
@end

@implementation CalibrationWindow
- (UIScreen *)screen { return self.useReportedScreen ? (UIScreen *)self.reportedScreen : [super screen]; }
@end

// UIKit's window geometry internals require the actual registered screen
// identity. Inject metrics only while exercising the production capability
// predicate; window creation, layout, and presentation still use real UIKit.
@interface CalibrationCoordinator : ExternalDisplayCoordinator
@end

@implementation CalibrationCoordinator
- (CGSize)outputPixelSize {
    CalibrationWindow *window = (CalibrationWindow *)self.externalWindow;
    BOOL wasReported = window.useReportedScreen;
    window.useReportedScreen = YES;
    @try { return [super outputPixelSize]; }
    @finally { window.useReportedScreen = wasReported; }
}
@end

@interface CalibrationFixture : NSObject
@property(nonatomic, strong) ExternalDisplayCoordinator *coordinator;
@property(nonatomic, strong) NSMutableArray<CalibrationWindow *> *windows;
@property(nonatomic, strong) UIView *phoneHost;
@end

@implementation CalibrationFixture
- (instancetype)initWithPrimaryWindow:(UIWindow *)primaryWindow {
    self = [super init];
    if (self) {
        _coordinator = [[CalibrationCoordinator alloc] init];
        _windows = [NSMutableArray array];
        _phoneHost = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 180)];
        [primaryWindow.rootViewController.view addSubview:_phoneHost];
    }
    return self;
}

- (CalibrationWindow *)windowWithPixels:(CGSize)pixels size:(CGSize)points scale:(CGFloat)scale {
    CalibrationWindow *window = [[CalibrationWindow alloc] initWithFrame:(CGRect){CGPointZero, points}];
    UIScreen *actualScreen = window.screen;
    CalibrationModeDouble *mode = [CalibrationModeDouble alloc];
    mode.backingMode = actualScreen.currentMode;
    mode.pixelSize = pixels;
    CalibrationScreenDouble *screen = [CalibrationScreenDouble alloc];
    screen.backingScreen = actualScreen;
    screen.mode = mode;
    screen.reportedScale = scale;
    window.reportedScreen = screen;
    window.rootViewController = [[ExternalDisplayViewController alloc] init];
    [self.windows addObject:window];
    return window;
}

- (CalibrationWindow *)fullSBSWindow {
    return [self windowWithPixels:CGSizeMake(3840, 1080) size:CGSizeMake(3840, 1080) scale:1];
}

- (void)setWindow:(CalibrationWindow *)window pixels:(CGSize)pixels size:(CGSize)points scale:(CGFloat)scale {
    window.reportedScreen.mode.pixelSize = pixels;
    window.reportedScreen.reportedScale = scale;
    window.frame = (CGRect){CGPointZero, points};
    [self.coordinator windowDidUpdate:window];
}

- (void)cleanUp {
    [self.coordinator stopCalibration];
    [self.coordinator clearRenderView];
    for (CalibrationWindow *window in self.windows) {
        [self.coordinator unregisterWindow:window];
        window.hidden = YES;
        window.reportedScreen = nil;
    }
    [self.phoneHost removeFromSuperview];
}
@end

static void RequireCalibration(BOOL condition, NSString *message) {
    if (!condition) [NSException raise:@"SBSCalibrationAssertion" format:@"%@", message];
}

static UIView *CalibrationHost(UIWindow *window) {
    return ((ExternalDisplayViewController *)window.rootViewController).contentHostView;
}

static SBSCalibrationView *PresentedPattern(UIWindow *window) {
    UIView *host = CalibrationHost(window);
    for (UIView *view in host.subviews) {
        if ([view isKindOfClass:SBSCalibrationView.class]) return (SBSCalibrationView *)view;
    }
    return nil;
}

static void RunCalibrationCase(UIWindow *primaryWindow, SunlightCalibrationCaseRunner runCase,
                               NSString *name, void (^body)(CalibrationFixture *)) {
    runCase(name, ^{
        CalibrationFixture *fixture = [[CalibrationFixture alloc] initWithPrimaryWindow:primaryWindow];
        @try { body(fixture); }
        @finally { [fixture cleanUp]; }
    });
}

static UIImage *RenderCalibration(SBSCalibrationView *view, NSString *filename) {
    view.contentScaleFactor = 1;
    [view setNeedsLayout];
    [view layoutIfNeeded];
    [view setNeedsDisplay];
    [view.layer displayIfNeeded];
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [view.layer renderInContext:context.CGContext];
    }];
    NSString *path = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:filename];
    RequireCalibration([UIImagePNGRepresentation(image) writeToFile:path atomically:YES], @"Calibration preview must be saved");
    return image;
}

static NSData *NormalizedImagePixels(CGImageRef image) {
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    NSMutableData *bytes = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(bytes.mutableBytes, width, height, 8, width * 4,
                                                 colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    return bytes;
}

static BOOL ImageRegionsMatch(CGImageRef first, CGRect firstRect, CGImageRef second, CGRect secondRect, BOOL allowEdgeRounding) {
    CGImageRef firstCrop = CGImageCreateWithImageInRect(first, firstRect);
    CGImageRef secondCrop = CGImageCreateWithImageInRect(second, secondRect);
    NSData *firstData = NormalizedImagePixels(firstCrop);
    NSData *secondData = NormalizedImagePixels(secondCrop);
    CGImageRelease(firstCrop);
    CGImageRelease(secondCrop);
    if (!allowEdgeRounding) return [firstData isEqualToData:secondData];
    if (firstData.length != secondData.length) return NO;
    const uint8_t *firstBytes = firstData.bytes, *secondBytes = secondData.bytes;
    NSUInteger changedPixels = 0;
    int maximumDelta = 0;
    for (NSUInteger index = 0; index < firstData.length; index += 4) {
        BOOL changed = NO;
        for (NSUInteger channel = 0; channel < 4; channel++) {
            int delta = abs(firstBytes[index + channel] - secondBytes[index + channel]);
            maximumDelta = MAX(maximumDelta, delta);
            changed |= delta > 0;
        }
        changedPixels += changed;
    }
    printf("SBS eye comparison: %lu changed pixels, maximum channel delta %d\n", (unsigned long)changedPixels, maximumDelta);
    // Translating identical paths by one eye width produced only 12/14 pixels
    // of one-level antialiasing rounding per 2,073,600-pixel eye on iOS 26.5.
    // Permit at most 64 such pixels; geometry assertions remain exact.
    return maximumDelta <= 1 && changedPixels <= 64;
}

void SunlightRunSBSCalibrationTests(UIWindow *primaryWindow, SunlightCalibrationCaseRunner runCase) {
    RunCalibrationCase(primaryWindow, runCase, @"display mode distinguishes missing, disabled and incomplete output", ^(CalibrationFixture *t) {
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayModeUnknown && CGSizeEqualToSize(t.coordinator.outputPixelSize, CGSizeZero), @"Absent output must be unknown with no pixels");
        CalibrationWindow *window = [t windowWithPixels:CGSizeMake(1920,1080) size:CGSizeMake(1920,1080) scale:1];
        [t.coordinator registerWindow:window];
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayMode2D && CGSizeEqualToSize(t.coordinator.outputPixelSize, CGSizeMake(1920,1080)), @"Settled normal mode must report actual pixels");
        t.coordinator.enabled = NO;
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayModeUnknown && CGSizeEqualToSize(t.coordinator.outputPixelSize, CGSizeZero), @"Disabled routing is unknown, not normal mode");
        t.coordinator.enabled = YES;
        [t setWindow:window pixels:CGSizeMake(3840,1080) size:CGSizeMake(1920,1080) scale:1];
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayModeUnknown && CGSizeEqualToSize(t.coordinator.outputPixelSize, CGSizeZero), @"Unsettled canvas must not trigger a 2D fallback");
        window.reportedScreen.mode.pixelSize = CGSizeZero;
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayModeUnknown, @"Missing current mode must stay unknown");
        window.reportedScreen.mode.pixelSize = CGSizeMake(NAN, 1080);
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayModeUnknown, @"Nonfinite mode must stay unknown");
        window.reportedScreen.mode.pixelSize = CGSizeMake(1920,1080);
        window.reportedScreen.reportedScale = 0;
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayModeUnknown, @"Invalid pixel scale must stay unknown");
    });

    RunCalibrationCase(primaryWindow, runCase, @"normal to unknown to SBS never mistakes reconnect gap for normal output", ^(CalibrationFixture *t) {
        CalibrationWindow *normal = [t windowWithPixels:CGSizeMake(1920,1080) size:CGSizeMake(1920,1080) scale:1];
        [t.coordinator registerWindow:normal];
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayMode2D, @"Normal output must be classified");
        [t.coordinator unregisterWindow:normal];
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayModeUnknown, @"Physical mode reconnect gap must be unknown");
        CalibrationWindow *sbs = [t windowWithPixels:CGSizeMake(3840,1080) size:CGSizeMake(1920,540) scale:2];
        [t.coordinator registerWindow:sbs];
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayMode3D && t.coordinator.calibrationOutputCompatible, @"Settled scaled SBS canvas must be recognized");
        RequireCalibration(CGSizeEqualToSize(t.coordinator.outputPixelSize, CGSizeMake(3840,1080)), @"Report scanout pixels rather than UIKit points");
        [t.coordinator windowDidUpdate:normal];
        [t.coordinator unregisterWindow:normal];
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayMode3D, @"Stale old-window updates cannot override current SBS mode");
    });

    RunCalibrationCase(primaryWindow, runCase, @"SBS to unknown to normal reports confirmed fallback only after canvas settles", ^(CalibrationFixture *t) {
        CalibrationWindow *sbs = [t fullSBSWindow];
        [t.coordinator registerWindow:sbs];
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayMode3D, @"Initial SBS mode must be recognized");
        [t.coordinator unregisterWindow:sbs];
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayModeUnknown, @"Disconnect must not manufacture a normal-mode event");
        CalibrationWindow *normal = [t windowWithPixels:CGSizeMake(1920,1080) size:CGSizeMake(3840,1080) scale:1];
        [t.coordinator registerWindow:normal];
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayModeUnknown, @"Replacement window can arrive before normal geometry settles");
        [t setWindow:normal pixels:CGSizeMake(1920,1080) size:CGSizeMake(1920,1080) scale:1];
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayMode2D && !t.coordinator.calibrationOutputCompatible, @"Settled normal output must report 2D");
        [t.coordinator unregisterWindow:sbs];
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayMode2D, @"Late disconnect for old SBS scene must leave replacement mode intact");
    });

    RunCalibrationCase(primaryWindow, runCase, @"only verified SBS scanout is 3D and other settled pixels are 2D", ^(CalibrationFixture *t) {
        CalibrationWindow *window = [t windowWithPixels:CGSizeMake(2560,1440) size:CGSizeMake(1280,720) scale:2];
        [t.coordinator registerWindow:window];
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayMode2D && CGSizeEqualToSize(t.coordinator.outputPixelSize, CGSizeMake(2560,1440)), @"Normal classification must use any other settled pixel mode");
        [t setWindow:window pixels:CGSizeMake(3841,1080) size:CGSizeMake(3841,1080) scale:1];
        RequireCalibration(t.coordinator.displayMode == SunlightExternalDisplayMode2D, @"An approximately wide mode is not verified SBS");
    });

    RunCalibrationCase(primaryWindow, runCase, @"glasses mode policy preserves 2D through a normal to SBS transition", ^(CalibrationFixture *t) {
        SunlightStreamMode active = SunlightStreamMode2D;
        CalibrationWindow *normal = [t windowWithPixels:CGSizeMake(1920,1080) size:CGSizeMake(1920,1080) scale:1];
        [t.coordinator registerWindow:normal];
        RequireCalibration(SunlightAllowedStreamMode(active, YES, t.coordinator.displayMode) == active && !SunlightShouldReturnTo2D(active, t.coordinator.displayMode, YES, YES, NO), @"Normal 2D must not schedule a reconnect");
        [t.coordinator unregisterWindow:normal];
        RequireCalibration(SunlightAllowedStreamMode(active, YES, t.coordinator.displayMode) == active && !SunlightShouldReturnTo2D(active, t.coordinator.displayMode, YES, YES, NO), @"Unknown reconnect gap must keep existing 2D");
        [t.coordinator registerWindow:[t fullSBSWindow]];
        RequireCalibration(SunlightAllowedStreamMode(active, YES, t.coordinator.displayMode) == active && !SunlightShouldReturnTo2D(active, t.coordinator.displayMode, YES, YES, NO), @"Entering SBS must not automatically convert a 2D session");
    });

    RunCalibrationCase(primaryWindow, runCase, @"glasses mode policy permits explicit stereo only on enabled confirmed SBS", ^(CalibrationFixture *t) {
        SunlightStreamMode requestedModes[] = { SunlightStreamModeHost3D, SunlightStreamModeRawFullSBS, SunlightStreamModeRawHalfSBS };
        for (NSUInteger index = 0; index < sizeof(requestedModes) / sizeof(requestedModes[0]); index++) {
            SunlightStreamMode requested = requestedModes[index];
            RequireCalibration(SunlightAllowedStreamMode(requested, YES, SunlightExternalDisplayModeUnknown) == SunlightStreamMode2D, @"Unknown output must clamp fresh stereo launch");
            RequireCalibration(SunlightAllowedStreamMode(requested, YES, SunlightExternalDisplayMode2D) == SunlightStreamMode2D, @"Normal output must clamp fresh stereo launch");
            RequireCalibration(SunlightAllowedStreamMode(requested, NO, SunlightExternalDisplayMode3D) == SunlightStreamMode2D, @"Disabled glasses must clamp fresh stereo launch");
            SunlightStreamMode expected = requested == SunlightStreamModeRawHalfSBS ? SunlightStreamModeRawFullSBS : requested;
            RequireCalibration(SunlightAllowedStreamMode(requested, YES, SunlightExternalDisplayMode3D) == expected, @"Confirmed SBS must honor explicit source while normalizing stale half-SBS");
        }
        RequireCalibration(SunlightAllowedStreamMode((SunlightStreamMode)-1, YES, SunlightExternalDisplayMode3D) == SunlightStreamMode2D && SunlightAllowedStreamMode((SunlightStreamMode)99, YES, SunlightExternalDisplayMode3D) == SunlightStreamMode2D, @"Invalid persisted modes must clamp to 2D");
    });

    RunCalibrationCase(primaryWindow, runCase, @"glasses mode policy defers stereo downgrade until settled normal and ready", ^(CalibrationFixture *t) {
        CalibrationWindow *sbs = [t fullSBSWindow];
        [t.coordinator registerWindow:sbs];
        RequireCalibration(!SunlightShouldReturnTo2D(SunlightStreamModeHost3D, t.coordinator.displayMode, YES, YES, NO), @"Confirmed SBS must keep Host 3D");
        [t.coordinator unregisterWindow:sbs];
        RequireCalibration(!SunlightShouldReturnTo2D(SunlightStreamModeHost3D, t.coordinator.displayMode, YES, YES, NO), @"Unknown output must preserve the in-flight stereo session");
        CalibrationWindow *normal = [t windowWithPixels:CGSizeMake(1920,1080) size:CGSizeMake(1920,1080) scale:1];
        [t.coordinator registerWindow:normal];
        SunlightStreamMode activeModes[] = { SunlightStreamModeHost3D, SunlightStreamModeRawFullSBS, SunlightStreamModeRawHalfSBS };
        for (NSUInteger index = 0; index < sizeof(activeModes) / sizeof(activeModes[0]); index++) {
            SunlightStreamMode active = activeModes[index];
            RequireCalibration(!SunlightShouldReturnTo2D(active, t.coordinator.displayMode, YES, NO, NO), @"Startup must wait for connection readiness");
            RequireCalibration(SunlightShouldReturnTo2D(active, t.coordinator.displayMode, YES, YES, NO), @"Ready stereo on settled normal output must reconnect as 2D");
            RequireCalibration(!SunlightShouldReturnTo2D(active, t.coordinator.displayMode, YES, YES, YES), @"Ending controllers must never schedule a second reconnect");
            RequireCalibration(!SunlightShouldReturnTo2D(active, t.coordinator.displayMode, NO, YES, NO), @"Disabled output must not force a reconnect");
        }
    });

    RunCalibrationCase(primaryWindow, runCase, @"calibration requires explicit Start even on compatible output", ^(CalibrationFixture *t) {
        CalibrationWindow *window = [t fullSBSWindow];
        [t.coordinator registerWindow:window];
        RequireCalibration(t.coordinator.calibrationOutputCompatible, @"Full SBS capability must be recognized");
        RequireCalibration(!t.coordinator.calibrationRequested && !t.coordinator.calibrationPresented, @"Connecting glasses alone must not start calibration");
        RequireCalibration(!t.coordinator.hasRenderViewRequest, @"Idle output must have no PC request");
        RequireCalibration([t.coordinator startCalibration], @"Explicit Start must accept compatible idle output");
        RequireCalibration(t.coordinator.calibrationRequested && t.coordinator.calibrationPresented, @"Explicit Start must show calibration");
        RequireCalibration(PresentedPattern(window) != nil && !CalibrationHost(window).hidden, @"Calibration must occupy the real visible output host");
    });

    RunCalibrationCase(primaryWindow, runCase, @"calibration gates exact mode pixels and per-window drawable size", ^(CalibrationFixture *t) {
        CalibrationWindow *window = [t fullSBSWindow];
        [t.coordinator registerWindow:window];
        RequireCalibration([t.coordinator startCalibration], @"Calibration request must be accepted");
        struct { CGSize mode; CGSize points; CGFloat scale; BOOL compatible; } cases[] = {
            {{1920,1080}, {1920,1080}, 1, NO},
            {{3840,1080}, {1920,1080}, 1, NO},
            {{3840,1080}, {1920,540}, 2, YES},
            {{3840,1080}, {1919,540}, 2, NO},
            {{3841,1080}, {3841,1080}, 1, NO},
            {{3840,1081}, {3840,1081}, 1, NO},
            {{3840,1080}, {3840,1079}, 1, NO},
            {{3840,1080}, {3840,1080}, 1, YES},
        };
        for (NSUInteger index = 0; index < sizeof(cases) / sizeof(cases[0]); index++) {
            [t setWindow:window pixels:cases[index].mode size:cases[index].points scale:cases[index].scale];
            NSString *context = [NSString stringWithFormat:@"mode %.0fx%.0f, window %.0fx%.0f at scale %.0f", cases[index].mode.width, cases[index].mode.height, cases[index].points.width, cases[index].points.height, cases[index].scale];
            RequireCalibration(t.coordinator.calibrationOutputCompatible == cases[index].compatible, [@"Incorrect compatibility for " stringByAppendingString:context]);
            RequireCalibration(t.coordinator.calibrationPresented == cases[index].compatible, [@"Incorrect presentation gate for " stringByAppendingString:context]);
            RequireCalibration(t.coordinator.calibrationRequested, @"Mode changes must retain the explicit calibration request");
        }
    });

    RunCalibrationCase(primaryWindow, runCase, @"pending calibration and eye swap survive reconnect and 2D transitions", ^(CalibrationFixture *t) {
        RequireCalibration([t.coordinator startCalibration], @"Start without glasses must preserve a pending request");
        RequireCalibration(t.coordinator.calibrationRequested && !t.coordinator.calibrationPresented, @"No display must leave calibration pending");
        t.coordinator.calibrationEyesSwapped = YES;
        CalibrationWindow *window = [t windowWithPixels:CGSizeMake(1920,1080) size:CGSizeMake(1920,1080) scale:1];
        [t.coordinator registerWindow:window];
        RequireCalibration(!t.coordinator.calibrationPresented, @"A 2D display must suspend the pending calibration");
        [t setWindow:window pixels:CGSizeMake(3840,1080) size:CGSizeMake(3840,1080) scale:1];
        RequireCalibration(t.coordinator.calibrationPresented && PresentedPattern(window).eyesSwapped, @"Entering SBS mode must restore the saved eye assignment");
        [t.coordinator unregisterWindow:window];
        RequireCalibration(t.coordinator.calibrationRequested && t.coordinator.calibrationEyesSwapped && !t.coordinator.calibrationPresented, @"Disconnect must preserve request and swap without presenting");
        CalibrationWindow *replacement = [t fullSBSWindow];
        [t.coordinator registerWindow:replacement];
        RequireCalibration(t.coordinator.calibrationPresented && PresentedPattern(replacement).eyesSwapped, @"Reconnect must resume the pending swapped pattern");
        [t setWindow:replacement pixels:CGSizeMake(1920,1080) size:CGSizeMake(1920,1080) scale:1];
        RequireCalibration(!t.coordinator.calibrationPresented && t.coordinator.calibrationRequested, @"Switching back to 2D must suspend output without losing the request");
    });

    RunCalibrationCase(primaryWindow, runCase, @"disabled external output suspends and resumes calibration", ^(CalibrationFixture *t) {
        CalibrationWindow *window = [t fullSBSWindow];
        [t.coordinator registerWindow:window];
        [t.coordinator startCalibration];
        t.coordinator.calibrationEyesSwapped = YES;
        t.coordinator.enabled = NO;
        RequireCalibration(t.coordinator.calibrationRequested && !t.coordinator.calibrationPresented, @"Disabling output must suspend the requested calibration");
        RequireCalibration(window.hidden, @"Disabled calibration must not leave the external window visible");
        t.coordinator.enabled = YES;
        RequireCalibration(t.coordinator.calibrationPresented && PresentedPattern(window).eyesSwapped, @"Re-enabling output must restore calibration and swap");
    });

    RunCalibrationCase(primaryWindow, runCase, @"PC requests take priority and calibration Stop cannot clear PC content", ^(CalibrationFixture *t) {
        UIView *pcView = [[UIView alloc] initWithFrame:t.phoneHost.bounds];
        [t.phoneHost addSubview:pcView];
        [t.coordinator setRenderView:pcView];
        RequireCalibration(t.coordinator.hasRenderViewRequest, @"Pending PC content must be recognized without glasses");
        RequireCalibration(![t.coordinator startCalibration], @"Calibration must not steal an existing PC request");
        RequireCalibration(!t.coordinator.calibrationRequested, @"Rejected Start must not queue calibration behind the PC");
        CalibrationWindow *window = [t fullSBSWindow];
        [t.coordinator registerWindow:window];
        [t.coordinator stopCalibration];
        RequireCalibration(t.coordinator.hasRenderViewRequest && [t.coordinator isPresentingView:pcView], @"Calibration Stop must leave PC output running");
        [t.coordinator clearRenderView];
        RequireCalibration([t.coordinator startCalibration], @"Calibration may start after PC content is released");
        SBSCalibrationView *standalonePattern = PresentedPattern(window);
        [t.coordinator clearRenderView];
        RequireCalibration(!t.coordinator.hasRenderViewRequest, @"Calibration must not be mistaken for an owned PC render request");
        RequireCalibration(t.coordinator.calibrationRequested && t.coordinator.calibrationPresented &&
                           PresentedPattern(window) == standalonePattern && !CalibrationHost(window).hidden,
                           @"PC teardown with no PC request must preserve standalone calibration ownership");
        [t.coordinator setRenderView:pcView];
        RequireCalibration(!t.coordinator.calibrationRequested && !t.coordinator.calibrationPresented, @"A new PC request must cancel calibration");
        RequireCalibration([t.coordinator isPresentingView:pcView], @"PC content must immediately replace calibration");
        [t.coordinator stopCalibration];
        RequireCalibration([t.coordinator isPresentingView:pcView], @"Repeated calibration Stop must preserve the new PC view");
        [t.coordinator clearRenderView];
        RequireCalibration(!t.coordinator.calibrationRequested && !t.coordinator.calibrationPresented, @"Ending PC content must not silently restart canceled calibration");
    });

    RunCalibrationCase(primaryWindow, runCase, @"repeated calibration Start and Stop are idempotent", ^(CalibrationFixture *t) {
        CalibrationWindow *window = [t fullSBSWindow];
        [t.coordinator registerWindow:window];
        RequireCalibration([t.coordinator startCalibration], @"Initial Start must be accepted");
        SBSCalibrationView *firstPattern = PresentedPattern(window);
        RequireCalibration([t.coordinator startCalibration], @"Repeated Start must preserve the accepted request");
        RequireCalibration(PresentedPattern(window) == firstPattern && CalibrationHost(window).subviews.count == 1, @"Repeated Start must not stack or replace calibration views");
        [t.coordinator stopCalibration];
        [t.coordinator stopCalibration];
        RequireCalibration(!t.coordinator.calibrationRequested && !t.coordinator.calibrationPresented, @"Repeated Stop must leave calibration stopped");
        RequireCalibration(CalibrationHost(window).hidden, @"Stopping calibration must restore standalone readiness");
    });

    RunCalibrationCase(primaryWindow, runCase, @"SBS halves and circles preserve geometry and swap complete eye pixels", ^(CalibrationFixture *t) {
        CalibrationWindow *window = [t fullSBSWindow];
        [t.coordinator registerWindow:window];
        [t.coordinator startCalibration];
        SBSCalibrationView *pattern = PresentedPattern(window);
        RequireCalibration(pattern != nil, @"Compatible calibration must provide its pattern");
        CGRect left = CGRectMake(0, 0, 1920, 1080), right = CGRectMake(1920, 0, 1920, 1080);
        RequireCalibration(CGRectEqualToRect(pattern.leftEyeRect, left) && CGRectEqualToRect(pattern.rightEyeRect, right), @"Full SBS must split into exact 1920×1080 eye halves");
        CGRect leftCircle = pattern.leftEyeCircleRect, rightCircle = pattern.rightEyeCircleRect;
        RequireCalibration(leftCircle.size.width == leftCircle.size.height && rightCircle.size.width == rightCircle.size.height, @"Both eye alignment targets must be circular, not stretched");
        RequireCalibration(CGRectGetMidX(leftCircle) == 960 && CGRectGetMidY(leftCircle) == 540 && CGRectGetMidX(rightCircle) == 2880 && CGRectGetMidY(rightCircle) == 540, @"Eye circles must be centered with identical corresponding coordinates");
        UIImage *normal = RenderCalibration(pattern, @"calibration-normal-3840x1080.png");
        t.coordinator.calibrationEyesSwapped = YES;
        RequireCalibration(CGRectEqualToRect(pattern.leftEyeCircleRect, leftCircle) && CGRectEqualToRect(pattern.rightEyeCircleRect, rightCircle), @"Eye swap must not alter physical alignment geometry");
        UIImage *swapped = RenderCalibration(pattern, @"calibration-swapped-3840x1080.png");
        RequireCalibration(CGImageGetWidth(normal.CGImage) == 3840 && CGImageGetHeight(normal.CGImage) == 1080, @"Normal calibration preview must preserve native output pixels");
        RequireCalibration(ImageRegionsMatch(normal.CGImage, left, swapped.CGImage, right, YES) && ImageRegionsMatch(normal.CGImage, right, swapped.CGImage, left, YES), @"Swap must exchange complete eye patterns with only bounded one-level edge rounding");
        RequireCalibration(!ImageRegionsMatch(normal.CGImage, left, normal.CGImage, right, NO), @"Normal output must visibly distinguish LEFT from RIGHT");
    });
}
