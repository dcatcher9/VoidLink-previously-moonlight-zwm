//
//  MetalViewController.m
//
//  Created by Andy Grundman.
//  Ported to VoidLink by Acaki.
//  Copyright (c) 2025 Moonlight Stream. All rights reserved.
//

#import "MetalViewController.h"
#import "FrameQueue.h"
#import "ImGuiRenderer.h"
#import "MetalVideoRenderer.h"

@implementation MetalViewController {
    FrameQueue *_frameQueue;
    float _framerate;
    TemporarySettings* _currentSettings;
    MetalView *_metalView;
    MetalVideoRenderer *_renderer;
    MetricsHandler _metricsHandler;
    CADisplayLink *_displayLink;
    // Only the render worker accesses this reference. It owns a successful
    // wait/render pair even if shutdown clears the active renderer meanwhile.
    MetalVideoRenderer *_acquiredFrameRenderer;
    SunlightStreamMode _streamMode;
    BOOL _stereoOutputEnabled;
}

- (nonnull instancetype)initWithFrame:(CGRect)bounds framerate:(float)framerate settings:(TemporarySettings* )settings metricsHandler:(MetricsHandler)metricsHandler {
    self = [super init];
    if (self) {
        _bounds = bounds;
        _frameQueue = [FrameQueue sharedInstance];
        _framerate = framerate;
        _currentSettings = settings;
        _metricsHandler = metricsHandler;
    }
    return self;
}

- (void)loadView {
    self.view = [[MetalView alloc] initWithFrame:_bounds];
    Log(LOG_I, @"[MetalViewController] created MetalView %@", (MetalView *)self.view);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    __block MetalView *view = (MetalView *)self.view;
    if (!view) {
        Log(LOG_E, @"The view attached to MetalViewController isn't a MetalView.");
        return;
    }
    _metalView = view;
    _metalView.delegate = self;
    _metalView.framerate = _framerate;

    // Select the device to render with.
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        Log(LOG_E, @"Metal isn't supported on this device.");
        self.view = [[UIView alloc] initWithFrame:self.view.frame];
        return;
    }
    view.metalLayer.device = device;

    // Determine supported pixel format before initializing renderer
    // Use TARGET_OS_SIMULATOR to detect simulator environment
    MTLPixelFormat pixelFormat;
#if TARGET_OS_SIMULATOR
    // iOS Simulator doesn't support BGRA10_XR
    pixelFormat = MTLPixelFormatBGRA8Unorm;
    Log(LOG_W, @"Running on iOS Simulator, using BGRA8Unorm pixel format");
#else
    // On real devices, check if we should enable HDR
    if (_currentSettings.enableHdr) {
        pixelFormat = MTLPixelFormatBGRA10_XR;
        Log(LOG_I, @"HDR enabled, using BGRA10_XR pixel format");
    } else {
        pixelFormat = MTLPixelFormatBGRA8Unorm;
        Log(LOG_I, @"HDR disabled, using BGRA8Unorm pixel format");
    }
#endif

    // Initialize the renderer.
    MetalVideoRenderer *renderer = [[MetalVideoRenderer alloc] initWithMetalDevice:device
                                                               drawablePixelFormat:pixelFormat
                                                                         settings:_currentSettings];
    if (!renderer) {
        Log(LOG_E, @"The renderer couldn't be initialized.");
        return;
    }
    @synchronized (self) {
        renderer.streamMode = _streamMode;
        renderer.stereoOutputEnabled = _stereoOutputEnabled;
        _renderer = renderer;
    }
    Log(LOG_I, @"[MetalViewController] viewDidLoad, created renderer: %@", renderer);

    // Initialize the renderer-dependent view properties.
    view.metalLayer.pixelFormat = renderer.colorPixelFormat;
    view.metalLayer.maximumDrawableCount = 3;

    // We need a no-op displaylink timer or iOS can decide to run at 60fps
    // The overhead from this should be minimal.
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkHandler:)];
    if (@available(iOS 15.0, tvOS 15.0, *)) {
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(_framerate, _framerate, _framerate);
    } else {
        _displayLink.preferredFramesPerSecond = _framerate;
    }
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)displayLinkHandler:(CADisplayLink *)link {
    // Rendering does not use DisplayLink, this exists to fool iOS into keeping us running at the desired framerate
}

