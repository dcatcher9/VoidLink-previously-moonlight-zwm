#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const SunlightExternalDisplayChangedNotification;

typedef NS_ENUM(NSInteger, SunlightExternalDisplayMode) {
    SunlightExternalDisplayModeUnknown,
    SunlightExternalDisplayMode2D,
    SunlightExternalDisplayMode3D,
};

/// Main-thread owner of presentation routing. Display lifetime is independent of content lifetime.
@interface ExternalDisplayCoordinator : NSObject

+ (instancetype)sharedCoordinator;

@property (nonatomic) BOOL enabled;
@property (nonatomic, readonly, nullable) UIWindow *externalWindow;
@property (nonatomic, readonly, nullable) UIScreen *externalScreen;
@property (nonatomic, readonly, getter=isAvailable) BOOL available;
/// A settled, enabled output only. Missing or mismatched scanout is Unknown.
@property (nonatomic, readonly) SunlightExternalDisplayMode displayMode;
@property (nonatomic, readonly) CGSize outputPixelSize;

/// Calibration is explicitly selected by the user; a wide display alone never starts it.
@property (nonatomic, readonly) BOOL calibrationRequested;
@property (nonatomic, readonly) BOOL calibrationPresented;
@property (nonatomic, readonly) BOOL calibrationOutputCompatible;
@property (nonatomic, readonly) BOOL hasRenderViewRequest;
@property (nonatomic) BOOL calibrationEyesSwapped;

/// May wait for a compatible external display. Returns NO while a PC view owns the source.
- (BOOL)startCalibration;
- (void)stopCalibration;

- (void)registerWindow:(UIWindow *)window;
- (void)unregisterWindow:(UIWindow *)window;
- (void)windowDidUpdate:(UIWindow *)window;

/// Keeps a pending request when no display is ready, leaving the view on the phone.
- (void)setRenderView:(UIView *)view;
/// Releases the request and removes only content still owned by an external host.
- (void)clearRenderView;
/// A retiring stream may release only the request it created.
- (void)clearRenderView:(UIView *)view;
- (BOOL)isPresentingView:(UIView *)view;

@end

NS_ASSUME_NONNULL_END
