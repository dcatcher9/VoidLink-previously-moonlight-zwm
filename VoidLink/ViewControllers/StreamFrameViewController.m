//
//  StreamFrameViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//
//  Modified by True砖家 since 2024.6.1
//  Copyright © 2024 True砖家 @ Bilibili. All rights reserved.
//

#import <AVKit/AVKit.h>
#import "StreamFrameViewController.h"
#import "MainFrameViewController.h"
#import "VideoDecoderRenderer.h"
#import "StreamManager.h"
#import "ConnectionLifecycle.h"
#import "SunlightPlatform.h"
#import "SceneDelegate.h"
#import "ControllerSupport.h"
#import "DataManager.h"
#import "PaddedLabel.h"
#import "ImGuiRenderer.h"
#import "MetalVideoRenderer.h"
#import "CustomTapGestureRecognizer.h"
#import "LocalizationHelper.h"
#import "VoidLink-Swift.h"
#import "NativeTouchPointer.h"
#if !TARGET_OS_TV
#import "ExternalDisplayCoordinator.h"
#import "SunlightGlassesModePolicy.h"
#import "SunlightStreamQualityProfile.h"
#import "SunlightStreamQualitySession.h"
#import "SunlightInputDispatch.h"
#import "SunlightNativeResolution.h"
#import "SunlightMachineControlsSettings.h"
#import "SunlightStreamControlsView.h"
#import "SunlightControlPadView.h"
#endif

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <math.h>
#include <Limelight.h>

#if TARGET_OS_TV
#import <AVFoundation/AVDisplayCriteria.h>
#import <AVKit/AVDisplayManager.h>
#import <AVKit/UIWindow.h>
#endif

@interface AVDisplayCriteria()
@property(readonly) int videoDynamicRange;
@property(readonly, nonatomic) float refreshRate;

- (id)initWithRefreshRate:(float)arg1 videoDynamicRange:(int)arg2;
@end

static NSString* VLTerminationHintForErrorCode(int errorCode) {
    switch (errorCode) {
        case -1:
            return @"Possible causes:\n- control disconnect timeout\n- enet peer timeout disconnect\n- unexpected control stream disconnect\n- video receive socket failure\n- audio receive socket failure\n- input send socket failure\n- control message send/ack failure\n- loss stats/control buffer malloc failure\n- video buffer malloc failure\n- audio packet malloc failure\n- unknown socket failure";
        case ETIMEDOUT:
            return @"Timeout type: socket or control channel timeout.";
        case ECONNRESET:
            return @"Possible cause: the host or network reset the connection.";
        case EPIPE:
            return @"Possible cause: write failed because the peer closed the connection.";
        case ECONNABORTED:
            return @"Possible cause: the local network stack aborted the connection.";
        case ENETDOWN:
            return @"Possible cause: the local network interface went down.";
        case ENETUNREACH:
            return @"Possible cause: the network became unreachable.";
        case EHOSTUNREACH:
            return @"Possible cause: the host became unreachable.";
        case ENOBUFS:
            return @"Possible cause: the network stack ran out of buffer space.";
        case ENOMEM:
            return @"Possible cause: memory allocation failed.";
        default:
            return nil;
    }
}


@interface StreamFrameViewController () <ToolboxSpecialEntryDelegate, OnScreenFunctionalWidgetDelegate, AbstractGamepadOverlayCloseButtonDelegate, UIAdaptivePresentationControllerDelegate>
@end

static __weak StreamFrameViewController *VLSharedStreamFrameViewController = nil;

@implementation StreamFrameViewController {
    ControllerSupport *_controllerSupport;
    TemporarySettings *_settings;
    OSCProfile* _oscProfile;
    NSTimer *_inactivityTimer;
    NSTimer *_statsUpdateTimer;
    PaddedLabel *_overlayView;
    PaddedLabel *_transientHUDView;
    UITapGestureRecognizer *_menuTapGestureRecognizer;
    UITapGestureRecognizer *_menuDoubleTapGestureRecognizer;
    UITapGestureRecognizer *_playPauseTapGestureRecognizer;
    uint16_t overlayLevel;
    UILabel *_stageLabel;
    UILabel *_tipLabel;
    UIActivityIndicatorView *_spinner;
    StreamView *_streamView;
    BOOL _magnifierViewportInteractionActive;
    BOOL _userIsInteracting;
    bool viewIsBeingResized;
    bool previousOnScreenWidgetEnabled;
    PlotMetrics _decodeMetrics;
    PlotMetrics _frameDropMetrics;
    PlotMetrics _frameQueueMetrics;
    UIView *_streamVideoRenderView;
    UIView *_externalDisplayRenderViewRequest;
    __weak UIView *_lastRoutedRenderView;
    __weak UIWindow *_lastRenderWindow;
    CGRect _lastRenderBounds;
    BOOL _lastRenderWasExternal;
    BOOL _externalDisplayRoutingReady;
    BOOL _isUpdatingExternalDisplayRouting;
    BOOL _isEndingStream;
    /*
     * View architecture of this viewController:
     * self.view (named `streamFrameTopLayerView` in StreamView.m, where slide & tap gestures, and onScreenControls & OnScreenWidgetView buttons are registered)
     *   - streamView (where touchHandlers are registered)
     *     - streamVideoRenderView (where stream view is rendered)
     */
    UIWindow *_deviceWindow;
    dispatch_block_t _delayedRemoveExtScreen;
    VideoDecoderRenderer *_videoRenderer;
    BOOL _isRestoringFromPiP;
    SafeTimer* safeTimer;

#if !TARGET_OS_TV
    SunlightStreamControlsView *_streamControls;
    SunlightControlPadView *_controlPad;
    CommandExecutionOwner *_commandOwner;
    BOOL _hostInputReady;
    BOOL _automatic2DReconnectPending;
    SunlightStreamQualitySession *_qualitySession;
    BOOL _streamUIObserversInstalled;
    BOOL _preferSessionTrackpad;
    CustomTapGestureRecognizer *_oscLayoutTapRecoginizer;
    LayoutOnScreenControlsViewController *_layoutOnScreenControlsVC;
    ToolboxViewController* toolBoxViewController;
    MicHandler* micHandler;
    NSUInteger _microphoneGeneration;
    BOOL _microphoneCaptureStopped;
    MotionHandler *_motionHandler;

    
#else
    UITapGestureRecognizer *_menuTapGestureRecognizer;
    UITapGestureRecognizer *_menuDoubleTapGestureRecognizer;
    UITapGestureRecognizer *_playPauseTapGestureRecognizer;
#endif

}

+ (StreamFrameViewController *)sharedInstance {
    return VLSharedStreamFrameViewController;
}

#if !TARGET_OS_TV
- (SunlightMachineControlsSettings *)globalMachineControls {
    TemporarySettings *saved = [[[DataManager alloc] init] getSettings];
    SunlightMachineControlsSettings *controls = [[SunlightMachineControlsSettings alloc] init];
    id trackpad = [NSUserDefaults.standardUserDefaults objectForKey:@"sunlight.preferTrackpad"];
    BOOL preferTrackpad = ![trackpad isKindOfClass:NSNumber.class] || [trackpad boolValue];
    controls.controlMode = preferTrackpad ? SunlightMachineControlModeTrackpad : SunlightMachineControlModeSavedTouchProfile;
    controls.localVolume = saved.localVolume ? saved.localVolume.doubleValue : 1;
    controls.statsOverlayLevel = saved.statsOverlayEnabled ? MIN(2, MAX(1, saved.statsOverlayLevel.integerValue)) : 0;
    return [SunlightMachineControlsSettings globalControlsWithDefaults:NSUserDefaults.standardUserDefaults fallback:controls];
}

- (SunlightMachineControlsSettings *)resolvedMachineControls {
    if (!self.streamConfig.machineControls) {
        self.streamConfig.machineControls = [SunlightMachineControlsSettings settingsForHostUUID:self.streamConfig.hostUUID
            defaults:NSUserDefaults.standardUserDefaults globalDefaults:[self globalMachineControls]];
    }
    return self.streamConfig.machineControls;
}

- (void)setupStreamControls {
    if (_streamControls) return;
    _qualitySession = [[SunlightStreamQualitySession alloc] initWithConfiguration:self.streamConfig
        defaults:NSUserDefaults.standardUserDefaults fallback:[self globalQualityDefaults]
        nativeSize:SunlightNativeLandscapeSize() drafts:self.initialQualityDrafts resetModes:self.initialQualityResetModes];
    self.initialQualityDrafts = nil;
    self.initialQualityResetModes = nil;
    SunlightMachineControlsSettings *machine = [self resolvedMachineControls];
    _preferSessionTrackpad = machine.controlMode == SunlightMachineControlModeTrackpad;
    _touchDisabled = !machine.touchEnabled;
    _controlPad = [[SunlightControlPadView alloc] initWithFrame:CGRectZero];
    _controlPad.hidden = YES;
    [self.view addSubview:_controlPad];
    _streamControls = [[SunlightStreamControlsView alloc] initWithFrame:self.view.bounds];
    _streamControls.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _streamControls.glasses3DAvailable = [self isAirPlayEnabled] &&
        [ExternalDisplayCoordinator sharedCoordinator].displayMode == SunlightExternalDisplayMode3D;
    _streamControls.activeMode = self.streamConfig.streamMode;
    _streamControls.controlPadEnabled = machine.controlMode == SunlightMachineControlModeGamepad;
    _streamControls.appName = self.streamConfig.appName ?: @"";
    [self.view addSubview:_streamControls];
    __weak typeof(self) weakSelf = self;
    _commandOwner = [[CommandExecutionOwner alloc] initWithCanSend:^BOOL{
        typeof(self) self = weakSelf;
        return self && self->_hostInputReady && !self->_isEndingStream;
    }];
    _streamControls.expansionChangedHandler = ^(BOOL expanded) {
        typeof(self) self = weakSelf; if (!self) return;
        [self->_controlPad releaseAllControls];
        [self updateStreamControls];
    };
    _streamControls.actionHandler = ^(SunlightStreamControlsAction action) {
        [weakSelf handleStreamControlAction:action];
    };
    _streamControls.qualityChangedHandler = ^(int width, int height, int fps, int bitrate) {
        [weakSelf stageStreamQualityWidth:width height:height frameRate:fps bitRate:bitrate];
    };
    _streamControls.modeApplyHandler = ^(SunlightStreamMode mode) {
        [weakSelf reconnectWithStreamMode:mode];
    };
    _streamControls.selectionChangedHandler = ^{
        [weakSelf updateStreamControls];
    };
    _streamControls.pendingChangesDiscardedHandler = ^{
        typeof(self) self = weakSelf; if (!self) return;
        [self->_qualitySession discardPendingChanges];
        [self updateStreamControls];
    };
    _controlPad.buttonChangedHandler = ^(int flag, BOOL down) {
        typeof(self) self = weakSelf;
        if (!self || ![self canSendControlPadInput]) return;
        VoidController *controller = [self->_controllerSupport getOscController];
        if (down) [self->_controllerSupport setButtonFlag:controller flags:flag];
        else [self->_controllerSupport clearButtonFlag:controller flags:flag];
        [self->_controllerSupport updateFinished:controller];
    };
    _controlPad.leftStickChangedHandler = ^(CGPoint value) { [weakSelf sendControlPadStick:value right:NO]; };
    _controlPad.rightStickChangedHandler = ^(CGPoint value) { [weakSelf sendControlPadStick:value right:YES]; };
    _controlPad.leftTriggerChangedHandler = ^(float value) { [weakSelf sendControlPadTrigger:value right:NO]; };
    _controlPad.rightTriggerChangedHandler = ^(float value) { [weakSelf sendControlPadTrigger:value right:YES]; };
}

- (BOOL)canSendControlPadInput {
    return _hostInputReady && !_isEndingStream;
}

- (void)sendControlPadStick:(CGPoint)value right:(BOOL)right {
    if (![self canSendControlPadInput]) return;
    VoidController *controller = [_controllerSupport getOscController];
    short x = (short)(fmax(-1, fmin(1, value.x)) * 32767);
    short y = (short)(fmax(-1, fmin(1, value.y)) * 32767);
    if (right) [_controllerSupport updateRightStick:controller x:x y:y];
    else [_controllerSupport updateLeftStick:controller x:x y:y];
    [_controllerSupport updateFinished:controller];
}

- (void)sendControlPadTrigger:(float)value right:(BOOL)right {
    if (![self canSendControlPadInput]) return;
    VoidController *controller = [_controllerSupport getOscController];
    unsigned char position = (unsigned char)(fmaxf(0, fminf(1, value)) * 255);
    if (right) [_controllerSupport updateRightTrigger:controller right:position];
    else [_controllerSupport updateLeftTrigger:controller left:position];
    [_controllerSupport updateFinished:controller];
}

