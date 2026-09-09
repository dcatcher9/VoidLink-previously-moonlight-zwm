#import "ExternalDisplayCoordinator.h"
#import "ExternalDisplayViewController.h"
#import "SBSCalibrationView.h"
#include <math.h>

NSNotificationName const SunlightExternalDisplayChangedNotification = @"SunlightExternalDisplayChanged";

@interface ExternalDisplayCoordinator ()
@property (nonatomic, strong) NSMutableArray<UIWindow *> *windows;
@property (nonatomic, strong, nullable) UIView *requestedView;
@property (nonatomic, weak, nullable) UIView *presentedView;
@property (nonatomic, weak, nullable) UIView *presentationHost;
@property (nonatomic, weak, nullable) UIScreen *lastScreen;
@property (nonatomic) CGRect lastWindowBounds;
@property (nonatomic) CGSize lastModeSize;
@property (nonatomic) CGFloat lastScreenScale;
@property (nonatomic) NSInteger lastMaximumFramesPerSecond;
@property (nonatomic, readwrite) BOOL calibrationRequested;
@property (nonatomic, strong) SBSCalibrationView *calibrationView;
@end

@implementation ExternalDisplayCoordinator

+ (instancetype)sharedCoordinator {
    static ExternalDisplayCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [[self alloc] init];
    });
    return coordinator;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _windows = [NSMutableArray array];
        _enabled = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(screenModeDidChange:)
                                                     name:UIScreenModeDidChangeNotification object:nil];
    }
    return self;
}

- (UIWindow *)externalWindow {
    return self.enabled ? self.windows.firstObject : nil;
}

- (UIScreen *)externalScreen {
    return self.externalWindow.screen;
}

- (BOOL)isAvailable {
    return self.externalWindow != nil;
}

- (BOOL)hasRenderViewRequest {
    return self.requestedView != nil;
}

- (CGSize)outputPixelSize {
    UIWindow *window = self.externalWindow;
    if (!window) return CGSizeZero;
    UIScreen *screen = window.screen;
    CGSize mode = screen.currentMode.size;
    CGFloat scale = screen.scale;
    CGSize pixels = CGSizeMake(window.bounds.size.width * scale,
                               window.bounds.size.height * scale);
    // Scene connection and hardware-mode changes can temporarily disagree on
    // canvas size. That is unknown output, never evidence of normal 2D mode.
    if (!isfinite(mode.width) || !isfinite(mode.height) || mode.width <= 0 || mode.height <= 0 ||
        !isfinite(scale) || scale <= 0 || !isfinite(pixels.width) || !isfinite(pixels.height) ||
        pixels.width <= 0 || pixels.height <= 0 ||
        fabs(pixels.width - mode.width) >= 1.0 || fabs(pixels.height - mode.height) >= 1.0) {
        return CGSizeZero;
    }
    return mode;
}

- (SunlightExternalDisplayMode)displayMode {
    CGSize pixels = self.outputPixelSize;
    if (CGSizeEqualToSize(pixels, CGSizeZero)) return SunlightExternalDisplayModeUnknown;
    // This exact scanout was verified on the user's glasses. A wide desktop
    // source or an advertised available mode does not establish SBS output.
    return CGSizeEqualToSize(pixels, CGSizeMake(3840, 1080))
        ? SunlightExternalDisplayMode3D : SunlightExternalDisplayMode2D;
}

- (BOOL)calibrationOutputCompatible {
    return self.displayMode == SunlightExternalDisplayMode3D;
}

- (void)screenModeDidChange:(NSNotification *)notification {
    if (!NSThread.isMainThread) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf screenModeDidChange:notification]; });
        return;
    }
    UIWindow *window = self.externalWindow;
    if (window && window.screen == notification.object) [self windowDidUpdate:window];
}

- (BOOL)calibrationPresented {
    return self.calibrationRequested && self.calibrationView &&
        [self isPresentingView:self.calibrationView];
}

- (BOOL)startCalibration {
    NSAssert(NSThread.isMainThread, @"Display routing must run on the main thread");
    if (self.hasRenderViewRequest) {
        return NO;
    }
    if (!self.calibrationRequested) {
        self.calibrationRequested = YES;
        [self updatePresentation];
        Log(LOG_I, @"Sunlight SBS calibration requested (presented=%d, swapped=%d)", self.calibrationPresented, self.calibrationEyesSwapped);
        [self notifyChange];
    }
    return YES;
}

- (void)stopCalibration {
    NSAssert(NSThread.isMainThread, @"Display routing must run on the main thread");
    if (!self.calibrationRequested) {
        return;
    }
    self.calibrationRequested = NO;
    [self updatePresentation];
    Log(LOG_I, @"Sunlight SBS calibration stopped");
    [self notifyChange];
}

- (void)setCalibrationEyesSwapped:(BOOL)calibrationEyesSwapped {
    NSAssert(NSThread.isMainThread, @"Display routing must run on the main thread");
    if (_calibrationEyesSwapped == calibrationEyesSwapped) {
        return;
    }
    _calibrationEyesSwapped = calibrationEyesSwapped;
    self.calibrationView.eyesSwapped = calibrationEyesSwapped;
    Log(LOG_I, @"Sunlight SBS calibration eye order: %@", calibrationEyesSwapped ? @"swapped" : @"normal");
    [self notifyChange];
}

- (void)notifyChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:SunlightExternalDisplayChangedNotification
                                                      object:self];
}

- (void)detachPresentedView {
    // Never remove a view that its source has already restored to the phone.
    UIView *view = self.presentedView;
    if (view && view.superview == self.presentationHost) {
        [view removeFromSuperview];
    }
    self.presentedView = nil;
    self.presentationHost = nil;
}

