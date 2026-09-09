#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Connection preferences shared by every app/mode on one PC. Input, volume,
// and statistics use SunlightMachineControlsSettings at the same PC scope.
// Instances are detached drafts; this store never writes Core Data.
@interface SunlightSharedSettings : NSObject <NSCopying>
// TemporarySettings: Auto=0, H.264=1, HEVC=2, AV1=3.
@property NSInteger preferredCodec;
// DataManager FramePacingMode: Off=0, Legacy=1, Queue=2, Interpolation=3.
@property NSInteger framePacingMode;
// Settings UI: system stereo=2, alternate stereo=3, 5.1=6, 7.1=8.
@property NSInteger audioConfig;
@property BOOL enableHdr;
@property BOOL fullColorRange;
@property BOOL playAudioOnPC;

// Valid PC fields override a copy of globalDefaults independently. Missing or
// corrupt fields inherit; blank UUID reads globals but cannot save/reset.
+ (instancetype)settingsForHostUUID:(nullable NSString *)hostUUID
                           defaults:(NSUserDefaults *)defaults
                     globalDefaults:(SunlightSharedSettings *)globalDefaults;
// Writes only fields differing from globalDefaults, removing an empty override.
// Returns NO without writing when UUID or the draft's enum values are invalid.
- (BOOL)saveForHostUUID:(nullable NSString *)hostUUID
               defaults:(NSUserDefaults *)defaults
         globalDefaults:(SunlightSharedSettings *)globalDefaults;
+ (BOOL)removeForHostUUID:(nullable NSString *)hostUUID defaults:(NSUserDefaults *)defaults;
- (BOOL)isEqualToSettings:(nullable SunlightSharedSettings *)settings;
@end

NS_ASSUME_NONNULL_END
