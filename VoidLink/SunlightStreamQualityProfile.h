#import <Foundation/Foundation.h>
#import "StreamConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

// A detached, mutable quality draft. Loading never writes defaults; only the
// owning picture panel saves accepted drafts when its Reconnect action is used.
@interface SunlightStreamQualityProfile : NSObject <NSCopying>
@property int width;
@property int height;
@property int frameRate;
@property int bitRate;
// Native dimensions are resolved for the current device before negotiation.
// Older records without this field remain fixed until explicitly migrated.
@property BOOL usesNativeResolution;

// Updates only this detached profile's dimensions; never writes preferences.
// Invalid dimensions (outside 1..16384) or fixed profiles are unchanged.
- (void)resolveNativeWidth:(int)width height:(int)height;
// Cheap read-only marker check, shared with the Core Data startup migration.
+ (BOOL)needsNativeResolutionMigrationInDefaults:(NSUserDefaults *)defaults;
// One-time migration of valid legacy 16:9 presets for 2D and Host 3D across
// global, PC and app scopes. Explicit choices, custom sizes and Raw are retained.
// Invalid native dimensions leave both records and the migration marker intact.
+ (void)migrateLegacyPresetResolutionsToNativeWidth:(int)width
                                           height:(int)height
                                         defaults:(NSUserDefaults *)defaults;

// Missing or invalid records return an isolated copy of fallback. Legacy Raw
// Half shares the canonical Raw profile. Unsupported modes never read/write a key.
+ (instancetype)profileForMode:(SunlightStreamMode)mode
                      defaults:(NSUserDefaults *)defaults
                      fallback:(SunlightStreamQualityProfile *)fallback;
// Returns NO without changing defaults for unsupported modes or invalid values.
// Dimensions 1..16384 (odd sizes allowed), FPS 1..240, bitrate 500..800000 Kbps.
// The bitrate upper bound preserves the existing Settings UI's saved choices.
- (BOOL)isValid;
- (BOOL)saveForMode:(SunlightStreamMode)mode defaults:(NSUserDefaults *)defaults;
// Legacy PC-specific mode profile, then global mode profile, then fallback. UUIDs are
// trimmed/lowercased; missing UUIDs only read global values and cannot save/reset.
+ (instancetype)profileForMode:(SunlightStreamMode)mode
                      hostUUID:(nullable NSString *)hostUUID
                      defaults:(NSUserDefaults *)defaults
                      fallback:(SunlightStreamQualityProfile *)fallback;
- (BOOL)saveForMode:(SunlightStreamMode)mode hostUUID:(nullable NSString *)hostUUID defaults:(NSUserDefaults *)defaults;
+ (BOOL)hasOverrideForMode:(SunlightStreamMode)mode hostUUID:(nullable NSString *)hostUUID defaults:(NSUserDefaults *)defaults;
+ (BOOL)removeForMode:(SunlightStreamMode)mode hostUUID:(nullable NSString *)hostUUID defaults:(NSUserDefaults *)defaults;

// Current picture settings belong to one app on one PC. Precedence is a valid
// app-mode record, legacy PC-mode record, global mode record, then fallback.
// App IDs are trimmed and case-sensitive. Loading never migrates/writes records.
+ (instancetype)profileForMode:(SunlightStreamMode)mode
                      hostUUID:(nullable NSString *)hostUUID
                         appID:(nullable NSString *)appID
                      defaults:(NSUserDefaults *)defaults
                      fallback:(SunlightStreamQualityProfile *)fallback;
- (BOOL)saveForMode:(SunlightStreamMode)mode hostUUID:(nullable NSString *)hostUUID
             appID:(nullable NSString *)appID defaults:(NSUserDefaults *)defaults;
// Only an explicit, valid app-mode tuple is an override; legacy fallback and
// reset markers are not. Restore defaults may still be offered in either case.
+ (BOOL)hasOverrideForMode:(SunlightStreamMode)mode hostUUID:(nullable NSString *)hostUUID
                    appID:(nullable NSString *)appID defaults:(NSUserDefaults *)defaults;
// Reset replaces only this app-mode tuple with an inheritance marker. It skips
// the legacy PC-mode record and follows global mode/default changes thereafter.
// A later explicit save replaces the marker. Blank PC/app identities reject
// saves/resets without mutating any defaults; legacy PC records are untouched.
+ (BOOL)removeForMode:(SunlightStreamMode)mode hostUUID:(nullable NSString *)hostUUID
               appID:(nullable NSString *)appID defaults:(NSUserDefaults *)defaults;
- (BOOL)isEqualToProfile:(nullable SunlightStreamQualityProfile *)profile;
@end

NS_ASSUME_NONNULL_END