- (void)updatePresentation {
    UIWindow *selectedWindow = self.externalWindow;
    for (UIWindow *window in self.windows) {
        ExternalDisplayViewController *controller = (ExternalDisplayViewController *)window.rootViewController;
        if (window != selectedWindow) {
            window.hidden = YES;
            [controller setPresentingContent:NO];
        }
    }

    if (!selectedWindow) {
        [self detachPresentedView];
        self.lastScreen = nil;
        return;
    }

    ExternalDisplayViewController *controller = (ExternalDisplayViewController *)selectedWindow.rootViewController;
    UIView *host = controller.contentHostView;
    UIView *desiredView = self.requestedView;
    if (!desiredView && self.calibrationRequested && self.calibrationOutputCompatible) {
        if (!self.calibrationView) {
            self.calibrationView = [[SBSCalibrationView alloc] initWithFrame:host.bounds];
        }
        self.calibrationView.eyesSwapped = self.calibrationEyesSwapped;
        self.calibrationView.contentScaleFactor = selectedWindow.screen.scale;
        desiredView = self.calibrationView;
    }
    BOOL contentChanged = self.presentationHost != host || self.presentedView != desiredView;
    if (contentChanged) {
        [self detachPresentedView];
    }

    // Show the idle window even when there has never been a PC stream.
    // Keep key-window status on the phone for its controls.
    selectedWindow.hidden = NO;
    [selectedWindow layoutIfNeeded];
    [controller.view layoutIfNeeded];
    if (desiredView) {
        UIView *view = desiredView;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        view.frame = host.bounds;
        [controller setPresentingContent:YES];
        if (view.superview != host) {
            [host addSubview:view];
        }
        self.presentationHost = host;
        self.presentedView = view;
        [view setNeedsLayout];
        [view layoutIfNeeded];
        if (contentChanged && view == self.calibrationView) {
            Log(LOG_I, @"Sunlight SBS calibration presenting: canvas=%@, swapped=%d",
                NSStringFromCGSize(view.bounds.size), self.calibrationEyesSwapped);
        }
    } else {
        [controller setPresentingContent:NO];
    }
    self.lastScreen = selectedWindow.screen;
    self.lastWindowBounds = selectedWindow.bounds;
    self.lastModeSize = selectedWindow.screen.currentMode.size;
    self.lastScreenScale = selectedWindow.screen.scale;
    self.lastMaximumFramesPerSecond = selectedWindow.screen.maximumFramesPerSecond;
}

- (void)setEnabled:(BOOL)enabled {
    NSAssert(NSThread.isMainThread, @"Display routing must run on the main thread");
    if (_enabled == enabled) {
        return;
    }
    _enabled = enabled;
    [self updatePresentation];
    [self notifyChange];
}

- (void)registerWindow:(UIWindow *)window {
    NSAssert(NSThread.isMainThread, @"Display routing must run on the main thread");
    NSParameterAssert([window.rootViewController isKindOfClass:ExternalDisplayViewController.class]);
    if ([self.windows containsObject:window]) {
        return;
    }
    [self.windows addObject:window];
    [self updatePresentation];
    [self notifyChange];
}

- (void)unregisterWindow:(UIWindow *)window {
    NSAssert(NSThread.isMainThread, @"Display routing must run on the main thread");
    if (![self.windows containsObject:window]) {
        return;
    }
    if (window == self.externalWindow) {
        [self detachPresentedView];
    }
    window.hidden = YES;
    [(ExternalDisplayViewController *)window.rootViewController setPresentingContent:NO];
    [self.windows removeObjectIdenticalTo:window];
    [self updatePresentation];
    [self notifyChange];
}

- (void)windowDidUpdate:(UIWindow *)window {
    NSAssert(NSThread.isMainThread, @"Display routing must run on the main thread");
    if (window != self.externalWindow) {
        return;
    }
    UIScreen *screen = window.screen;
    if (screen == self.lastScreen && CGRectEqualToRect(window.bounds, self.lastWindowBounds) &&
        CGSizeEqualToSize(screen.currentMode.size, self.lastModeSize) &&
        screen.scale == self.lastScreenScale && screen.maximumFramesPerSecond == self.lastMaximumFramesPerSecond) {
        return;
    }
    [self updatePresentation];
    [self notifyChange];
}

- (void)setRenderView:(UIView *)view {
    NSAssert(NSThread.isMainThread, @"Display routing must run on the main thread");
    NSParameterAssert(view);
    if (self.requestedView == view && (!self.isAvailable || [self isPresentingView:view])) {
        return;
    }
    // The PC source takes over deliberately; stopping it returns to readiness.
    // Calibration controls never stop or steal an existing PC stream.
    self.calibrationRequested = NO;
    self.requestedView = view;
    [self updatePresentation];
    [self notifyChange];
}

- (void)clearRenderView {
    NSAssert(NSThread.isMainThread, @"Display routing must run on the main thread");
    if (!self.requestedView) {
        return;
    }
    [self detachPresentedView];
    self.requestedView = nil;
    [self updatePresentation];
    [self notifyChange];
}

- (void)clearRenderView:(UIView *)view {
    NSAssert(NSThread.isMainThread, @"Display routing must run on the main thread");
    if (view && self.requestedView == view) {
        [self clearRenderView];
    }
}

- (BOOL)isPresentingView:(UIView *)view {
    return view && self.isAvailable && self.presentedView == view &&
        view.superview == self.presentationHost && self.presentationHost != nil;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIScreenModeDidChangeNotification object:nil];
}

@end