- (void)updateStreamControls {
    if (!_streamControls || _isEndingStream) return;
    BOOL external = [self isAirPlaying];
    BOOL expanded = _streamControls.isExpanded;
    BOOL pad = _streamControls.controlPadEnabled;
    ExternalDisplayCoordinator *display = [ExternalDisplayCoordinator sharedCoordinator];
    _streamControls.externalOutputActive = external;
    _streamControls.glasses3DAvailable = [self isAirPlayEnabled] && display.displayMode == SunlightExternalDisplayMode3D;
    _streamControls.connectionReady = _hostInputReady;
    _streamControls.touchEnabled = !_touchDisabled;
    _streamControls.usesSavedTouchProfile = !_preferSessionTrackpad;
    StreamConfiguration *quality = [self qualityConfigurationForMode:_streamControls.selectedMode includingPending:YES];
    _streamControls.qualityChangesPending = [_qualitySession hasPendingChangesForMode:_streamControls.selectedMode];
    _streamControls.qualityWidth = quality.width;
    _streamControls.qualityHeight = quality.height;
    _streamControls.qualityUsesNativeResolution =
        [self qualityProfileForMode:_streamControls.selectedMode includingPending:YES].usesNativeResolution;
    _streamControls.qualityFrameRate = quality.frameRate;
    _streamControls.qualityBitrateKbps = quality.bitRate;
    _streamControls.qualityResolutionLocked = quality.isRawSbsStream;
    _streamControls.qualityMaxFrameRate = quality.streamMode != SunlightStreamMode2D || self.streamConfig.glassesOutputEnabled ? 60 : 240;
    _streamControls.inputHint = _preferSessionTrackpad
        ? NSLocalizedString(@"Slide to move · Tap to click\nTwo-finger tap to right-click · Two fingers to scroll", nil)
        : [self savedTouchProfileSummary];
    NSString *outputDescription = NSLocalizedString(@"This display", nil);
    if (external) {
        outputDescription = display.displayMode == SunlightExternalDisplayMode3D
            ? NSLocalizedString(@"Glasses in 3D mode", nil)
            : display.displayMode == SunlightExternalDisplayMode2D
                ? NSLocalizedString(@"Glasses in 2D mode", nil) : NSLocalizedString(@"Glasses switching mode…", nil);
    }
    _streamControls.statusText = _hostInputReady
        ? [NSString stringWithFormat:NSLocalizedString(@"%@ · %@", nil), self.streamConfig.appName ?: @"PC", outputDescription]
        : NSLocalizedString(@"Connecting to your PC…", nil);
    [_streamView setLocalControlsPresented:expanded];
    [_streamView setSessionTrackpadOverrideEnabled:_preferSessionTrackpad];
    [_streamView toggleTouchDisabled:_touchDisabled];
    [self updateScrollViewInteractionState];
    [_controllerSupport setLocalControlPadEnabled:pad];
    _controlPad.hidden = !pad || expanded || !_hostInputReady || _touchDisabled;
    [self streamContentContainerView].userInteractionEnabled = !expanded && !pad;
    _streamView.accessibilityElementsHidden = expanded;
    if (external || pad) {
        [_streamView disableOnScreenControls];
        [_streamView clearOnScreenWidgets];
    }
    // Local controls live on the phone even when the sole video renderer moves
    // to the external display. No second decoded-frame consumer is introduced.
    [self.view bringSubviewToFront:_controlPad];
    [self.view bringSubviewToFront:_streamControls];
    [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [_streamControls layoutIfNeeded];
    _controlPad.frame = _streamControls.controlPadLayoutGuide.layoutFrame;
}

- (void)openStreamControls {
    _streamControls.expanded = YES;
    [self updateStreamControls];
}

- (void)showStreamControlMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Picture settings", nil) message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)canReconnectWithMode:(SunlightStreamMode)mode {
    if (!_hostInputReady || _isEndingStream || _automatic2DReconnectPending) return NO;
    if (mode != SunlightStreamMode2D &&
        (![self isAirPlayEnabled] || [ExternalDisplayCoordinator sharedCoordinator].displayMode != SunlightExternalDisplayMode3D)) {
        [self showStreamControlMessage:NSLocalizedString(@"Switch your glasses to 3D mode before choosing a 3D picture.", nil)];
        return NO;
    }
    if (mode == SunlightStreamModeHost3D && !self.streamConfig.hostSessionIdSupported) {
        [self showStreamControlMessage:NSLocalizedString(@"3D conversion needs Sunshine 3D on your PC.", nil)];
        return NO;
    }
    return YES;
}

- (void)reconcileGlassesStreamMode {
    // A mode switch may briefly remove the external scene or report new screen
    // pixels before its canvas has caught up. Only a confirmed normal output
    // requires a transport change; entering SBS never opts into 3D conversion.
    ExternalDisplayCoordinator *display = [ExternalDisplayCoordinator sharedCoordinator];
    if (_automatic2DReconnectPending || !SunlightShouldReturnTo2D(self.streamConfig.streamMode,
        display.displayMode, [self isAirPlayEnabled], _hostInputReady, _isEndingStream)) return;
    _automatic2DReconnectPending = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (!self) return;
        void (^reconnectIfStillNeeded)(void) = ^{
            self->_automatic2DReconnectPending = NO;
            ExternalDisplayCoordinator *current = [ExternalDisplayCoordinator sharedCoordinator];
            if (!SunlightShouldReturnTo2D(self.streamConfig.streamMode, current.displayMode,
                [self isAirPlayEnabled], self->_hostInputReady, self->_isEndingStream)) return;
            CGSize pixels = current.outputPixelSize;
            Log(LOG_I, @"Glasses returned to normal %.0fx%.0f output; reconnecting the current PC app in 2D", pixels.width, pixels.height);
            [self->_streamControls discardPendingChanges];
            self->_streamControls.expanded = NO;
            [self reconnectWithStreamMode:SunlightStreamMode2D];
        };
        if (self.presentedViewController && !self->_isEndingStream) {
            [self dismissViewControllerAnimated:NO completion:reconnectIfStillNeeded];
        } else {
            reconnectIfStillNeeded();
        }
    });
}

- (void)reconnectWithStreamMode:(SunlightStreamMode)mode {
    if (![self canReconnectWithMode:mode]) return;
    SunlightStreamQualityProfile *qualityDraft = _qualitySession.drafts[@(mode)];
    BOOL resetQuality = [_qualitySession.resetModes containsObject:@(mode)];
    if (qualityDraft && !resetQuality && !qualityDraft.isValid) {
        [self showStreamControlMessage:NSLocalizedString(@"These quality values are unsupported. Review this tab’s stream quality before reconnecting.", nil)];
        return;
    }
    if ((qualityDraft || resetQuality) &&
        ([self.streamConfig.hostUUID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0 ||
         [self.streamConfig.appID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0)) {
        [self showStreamControlMessage:NSLocalizedString(@"This app’s identity is missing. Return to the app list and connect again before saving picture settings.", nil)];
        return;
    }
    NSMutableDictionary<NSNumber *, SunlightStreamQualityProfile *> *remainingDrafts = [_qualitySession.drafts mutableCopy];
    NSMutableSet<NSNumber *> *remainingResets = [_qualitySession.resetModes mutableCopy];
    [remainingDrafts removeObjectForKey:@(mode)];
    [remainingResets removeObject:@(mode)];
    BOOL (^commitReviewedQuality)(void) = [_qualitySession commitActionForMode:mode];
    [_controlPad releaseAllControls];
    if (![self.mainFrameViewcontroller reconnectStreamFromController:self mode:mode
        remainingQualityDrafts:remainingDrafts remainingQualityResets:remainingResets]) {
        [self showStreamControlMessage:NSLocalizedString(@"This stream is no longer selected. Return to your PC’s app list and connect again.", nil)];
    } else {
        // The accepted reconnect queues its replacement on the main thread.
        // Save the reviewed draft now, before that replacement reads settings.
        commitReviewedQuality();
    }
}

- (SunlightStreamQualityProfile *)qualityProfileForMode:(SunlightStreamMode)mode includingPending:(BOOL)includingPending {
    _qualitySession.outputSize = [ExternalDisplayCoordinator sharedCoordinator].outputPixelSize;
    return [_qualitySession profileForMode:mode includingPending:includingPending];
}

- (SunlightStreamQualityProfile *)globalQualityDefaults {
    TemporarySettings *saved = [[[DataManager alloc] init] getSettings];
    SunlightStreamQualityProfile *quality = [[SunlightStreamQualityProfile alloc] init];
    quality.width = saved.width.intValue; quality.height = saved.height.intValue;
    quality.frameRate = saved.framerate.intValue; quality.bitRate = saved.bitrate.intValue;
    quality.usesNativeResolution = saved.resolutionSelected.integerValue == 4;
    return quality;
}

- (void)useGlobalQualityDefaults {
    if (_streamControls.selectedTab == SunlightStreamControlsTabClient3D) return;
    _qualitySession.outputSize = [ExternalDisplayCoordinator sharedCoordinator].outputPixelSize;
    [_qualitySession restoreDefaultsForMode:_streamControls.selectedMode globalFallback:[self globalQualityDefaults]];
    [self updateStreamControls];
}

- (StreamConfiguration *)qualityConfigurationForMode:(SunlightStreamMode)mode includingPending:(BOOL)includingPending {
    _qualitySession.outputSize = [ExternalDisplayCoordinator sharedCoordinator].outputPixelSize;
    return [_qualitySession configurationForMode:mode includingPending:includingPending];
}

- (void)stageStreamQualityWidth:(int)width height:(int)height frameRate:(int)fps bitRate:(int)bitrate {
    if (_streamControls.selectedTab == SunlightStreamControlsTabClient3D || !_hostInputReady ||
        _isEndingStream || _automatic2DReconnectPending) return;
    _qualitySession.outputSize = [ExternalDisplayCoordinator sharedCoordinator].outputPixelSize;
    [_qualitySession stageWidth:width height:height frameRate:fps bitRate:bitrate
        usesNativeResolution:_streamControls.qualityUsesNativeResolution forMode:_streamControls.selectedMode];
    [self updateStreamControls];
}

- (NSString *)savedTouchProfileSummary {
    NSString *behavior;
    switch (_oscProfile.touchMode) {
        case RelativeTouch: behavior = NSLocalizedString(@"Trackpad", nil); break;
        case AbsoluteTouch: behavior = NSLocalizedString(@"Direct mouse", nil); break;
        case NativeTouch:
        case NativeTouchOnly: behavior = NSLocalizedString(@"Touchscreen", nil); break;
        case TouchDisabled: behavior = NSLocalizedString(@"Touch off", nil); break;
        default: behavior = NSLocalizedString(@"Custom touch", nil); break;
    }
    return [NSString stringWithFormat:@"%@ · %@", _oscProfile.name ?: NSLocalizedString(@"Saved profile", nil), behavior];
}

- (void)handleStreamControlAction:(SunlightStreamControlsAction)action {
    if (_isEndingStream) return;
    switch (action) {
        case SunlightStreamControlsActionModeDefaults: [self useGlobalQualityDefaults]; break;
        case SunlightStreamControlsActionDisconnect: [self returnToMainFrame]; break;
    }
}
#else
- (void)setupStreamControls {}
- (void)updateStreamControls {}
#endif

- (void)pictureInPictureControllerWillStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    _streamView.hidden = YES;
    if (self.imguiView) {
        self.imguiView.mtkView.hidden = YES;
        Log(LOG_I, @"Hiding ImGui view for PiP start.");
    }
}

- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController failedToStartPictureInPictureWithError:(NSError *)error {
    Log(LOG_E, @"PiP Failed to Start: %@", error);
    _streamView.hidden = NO;
}

- (void)pictureInPictureControllerWillStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    _streamView.hidden = NO;
    if (self.imguiView) {
        self.imguiView.mtkView.hidden = NO;
        Log(LOG_I, @"Showing ImGui view after PiP stop.");
    }

    if (!_isRestoringFromPiP) {
        [self returnToMainFrame];
    }
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL restored))completionHandler {
    _isRestoringFromPiP = YES;
    _streamView.hidden = NO;
    if (self.imguiView) {
        self.imguiView.mtkView.hidden = NO;
        Log(LOG_I, @"Showing ImGui view for PiP restore.");
    }
    completionHandler(YES);
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController
           didTransitionToRenderSize:(CMVideoDimensions)newRenderSize API_AVAILABLE(ios(15.0)){
    Log(LOG_I, @"PiP transitioned to size: %d x %d", newRenderSize.width, newRenderSize.height);
 }

// Indicate that playback is never paused for a live stream
- (BOOL)pictureInPictureControllerIsPlaybackPaused:(AVPictureInPictureController *)pictureInPictureController API_AVAILABLE(ios(14.0)) {
    return NO;
}

// Return an indefinite time range for a live stream
- (CMTimeRange)pictureInPictureControllerTimeRangeForPlayback:(AVPictureInPictureController *)pictureInPictureController API_AVAILABLE(ios(14.0)) {
    return CMTimeRangeMake(kCMTimeZero, kCMTimePositiveInfinity);
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController setPlaying:(BOOL)playing API_AVAILABLE(ios(14.0)) {
}

// Live streams typically can't skip, so just call the completion handler.
- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController skipByInterval:(CMTime)skipInterval completionHandler:(void (^)(void))completionHandler API_AVAILABLE(ios(14.0)) {
    if (completionHandler) {
        completionHandler();
    }
}

- (BOOL)isFirstStreaming {
    NSString *key = @"hasStreamedBefore";
    BOOL streamedBefore = [[NSUserDefaults standardUserDefaults] boolForKey:key];

    if (!streamedBefore) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:key];
        [[NSUserDefaults standardUserDefaults] synchronize]; // iOS 12+ 可省略
        return YES;
    }
    return NO;
}


- (bool)isOnScreenWidgetEnabled{
    return _settings.onscreenControls.intValue == OnScreenControlsLevelCustom;
}

- (void)setupPiPControllerWithRenderer:(VideoDecoderRenderer *)videoRenderer {    // Ensure we have the renderer and its layer
    if (self.pipController) {
        return;
    }
    Log(LOG_I, @"Setting up PiP controller...");

    if (!videoRenderer || !videoRenderer.displayLayer) {
        Log(LOG_E, @"PiP setup failed: Video renderer or display layer not ready.");
        return;
    }

    AVSampleBufferDisplayLayer *streamLayer = videoRenderer.displayLayer;

    if ([AVPictureInPictureController isPictureInPictureSupported]) {
        if (@available(iOS 15.0, *)) {
            self.pipContentSource = [[AVPictureInPictureControllerContentSource alloc] initWithSampleBufferDisplayLayer:streamLayer playbackDelegate:(id<AVPictureInPictureSampleBufferPlaybackDelegate>)self];
            self.pipController = [[AVPictureInPictureController alloc] initWithContentSource:self.pipContentSource];
            self.pipController.canStartPictureInPictureAutomaticallyFromInline = YES;
        } else {
            Log(LOG_E, @"PiP not fully supported on this device.");
            return;
        }

        if (self.pipController) {
            self.pipController.delegate = self;
            Log(LOG_I, @"PiP controller created successfully.");
        } else {
            Log(LOG_E, @"Failed to create PiP controller.");
        }
    } else {
        Log(LOG_E, @"PiP not supported on this device.");
    }
}

- (void)cleanupPiPController {
    if (self.pipController) {
        self.pipController.delegate = nil;
        self.pipController = nil;
        if (@available(iOS 15.0, *)) {
            self.pipContentSource = nil;
        }

        Log(LOG_I, @"PiP controller cleaned up.");
    }
}