- (MetalVideoRenderer *)currentRenderer {
    // Strong ivar reads must synchronize with shutdown's final release.
    @synchronized (self) {
        return _renderer;
    }
}

- (SunlightStreamMode)streamMode {
    @synchronized (self) {
        return _streamMode;
    }
}

- (void)setStreamMode:(SunlightStreamMode)streamMode {
    @synchronized (self) {
        _streamMode = streamMode;
        _renderer.streamMode = streamMode;
    }
}

- (BOOL)stereoOutputEnabled {
    @synchronized (self) {
        return _stereoOutputEnabled;
    }
}

- (void)setStereoOutputEnabled:(BOOL)stereoOutputEnabled {
    @synchronized (self) {
        _stereoOutputEnabled = stereoOutputEnabled;
        _renderer.stereoOutputEnabled = stereoOutputEnabled;
    }
}

- (void)waitToRenderTo:(nonnull CAMetalLayer *)layer {
    MetalVideoRenderer *renderer = [self currentRenderer];
    _acquiredFrameRenderer = nil;

    // Skip waiting when renderer is paused or gone
    if (!renderer || renderer.isStopping) {
        return;
    }

    if (@available(iOS 13.0, *)) {
        if ([renderer waitToRenderTo:layer]) {
            _acquiredFrameRenderer = renderer;
        }
    }

    if (_acquiredFrameRenderer) {
        [_frameQueue waitForActiveEnqueueUntilCancelled:^BOOL{
            return renderer.isStopping;
        }];
    }
}

/// Draw frame (used by manual loop)
- (void)renderTo:(nonnull CAMetalLayer *)layer {
    MetalVideoRenderer *renderer = _acquiredFrameRenderer;
    _acquiredFrameRenderer = nil;
    if (!renderer) {
        return;
    }
    if (renderer.isStopping) {
        // A cancelled session must not consume the next session's first frame.
        dispatch_semaphore_signal(renderer.inFlightSemaphore);
        return;
    }
    CFTimeInterval timeout = (1.0f / _framerate) - renderer.averageGPUTime;
    Frame *frame = [_frameQueue dequeueWithTimeoutSync:timeout untilCancelled:^BOOL{ return renderer.isStopping; }];

    if (!renderer.isStopping) {
        // Only render if not paused
        if (frame) {
            //if (@available(iOS 13.0, *)) {
                [renderer renderFrame:frame toLayer:layer];
            //}
        } else {
            dispatch_semaphore_signal([renderer inFlightSemaphore]);
        }
    } else {
        dispatch_semaphore_signal([renderer inFlightSemaphore]);
    }
}

- (void)drawableResize:(CGSize)size {
    [[self currentRenderer] drawableResize:size];
}

- (void)pauseRendering {
    _metalView.renderingPaused = YES;
    if (_displayLink) {
        _displayLink.paused = YES;
    }
    [self currentRenderer].isStopping = YES;
    Log(LOG_I, @"[MetalViewController] Rendering paused");
}

- (void)resumeRendering {
    [self currentRenderer].isStopping = NO;
    _metalView.renderingPaused = NO;
    if (_displayLink) {
        _displayLink.paused = NO;
    }
    Log(LOG_I, @"[MetalViewController] Rendering resumed");
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    // Appearance follows the phone's parent controller, while the Metal view
    // can be presenting in a different window. Only the owning stream session
    // decides when to permanently shut down its renderer.
}

- (void)shutdown {
    if (_displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
    }

    // Stop the renderer before the render thread: isStopping makes the thread's
    // renderFrame return early, so it can't enter the dispatch_sync-to-main path
    // while we wait for it below.
    MetalVideoRenderer *renderer;
    @synchronized (self) {
        renderer = _renderer;
        _renderer = nil;
    }
    [renderer shutdown];

    if (_metalView) {
        _metalView.delegate = nil;
        [_metalView shutdown];
        _metalView = nil;
    }
}

#if TARGET_OS_IOS
// Hides the Home indicator button automatically.
- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}
#endif

@end
