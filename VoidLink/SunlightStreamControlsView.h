#import <UIKit/UIKit.h>
#import "StreamConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SunlightStreamControlsAction) {
    SunlightStreamControlsActionDisconnect,
    SunlightStreamControlsActionModeDefaults,
};

typedef NS_ENUM(NSInteger, SunlightStreamControlsTab) {
    SunlightStreamControlsTab2D,
    SunlightStreamControlsTabHost3D,
    SunlightStreamControlsTabClient3D,
    SunlightStreamControlsTabRaw3D,
};

@interface SunlightStreamControlsView : UIView
@property (nonatomic, copy) NSString *appName;
@property (nonatomic) SunlightStreamMode activeMode;
@property (nonatomic, readonly) SunlightStreamControlsTab selectedTab;
// Client 3D is browse-only and retains the last usable mode here.
@property (nonatomic, readonly) SunlightStreamMode selectedMode;
@property (nonatomic) BOOL qualityChangesPending;
@property (nonatomic, getter=isExpanded) BOOL expanded;
@property (nonatomic) BOOL externalOutputActive;
// True only when the stream owner confirms an output suitable for 3D glasses.
// Availability gates choices without changing activeMode or reconnecting.
@property (nonatomic) BOOL glasses3DAvailable;
@property (nonatomic) BOOL touchEnabled;
@property (nonatomic) BOOL connectionReady;
@property (nonatomic) BOOL controlPadEnabled;
@property (nonatomic) BOOL usesSavedTouchProfile;
// Root may constrain the separate gamepad to this guide in overlay coordinates.
@property (nonatomic, readonly) UILayoutGuide *controlPadLayoutGuide;
@property (nonatomic, copy) NSString *inputHint;
@property (nonatomic, copy) NSString *statusText;
// Selected app/PC/mode draft. Setters display saved values without normalizing
// or emitting edits. The owner handles persistence only after explicit Apply.
@property (nonatomic) int qualityWidth;
@property (nonatomic) int qualityHeight;
@property (nonatomic) int qualityFrameRate;
@property (nonatomic) int qualityBitrateKbps;
@property (nonatomic) int qualityMaxFrameRate;
@property (nonatomic) BOOL qualityResolutionLocked;
// Native is a policy, distinct from a fixed tuple with identical dimensions.
// Read this flag in qualityChangedHandler; the owner stages/persists it per mode.
@property (nonatomic) BOOL qualityUsesNativeResolution;
@property (nonatomic, copy, nullable) void (^qualityChangedHandler)(int width, int height, int frameRate, int bitrateKbps);

// The owner applies picture changes or ends the stream. No input or sound
// settings are exposed by this view.
@property (nonatomic, copy, nullable) void (^actionHandler)(SunlightStreamControlsAction action);
@property (nonatomic, copy, nullable) void (^modeApplyHandler)(SunlightStreamMode mode);
@property (nonatomic, copy, nullable) void (^expansionChangedHandler)(BOOL expanded);
@property (nonatomic, copy, nullable) void (^selectionChangedHandler)(void);
@property (nonatomic, copy, nullable) void (^pendingChangesDiscardedHandler)(void);
- (void)discardPendingChanges;
@end

NS_ASSUME_NONNULL_END