- (void)updateToolboxSpecialEntries{
    if([self isOnScreenWidgetEnabled]){
        if(![toolBoxViewController.specialEntries containsObject:@"widgetLayoutTool"]) [toolBoxViewController.specialEntries insertObject:@"widgetLayoutTool" atIndex:0];
        // if(![toolBoxViewController.specialEntries containsObject:@"widgetSwitchTool"]) [toolBoxViewController.specialEntries insertObject:@"widgetSwitchTool" atIndex:1];
    }
    else{
        [toolBoxViewController.specialEntries removeObject:@"widgetLayoutTool"];
        // [toolBoxViewController.specialEntries removeObject:@"widgetSwitchTool"];
    }
    if(_settings.enablePIP){
        if(![toolBoxViewController.specialEntries containsObject:@"enterPip"]) [toolBoxViewController.specialEntries addObject:@"enterPip"];
    }
    else [toolBoxViewController.specialEntries removeObject:@"enterPip"];
    
    NSLog(@"toolBoxViewController.specialEntries %@", toolBoxViewController.specialEntries);
}

- (void)prepareGameProfileSelector{
    if(true){
        /* sets a reference to the correct 'LayoutOnScreenControlsViewController' depending on whether the user is on an iPhone or iPad */
        // _layoutOnScreenControlsVC = [[LayoutOnScreenControlsViewController alloc] init];
        BOOL isIPhone = ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone);
        if (isIPhone) {
            UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"iPhone" bundle:nil];
            _layoutOnScreenControlsVC = [storyboard instantiateViewControllerWithIdentifier:@"LayoutOnScreenControlsViewController"];
        }
        else {
            UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"iPad" bundle:nil];
            _layoutOnScreenControlsVC = [storyboard instantiateViewControllerWithIdentifier:@"LayoutOnScreenControlsViewController"];
            _layoutOnScreenControlsVC.modalPresentationStyle = UIModalPresentationFullScreen;
        }
        _layoutOnScreenControlsVC.view.backgroundColor = UIColor.clearColor;
        _layoutOnScreenControlsVC.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    }
    //NSLog(@"in osc frameview gestures: %d", (uint32_t)[self.view.gestureRecognizers count]);
    //NSLog(@"in osc streamview gestures: %d", (uint32_t)[_streamView.gestureRecognizers count]);
}

- (void)bringUpToolboxMenu{
    [self bringUpToolboxMenuWithoutWidgetLayoutTool:NO];
}

- (void)bringUpToolboxMenuWithoutWidgetLayoutTool{
    [self bringUpToolboxMenuWithoutWidgetLayoutTool:YES];
}

- (void)bringUpToolboxMenuWithoutWidgetLayoutTool:(BOOL)hideWidgetLayoutToolEntry{
    [self openStreamControls];
    [self prepareGameProfileSelector];
    ToolboxViewController* oldToolboxVC = toolBoxViewController;
    toolBoxViewController = [[ToolboxViewController alloc] init];
    toolBoxViewController.specialEntryDelegate = self;
    toolBoxViewController.commandOwner = _commandOwner;
    toolBoxViewController.specialEntries = [oldToolboxVC.specialEntries mutableCopy];
    if(hideWidgetLayoutToolEntry) [toolBoxViewController.specialEntries removeObject:@"widgetLayoutTool"];
    toolBoxViewController.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    if([GenericUtils isFirstOpeningNewToolbox]){
        [GenericUtils handleFirstOpeningNewToolboxIn:self handler:^{
            [self presentViewController:self->toolBoxViewController animated:YES completion:^{}];
        }];
    }
    else [self presentViewController:toolBoxViewController animated:YES completion:^{}];
}


- (BOOL)currentProfileContainsMagnifierWidget {
    OSCProfilesManager *profileManager = [OSCProfilesManager sharedManager:CGRectZero];
    for (NSData *buttonStateEncoded in _oscProfile.buttonStatesEncoded) {
        OnScreenButtonState *buttonState = [profileManager unarchiveButtonStateEncoded:buttonStateEncoded];
        if (buttonState.widgetType == CustomOnScreenWidget &&
            [buttonState.name containsString:@"MAGNIFIER"]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)shouldWrapStreamViewInScrollView {
    return YES;
}

- (UIView *)streamContentContainerView {
    if (_scrollView && _streamView.superview == _scrollView && _scrollView.superview == self.view) {
        return _scrollView;
    }
    return _streamView;
}

- (void)syncMagnifierStateFromScrollView {
    if (!_scrollView) {
        _streamViewMagnifierContentOffset = CGPointZero;
        _streamViewMagnifierZoomScale = 1.0f;
        return;
    }

    _streamViewMagnifierContentOffset = _scrollView.contentOffset;
    _streamViewMagnifierZoomScale = _scrollView.zoomScale;
}

- (UIEdgeInsets)magnifierViewportInsets {
    if (!_scrollView) {
        return UIEdgeInsetsZero;
    }

    CGSize contentSize = _scrollView.contentSize;
    CGSize boundsSize = _scrollView.bounds.size;
    CGFloat insetX = MAX(boundsSize.width - contentSize.width * 0.1f, 0.0f);
    CGFloat insetY = MAX(boundsSize.height - contentSize.height * 0.1f, 0.0f);
    return UIEdgeInsetsMake(insetY, insetX, insetY, insetX);
}

- (CGPoint)clampedMagnifierContentOffset:(CGPoint)candidateOffset {
    if (!_scrollView) {
        return CGPointZero;
    }

    UIEdgeInsets insets = _scrollView.contentInset;
    CGFloat minOffsetX = -insets.left;
    CGFloat minOffsetY = -insets.top;
    CGFloat maxOffsetX = MAX(_scrollView.contentSize.width - CGRectGetWidth(_scrollView.bounds) + insets.right, minOffsetX);
    CGFloat maxOffsetY = MAX(_scrollView.contentSize.height - CGRectGetHeight(_scrollView.bounds) + insets.bottom, minOffsetY);

    candidateOffset.x = MIN(MAX(candidateOffset.x, minOffsetX), maxOffsetX);
    candidateOffset.y = MIN(MAX(candidateOffset.y, minOffsetY), maxOffsetY);
    return candidateOffset;
}

- (void)updateMagnifierViewportMetrics {
    if (!_scrollView) {
        return;
    }

    _scrollView.contentInset = [self magnifierViewportInsets];
    _scrollView.contentOffset = [self clampedMagnifierContentOffset:_scrollView.contentOffset];
}

- (void)updateScrollViewInteractionState {
    if (!_scrollView) {
        return;
    }

    BOOL interactionEnabled = _magnifierViewportInteractionActive;
#if !TARGET_OS_TV
    // Trackpad two-finger motion scrolls the PC, not the phone video viewport.
    interactionEnabled = interactionEnabled && !_preferSessionTrackpad;
#endif
    if (@available(iOS 17.0, *)) {
        _scrollView.allowsKeyboardScrolling = false;
    }
    _scrollView.scrollEnabled = interactionEnabled;
    _scrollView.panGestureRecognizer.enabled = interactionEnabled;
    _scrollView.pinchGestureRecognizer.enabled = interactionEnabled;
}

- (void)resetMagnifierTransformState {
    if (_scrollView) {
        [_scrollView setZoomScale:1.0f animated:NO];
        _scrollView.contentOffset = CGPointZero;
    }
    _streamViewMagnifierContentOffset = CGPointZero;
    _streamViewMagnifierZoomScale = 1.0f;
    _magnifierViewportInteractionActive = NO;
}

- (void)applyMagnifierTranslation:(CGVector)translation pinchDelta:(CGFloat)pinchDelta {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyMagnifierTranslation:translation pinchDelta:pinchDelta];
        });
        return;
    }

    if (!_scrollView || _streamView.superview != _scrollView) {
        return;
    }

    CGFloat previousZoomScale = MAX(_scrollView.zoomScale, _scrollView.minimumZoomScale);
    CGPoint visibleCenter = CGPointMake(_scrollView.contentOffset.x + CGRectGetWidth(_scrollView.bounds) * 0.5f,
                                        _scrollView.contentOffset.y + CGRectGetHeight(_scrollView.bounds) * 0.5f);

    CGFloat targetZoomScale = previousZoomScale;
    if (fabs(pinchDelta) > 0.0001f) {
        targetZoomScale += pinchDelta / 240.0f;
        targetZoomScale = MIN(MAX(targetZoomScale, _scrollView.minimumZoomScale), _scrollView.maximumZoomScale);
    }

    if (fabs(targetZoomScale - previousZoomScale) > 0.0001f) {
        CGFloat zoomRatio = targetZoomScale / previousZoomScale;
        [_scrollView setZoomScale:targetZoomScale animated:NO];
        visibleCenter = CGPointMake(visibleCenter.x * zoomRatio, visibleCenter.y * zoomRatio);
    }

    CGPoint targetOffset = CGPointMake(visibleCenter.x - CGRectGetWidth(_scrollView.bounds) * 0.5f - translation.dx,
                                       visibleCenter.y - CGRectGetHeight(_scrollView.bounds) * 0.5f - translation.dy);
    [self updateMagnifierViewportMetrics];
    _scrollView.contentOffset = [self clampedMagnifierContentOffset:targetOffset];
    [self syncMagnifierStateFromScrollView];
}

- (void)handleScrollPan:(UIPanGestureRecognizer *)gesture {
    switch (gesture.state){
        case UIGestureRecognizerStateEnded:
            if(_oscProfile.touchMode == AbsoluteTouch && _scrollView.zoomScale < 1.0) [self resetMagnifierStreamViewWithAnimated:true];
            break;
        default:
            break;
    }
}

- (void)configZoomGestureAndAddStreamView{
    BOOL shouldWrapInScrollView = [self shouldWrapStreamViewInScrollView];

    if (shouldWrapInScrollView) {
        if(!_scrollView) _scrollView = [[UIScrollView alloc] initWithFrame:self.view.frame];
        _scrollView.scrollsToTop = false;
        _scrollView.frame = self.view.bounds;
        _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
#if !TARGET_OS_TV
        [_scrollView.panGestureRecognizer setMinimumNumberOfTouches:2];
        [_scrollView.panGestureRecognizer setMaximumNumberOfTouches:2]; // reduce competing with keyboardToggleRecognizer in StreamView.
        [_scrollView.panGestureRecognizer addTarget:self
                                             action:@selector(handleScrollPan:)];
#endif
        [_scrollView setShowsHorizontalScrollIndicator:NO];
        [_scrollView setShowsVerticalScrollIndicator:NO];
        [_scrollView setDelegate:self];
        [_scrollView setBackgroundColor:UIColor.blackColor];
        [_scrollView setClipsToBounds:YES];
        [_scrollView setBouncesZoom:NO];
        [_scrollView setMinimumZoomScale:0.1f];
        [_scrollView setMaximumZoomScale:10.0f];
        if(!_mainFrameViewcontroller.settingsExpandedInStreamView){
            if (_streamView.superview != _scrollView) {
                [_streamView removeFromSuperview];
                _streamView.frame = _scrollView.bounds;
                [_scrollView addSubview:_streamView];
            }
            if (_scrollView.superview != self.view) {
                [self.view insertSubview:_scrollView atIndex:0];
            } else {
                [self.view sendSubviewToBack:_scrollView];
            }
        }
        if (_streamViewMagnifierZoomScale < _scrollView.minimumZoomScale) {
            _streamViewMagnifierZoomScale = 1.0f;
        }
        [_scrollView setZoomScale:_streamViewMagnifierZoomScale animated:NO];
        _scrollView.contentOffset = _streamViewMagnifierContentOffset;
        [self updateMagnifierViewportMetrics];
        [self syncMagnifierStateFromScrollView];
    }
    else{
        if([_streamView.superview isKindOfClass:[UIScrollView class]]){
            [self resetMagnifierTransformState];
            [_streamView removeFromSuperview];
        }
        [_scrollView removeFromSuperview];
        [self.view insertSubview:_streamView atIndex:0];
    }
}

- (void)reConfigStreamViewRealtime {
    //if(!viewJustLoaded) [self handleViewResize];
    [self reConfigStreamViewRealtimeAndReloadSettings:YES reloadOnscreenWidgets:NO];
}

- (TemporarySettings *)effectivePresentationSettings {
    TemporarySettings *settings = [[[DataManager alloc] init] getSettings];
    TemporarySettings *snapshot = self.streamConfig.presentationSettings;
    if (snapshot) {
        settings.renderingBackend = snapshot.renderingBackend;
        settings.framePacingMode = snapshot.framePacingMode;
        settings.asyncFrameDequeue = snapshot.asyncFrameDequeue;
        settings.frameQueueSize = snapshot.frameQueueSize;
        settings.enableHdr = snapshot.enableHdr;
        settings.fullColorRange = snapshot.fullColorRange;
        settings.preferredCodec = snapshot.preferredCodec;
        settings.enableYUV444 = snapshot.enableYUV444;
        settings.enablePIP = snapshot.enablePIP;
        settings.sdrPerformanceWorkaround = snapshot.sdrPerformanceWorkaround;
        settings.audioConfig = snapshot.audioConfig;
        settings.playAudioOnPC = snapshot.playAudioOnPC;
        settings.framerate = @(self.streamConfig.frameRate);
    }
    if (self.streamConfig.requiresMetalPresentation) {
        settings.renderingBackend = @(RENDER_METAL);
        settings.framePacingMode = @(FramePacingModeQueue);
        settings.enableHdr = NO;
        settings.enablePIP = NO;
        settings.sdrPerformanceWorkaround = NO;
        settings.framerate = @(self.streamConfig.frameRate);
        settings.enableYUV444 = NO;
    }
#if !TARGET_OS_TV
    SunlightMachineControlsSettings *machine = [self resolvedMachineControls];
    settings.localVolume = @(machine.localVolume);
    settings.statsOverlayLevel = @(machine.statsOverlayLevel);
    settings.statsOverlayEnabled = machine.statsOverlayEnabled;
#endif
    return settings;
}

