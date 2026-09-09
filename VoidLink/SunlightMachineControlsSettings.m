#import "SunlightMachineControlsSettings.h"
#include <math.h>

static NSString *SLMachineControlsKey(NSString *hostUUID) {
    NSString *uuid = [[hostUUID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    return uuid.length ? [@"sunlight.pc.controls." stringByAppendingString:uuid] : nil;
}
static NSString * const SLMachineGlobalControlsKey = @"sunlight.global.controls";

static BOOL SLMachineNumber(id value, double minimum, double maximum, BOOL integer, BOOL allowBoolean) {
    if (![value isKindOfClass:NSNumber.class] ||
        (!allowBoolean && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())) return NO;
    double number = [value doubleValue];
    return isfinite(number) && number >= minimum && number <= maximum && (!integer || floor(number) == number);
}

@implementation SunlightMachineControlsSettings
- (instancetype)init {
    if ((self = [super init])) { _controlMode = SunlightMachineControlModeTrackpad; _touchEnabled = YES; _localVolume = 1; }
    return self;
}
- (BOOL)statsOverlayEnabled { return _statsOverlayLevel > 0; }
- (void)setStatsOverlayEnabled:(BOOL)statsOverlayEnabled {
    if (!statsOverlayEnabled) _statsOverlayLevel = 0;
    else if (_statsOverlayLevel == 0) _statsOverlayLevel = 1;
}
+ (instancetype)globalControlsWithDefaults:(NSUserDefaults *)defaults fallback:(SunlightMachineControlsSettings *)fallback {
    SunlightMachineControlsSettings *settings = [self settingsForHostUUID:nil defaults:defaults globalDefaults:fallback];
    id record = [defaults objectForKey:SLMachineGlobalControlsKey];
    if (![record isKindOfClass:NSDictionary.class]) return settings;
    if (SLMachineNumber(record[@"controlMode"], 0, 2, YES, NO)) settings.controlMode = [record[@"controlMode"] integerValue];
    if (SLMachineNumber(record[@"touchEnabled"], 0, 1, YES, YES)) settings.touchEnabled = [record[@"touchEnabled"] boolValue];
    return settings;
}
- (BOOL)saveGlobalControlsToDefaults:(NSUserDefaults *)defaults {
    if (self.controlMode < 0 || self.controlMode > 2) return NO;
    [defaults setObject:@{@"controlMode": @(self.controlMode), @"touchEnabled": @(self.touchEnabled)} forKey:SLMachineGlobalControlsKey];
    return YES;
}
+ (instancetype)settingsForHostUUID:(NSString *)hostUUID defaults:(NSUserDefaults *)defaults
                     globalDefaults:(SunlightMachineControlsSettings *)globalDefaults {
    SunlightMachineControlsSettings *settings = [globalDefaults copy];
    if (settings.controlMode < 0 || settings.controlMode > 2) settings.controlMode = SunlightMachineControlModeTrackpad;
    if (!isfinite(settings.localVolume) || settings.localVolume < 0 || settings.localVolume > 1) settings.localVolume = 1;
    if (settings.statsOverlayLevel < 0 || settings.statsOverlayLevel > 2) settings.statsOverlayLevel = 0;
    NSString *key = SLMachineControlsKey(hostUUID);
    id record = key ? [defaults objectForKey:key] : nil;
    if (![record isKindOfClass:NSDictionary.class]) return settings;
    if (SLMachineNumber(record[@"controlMode"], 0, 2, YES, NO)) settings.controlMode = [record[@"controlMode"] integerValue];
    if (SLMachineNumber(record[@"touchEnabled"], 0, 1, YES, YES)) settings.touchEnabled = [record[@"touchEnabled"] boolValue];
    if (SLMachineNumber(record[@"localVolume"], 0, 1, NO, NO)) settings.localVolume = [record[@"localVolume"] doubleValue];
    if (SLMachineNumber(record[@"statsOverlayLevel"], 0, 2, YES, NO)) settings.statsOverlayLevel = [record[@"statsOverlayLevel"] integerValue];
    return settings;
}
- (BOOL)saveForHostUUID:(NSString *)hostUUID defaults:(NSUserDefaults *)defaults
         globalDefaults:(SunlightMachineControlsSettings *)globalDefaults {
    NSString *key = SLMachineControlsKey(hostUUID);
    if (!key || self.controlMode < 0 || self.controlMode > 2 || self.statsOverlayLevel < 0 || self.statsOverlayLevel > 2 ||
        !isfinite(self.localVolume) || self.localVolume < 0 || self.localVolume > 1) return NO;
    NSMutableDictionary *record = [NSMutableDictionary dictionary];
    if (self.controlMode != globalDefaults.controlMode) record[@"controlMode"] = @(self.controlMode);
    if (self.touchEnabled != globalDefaults.touchEnabled) record[@"touchEnabled"] = @(self.touchEnabled);
    // Core Data stores the legacy volume as Float; do not create an override
    // for its rounding difference from the editor's equivalent Double value.
    if (fabs(self.localVolume - globalDefaults.localVolume) > 0.000001) record[@"localVolume"] = @(self.localVolume);
    if (self.statsOverlayLevel != globalDefaults.statsOverlayLevel) record[@"statsOverlayLevel"] = @(self.statsOverlayLevel);
    if (record.count) [defaults setObject:record forKey:key];
    else [defaults removeObjectForKey:key];
    return YES;
}
+ (BOOL)removeForHostUUID:(NSString *)hostUUID defaults:(NSUserDefaults *)defaults {
    NSString *key = SLMachineControlsKey(hostUUID);
    if (!key) return NO;
    [defaults removeObjectForKey:key];
    return YES;
}
- (id)copyWithZone:(NSZone *)zone {
    SunlightMachineControlsSettings *settings = [[[self class] allocWithZone:zone] init];
    settings.controlMode = self.controlMode; settings.touchEnabled = self.touchEnabled;
    settings.localVolume = self.localVolume; settings.statsOverlayLevel = self.statsOverlayLevel;
    return settings;
}
- (BOOL)isEqualToSettings:(SunlightMachineControlsSettings *)settings {
    return settings != nil && self.controlMode == settings.controlMode && self.touchEnabled == settings.touchEnabled &&
        fabs(self.localVolume - settings.localVolume) <= 0.000001 && self.statsOverlayLevel == settings.statsOverlayLevel;
}
@end
