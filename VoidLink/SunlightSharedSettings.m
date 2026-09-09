#import "SunlightSharedSettings.h"
#include <math.h>

static NSString *SLSharedPCKey(NSString *hostUUID) {
    NSString *uuid = [[hostUUID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    return uuid.length > 0 ? [@"sunlight.pc.shared." stringByAppendingString:uuid] : nil;
}

static BOOL SLSharedInteger(id value, NSInteger minimum, NSInteger maximum, BOOL allowBoolean) {
    if (![value isKindOfClass:NSNumber.class] ||
        (!allowBoolean && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())) return NO;
    double number = [value doubleValue];
    return isfinite(number) && number >= minimum && number <= maximum && floor(number) == number;
}

static BOOL SLSharedAudioConfig(NSInteger value) {
    return value == 2 || value == 3 || value == 6 || value == 8;
}

@implementation SunlightSharedSettings

- (instancetype)init {
    if ((self = [super init])) {
        _preferredCodec = 0;
        _framePacingMode = 2;
        _audioConfig = 2;
        _fullColorRange = YES;
    }
    return self;
}

+ (instancetype)settingsForHostUUID:(NSString *)hostUUID defaults:(NSUserDefaults *)defaults
                     globalDefaults:(SunlightSharedSettings *)globalDefaults {
    SunlightSharedSettings *settings = [globalDefaults copy];
    // Guard inherited legacy values too; these defaults match the supported
    // enum contract without persisting a repair into the global settings store.
    if (settings.preferredCodec < 0 || settings.preferredCodec > 3) settings.preferredCodec = 0;
    if (settings.framePacingMode < 0 || settings.framePacingMode > 3) settings.framePacingMode = 2;
    if (!SLSharedAudioConfig(settings.audioConfig)) settings.audioConfig = 2;
    NSString *key = SLSharedPCKey(hostUUID);
    id record = key ? [defaults objectForKey:key] : nil;
    if (![record isKindOfClass:NSDictionary.class]) return settings;
    if (SLSharedInteger(record[@"preferredCodec"], 0, 3, NO)) settings.preferredCodec = [record[@"preferredCodec"] integerValue];
    if (SLSharedInteger(record[@"framePacingMode"], 0, 3, NO)) settings.framePacingMode = [record[@"framePacingMode"] integerValue];
    if (SLSharedInteger(record[@"audioConfig"], 2, 8, NO) && SLSharedAudioConfig([record[@"audioConfig"] integerValue])) {
        settings.audioConfig = [record[@"audioConfig"] integerValue];
    }
    if (SLSharedInteger(record[@"enableHdr"], 0, 1, YES)) settings.enableHdr = [record[@"enableHdr"] boolValue];
    if (SLSharedInteger(record[@"fullColorRange"], 0, 1, YES)) settings.fullColorRange = [record[@"fullColorRange"] boolValue];
    if (SLSharedInteger(record[@"playAudioOnPC"], 0, 1, YES)) settings.playAudioOnPC = [record[@"playAudioOnPC"] boolValue];
    return settings;
}

- (BOOL)saveForHostUUID:(NSString *)hostUUID defaults:(NSUserDefaults *)defaults
         globalDefaults:(SunlightSharedSettings *)globalDefaults {
    NSString *key = SLSharedPCKey(hostUUID);
    if (!key || self.preferredCodec < 0 || self.preferredCodec > 3 ||
        self.framePacingMode < 0 || self.framePacingMode > 3 || !SLSharedAudioConfig(self.audioConfig)) return NO;
    NSMutableDictionary *record = [NSMutableDictionary dictionary];
    if (self.preferredCodec != globalDefaults.preferredCodec) record[@"preferredCodec"] = @(self.preferredCodec);
    if (self.framePacingMode != globalDefaults.framePacingMode) record[@"framePacingMode"] = @(self.framePacingMode);
    if (self.audioConfig != globalDefaults.audioConfig) record[@"audioConfig"] = @(self.audioConfig);
    if (self.enableHdr != globalDefaults.enableHdr) record[@"enableHdr"] = @(self.enableHdr);
    if (self.fullColorRange != globalDefaults.fullColorRange) record[@"fullColorRange"] = @(self.fullColorRange);
    if (self.playAudioOnPC != globalDefaults.playAudioOnPC) record[@"playAudioOnPC"] = @(self.playAudioOnPC);
    if (record.count > 0) [defaults setObject:record forKey:key];
    else [defaults removeObjectForKey:key];
    return YES;
}

+ (BOOL)removeForHostUUID:(NSString *)hostUUID defaults:(NSUserDefaults *)defaults {
    NSString *key = SLSharedPCKey(hostUUID);
    if (!key) return NO;
    [defaults removeObjectForKey:key];
    return YES;
}

- (id)copyWithZone:(NSZone *)zone {
    SunlightSharedSettings *settings = [[[self class] allocWithZone:zone] init];
    settings.preferredCodec = self.preferredCodec;
    settings.framePacingMode = self.framePacingMode;
    settings.audioConfig = self.audioConfig;
    settings.enableHdr = self.enableHdr;
    settings.fullColorRange = self.fullColorRange;
    settings.playAudioOnPC = self.playAudioOnPC;
    return settings;
}

- (BOOL)isEqualToSettings:(SunlightSharedSettings *)settings {
    return settings != nil && self.preferredCodec == settings.preferredCodec &&
        self.framePacingMode == settings.framePacingMode && self.audioConfig == settings.audioConfig &&
        self.enableHdr == settings.enableHdr && self.fullColorRange == settings.fullColorRange &&
        self.playAudioOnPC == settings.playAudioOnPC;
}

@end
