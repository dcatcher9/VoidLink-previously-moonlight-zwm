#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SunlightMachineControlMode) {
    SunlightMachineControlModeTrackpad = 0,
    SunlightMachineControlModeSavedTouchProfile = 1,
    SunlightMachineControlModeGamepad = 2,
};

// Input and local presentation preferences shared by every app on one PC.
// SavedTouchProfile uses the selected profile in the existing device catalog;
// profile contents and selection are not duplicated into this record.
@interface SunlightMachineControlsSettings : NSObject <NSCopying>
@property SunlightMachineControlMode controlMode;
@property BOOL touchEnabled;
@property double localVolume;
// Existing statistics levels: Off=0, Simplified=1, Detailed=2.
@property NSInteger statsOverlayLevel;
@property BOOL statsOverlayEnabled;

// Global input defaults own only mode and touch availability. The caller's
// fallback supplies legacy input, volume and statistics defaults unchanged.
+ (instancetype)globalControlsWithDefaults:(NSUserDefaults *)defaults
                                  fallback:(SunlightMachineControlsSettings *)fallback;
- (BOOL)saveGlobalControlsToDefaults:(NSUserDefaults *)defaults;

+ (instancetype)settingsForHostUUID:(nullable NSString *)hostUUID
                           defaults:(NSUserDefaults *)defaults
                     globalDefaults:(SunlightMachineControlsSettings *)globalDefaults;
- (BOOL)saveForHostUUID:(nullable NSString *)hostUUID
               defaults:(NSUserDefaults *)defaults
         globalDefaults:(SunlightMachineControlsSettings *)globalDefaults;
+ (BOOL)removeForHostUUID:(nullable NSString *)hostUUID defaults:(NSUserDefaults *)defaults;
- (BOOL)isEqualToSettings:(nullable SunlightMachineControlsSettings *)settings;
@end

NS_ASSUME_NONNULL_END