// key implementation of reconfiguring streamview after realtime setting menu is closed.
- (void)reConfigStreamViewRealtimeAndReloadSettings:(BOOL)reloadSettings reloadOnscreenWidgets:(BOOL)reloadOnscreenWidgets{
    //[self.view removeGestureRecognizer:]
    //first, remove all gesture recognizers:
    for (UIGestureRecognizer *recognizer in _streamView.gestureRecognizers) {
        [_streamView removeGestureRecognizer:recognizer];
    }
    for (UIGestureRecognizer *recognizer in self.view.gestureRecognizers) {
        [self.view removeGestureRecognizer:recognizer];
    }
    
    if (reloadSettings) {
        _settings = [self effectivePresentationSettings];
    }
    _oscProfile = [[OSCProfilesManager sharedManager:CGRectZero] getSelectedProfile];
    
    // A hidden overlay keeps its last detail level for the keyboard shortcut.
    overlayLevel = _settings.statsOverlayLevel.intValue > 0
        ? _settings.statsOverlayLevel.intValue : MAX(1, overlayLevel);
    [self setupOverlayView];
    
    if(viewIsBeingResized) viewIsBeingResized = false;
    else [self prepareGameProfileSelector];
    [self updateToolboxSpecialEntries];
    [self configZoomGestureAndAddStreamView];
    [self->_streamView disableOnScreenControls]; //don't know why but this must be called outside the streamview class, just put it here. execute in streamview class cause hang
    // Refresh only live input behavior. The active mode, quality and codec
    // remain frozen until this mode tab's explicit reconnect (or a confirmed
    // glasses downgrade); a gesture/settings refresh cannot renegotiate them.
    self.streamConfig.swapABXYButtons = _settings.swapABXYButtons;
    self.streamConfig.buttonVisualFeedback = _settings.buttonVisualFeedback;
    self.streamConfig.asyncNativeTouchPriority = _settings.asyncNativeTouchPriority.boolValue;
    self.streamConfig.gyroMode = _settings.gyroMode.intValue;
    self.streamConfig.emulatedControllerType = _settings.emulatedControllerType.intValue;
    self.streamConfig.hapticEngine = _settings.hapticEngine.intValue;
    self.streamConfig.multiController = _settings.multiController;
    self.streamConfig.localMousePointerMode = _settings.localMousePointerMode.intValue;
    self.streamConfig.redirectMic = _settings.redirectMic;

    @synchronized (self) {
        if (!_microphoneCaptureStopped && _micStreamInitialized &&
            [MicHandler permissionGranted] && _settings.redirectMic) {
            [micHandler startTapping];
        }
        else [micHandler stopTappingWithStopEngine:false];
    }
    
    Connection.muteInBackground = _settings.muteInBackground;
    
    if(!_viewJustLoaded) [_controllerSupport updateControllerSupport:self.streamConfig delegate:self];
    // reload controllerSupport obj, this is mandatory for OSC reload,especially when the stream view is launched without OSC
    [_streamView setupStreamViewWithControllerSupport:_controllerSupport interactionDelegate:self streamConfig:self.streamConfig gameProfile:_oscProfile streamFrameTopLayerView:self.view]; //reinitiate setupStreamView process.
    [self->_streamView reloadOnScreenControlsRealtimeWithControllerSupport:(ControllerSupport*)_controllerSupport
                                        streamConfig:(StreamConfiguration*)_streamConfig]; //reload OSC here.
    
    bool onScreenWidgetSwitched = previousOnScreenWidgetEnabled != [_streamView isOnScreenWidgetEnabled];
    bool needReload = onScreenWidgetSwitched && !previousOnScreenWidgetEnabled;
    OnScreenWidgetView.trackPointEnabled = _settings.touchPointTracking;
    [_streamView reloadGameProfile:_oscProfile reloadWidgets:reloadOnscreenWidgets||needReload];
    
    if(onScreenWidgetSwitched && previousOnScreenWidgetEnabled) [_streamView clearOnScreenWidgets];
    previousOnScreenWidgetEnabled = [_streamView isOnScreenWidgetEnabled];
    
    [self reloadAirPlayConfig];
    [self mousePresenceChanged];
    
    // Invalidate the old timer to prevent duplicates
    if (self->_statsUpdateTimer) {
        [self->_statsUpdateTimer invalidate];
        self->_statsUpdateTimer = nil;
    }
    // Re-schedule the timer only if the overlay is enabled
    if (_settings.statsOverlayEnabled) {
        self->_statsUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                                                 target:self
                                                               selector:@selector(updateStatsOverlay)
                                                               userInfo:nil
                                                                repeats:YES];
    } else {
        // Ensure the overlay is removed when disabled
        [_overlayView removeFromSuperview];
    }
    
    // Re-create the ImGui view to properly apply the 'enableGraphs' setting
    if (self.imguiView && self.imguiView.mtkView) {
        [self.imguiView stop];
        [self.imguiView.mtkView removeFromSuperview];
        self.imguiView = nil;
    }
    self.imguiView = [[ImGuiRenderer alloc] initWithFrame:self.view.bounds
                                                streamFps:[_settings.framerate intValue]
                                             enableGraphs:_settings.enableGraphs
                                             graphOpacity:[_settings.graphOpacity intValue]];
    self.imguiView.mtkView.userInteractionEnabled = NO;
    [self.view addSubview:self.imguiView.mtkView];

    // Ensure views are layered correctly
    // Metal view should be at the bottom for video rendering
    if (self.metalViewController && self.metalViewController.view.superview == self.view) {
        [self.view sendSubviewToBack:self.metalViewController.view];
    }
    // StreamView should also be at the back so OSC CALayers on self.view show
    if (self->_streamView && self->_streamView.superview) {
        [self.view sendSubviewToBack:[self streamContentContainerView]];
    }
    // ImGui view should be on top for debug graphs
    if (self.imguiView && self.imguiView.mtkView.superview) {
        [self.view bringSubviewToFront:self.imguiView.mtkView];
    }
    
    // [self pauseTimer];
    if(_settings.sendDummyEvent){
        if(!safeTimer) [self setupTimer];
        if(!_viewJustLoaded) [safeTimer start];
    }
    else [safeTimer pause];
    
    _motionHandler = [MotionHandler sharedWithProfile: nil];
    _motionHandler.gyroBiasX = _settings.gyroBiasX.doubleValue;
    _motionHandler.gyroBiasY = _settings.gyroBiasY.doubleValue;
    _motionHandler.gyroBiasZ = _settings.gyroBiasZ.doubleValue;
    _motionHandler.controllerGyroBiasX = _settings.controllerGyroBiasX.doubleValue;
    _motionHandler.controllerGyroBiasY = _settings.controllerGyroBiasY.doubleValue;
    _motionHandler.controllerGyroBiasZ = _settings.controllerGyroBiasZ.doubleValue;

    TouchPadGestureHandler.enablePinch = _settings.enablePinch;
    TouchPadGestureHandler.ctrlDownForPinch = _settings.ctrlDownForPinch;
    TouchPadGestureHandler.scrollSensitivity = _settings.scrollSensitivity.floatValue;
    TouchPadGestureHandler.pinchSensitivity = _settings.pinchSensitivity.floatValue;
    TouchPadGestureHandler.displayLinkRate = _settings.framerate.intValue;
    
    [self setMagnifierViewportInteractionEnabled:_oscProfile.touchMode == AbsoluteTouch && !_settings.passthroughGestures];
    
    GenericUtils.globeAsEscape = _settings.globeAsEscape;
    
    if (@available(iOS 13.0, *)) {
        ControllerNavigator.localRadialMenuButton = (ControllerElement)_settings.localRadialMenuButton.intValue;
        ControllerNavigator.streamingRadialMenuButton = (ControllerElement)_settings.streamingRadialMenuButton.intValue;
        ControllerNavigator.streamingRadialMenuDelay = (NSTimeInterval)_settings.streamingRadialMenuDelay.floatValue;
    }

    [self updateStreamControls];
    NSLog(@"frameview gestures: %d", (uint32_t)[self.view.gestureRecognizers count]);
    NSLog(@"streamview gestures: %d", (uint32_t)[_streamView.gestureRecognizers count]);
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    _viewJustLoaded = false;
    _deviceWindow = self.view.window;
    previousOnScreenWidgetEnabled = [_streamView isOnScreenWidgetEnabled];
    // Both renderer creation and the device window must be ready before routing.
    _externalDisplayRoutingReady = !_isEndingStream;
    [self reloadAirPlayConfig];

    self->_streamView.originalFrame = self->_streamView.frame;
    
#if !TARGET_OS_TV
    [[self revealViewController] setPrimaryViewController:self];
    
    [self restorePersistedStreamViewOffsetAndScaleWithProfile:_oscProfile];
    
    GenericUtils.pencilInStreaming = false;
    
    if (!_streamUIObserversInstalled) {
        _streamUIObserversInstalled = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateContentOffsetAndScale:)
                                                 name:@"GameProfileSelectedNotification"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reConfigStreamViewRealtime) // reconfig streamview when settings view is closed in stream view
                                                 name:@"SettingsViewClosedNotification"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(disconnectRemoteSession) //quit session when exit button is press in setting view during streaming
                                                 name:@"SessionDisconnectedBySettingsMenuNotification"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(expandSettingsView) // //force expand settings view to update resolution table, and all setting includes current fullscreen resolution will be updated.
                                                 name:@"SettingsOverlayButtonPressedNotification"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleNonStandardKeyboard:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidHide)
                                                 name:UIKeyboardDidHideNotification
                                               object:nil];

    }

    [safeTimer start];
    
    #endif
}

#if TARGET_OS_TV
- (void)controllerPauseButtonPressed:(id)sender { }
- (void)controllerPauseButtonDoublePressed:(id)sender {
    Log(LOG_I, @"Menu double-pressed -- backing out of stream");
    [self returnToMainFrame];
}
- (void)controllerPlayPauseButtonPressed:(id)sender {
    Log(LOG_I, @"Play/Pause button pressed -- backing out of stream");
    [self returnToMainFrame];
}
#endif

- (void)popKeyboardAndMouseStreamingTip {
    [AlertControllerUtil showAlertIn:self
                                    title:[LocalizationHelper localizedStringForKey:@"Keyboard/Mouse Connected"]
                                  message:[LocalizationHelper localizedStringForKey:@"keyboard&MouseStreamingTip"]
                               withCancel:NO
                              buttonTitle:[LocalizationHelper localizedStringForKey:@"This tip won't be shown again"]
                                countdown:5
                                   action:^{}
                               completion:^{
                    }];
}

- (void)popFirstStreamingTip {
    // The persistent controls pill and contextual touch hint replace the timed
    // first-launch alert that taught hidden edge gestures.
}

- (void)updateTheme {
    self.view.backgroundColor = UIColor.blackColor;
    _stageLabel.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.9];
    _spinner.color = UIColor.whiteColor;
}

- (void)viewDidLoad
{
    VLSharedStreamFrameViewController = self;
    _viewJustLoaded = true;
    viewIsBeingResized = false;
    _magnifierViewportInteractionActive = false;
    
    _touchDisabled = false;
    _singleTouchDisabled = false;
    
    [super viewDidLoad];

    
    [self.navigationController setNavigationBarHidden:YES animated:YES];
    
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    _settings = [self effectivePresentationSettings];
    
    _stageLabel = [[UILabel alloc] init];
    [_stageLabel setUserInteractionEnabled:NO];
    // [_stageLabel setText:[NSString stringWithFormat:@"Starting %@...", self.streamConfig.appName]];
    [_stageLabel setText: [LocalizationHelper localizedStringForKey:@"Connecting..."]];
    [_stageLabel sizeToFit];
    _stageLabel.textAlignment = NSTextAlignmentCenter;
    _stageLabel.textColor = [UIColor whiteColor];
    _stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2);
    
    _spinner = [[UIActivityIndicatorView alloc] init];
    _spinner.color = UIColor.whiteColor;
    [_spinner setUserInteractionEnabled:NO];
#if TARGET_OS_TV
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhiteLarge];
#else
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhite];
#endif
    [_spinner sizeToFit];
    [_spinner startAnimating];
    _spinner.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2 - _stageLabel.frame.size.height - _spinner.frame.size.height);
    
    _oscProfile = [[OSCProfilesManager sharedManager:CGRectZero] getSelectedProfile];
    
    _controllerSupport = [[ControllerSupport alloc] initWithConfig:self.streamConfig delegate:self];
    _inactivityTimer = nil;
    
    _streamView = [[StreamView alloc] initWithFrame:self.view.frame];
    _streamViewMagnifierContentOffset = CGPointZero;
    _streamViewMagnifierZoomScale = 1.0f;
    _magnifierViewportInteractionActive = NO;
    
    toolBoxViewController = [[ToolboxViewController alloc] init];
    toolBoxViewController.specialEntryDelegate = self;
    
    _isRestoringFromPiP = NO;
    
    /*
     _settings.externalDisplayMode.intValue:
     0 - stage manager
     1 - airplay
     */
    // A separate render view is always created to support external displays.
    _streamVideoRenderView = [[UIView alloc] initWithFrame:_streamView.bounds];
    _streamVideoRenderView.bounds = _streamView.bounds;
    _streamVideoRenderView.userInteractionEnabled = false;
    _streamVideoRenderView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_streamView insertSubview:_streamVideoRenderView atIndex:0];

    // Scene availability follows UIScreen connection asynchronously. Observe the
    // coordinator after its window and render-view layout are ready instead.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(externalDisplayChanged:)
                                                 name:@"SunlightExternalDisplayChanged"
                                               object:nil];
    
    //[_streamView setupStreamView:_controllerSupport interactionDelegate:self config:self.streamConfig];
    [self setupStreamControls];
    [self reConfigStreamViewRealtime]; // call this method again to make sure all gestures are configured & added to the superview(self.view), including the gestures added from inside the streamview.
    
    if([self isFirstStreaming] || GenericUtils.isFirstStreamingOnMac) [self popFirstStreamingTip];
    
#if TARGET_OS_TV
    if (!_menuTapGestureRecognizer || !_menuDoubleTapGestureRecognizer || !_playPauseTapGestureRecognizer) {
        _menuTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonPressed:)];
        _menuTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];
        
        _playPauseTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPlayPauseButtonPressed:)];
        _playPauseTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypePlayPause)];
        
        _menuDoubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonDoublePressed:)];
        _menuDoubleTapGestureRecognizer.numberOfTapsRequired = 2;
        [_menuTapGestureRecognizer requireGestureRecognizerToFail:_menuDoubleTapGestureRecognizer];
        _menuDoubleTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];
    }
    
    [self.view addGestureRecognizer:_menuTapGestureRecognizer];
    [self.view addGestureRecognizer:_menuDoubleTapGestureRecognizer];
    [self.view addGestureRecognizer:_playPauseTapGestureRecognizer];
    
