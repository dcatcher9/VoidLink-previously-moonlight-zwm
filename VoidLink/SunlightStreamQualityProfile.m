#import "SunlightStreamQualityProfile.h"
#include <math.h>

static NSString * const SLQualityNativeMigrationKey = @"sunlight.nativeResolutionProfiles.v1";

static NSString *SLQualityProfileKey(SunlightStreamMode mode) {
    switch (mode) {
        case SunlightStreamMode2D: return @"sunlight.streamQuality.2d";
        case SunlightStreamModeHost3D: return @"sunlight.streamQuality.host3d";
        case SunlightStreamModeRawFullSBS:
        case SunlightStreamModeRawHalfSBS: return @"sunlight.streamQuality.raw3d";
        default: return nil;
    }
}

static BOOL SLQualityStoredInteger(id value, int minimum, int maximum) {
    if (![value isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    double number = [value doubleValue];
    return isfinite(number) && number >= minimum && number <= maximum && floor(number) == number;
}

static BOOL SLQualityStoredBoolean(id value) {
    return [value isKindOfClass:NSNumber.class] &&
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

static BOOL SLQualityValidDimensions(int width, int height) {
    return width >= 1 && width <= 16384 && height >= 1 && height <= 16384;
}

static NSString *SLQualityPCKey(SunlightStreamMode mode, NSString *hostUUID) {
    NSString *globalKey = SLQualityProfileKey(mode);
    NSString *uuid = [[hostUUID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    return globalKey && uuid.length > 0 ? [globalKey stringByAppendingFormat:@".pc.%@", uuid] : nil;
}

static NSString *SLQualityAppKey(SunlightStreamMode mode, NSString *hostUUID, NSString *appID) {
    NSString *globalKey = SLQualityProfileKey(mode);
    if (![hostUUID isKindOfClass:NSString.class] || ![appID isKindOfClass:NSString.class]) return nil;
    NSString *uuid = [[hostUUID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    NSString *application = [appID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!globalKey || !uuid.length || !application.length) return nil;
    // Encode each component separately so punctuation in either identity cannot
    // collide with another PC/app pair or a legacy PC-only key.
    NSString *encodedUUID = [[uuid dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    NSString *encodedAppID = [[application dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    return [globalKey stringByAppendingFormat:@".app.%@.%@", encodedUUID, encodedAppID];
}

static BOOL SLQualityValidRecord(id record) {
    return [record isKindOfClass:NSDictionary.class] &&
        SLQualityStoredInteger(record[@"width"], 1, 16384) &&
        SLQualityStoredInteger(record[@"height"], 1, 16384) &&
        SLQualityStoredInteger(record[@"frameRate"], 1, 240) &&
        SLQualityStoredInteger(record[@"bitRate"], 500, 800000) &&
        (!record[@"usesNativeResolution"] || SLQualityStoredBoolean(record[@"usesNativeResolution"]));
}

static BOOL SLQualityIsMigratableKey(NSString *key) {
    for (NSNumber *modeValue in @[@(SunlightStreamMode2D), @(SunlightStreamModeHost3D)]) {
        SunlightStreamMode mode = modeValue.integerValue;
        NSString *globalKey = SLQualityProfileKey(mode);
        if ([key isEqualToString:globalKey]) return YES;
        NSString *pcPrefix = [globalKey stringByAppendingString:@".pc."];
        if ([key hasPrefix:pcPrefix]) {
            NSString *uuid = [key substringFromIndex:pcPrefix.length];
            return [key isEqualToString:SLQualityPCKey(mode, uuid)];
        }
        NSString *appPrefix = [globalKey stringByAppendingString:@".app."];
        if ([key hasPrefix:appPrefix]) {
            NSArray<NSString *> *parts = [[key substringFromIndex:appPrefix.length] componentsSeparatedByString:@"."];
            if (parts.count != 2) return NO;
            NSData *uuidData = [[NSData alloc] initWithBase64EncodedString:parts[0] options:0];
            NSData *appData = [[NSData alloc] initWithBase64EncodedString:parts[1] options:0];
            if (!uuidData.length || !appData.length) return NO;
            NSString *uuid = [[NSString alloc] initWithData:uuidData encoding:NSUTF8StringEncoding];
            NSString *appID = [[NSString alloc] initWithData:appData encoding:NSUTF8StringEncoding];
            return [key isEqualToString:SLQualityAppKey(mode, uuid, appID)];
        }
    }
    return NO;
}

static BOOL SLQualityIsLegacyPreset(id record) {
    if (!SLQualityValidRecord(record) || record[@"usesNativeResolution"] != nil) return NO;
    int width = [record[@"width"] intValue], height = [record[@"height"] intValue];
    return (width == 1280 && height == 720) || (width == 1920 && height == 1080) ||
        (width == 2560 && height == 1440) || (width == 3840 && height == 2160);
}

static BOOL SLQualityRecordInheritsGlobal(id record) {
    if (![record isKindOfClass:NSDictionary.class] || [record count] != 2 ||
        !SLQualityStoredInteger(record[@"version"], 1, 1)) return NO;
    id inherit = record[@"inheritsGlobalDefaults"];
    return [inherit isKindOfClass:NSNumber.class] &&
        CFGetTypeID((__bridge CFTypeRef)inherit) == CFBooleanGetTypeID() && [inherit boolValue];
}

@implementation SunlightStreamQualityProfile

- (void)resolveNativeWidth:(int)width height:(int)height {
    if (self.usesNativeResolution && SLQualityValidDimensions(width, height)) {
        self.width = width;
        self.height = height;
    }
}

+ (BOOL)needsNativeResolutionMigrationInDefaults:(NSUserDefaults *)defaults {
    id completed = [defaults objectForKey:SLQualityNativeMigrationKey];
    return !SLQualityStoredBoolean(completed) || ![completed boolValue];
}

+ (void)migrateLegacyPresetResolutionsToNativeWidth:(int)width height:(int)height defaults:(NSUserDefaults *)defaults {
    if (!SLQualityValidDimensions(width, height) || ![self needsNativeResolutionMigrationInDefaults:defaults]) return;

    NSDictionary<NSString *, id> *records = defaults.dictionaryRepresentation;
    for (NSString *key in records) {
        id record = records[key];
        if (!SLQualityIsMigratableKey(key) || !SLQualityIsLegacyPreset(record)) continue;
        NSMutableDictionary *migrated = [record mutableCopy];
        migrated[@"width"] = @(width);
        migrated[@"height"] = @(height);
        migrated[@"usesNativeResolution"] = @YES;
        [defaults setObject:migrated forKey:key];
    }
    [defaults setBool:YES forKey:SLQualityNativeMigrationKey];
}

+ (instancetype)profileForMode:(SunlightStreamMode)mode
                      defaults:(NSUserDefaults *)defaults
                      fallback:(SunlightStreamQualityProfile *)fallback {
    NSString *key = SLQualityProfileKey(mode);
    return [self profileFromRecord:key ? [defaults objectForKey:key] : nil fallback:fallback];
}

+ (instancetype)profileForMode:(SunlightStreamMode)mode hostUUID:(NSString *)hostUUID
                      defaults:(NSUserDefaults *)defaults fallback:(SunlightStreamQualityProfile *)fallback {
    SunlightStreamQualityProfile *global = [self profileForMode:mode defaults:defaults fallback:fallback];
    NSString *key = SLQualityPCKey(mode, hostUUID);
    return [self profileFromRecord:key ? [defaults objectForKey:key] : nil fallback:global];
}

+ (instancetype)profileForMode:(SunlightStreamMode)mode hostUUID:(NSString *)hostUUID appID:(NSString *)appID
                      defaults:(NSUserDefaults *)defaults fallback:(SunlightStreamQualityProfile *)fallback {
    NSString *key = SLQualityAppKey(mode, hostUUID, appID);
    id record = key ? [defaults objectForKey:key] : nil;
    if (SLQualityValidRecord(record)) return [self profileFromRecord:record fallback:fallback];
    if (SLQualityRecordInheritsGlobal(record)) return [self profileForMode:mode defaults:defaults fallback:fallback];
    return [self profileForMode:mode hostUUID:hostUUID defaults:defaults fallback:fallback];
}

+ (instancetype)profileFromRecord:(id)record fallback:(SunlightStreamQualityProfile *)fallback {
    if (!SLQualityValidRecord(record)) {
        return [fallback copy];
    }
    SunlightStreamQualityProfile *profile = [self new];
    profile.width = [record[@"width"] intValue];
    profile.height = [record[@"height"] intValue];
    profile.frameRate = [record[@"frameRate"] intValue];
    profile.bitRate = [record[@"bitRate"] intValue];
    profile.usesNativeResolution = [record[@"usesNativeResolution"] boolValue];
    return profile;
}

- (BOOL)saveForMode:(SunlightStreamMode)mode defaults:(NSUserDefaults *)defaults {
    return [self saveForKey:SLQualityProfileKey(mode) defaults:defaults];
}

- (BOOL)saveForMode:(SunlightStreamMode)mode hostUUID:(NSString *)hostUUID defaults:(NSUserDefaults *)defaults {
    return [self saveForKey:SLQualityPCKey(mode, hostUUID) defaults:defaults];
}

- (BOOL)saveForMode:(SunlightStreamMode)mode hostUUID:(NSString *)hostUUID appID:(NSString *)appID defaults:(NSUserDefaults *)defaults {
    return [self saveForKey:SLQualityAppKey(mode, hostUUID, appID) defaults:defaults];
}

+ (BOOL)hasOverrideForMode:(SunlightStreamMode)mode hostUUID:(NSString *)hostUUID appID:(NSString *)appID defaults:(NSUserDefaults *)defaults {
    NSString *key = SLQualityAppKey(mode, hostUUID, appID);
    return key && SLQualityValidRecord([defaults objectForKey:key]);
}

+ (BOOL)removeForMode:(SunlightStreamMode)mode hostUUID:(NSString *)hostUUID appID:(NSString *)appID defaults:(NSUserDefaults *)defaults {
    NSString *key = SLQualityAppKey(mode, hostUUID, appID);
    if (!key) return NO;
    [defaults setObject:@{@"version": @1, @"inheritsGlobalDefaults": @YES} forKey:key];
    return YES;
}

+ (BOOL)hasOverrideForMode:(SunlightStreamMode)mode hostUUID:(NSString *)hostUUID defaults:(NSUserDefaults *)defaults {
    NSString *key = SLQualityPCKey(mode, hostUUID);
    return key && SLQualityValidRecord([defaults objectForKey:key]);
}

+ (BOOL)removeForMode:(SunlightStreamMode)mode hostUUID:(NSString *)hostUUID defaults:(NSUserDefaults *)defaults {
    NSString *key = SLQualityPCKey(mode, hostUUID);
    if (!key) return NO;
    [defaults removeObjectForKey:key];
    return YES;
}

- (BOOL)saveForKey:(NSString *)key defaults:(NSUserDefaults *)defaults {
    if (!key || ![self isValid]) return NO;
    [defaults setObject:@{@"width": @(self.width), @"height": @(self.height),
                         @"frameRate": @(self.frameRate), @"bitRate": @(self.bitRate),
                         @"usesNativeResolution": @(self.usesNativeResolution)} forKey:key];
    return YES;
}

- (BOOL)isValid {
    return SLQualityValidDimensions(self.width, self.height) &&
        self.frameRate >= 1 && self.frameRate <= 240 && self.bitRate >= 500 && self.bitRate <= 800000;
}

- (id)copyWithZone:(NSZone *)zone {
    SunlightStreamQualityProfile *profile = [[[self class] allocWithZone:zone] init];
    profile.width = self.width;
    profile.height = self.height;
    profile.frameRate = self.frameRate;
    profile.bitRate = self.bitRate;
    profile.usesNativeResolution = self.usesNativeResolution;
    return profile;
}

- (BOOL)isEqualToProfile:(SunlightStreamQualityProfile *)profile {
    return profile != nil && self.width == profile.width && self.height == profile.height &&
        self.frameRate == profile.frameRate && self.bitRate == profile.bitRate &&
        self.usesNativeResolution == profile.usesNativeResolution;
}

@end