#else
    //[self configSwipeGestures]; // swipe & exit gesture configured here
    //[self configOscLayoutTool]; //_oscLayoutTapRecoginizer will be added or removed to the view here
#endif
    
    _tipLabel = [[UILabel alloc] init];
    [_tipLabel setUserInteractionEnabled:NO];
    
#if TARGET_OS_TV
    [_tipLabel setText:@"Tip: Tap the Play/Pause button on the Apple TV Remote to disconnect from your PC"];
#else
    // [_tipLabel setText:[LocalizationHelper localizedStringForKey:@"Tip: Swipe from screen edge to a certiain distance (configured by Swipe & Exit settings) to disconnect from your PC"]];
#endif
    
    [_tipLabel sizeToFit];
    _tipLabel.textColor = [UIColor whiteColor];
    _tipLabel.textAlignment = NSTextAlignmentCenter;
    _tipLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height * 0.9);
    
    _streamMan = [[StreamManager alloc] initWithConfig:self.streamConfig
                                            renderView:_streamVideoRenderView
                                   connectionCallbacks:self];
    NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
    [opQueue addOperation:_streamMan];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector: @selector(applicationDidBecomeActive:)
                                                 name: UIApplicationDidBecomeActiveNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector: @selector(applicationDidEnterBackground:)
                                                 name: UIApplicationDidEnterBackgroundNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(gameProfileSelectorClosed)
                                                 name:@"GameProfileSelectorCloseNotification"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleStreamAspectRatioChanged:)
                                                 name:@"StreamAspectRatioChanged"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(externalDisplayPreferenceChanged:)
                                                 name:SunlightExternalDisplayPreferenceChangedNotification
                                               object:nil];
#if 0
    // FIXME: This doesn't work reliably on iPad for some reason. Showing and hiding the keyboard
    // several times in a row will not correctly restore the state of the UIScrollView.
    // TrueZhuanJia: Already fixed by my refactored keyboard toggle gesture recognizer, and the keyboardWillShow/Hide method in StreamView.m
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillShow:)
                                                 name: UIKeyboardWillShowNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillHide:)
                                                 name: UIKeyboardWillHideNotification
                                               object: nil];
#endif
    
    // for compatibility of iOS14 & lower
    self.view.backgroundColor = [UIColor systemGrayColor];
    _stageLabel.textColor = [UIColor systemGrayColor];
    _spinner.color = [UIColor systemGrayColor];
    
    [self updateTheme];
    
    [self.view addSubview:_stageLabel];
    [self.view addSubview:_spinner];
    [self.view addSubview:_tipLabel];
    
    if ([_settings.renderingBackend intValue] == RENDER_METAL) {
        // Metal view for video
        Log(LOG_I, @"StreamFrameViewController creating MetalViewController");
        self.metalViewController = [[MetalViewController alloc] initWithFrame:self.view.bounds
                                                                    framerate:[self->_settings.framerate floatValue]
                                                                     settings:self->_settings
                                                               metricsHandler:self.imguiView.metricsHandler];
        self.metalViewController.streamMode = self.streamConfig.streamMode;
        self.metalViewController.view.userInteractionEnabled = NO;
        self.metalViewController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addChildViewController:self.metalViewController];
        // Insert Metal view at the bottom of the view hierarchy
        [self.view insertSubview:self.metalViewController.view atIndex:0];
        [self.metalViewController didMoveToParentViewController:self];
    }
    
    ControllerUtil.gamepadArrivalReported = false;
    
    [OnScreenWidgetView disableFolderAnimationFor:2];
}

- (void)keyboardWillShow:(NSNotification *)notification{
    [_streamView keyboardWillShow:notification];
}

- (void)keyboardWillHide{
    [_streamView keyboardWillHide];
}

- (void)keyboardDidHide{
    _streamView.bounds = _deviceWindow.bounds;
    _streamView.frame = _deviceWindow.frame;
}

- (void)handleNonStandardKeyboard:(NSNotification *)notification{
    [_streamView handleNonStandardKeyboard:notification];
}

- (void)handleWidgetLayoutGesture{
    [self prepareGameProfileSelector];
    [self openWidgetLayoutTool];
}

- (void)openWidgetLayoutTool{
    [_streamView saveStreamingGameProfileChanges];
    _streamView.widgetToolOpened = true;
    [self->_streamView disableOnScreenControls];
    [self->_streamView clearOnScreenWidgets]; // clear all onScreenKeyboardButtons before entering edit mode
    _layoutOnScreenControlsVC.quickSwitchEnabled = false;
    _layoutOnScreenControlsVC.toolbarStackView.hidden = false;
    _layoutOnScreenControlsVC.toolbarRootView.hidden = false;
    [self presentViewController:_layoutOnScreenControlsVC animated:YES completion:nil];
}

- (void)openWidgetProfileTableWithPickProfile:(BOOL)pickProfile{
    [_streamView saveStreamingGameProfileChanges];
    _streamView.widgetToolOpened = true;
    [self->_streamView disableOnScreenControls];
    [self->_streamView clearOnScreenWidgets]; // clear all onScreenKeyboardButtons before entering edit mode
    _layoutOnScreenControlsVC.quickSwitchEnabled = true;
    _layoutOnScreenControlsVC.toolbarStackView.hidden = true;
    _layoutOnScreenControlsVC.toolbarRootView.hidden = true;
    ProfileSelectorLoadingMode loadingMode = pickProfile ? ProfileSelectorLoadingModePickProfile : ProfileSelectorLoadingModeSelectProfileFromStreamView;
    _layoutOnScreenControlsVC.profileSelectorLoadingMode = loadingMode;
    [self presentViewController:_layoutOnScreenControlsVC animated:NO completion:^{
        [self->_layoutOnScreenControlsVC presentProfileSelectorWith:loadingMode animated:false];
    }];
}

- (void)bringUpSoftKeyboard{
    _streamControls.expanded = NO;
    [self updateStreamControls];
    [self->_streamView showSoftKeyboard];
}

- (void)enterPip{
    if (@available(iOS 15.0, tvOS 15.0, *)) {
        if(!_settings.enablePIP){
            AlertControllerUtil.autoCompletion = true;
            [AlertControllerUtil showAlertIn:self
                                       title:@""
                                     message:[LocalizationHelper localizedStringForKey:@"pipDisabled"]
                                  withCancel:NO
                                 buttonTitle:@""
                                   countdown:1
                                      action:^{}
                                  completion:^{}];
        }
    }
    else {
        AlertControllerUtil.autoCompletion = true;
        [AlertControllerUtil showAlertIn:self
                                   title:@""
                                 message:[LocalizationHelper localizedStringForKey:@"pipNotSupported"]
                              withCancel:NO
                             buttonTitle:@""
                               countdown:1
                                  action:^{}
                              completion:^{}];
    }
    [self.pipController startPictureInPicture];
}

- (void)alterAbsTouchDragWithMouseButton:(int32_t)mouseButton{
    [_streamView alterAbsTouchDragWith:mouseButton];
}

- (void)magnifierMoveStreamViewWithTranslation:(CGVector)translation {
    _magnifierViewportInteractionActive = YES;
    [self updateScrollViewInteractionState];
    [self applyMagnifierTranslation:translation pinchDelta:0.0f];
}

- (void)magnifierMoveStreamViewWithTranslation:(CGVector)translation pinchDelta:(CGFloat)pinchDelta {
    _magnifierViewportInteractionActive = YES;
    [self updateScrollViewInteractionState];
    [self applyMagnifierTranslation:translation pinchDelta:pinchDelta];
}

- (void)setMagnifierViewportInteractionEnabled:(BOOL)enabled {
    _magnifierViewportInteractionActive = enabled || (_oscProfile.touchMode == AbsoluteTouch && !_settings.passthroughGestures && !GenericUtils.pencilInStreaming);
    [self updateScrollViewInteractionState];
}

- (void)updateContentOffsetAndScale:(NSNotification*)notification {
    OSCProfile* profile = (OSCProfile* ) notification.object;
    [self restorePersistedStreamViewOffsetAndScaleWithProfile:profile];
}

- (void)restorePersistedStreamViewOffsetAndScaleWithProfile:(OSCProfile* )profile {
    if(!profile){
        profile = [OSCProfilesManager sharedManager:CGRectZero].getSelectedProfile;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setMagnifierViewportInteractionEnabled:true];
        CGPoint streamViewOffset = CGPointMake(profile.normalizedStreamViewOffset.x*self.view.bounds.size.width, profile.normalizedStreamViewOffset.y*self.view.bounds.size.height);
        [self restoreMagnifierStreamViewWithOffset:streamViewOffset scale:profile.streamViewScale animated:YES];
        [self setMagnifierViewportInteractionEnabled:profile.touchMode == AbsoluteTouch && !self->_settings.passthroughGestures];
    });
}

- (void)restoreMagnifierStreamViewWithOffset:(CGPoint)offset scale:(CGFloat)scale {
    [self restoreMagnifierStreamViewWithOffset:offset scale:scale animated:NO];
}

- (void)restoreMagnifierStreamViewWithOffset:(CGPoint)offset scale:(CGFloat)scale animated:(BOOL)animated {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self restoreMagnifierStreamViewWithOffset:offset scale:scale animated:animated];
        });
        return;
    }

    if (!_scrollView || _streamView.superview != _scrollView) {
        return;
    }

    CGFloat targetScale = MIN(MAX(scale, _scrollView.minimumZoomScale), _scrollView.maximumZoomScale);
    [_scrollView setZoomScale:targetScale animated:animated];
    [self updateMagnifierViewportMetrics];
    CGPoint clampedOffset = [self clampedMagnifierContentOffset:offset];

    if (animated) {
        [UIView animateWithDuration:0.1
                         animations:^{
                             self->_scrollView.contentOffset = clampedOffset;
                         }
                         completion:^(__unused BOOL finished) {
                             [self syncMagnifierStateFromScrollView];
                         }];
    }
    else {
        _scrollView.contentOffset = clampedOffset;
        [self syncMagnifierStateFromScrollView];
    }
}

- (void)resetMagnifierStreamViewWithAnimated:(BOOL)animated {
    [self restoreMagnifierStreamViewWithOffset:CGPointZero scale:1.0f animated:animated];
}

- (void)gameProfileSelectorClosed{
    // Handle the callback
    _streamView.widgetToolOpened = false;
    [self->_streamView disableOnScreenControls]; // add this to get realtime back menu working.
    [self->_streamView reloadOnScreenControlsWith:(ControllerSupport*)_controllerSupport
                                        andConfig:(StreamConfiguration*)_streamConfig];
    // [self->_streamView reloadLegacyWidgets];
    [self reConfigStreamViewRealtimeAndReloadSettings:NO reloadOnscreenWidgets:_settings.onscreenControls.intValue == OnScreenControlsLevelCustom];
    // [self->_streamView reloadGameProfile:nil reloadWidgets:true]; //update keyboard buttons here
    [OnScreenWidgetView disableFolderAnimationFor:2];
}

- (void)handleStreamAspectRatioChanged:(NSNotification *)notification {
    NSNumber *aspectRatioNum = notification.userInfo[@"aspectRatio"];
    if (aspectRatioNum && _streamView) {
        CGFloat aspectRatio = [aspectRatioNum doubleValue];
        if (self.streamConfig.streamMode == SunlightStreamModeHost3D) {
            aspectRatio *= 0.5; // Phone preview shows one eye of the packed stream.
        }
        if (!isfinite(aspectRatio) || aspectRatio <= 0) {
            return;
        }
        Log(LOG_I, @"Updating StreamView aspect ratio to %.4f", aspectRatio);
        _streamView.streamAspectRatio = aspectRatio;
        _streamView.pencilHandler.streamAspectRatio = aspectRatio;
    }
}

- (void)setUserInteractionEnabledForStreamView:(bool)enabled{
    _streamView.userInteractionEnabled = enabled;
    for(UIView* view in self.view.subviews){
        if([view isKindOfClass:[OnScreenWidgetView class]]) view.userInteractionEnabled = enabled;
    }
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _streamView;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == _scrollView) {
        [self syncMagnifierStateFromScrollView];
    }
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    if (scrollView == _scrollView) {
        [self updateMagnifierViewportMetrics];
        [self syncMagnifierStateFromScrollView];
    }
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    [super willMoveToParentViewController:parent];
    // Only cleanup when we're being destroyed
    if (parent == nil) {
#if !TARGET_OS_TV
        [_commandOwner cancelPendingCommands];
        [_controlPad releaseAllControls];
        _hostInputReady = NO;
#endif
        [self retireStreamPresentation];
        [_streamView cleanUp];
        _streamView = nil;
        [_controllerSupport cleanup];

        [UIApplication sharedApplication].idleTimerDisabled = NO;
        [_streamMan stopStream];
        if (self.metalViewController) {
            // Explicit shutdown: viewDidDisappear is not guaranteed to fire here
            // (e.g. teardown while backgrounded), and it's what stops the render
            // thread, display link and renderer.
            [self.metalViewController shutdown];
            [self.metalViewController.view removeFromSuperview];
            [self.metalViewController removeFromParentViewController];
            self.metalViewController = nil;
            NSLog(@"Metal renderer stopped and cleaned up.");
        }
        [NativeTouchPointer cleanUpContext];
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        for(UIView* view in self.view.subviews){
            [view removeFromSuperview];
        }
        
    }
}


- (void)updateStatsOverlay {
    if(!_settings.statsOverlayEnabled){
        [_overlayView removeFromSuperview];
        // Invalidate the timer when stats overlay is disabled
        if (_statsUpdateTimer) {
            [_statsUpdateTimer invalidate];
            _statsUpdateTimer = nil;
        }
        return; // add this for realtime streamview reconfig
    }
    
    // Only add the overlay if it's not already in the view hierarchy
    if (_overlayView.superview == nil) {
        [self.view addSubview:_overlayView];
    }

    NSString* overlayText = [self->_streamMan getStatsOverlayText:overlayLevel];
                             
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateOverlayText:overlayText];
    });
}

- (void)setupOverlayView{
    if (_overlayView == nil) {
        _overlayView = [[PaddedLabel alloc] initWithFrame:CGRectZero];
        [_overlayView setTextInsets:UIEdgeInsetsMake(PublicUtils.isIPhone?4:6, 12, PublicUtils.isIPhone?4:6, 12)];
        [_overlayView setUserInteractionEnabled:NO];
        [_overlayView setNumberOfLines:100];
        [_overlayView.layer setCornerRadius:PublicUtils.isIPhone?7:10];
        [_overlayView.layer setMasksToBounds:YES];
        
        // HACK: If not using stats overlay, center the text
        if (_statsUpdateTimer == nil) {
            [_overlayView setTextAlignment:NSTextAlignmentCenter];
        }
        
        [_overlayView setTextColor:[UIColor lightGrayColor]];
        [_overlayView setBackgroundColor:[UIColor blackColor]];
#if TARGET_OS_TV
        [_overlayView setFont:[UIFont systemFontOfSize:24 weight:UIFontWeightMedium]];
#else
        [_overlayView setFont:[UIFont systemFontOfSize: PublicUtils.isIPhone?10:12 weight:UIFontWeightMedium]];
#endif
        [_overlayView setAlpha:(float)[_settings.graphOpacity intValue]/ 100.0];
        [self.view addSubview:_overlayView];
    }
    if (@available(iOS 13.0, *)) {
       if(overlayLevel == 1) _overlayView.font = [UIFont monospacedSystemFontOfSize:PublicUtils.isIPhone?10:12 weight:UIFontWeightMedium];
    }
    
    [_overlayView setHidden:YES];
}

- (void)updateOverlayText:(NSString*)text {
    if (self->_isEndingStream) return;
    if (text != nil) {
        // We set our bounds to the maximum width in order to work around a bug where
        // sizeToFit interacts badly with the UITextView's line breaks, causing the
        // width to get smaller and smaller each time as more line breaks are inserted.
        //sdfdsf;
        if (_overlayView.superview == nil) {
            [self.view addSubview:_overlayView];
        }

        [_overlayView setBounds:CGRectMake(self.view.frame.origin.x,
                                           _overlayView.frame.origin.y,
                                           self.view.frame.size.width,
                                           _overlayView.frame.size.height)];
        [_overlayView setText:text];
        [_overlayView sizeToFit];
        [_overlayView setCenter:CGPointMake(self.view.frame.size.width / 2, (4 + (_overlayView.frame.size.height / 2)))];
        [_overlayView setHidden:NO];
    }
    else {
        [_overlayView setHidden:YES];
    }
}

- (void)updateTransientHUDText:(NSString*)text {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateTransientHUDText:text];
        });
        return;
    }
    if (_isEndingStream) return;

    if (text == nil) {
        _transientHUDView.hidden = YES;
        return;
    }

    if (_transientHUDView == nil) {
        _transientHUDView = [[PaddedLabel alloc] initWithFrame:CGRectZero];
        _transientHUDView.translatesAutoresizingMaskIntoConstraints = NO;
        _transientHUDView.textInsets = UIEdgeInsetsMake(10, 14, 10, 14);
        _transientHUDView.numberOfLines = 0;
        _transientHUDView.textAlignment = NSTextAlignmentLeft;
        _transientHUDView.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.7];
        _transientHUDView.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.5];
        _transientHUDView.font = [UIFont systemFontOfSize:PublicUtils.isIPhone ? 18 : 22
                                                  weight:UIFontWeightSemibold];
        _transientHUDView.layer.cornerRadius = 8;
        _transientHUDView.layer.masksToBounds = YES;
        _transientHUDView.userInteractionEnabled = NO;

        [self.view addSubview:_transientHUDView];
        UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_transientHUDView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:35],
            [_transientHUDView.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:12],
            [_transientHUDView.widthAnchor constraintLessThanOrEqualToAnchor:safeArea.widthAnchor multiplier:0.8]
        ]];
    }

    _transientHUDView.text = text;
    _transientHUDView.hidden = NO;
    [self.view bringSubviewToFront:_transientHUDView];
}

- (void)returnToMainFrame {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self returnToMainFrame];
        });
        return;
    }
    if (_isEndingStream) {
        return;
    }
#if !TARGET_OS_TV
    [_streamControls discardPendingChanges];
    [_commandOwner cancelPendingCommands];
    [_controlPad releaseAllControls];
    _hostInputReady = NO;
    [_streamView setHostInputConnected:NO];
#endif
    [self retireStreamPresentation];

    if (@available(iOS 13.0, *)) {
        // [ControllerNavigator setUINavigationDelegate:[_mainFrameViewcontroller isInAppView] ? _mainFrameViewcontroller : _mainFrameViewcontroller.hostCollectionVC];
        [ControllerNavigator restorePreviousUINavigationDelegateWithIfCurrentDelegateIs:self];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if(ControllerNavigator.radialMenuView) [ControllerNavigator updateRadialMenu];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [ControllerNavigator restoreUINavigationHighlight];
            // ControllerNavigator.radialMenuButtonPressed = false;
            if(ControllerNavigator.streamingRadialMenuButton == ControllerElementSpecial)  [GamepadNavigationIllustrationHud updateHudWithForceDisplay:true];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [ControllerNavigator restoreUINavigationHighlight];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [ControllerNavigator restoreUINavigationHighlight];
        });
    }
    
    [_streamView saveStreamingGameProfileChanges];
    [_streamView clearOnScreenWidgets];
    PencilHandler.shared = nil;
    
    // Reset display mode back to default
    [self updatePreferredDisplayMode:NO];
    
    if (_settings.enablePIP) {
        [self cleanupPiPController];
    }
    
    [self.navigationController popToRootViewControllerAnimated:NO];
    
    
    self.mainFrameViewcontroller.settingsExpandedInStreamView = false; // reset this flag to false
        
    [ControllerUtil disableSysGestures: ControllerUtil.primaryGCController];
}

- (UIView *)activeStreamRenderView {
    // The Metal backend renders into its controller's view; the AVSB container
    // remains present for the decoder but does not contain the Metal image.
    return self.metalViewController ? self.metalViewController.view : _streamVideoRenderView;
}

- (void)externalDisplayChanged:(NSNotification *)notification {
    [self reloadAirPlayConfig];
}

- (void)externalDisplayPreferenceChanged:(NSNotification *)notification {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self externalDisplayPreferenceChanged:notification]; });
        return;
    }
    NSNumber *mode = notification.userInfo[@"externalDisplayMode"];
    if ([mode isKindOfClass:NSNumber.class] && mode.integerValue >= 0 && mode.integerValue <= 2) {
        _settings.externalDisplayMode = mode;
        [self reloadAirPlayConfig];
    }
}

- (void)restoreStreamRenderViewToDevice:(UIView *)renderView {
    UIView *deviceContainer = self.metalViewController ? self.view : _streamView;
    if (renderView.superview != deviceContainer) {
        [deviceContainer insertSubview:renderView atIndex:0];
    }
    renderView.frame = deviceContainer.bounds;
    renderView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    if (self.metalViewController) {
        // Preserve the existing local order: stream input surface, video, then
        // the controls and HUD attached to the frame controller.
        UIView *streamContainerView = [self streamContentContainerView];
        if (streamContainerView.superview == self.view) {
            [self.view sendSubviewToBack:streamContainerView];
        }
    }
}

- (void)retireStreamPresentation {
    [self stopMicrophoneCapture];
    _isEndingStream = YES;
    [_statsUpdateTimer invalidate];
    _statsUpdateTimer = nil;
    [_inactivityTimer invalidate];
    _inactivityTimer = nil;
    [safeTimer clean];
    safeTimer = nil;
    if (_delayedRemoveExtScreen) {
        dispatch_block_cancel(_delayedRemoveExtScreen);
        _delayedRemoveExtScreen = nil;
    }
    _externalDisplayRoutingReady = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:@"SunlightExternalDisplayChanged"
                                                  object:nil];
    if (_externalDisplayRenderViewRequest) {
        UIView *retiringView = _externalDisplayRenderViewRequest;
        _externalDisplayRenderViewRequest = nil;
        if (@available(iOS 13.0, *)) {
            [SceneDelegate clearExternalDisplayRenderView:retiringView];
        }
    }
}

- (bool)shallDisableGyroHotSwitch{
    return _controllerSupport.shallDisableGyroHotSwitch;
}

- (BOOL) isAirPlaying{
    if (@available(iOS 13.0, *)) {
        UIView *renderView = [self activeStreamRenderView];
        return renderView && [SceneDelegate isExternalDisplayRenderView:renderView];
    }
    return NO;
}

- (BOOL) isAirPlayEnabled{
    return _settings.externalDisplayMode.intValue == 1;
}

- (void) reloadAirPlayConfig{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadAirPlayConfig];
        });
        return;
    }
    if (!_externalDisplayRoutingReady || _isEndingStream || _isUpdatingExternalDisplayRouting) {
        return;
    }

    UIView *renderView = [self activeStreamRenderView];
    if (!renderView || !_streamView || !self.view.window) {
        return;
    }

    _isUpdatingExternalDisplayRouting = YES;
    if (@available(iOS 13.0, *)) {
        if ([self isAirPlayEnabled]) {
            _externalDisplayRenderViewRequest = renderView;
            // The coordinator keeps this request pending until a scene exists.
            // It alone moves the view off the device after the window is ready.
            [SceneDelegate setExternalDisplayRenderView:renderView];
        } else if (_externalDisplayRenderViewRequest) {
            UIView *retiringView = _externalDisplayRenderViewRequest;
            _externalDisplayRenderViewRequest = nil;
            [SceneDelegate clearExternalDisplayRenderView:retiringView];
        }
    }

    BOOL isExternal = [self isAirPlaying];
#if !TARGET_OS_TV
    // Entering SBS changes only mono presentation. Leaving SBS also schedules
    // a 2D transport reconnect below, once the new normal output is confirmed.
    self.metalViewController.stereoOutputEnabled = isExternal &&
        [ExternalDisplayCoordinator sharedCoordinator].displayMode == SunlightExternalDisplayMode3D;
#endif
    if (!isExternal) {
        [self restoreStreamRenderViewToDevice:renderView];
    }
    [renderView setNeedsLayout];
    [renderView layoutIfNeeded];

    BOOL renderTargetChanged = _lastRoutedRenderView != renderView ||
        _lastRenderWindow != renderView.window ||
        !CGRectEqualToRect(_lastRenderBounds, renderView.bounds) ||
        _lastRenderWasExternal != isExternal;
    _lastRoutedRenderView = renderView;
    _lastRenderWindow = renderView.window;
    _lastRenderBounds = renderView.bounds;
    _lastRenderWasExternal = isExternal;
    _isUpdatingExternalDisplayRouting = NO;
    [self updateStreamControls];
#if !TARGET_OS_TV
    [self reconcileGlassesStreamMode];
#endif

    if (renderTargetChanged && !self.metalViewController) {
        // AVSB reinitialization resets decoder state, so only request it when
        // the actual target changes, after the new window and bounds are set.
        // Metal updates its drawable through its own view layout callbacks.
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ScreenChanged" object:self];
    }
}

- (void) handleViewResize{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleViewResize];
        });
        return;
    }
    if (_isEndingStream) {
        return;
    }
    viewIsBeingResized = true;
    
    _streamView.bounds = _deviceWindow.bounds;
    _streamView.frame = _deviceWindow.frame;
    
    [self reloadAirPlayConfig];
}


// This will fire if the user opens control center or gets a low battery message
- (void)applicationWillResignActive:(NSNotification *)notification {
    //[self.pipController startPictureInPicture];
    //sleep(1);
    if(_settings.framePacingMode.intValue == FramePacingModeQueue) appDidEnterBackgroundWithoutPip = true;
    
    NSLog(@"applicationWillResignActive %f", CACurrentMediaTime());
    [_streamView saveStreamingGameProfileChanges];

#if !TARGET_OS_TV
#endif
}

- (void)inactiveTimerExpired:(NSTimer*)timer {
    Log(LOG_I, @"Terminating stream after inactivity");

    [self returnToMainFrame];
    
    _inactivityTimer = nil;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    if(!PublicUtils.isIPhone){
        for(OnScreenWidgetView* widget in OnScreenWidgetView.mapping.allValues){
            if(widget.parentSequence != -1 && !widget.autoDockEnabled) continue;
            if(widget.autoDockEnabled){
                widget.autoDockIdleDuration = fmax(widget.autoDockIdleDuration, 3.0);
                [widget autoDockStopCountdown];
            }
            dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC));
            dispatch_after(delayTime, dispatch_get_main_queue(), ^{
                if(widget.autoDockEnabled){
                    OnScreenWidgetView.autoDockRestoreInitByViewResize = true;
                    [widget restoreFromAutoDockWithAnimated:true];
                }
            });
        }
    }
    
    appDidEnterBackgroundWithoutPip = false;
    [self->_streamMan.videoRenderer setDecodingPausedForBackground:NO];
    [_streamMan setNeedRequeuing:true];
    // dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC));
    // dispatch_after(delay, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [Connection resetSysAudioPlayback];
    // });
    
    // Stop the background timer, since we're foregrounded again
    if (_inactivityTimer != nil) {
        Log(LOG_I, @"Stopping inactivity timer after becoming active again");
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }

    // Check if we were in PiP
    if (self.pipController && self.pipController.isPictureInPictureActive) {
        [self.pipController stopPictureInPicture];
    }
    
    if ([_settings.renderingBackend intValue] == RENDER_METAL && self.metalViewController) {
        Log(LOG_I, @"Resuming Metal renderer on foreground");
        [self.metalViewController resumeRendering];
    }
    
    if (self.imguiView && self.imguiView.mtkView && _settings.enableGraphs) {
        self.imguiView.mtkView.enableSetNeedsDisplay = YES;
        self.imguiView.mtkView.paused = NO;
        Log(LOG_I, @"Resuming ImGui renderer on foreground");
    }
    
    [self->_streamMan.videoRenderer resetFramePacing];
    _isRestoringFromPiP = NO;
}

// This fires when the home button is pressed
- (void)applicationDidEnterBackground:(UIApplication *)application {
    NSLog(@"did enter background, %d, %@, %d", _settings.enablePIP, self.pipController, self.pipController.isPictureInPictureActive);
    if (_settings.enablePIP && self.pipController && self.pipController.isPictureInPictureActive) {
        //Log(LOG_I, @"PIP is active, not terminating stream");
        appDidEnterBackgroundWithoutPip = false;
    } else {
        appDidEnterBackgroundWithoutPip = true;

        if ([_settings.renderingBackend intValue] == RENDER_METAL && self.metalViewController) {
            Log(LOG_I, @"Pausing Metal renderer on background");
            [self.metalViewController pauseRendering];
        }
        
        if (self.imguiView && self.imguiView.mtkView) {
            self.imguiView.mtkView.paused = YES;
            self.imguiView.mtkView.enableSetNeedsDisplay = NO;
            Log(LOG_I, @"Pausing ImGui renderer on background");
        }
    }

    [self->_streamMan.videoRenderer setDecodingPausedForBackground:appDidEnterBackgroundWithoutPip];
    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }

    // Terminate the stream if the app is inactive for ...
    Log(LOG_I, @"Starting inactivity termination timer with %d min", _settings.backgroundSessionTimer.intValue);
    _inactivityTimer = [NSTimer scheduledTimerWithTimeInterval:60*(double)_settings.backgroundSessionTimer.intValue
                                  target:self
                                selector:@selector(inactiveTimerExpired:)
                                userInfo:nil
                                 repeats:NO];

#if !TARGET_OS_TV

#endif
}

- (void)expandSettingsView{
    [self openStreamControls];
}

- (void)edgeSwiped{
    /*
    if([self->_mainFrameViewcontroller isIPhonePortrait]){ // disable backmenu for iphone portrait mode;
        [self returnToMainFrame]; //directly quit the session
        return;
    } */
    [self expandSettingsView];  // expand settings view in other cases;
}

- (void)disconnectRemoteSession {
    Log(LOG_I, @"Settings view disconnect the session in stream view");
    [self returnToMainFrame];
}

- (void)disconnectAndQuitApp {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self disconnectAndQuitApp]; });
        return;
    }
    if (_isEndingStream) return;
    [self.mainFrameViewcontroller disconnectAndQuitStreamFromController:self];
}

- (void) connectionStarted {
    Log(LOG_I, @"Connection started");
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_isEndingStream) return;
#if !TARGET_OS_TV
        self->_hostInputReady = YES;
        [self->_streamView setHostInputConnected:YES];
        [self updateStreamControls];
#endif
        // Leave the spinner spinning until it's obscured by
        // the first frame of video.
        self->_stageLabel.hidden = YES;
        self->_tipLabel.hidden = YES;
        self->_spinner.hidden = YES;
        
        // Ensure correct view hierarchy before showing OSC
        if (self.metalViewController && self.metalViewController.view.superview == self.view) {
            [self.view sendSubviewToBack:self.metalViewController.view];
        }
        // For AVSB renderer, ensure streamView is at the back so OSC layers show
        UIView *streamContainerView = [self streamContentContainerView];
        if (streamContainerView && streamContainerView.superview) {
            [self.view sendSubviewToBack:streamContainerView];
        }
        
        // [self->_streamView showOnScreenControls];
        
        [self->_controllerSupport connectionEstablished];
        
        if (self->_settings.statsOverlayEnabled) {
            self->_statsUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                                                       target:self
                                                                     selector:@selector(updateStatsOverlay)
                                                                     userInfo:nil
                                                                      repeats:YES];
        }
#if !TARGET_OS_TV
        // Catch a hardware change that arrived while the host was connecting.
        [self reconcileGlassesStreamMode];
#endif
    });
}

- (void)connectionTerminated:(int)errorCode {
    [self stopMicrophoneCapture];
    Log(LOG_I, @"Connection terminated: %d", errorCode);
    
    unsigned int portFlags = LiGetPortFlagsFromTerminationErrorCode(errorCode);
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portFlags);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        if (self->_isEndingStream) return;
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        NSString* title;
        NSString* message;
        
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            title = [LocalizationHelper localizedStringForKey:@"Connection Error"];
            message = @"Your device's session connection is being blocked. Streaming may not work while connected to this network.";
        }
        else {
            switch (errorCode) {
                case ML_ERROR_GRACEFUL_TERMINATION:
                    [self returnToMainFrame];
                    return;
                    
                case ML_ERROR_NO_VIDEO_TRAFFIC:
                    title = [LocalizationHelper localizedStringForKey:@"Connection Error"];
                    message = [LocalizationHelper localizedStringForKey:@"No video received from host."];
                    if (portFlags != 0) {
                        char failingPorts[256];
                        LiStringifyPortFlags(portFlags, "\n", failingPorts, sizeof(failingPorts));
                        message = [message stringByAppendingString:[LocalizationHelper localizedStringForKey:@"ConnectionFailedFirewall", failingPorts]];
                    }
                    break;
                    
                case ML_ERROR_NO_VIDEO_FRAME:
                    title = [LocalizationHelper localizedStringForKey:@"Connection Error"];
                    message = [LocalizationHelper localizedStringForKey: @"Your network connection isn't performing well. Reduce your video bitrate setting or try a faster connection."];
                    break;
                    
                case ML_ERROR_UNEXPECTED_EARLY_TERMINATION:
                case ML_ERROR_PROTECTED_CONTENT:
                    title = [LocalizationHelper localizedStringForKey:@"Connection Error"];
                    message = @"Something went wrong on your host PC when starting the stream.\n\nMake sure you don't have any DRM-protected content open on your host PC. You can also try restarting your host PC.\n\nIf the issue persists, try reinstalling your GPU drivers and GeForce Experience.";
                    break;
                    
                case ML_ERROR_FRAME_CONVERSION:
                    title = [LocalizationHelper localizedStringForKey:@"Connection Error"];
                    message = @"The host PC reported a fatal video encoding error.\n\nTry disabling HDR mode, changing the streaming resolution, or changing your host PC's display resolution.";
                    break;
                    
                default:
                {
                    NSString* errorString;
                    NSString* errorHint;
                    if (errorCode > 1000 || errorCode < -1000) {
                        // We'll assume large errors are hex values
                        errorString = [NSString stringWithFormat:@"%08X", (uint32_t)errorCode];
                    }
                    else {
                        // Smaller values will just be printed as decimal (probably errno.h values)
                        errorString = [NSString stringWithFormat:@"%d", errorCode];
                    }
                    errorHint = VLTerminationHintForErrorCode(errorCode);
                    
                    title = [LocalizationHelper localizedStringForKey: @"Connection Terminated"];
                    message = [LocalizationHelper localizedStringForKey: @"The connection was terminated, Error code: %@", errorString];
                    if (errorHint != nil) {
                        message = [message stringByAppendingFormat:@"\n\n%@", errorHint];
                    }
                    break;
                }
            }
        }
        
        UIAlertController* conTermAlert = [UIAlertController alertControllerWithTitle:title
                                                                              message:message
                                                                       preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:conTermAlert];
        [conTermAlert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:conTermAlert animated:YES completion:nil];
    });

    [_streamMan stopStream];
}

- (void) stageStarting:(const char*)stageName {
    Log(LOG_I, @"Starting %s", stageName ?: "unknown stage");
}

// Retire the producer before stopping C or publishing a successor. This may be
// called from a C callback thread; the lock also invalidates a queued main start.
- (void)stopMicrophoneCapture {
#if !TARGET_OS_TV
    MicHandler *retiring;
    @synchronized (self) {
        _microphoneCaptureStopped = YES;
        _microphoneGeneration++;
        _micStreamInitialized = NO;
        retiring = micHandler;
        micHandler = nil;
    }
    [retiring clean];
#endif
}

- (void) stageComplete:(const char*)stageName {
#if !TARGET_OS_TV
    if (stageName == NULL) return;
    if (strcmp(stageName, LiGetStageName(STAGE_MIC_STREAM_UNSUPPORTED_OR_UNINITIALIZED)) == 0) {
        [self stopMicrophoneCapture];
        return;
    }
    if (strcmp(stageName, LiGetStageName(STAGE_MIC_STREAM_START)) == 0) {
        Connection *owner = [ConnectionLifecycle activeContext];
        if (![owner isKindOfClass:Connection.class]) return;
        NSUInteger generation;
        @synchronized (self) {
            if (_microphoneCaptureStopped || !_streamConfig.redirectMic) return;
            generation = ++_microphoneGeneration;
        }
        // Audio-session setup stays on main. Keeping the existing startup delay
        // must not permit capture after an early disconnect or failed launch.
        __weak StreamFrameViewController *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            StreamFrameViewController *self = weakSelf;
            if (self == nil) return;
            @synchronized (self) {
                if (self->_microphoneCaptureStopped || self->_isEndingStream ||
                    generation != self->_microphoneGeneration || !self->_streamConfig.redirectMic ||
                    ![MicHandler permissionGranted]) return;
                __block BOOL currentOwner = NO;
                [owner performMicrophoneInput:^{ currentOwner = YES; }];
                if (!currentOwner) return;
                [self->micHandler clean];
                self->micHandler = [[MicHandler alloc] initWithUseBuiltinMic:self->_settings.useBuiltinMic
                    sendPacket:^(NSData *packet) {
                        [owner performMicrophoneInput:^{
                            sendMicrophoneOpusData(packet.bytes, (int)packet.length);
                        }];
                    }];
                self->_micStreamInitialized = YES;
                [MicHandler setVolume:self->_settings.micVolume.floatValue];
                [self->micHandler startTapping];
            }
        });
    }
#endif

}

- (void) stageFailed:(const char*)stageName withError:(int)errorCode portTestFlags:(int)portTestFlags {
    [self stopMicrophoneCapture];
    Log(LOG_I, @"Stage %s failed: %d", stageName, errorCode);
    
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portTestFlags);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_isEndingStream) return;
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        NSString* message = [NSString stringWithFormat:@"%s failed with error %d", stageName, errorCode];
        if (portTestFlags != 0) {
            char failingPorts[256];
            LiStringifyPortFlags(portTestFlags, "\n", failingPorts, sizeof(failingPorts));
            message = [message stringByAppendingString:[LocalizationHelper localizedStringForKey:@"ConnectionFailedFirewall", failingPorts]];
        }
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            message = [message stringByAppendingString:[LocalizationHelper localizedStringForKey:@"!ML_TEST_RESULT_INCONCLUSIVE"]];
        }
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:[LocalizationHelper localizedStringForKey:@"Connection Failed"]
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
    
    [_streamMan stopStream];
}

- (void) launchFailed:(NSString*)message {
    Log(LOG_I, @"Launch failed: %@", message);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_isEndingStream) return;
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:[LocalizationHelper localizedStringForKey:@"Connection Error"]
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:[LocalizationHelper localizedStringForKey:@"Ok"] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_isEndingStream) return;
        [self->_controllerSupport rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
    });
}

- (void) rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_isEndingStream) return;
        [self->_controllerSupport rumbleTriggers:controllerNumber leftTrigger:leftTrigger rightTrigger:rightTrigger];
    });
}

- (void) setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_isEndingStream) return;
        [self->_controllerSupport setMotionEventState:controllerNumber motionType:motionType reportRateHz:reportRateHz];
    });
}

- (void) setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_isEndingStream) return;
        [self->_controllerSupport setControllerLed:controllerNumber r:r g:g b:b];
    });
}

- (void) setAdaptiveTriggers:(uint16_t)controllerNumber eventFlags:(uint8_t)eventFlags
                     typeLeft:(uint8_t)typeLeft typeRight:(uint8_t)typeRight
                         left:(const uint8_t*)left right:(const uint8_t*)right {
    if (!left || !right) return;
    NSData *leftEffect = [NSData dataWithBytes:left length:DS_EFFECT_PAYLOAD_SIZE];
    NSData *rightEffect = [NSData dataWithBytes:right length:DS_EFFECT_PAYLOAD_SIZE];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_isEndingStream) return;
        [self->_controllerSupport setAdaptiveTriggers:controllerNumber eventFlags:eventFlags
            typeLeft:typeLeft typeRight:typeRight left:leftEffect.bytes right:rightEffect.bytes];
    });
}

- (void)connectionStatusUpdate:(int)status {
    Log(LOG_W, @"Connection status update: %d", status);

    dispatch_async(dispatch_get_main_queue(), ^{
        // UI state belongs to main; an old status must not revive a retired HUD.
        if (self->_isEndingStream || self->_statsUpdateTimer != nil) return;
        switch (status) {
            case CONN_STATUS_OKAY:
                [self updateOverlayText:nil];
                break;
                
            case CONN_STATUS_POOR:
                if (self->_streamConfig.bitRate > 5000) {
                    [self updateOverlayText:[LocalizationHelper localizedStringForKey:@"Slow connection to PC, Reduce your bitrate"]];
                }
                else {
                    [self updateOverlayText:[LocalizationHelper localizedStringForKey:@"Poor connection to PC"]];
                }
                break;
        }
    });
}

- (void) updatePreferredDisplayMode:(BOOL)streamActive {
#if TARGET_OS_TV
    if (@available(tvOS 11.2, *)) {
        UIWindow* window = [[[UIApplication sharedApplication] delegate] window];
        AVDisplayManager* displayManager = [window avDisplayManager];
        
        // This logic comes from Kodi and MrMC
        if (streamActive) {
            int dynamicRange;
            
            if (LiGetCurrentHostDisplayHdrMode()) {
                dynamicRange = 2; // HDR10
            }
            else {
                dynamicRange = 0; // SDR
            }
            
            AVDisplayCriteria* displayCriteria = [[AVDisplayCriteria alloc] initWithRefreshRate:[_settings.framerate floatValue]
                                                                              videoDynamicRange:dynamicRange];
            displayManager.preferredDisplayCriteria = displayCriteria;
        }
        else {
            // Switch back to the default display mode
            displayManager.preferredDisplayCriteria = nil;
        }
    }
#endif
}

- (void) setHdrMode:(bool)enabled {
    Log(LOG_I, @"HDR is now: %s", enabled ? "active" : "inactive");
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_isEndingStream) return;
        [self updatePreferredDisplayMode:YES];
    });
}

- (void) videoContentShown {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_isEndingStream) return;
        [self->_spinner stopAnimating];
        [self.view setBackgroundColor:[UIColor blackColor]];

        if (@available(iOS 15.0, *)) {
            if (self->_settings.enablePIP) {
                if (self->_streamMan && self->_streamMan.videoRenderer) {
                    Log(LOG_I, @"Setting up PiP with renderer: %p", self->_streamMan.videoRenderer);
                    [self setupPiPControllerWithRenderer:self->_streamMan.videoRenderer];
                } else {
                    Log(LOG_I, @"No renderer available for PiP setup");
                }
            }
        }
    });
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)gamepadPresenceChanged {
    if(PublicUtils.iOS26Available) return;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)keyboardConnected {
    [GenericUtils handleKeyboardOrMouseConnectionTipIn:self];
}

- (void)mouseConnected {
    [GenericUtils handleKeyboardOrMouseConnectionTipIn:self];
}

- (void)mousePresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 14.0, *)) {
        [self setNeedsUpdateOfPrefersPointerLocked];
    }
#endif
}

- (void) streamExitRequested {
    Log(LOG_I, @"Gamepad combo requested stream exit");
    
    [self returnToMainFrame];
}

- (void)userInteractionBegan {
    // Disable hiding home bar when user is interacting.
    // iOS will force it to be shown anyway, but it will
    // also discard our edges deferring system gestures unless
    // we willingly give up home bar hiding preference.
    _userIsInteracting = YES;
    if(PublicUtils.iOS26Available) return;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)userInteractionEnded {
    // Enable home bar hiding again if conditions allow
    _userIsInteracting = NO;
    if(PublicUtils.iOS26Available) return;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)toggleStatsOverlay{
    _settings.statsOverlayEnabled = !_settings.statsOverlayEnabled;
#if !TARGET_OS_TV
    SunlightMachineControlsSettings *controls = [[self resolvedMachineControls] copy];
    controls.statsOverlayLevel = _settings.statsOverlayEnabled ? MIN(2, MAX(1, overlayLevel)) : 0;
    [controls saveForHostUUID:self.streamConfig.hostUUID defaults:NSUserDefaults.standardUserDefaults globalDefaults:[self globalMachineControls]];
    self.streamConfig.machineControls = controls;
    _settings.statsOverlayLevel = @(controls.statsOverlayLevel);
    // Keep the last visible detail level so the keyboard toggle restores it.
    if (controls.statsOverlayEnabled) overlayLevel = (int)controls.statsOverlayLevel;
#endif
    
    // Reconfigure the UI using the current in-memory settings, without reloading from disk
    if (_statsUpdateTimer) { [_statsUpdateTimer invalidate]; _statsUpdateTimer = nil; }
    [self setupOverlayView];
    if (_settings.statsOverlayEnabled) {
        _statsUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateStatsOverlay) userInfo:nil repeats:YES];
        [self updateStatsOverlay];
    } else [_overlayView removeFromSuperview];
    [self updateStreamControls];
}

- (void)toggleMouseCapture{
    DataManager* dataMan = [[DataManager alloc] init];
    Settings *currentSettings = [dataMan retrieveSettings];
    if(currentSettings.localMousePointerMode.intValue == 0){
        currentSettings.localMousePointerMode = @1;
    }else{
        currentSettings.localMousePointerMode = @0;
    }
    
    
    [dataMan saveData];
    [self reConfigStreamViewRealtime];
}

- (void)toggleMouseVisible{
    DataManager* dataMan = [[DataManager alloc] init];
    Settings *currentSettings = [dataMan retrieveSettings];
    
    if(currentSettings.localMousePointerMode.intValue == 2){
        currentSettings.localMousePointerMode = @1;
    }else{
        currentSettings.localMousePointerMode = @2;
    }
    
    [dataMan saveData];
    [self reConfigStreamViewRealtime];
}

/*
- (NSMutableDictionary *)startGyroUpdate:(OnScreenWidgetView *)sender yawFactor:(CGFloat)yawFactor pitchFactor:(CGFloat)pitchFactor rollFactor:(CGFloat)rollFactor{
    NSMutableDictionary* gyroControlPreviousStatus = [NSMutableDictionary dictionary];

    if(!_motionHandler.motionControlStarted) [gyroControlPreviousStatus setObject:sender forKey:@"gyroControlStarter"];
    [gyroControlPreviousStatus setObject:@(_motionHandler.widgetYawFactor) forKey:@"previousYawFactor"];
    [gyroControlPreviousStatus setObject:@(_motionHandler.widgetPitchFactor) forKey:@"previousPitchFactor"];
    [gyroControlPreviousStatus setObject:@(_motionHandler.widgetRollFactor) forKey:@"previousRollFactor"];
    _motionHandler.widgetYawFactor = yawFactor;
    _motionHandler.widgetPitchFactor = pitchFactor;
    _motionHandler.widgetRollFactor = rollFactor;
    [_motionHandler startMotionUpdate];

    return gyroControlPreviousStatus;
}


- (NSMutableDictionary*)start:(CGFloat)yawFactor pitchFactor:(CGFloat)pitchFactor rollFactor:(CGFloat)rollFactor{
    NSMutableDictionary* gyroControlPreviousStatus = [NSMutableDictionary dictionary];
    if(!_motionHandler.motionControlStarted){
        [gyroControlPreviousStatus setObject:@(_motionHandler.motionControlStarted) forKey:@"gyroStarted"];
    }
    [gyroControlPreviousStatus setObject:@(_motionHandler.widgetYawFactor) forKey:@"previousYawFactor"];
    [gyroControlPreviousStatus setObject:@(_motionHandler.widgetPitchFactor) forKey:@"previousPitchFactor"];
    [gyroControlPreviousStatus setObject:@(_motionHandler.widgetRollFactor) forKey:@"previousRollFactor"];

    _motionHandler.widgetYawFactor = yawFactor;
    _motionHandler.widgetPitchFactor = pitchFactor;
    _motionHandler.widgetRollFactor = rollFactor;
    [_motionHandler startMotionUpdate];
    
    return gyroControlPreviousStatus;
}
*/

- (void)startAccelUpdate{
    [_motionHandler startAccelUpdate];
}

- (void)stopGyroUpdateWithInterruptNoneGyroInput:(BOOL)interruption{
    [_motionHandler stopMotionUpdateWithInterruptNoneGyroInput:interruption];
}

- (void)stopAccelUpdate{
    [_motionHandler stopAccelUpdate];
}

- (void)enablePencilHover{
    [_streamView enablePencilHover];
}

- (void)disablePencilHover{
    [_streamView disablePencilHover];
}

- (void)handleDisableSingleTouchButtonUp {
    [_streamView setAllowSingleTouchEnabled:!_singleTouchDisabled];
}

- (void)replaceBrushWithShortcut:(NSString *)shortcut{
    if(PencilHandler.shared){
        [PencilHandler.shared replaceBrushWith:shortcut];
    }
}

- (void)replaceEraserWithShortcut:(NSString *)shortcut{
    if(PencilHandler.shared){
        [PencilHandler.shared replaceEraserWith:shortcut];
    }
}

- (void)handleTouchDisableButtonUp {
    [_streamView toggleTouchDisabled:self.touchDisabled];
#if !TARGET_OS_TV
    SunlightMachineControlsSettings *controls = [[self resolvedMachineControls] copy];
    controls.touchEnabled = !self.touchDisabled;
    [controls saveForHostUUID:self.streamConfig.hostUUID defaults:NSUserDefaults.standardUserDefaults globalDefaults:[self globalMachineControls]];
    self.streamConfig.machineControls = controls;
    [self updateStreamControls];
#endif
}

- (void)presentPressureCurveVC{
    if(_oscProfile.pressureCurveEnabled){
        PressureCurveViewController* pressureCurveVC = [[PressureCurveViewController alloc] init];
        pressureCurveVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
        [self presentViewController:pressureCurveVC animated:YES completion:nil];
    }
    else{
        AlertControllerUtil.autoCompletion = true;
        [AlertControllerUtil showAlertIn:self
                                        title:@""
                                      message:[LocalizationHelper localizedStringForKey:@"Please enable pressure curve in settings menu"]
                                   withCancel:NO
                                  buttonTitle:@""
                                    countdown:2
                                       action:^{}
                                   completion:^{}];
    }
}

#if !TARGET_OS_TV
// Require a confirmation when streaming to activate a system gesture
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
    return UIRectEdgeAll;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    if(OnScreenWidgetView.deferScreenEdgeSysGesturesDueToOnScreenWidgets) return NO;
    if ( [_controllerSupport getConnectedGamepadCount] > 0 &&
        _userIsInteracting == NO) {
        // Autohide the home bar when a gamepad is connected
        // and the on-screen controls are disabled. We can't
        // do this all the time because any touch on the display
        // will cause the home indicator to reappear, and our
        // preferredScreenEdgesDeferringSystemGestures will also
        // be suppressed (leading to possible errant exits of the
        // stream).
        return YES;
    }
    
    return NO;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (BOOL)prefersPointerLocked {
    // Pointer lock breaks the UIKit mouse APIs, which is a problem because
    // GCMouse is horribly broken on iOS 14.0 for certain mice. Only lock
    // the cursor if there is a GCMouse present.
    return ([GCMouse mice].count > 0) && [_settings localMousePointerMode].intValue == 0;
}
#endif

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    [self resetMagnifierStreamViewWithAnimated:false];
    
    // handle view size change for on-screen widgets
    CGSize oldSize = self.view.bounds.size;
    CGFloat scaleX = size.width  / oldSize.width;
    CGFloat scaleY = size.height / oldSize.height;
    for(OnScreenWidgetView* widget in OnScreenWidgetView.mapping.allValues){
        CGPoint oldCenter = widget.center;
        CGPoint oldStoredCenter = widget.storedCenter;
        
        if(widget.autoDockEnabled){
            widget.autoDockIdleDuration = fmax(widget.autoDockIdleDuration, 2.0);
            [widget autoDockStopCountdown];
        }
        dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC));
        dispatch_after(delayTime, dispatch_get_main_queue(), ^{
            if(widget.autoDockEnabled){
                OnScreenWidgetView.autoDockRestoreInitByViewResize = true;
                [widget restoreFromAutoDockWithAnimated:true];
            }
        });
        
        [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
            widget.center = CGPointMake(oldCenter.x * scaleX,oldCenter.y * scaleY);
            widget.storedCenter = CGPointMake(oldStoredCenter.x * scaleX,oldStoredCenter.y * scaleY);
        } completion:nil];
    }

    
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC));
    dispatch_after(delay, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self->_streamMan setNeedRequeuing:true];
    });

    /*
    if (_isRestoringFromPiP) {
        Log(LOG_I, @"View size changed during PiP restore, skipping redundant reconfiguration.");
        return;
    } */

    // Log(LOG_I, @"View size changed, terminating stream");

    double delayInSeconds = 0.2;
    if (_delayedRemoveExtScreen) {
        dispatch_block_cancel(_delayedRemoveExtScreen);
    }
        
    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        typeof(self) self = weakSelf;
        if (!self || self->_isEndingStream) return;
        self->_delayedRemoveExtScreen = nil;
        [self handleViewResize];
        [self reConfigStreamViewRealtimeAndReloadSettings:YES reloadOnscreenWidgets:NO];
    });
    _delayedRemoveExtScreen = block;
    dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(delayTime, dispatch_get_main_queue(), block);
}

- (void)controllerArrivalWithPlayerIndex:(int8_t)index{
    if(index == 0 && _oscProfile.gamepadOverlayEnabled){
        if (@available(iOS 13.0, *)) {
            [self loadAbstractGamepadOverlayIfNeeded];
        }
    }
}

- (void)toggleGamepadOverlayWithOverlayEnabled:(BOOL)overlayEnabled API_AVAILABLE(ios(13.0)){
    OnScreenWidgetView.gamepadOverlayFLag = overlayEnabled;
    OnScreenWidgetView.profileChangedDuringStreaming = true;

    if(overlayEnabled) [self loadAbstractGamepadOverlayIfNeeded];
    else {
        [_virtualGamepadOverlay removeFromSuperview];
        _virtualGamepadOverlay = nil;
    }
}

- (void)loadAbstractGamepadOverlayIfNeeded API_AVAILABLE(ios(13.0)){
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        
        if (self->_virtualGamepadOverlay != nil || self.view.window == nil) {
            return;
        }
        
        BOOL usesXboxFaceButtons = self->_settings.emulatedControllerType.intValue == LI_CTYPE_XBOX;
        
        // CGFloat maxWidth = MIN(CGRectGetWidth(self.view.bounds) * 0.72, 620);
        // CGFloat standardWidth = MAX(420, maxWidth);
        
        CGFloat standardWidth = PublicUtils.isIPhone ? 165 : 200;
        
        CGFloat standardhHeight = standardWidth / 1.82;
        CGRect overlayFrame = CGRectMake(0, 0, standardWidth, standardhHeight);
        
        AbstractGamepadOverlayView *overlayView = [[AbstractGamepadOverlayView alloc] initWithFrame:overlayFrame usesPlayStationFaceButtons:!usesXboxFaceButtons];
        overlayView.closeButtonDelegate = self;
        overlayView.center = CGPointMake(self.view.bounds.size.width-standardWidth/2-20, self.view.bounds.size.height-standardhHeight/2-20);
        overlayView.userInteractionEnabled = YES;
        [self.view addSubview:overlayView];
        [overlayView registerUserInteraction];
        [overlayView scheduleCloseButtonHideIfNeeded];
        
        self->_virtualGamepadOverlay = overlayView;
    });
}

- (void)startStreamViewInteractionTimer {
    [_streamView startInteractionTimer];
}

- (void)dealloc {
    if (VLSharedStreamFrameViewController == self) {
        VLSharedStreamFrameViewController = nil;
    }
    NSLog(@"dealloc StreamFrameViewController %f", CACurrentMediaTime());
}

- (void)setupTimer {
    // Retain the input destination, never look up the next active connection.
    // Its existing gate rejects work after disconnect or a local UI transition.
    __weak StreamView *inputView = _streamView;
    safeTimer = [[SafeTimer alloc] initWithInterval:1.0/MAX(1, self.streamConfig.frameRate)
        delay:0 queueLabel:@"streamview.timer" handler:^{
            SunlightDispatchHostInput(inputView, dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
                LiSendKeyboardEvent(0xFF, KEY_ACTION_UP, 0);
            });
        }];
}


@end
