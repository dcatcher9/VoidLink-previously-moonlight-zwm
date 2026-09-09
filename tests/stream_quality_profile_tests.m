#import <Foundation/Foundation.h>
#import "SunlightStreamQualityProfile.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned checks;
static void check(BOOL passed, const char *message) {
    checks++;
    if (!passed) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static SunlightStreamQualityProfile *profile(int width, int height, int fps, int bitrate) {
    SunlightStreamQualityProfile *value = [SunlightStreamQualityProfile new];
    value.width = width; value.height = height; value.frameRate = fps; value.bitRate = bitrate;
    return value;
}

static NSString *appRecordKey(NSString *mode, NSString *uuid, NSString *appID) {
    return [NSString stringWithFormat:@"sunlight.streamQuality.%@.app.%@.%@", mode,
        [[uuid dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0],
        [[appID dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0]];
}

static NSDictionary *legacyRecord(int width, int height) {
    return @{@"width": @(width), @"height": @(height), @"frameRate": @90, @"bitRate": @500,
             @"futureField": @{@"preserve": @YES}};
}

static void testNativeResolution(NSUserDefaults *defaults, NSString *suite) {
    [defaults removePersistentDomainForName:suite];
    NSString *globalKey = @"sunlight.streamQuality.2d";
    NSString *marker = @"sunlight.nativeResolutionProfiles.v1";
    check([SunlightStreamQualityProfile needsNativeResolutionMigrationInDefaults:defaults], "absent marker requires native migration");
    for (id markerValue in @[@NO, @0, @1, @2, @"YES", @[], @{}]) {
        [defaults setObject:markerValue forKey:marker];
        NSDictionary *beforeCheck = [defaults persistentDomainForName:suite];
        check([SunlightStreamQualityProfile needsNativeResolutionMigrationInDefaults:defaults], "only Boolean true completes native migration");
        check([[defaults persistentDomainForName:suite] isEqual:beforeCheck], "migration marker query never writes preferences");
    }
    [defaults setBool:YES forKey:marker];
    check(![SunlightStreamQualityProfile needsNativeResolutionMigrationInDefaults:defaults], "Boolean true skips completed native migration");
    [defaults removeObjectForKey:marker];
    SunlightStreamQualityProfile *fallback = profile(1919, 1081, 30, 10000);
    SunlightStreamQualityProfile *(^load)(void) = ^{
        return [SunlightStreamQualityProfile profileForMode:SunlightStreamMode2D defaults:defaults fallback:fallback];
    };
    [defaults setObject:legacyRecord(1920, 1080) forKey:globalKey];
    check(!load().usesNativeResolution, "legacy records without a native flag load as fixed");
    for (id invalidFlag in @[@0, @1, @2, @"YES", @[], @{}]) {
        NSMutableDictionary *record = [legacyRecord(1920, 1080) mutableCopy];
        record[@"usesNativeResolution"] = invalidFlag;
        [defaults setObject:record forKey:globalKey];
        check([load() isEqualToProfile:fallback], "only a stored Boolean can enable or disable native resolution");
    }
    SunlightStreamQualityProfile *fixed = profile(1920, 1080, 90, 500);
    check([fixed saveForMode:SunlightStreamMode2D defaults:defaults], "fixed quality saves with the new schema");
    id savedFixedFlag = [defaults dictionaryForKey:globalKey][@"usesNativeResolution"];
    check(CFGetTypeID((__bridge CFTypeRef)savedFixedFlag) == CFBooleanGetTypeID() && ![savedFixedFlag boolValue],
          "saving fixed quality explicitly persists Boolean NO for future migrations");
    SunlightStreamQualityProfile *native = [fixed copy];
    native.usesNativeResolution = YES;
    check(![native isEqualToProfile:fixed] && [[native copy] isEqualToProfile:native],
          "native selection participates in equality and detached copies");
    check([native saveForMode:SunlightStreamMode2D defaults:defaults] && load().usesNativeResolution,
          "native selection survives a save and reload");
    NSDictionary *beforeResolve = [defaults persistentDomainForName:suite];
    SunlightStreamQualityProfile *resolved = load();
    [resolved resolveNativeWidth:2622 height:1206];
    check(resolved.width == 2622 && resolved.height == 1206 && resolved.frameRate == 90 && resolved.bitRate == 500,
          "native resolution replaces only dimensions, preserving FPS and legacy bitrate");
    [resolved resolveNativeWidth:2732 height:2048];
    check(resolved.width == 2732 && resolved.height == 2048 && resolved.usesNativeResolution,
          "one native profile resolves again for a different device");
    check([[defaults persistentDomainForName:suite] isEqualToDictionary:beforeResolve] && load().width == 1920,
          "native resolution is detached and never writes cached device dimensions on load");
    [fixed resolveNativeWidth:2622 height:1206];
    check(fixed.width == 1920 && fixed.height == 1080, "explicit fixed dimensions ignore native resolution changes");
    const int invalidDimensions[][2] = {{0, 1206}, {-1, 1206}, {2622, 0}, {2622, -1}, {16385, 1206}, {2622, 16385}};
    for (size_t i = 0; i < sizeof(invalidDimensions) / sizeof(invalidDimensions[0]); i++) {
        [resolved resolveNativeWidth:invalidDimensions[i][0] height:invalidDimensions[i][1]];
        check(resolved.width == 2732 && resolved.height == 2048, "invalid native dimensions cannot corrupt the active draft");
    }

    [defaults removePersistentDomainForName:suite];
    NSMutableDictionary<NSString *, NSDictionary *> *eligible = [NSMutableDictionary dictionary];
    const int presets[][2] = {{1280, 720}, {1920, 1080}, {2560, 1440}, {3840, 2160}};
    for (NSString *mode in @[@"2d", @"host3d"]) {
        eligible[[@"sunlight.streamQuality." stringByAppendingString:mode]] = legacyRecord(1920, 1080);
        for (NSUInteger i = 0; i < 4; i++) {
            NSString *uuid = [NSString stringWithFormat:@"pc-%lu", (unsigned long)i];
            eligible[[NSString stringWithFormat:@"sunlight.streamQuality.%@.pc.%@", mode, uuid]] = legacyRecord(presets[i][0], presets[i][1]);
            eligible[appRecordKey(mode, uuid, @"100")] = legacyRecord(presets[i][0], presets[i][1]);
        }
    }
    NSMutableDictionary<NSString *, id> *retained = [NSMutableDictionary dictionary];
    for (NSString *mode in @[@"2d", @"host3d"]) {
        retained[[NSString stringWithFormat:@"sunlight.streamQuality.%@.pc.custom", mode]] = legacyRecord(2000, 1000);
        retained[appRecordKey(mode, @"custom", @"100")] = legacyRecord(2622, 1206);
        for (NSNumber *flag in @[@NO, @YES]) {
            NSMutableDictionary *record = [legacyRecord(2560, 1440) mutableCopy];
            record[@"usesNativeResolution"] = flag;
            retained[appRecordKey(mode, @"explicit", flag.boolValue ? @"native" : @"fixed")] = record;
            retained[[NSString stringWithFormat:@"sunlight.streamQuality.%@.pc.explicit-%@", mode, flag]] = record;
        }
    }
    for (NSString *rawMode in @[@"raw3d", @"rawhalf", @"rawHalfSBS"]) {
        retained[[@"sunlight.streamQuality." stringByAppendingString:rawMode]] = legacyRecord(3840, 2160);
        retained[[NSString stringWithFormat:@"sunlight.streamQuality.%@.pc.pc-0", rawMode]] = legacyRecord(1920, 1080);
        retained[appRecordKey(rawMode, @"pc-0", @"100")] = legacyRecord(2560, 1440);
    }
    retained[appRecordKey(@"2d", @"reset", @"100")] = @{@"version": @1, @"inheritsGlobalDefaults": @YES};
    retained[@"sunlight.streamQuality.2d.pc.bad-type"] = @"not a record";
    NSMutableDictionary *badTuple = [legacyRecord(1920, 1080) mutableCopy];
    badTuple[@"frameRate"] = @0;
    retained[@"sunlight.streamQuality.2d.pc.bad-tuple"] = badTuple;
    NSMutableDictionary *badFlag = [legacyRecord(1920, 1080) mutableCopy];
    badFlag[@"usesNativeResolution"] = @1;
    retained[@"sunlight.streamQuality.2d.pc.bad-flag"] = badFlag;
    for (NSString *otherKey in @[@"sunlight.streamQuality.2d.extra", @"sunlight.streamQuality.2d.pc.",
             @"sunlight.streamQuality.2d.app.", @"sunlight.streamQuality.2d.app.!invalid!.MTAw",
             @"sunlight.streamQuality.2d.app./w==.MTAw", @"sunlight.streamQuality.2d.app.cGM=.MTAw.extra",
             @"sunlight.streamQuality.2d.app..MTAw", @"sunlight.streamQuality.2d-other.pc.pc-0",
             @"sunlight.machineControls.pc-0", @"unrelated-preference"]) {
        retained[otherKey] = legacyRecord(1920, 1080);
    }
    for (NSString *key in eligible) [defaults setObject:eligible[key] forKey:key];
    for (NSString *key in retained) [defaults setObject:retained[key] forKey:key];
    NSDictionary *beforeMigration = [defaults persistentDomainForName:suite];
    for (size_t i = 0; i < sizeof(invalidDimensions) / sizeof(invalidDimensions[0]); i++) {
        [SunlightStreamQualityProfile migrateLegacyPresetResolutionsToNativeWidth:invalidDimensions[i][0]
                                                                         height:invalidDimensions[i][1] defaults:defaults];
        check([[defaults persistentDomainForName:suite] isEqualToDictionary:beforeMigration] && ![defaults objectForKey:marker],
              "invalid native size cannot migrate records or consume the one-time marker");
    }
    [SunlightStreamQualityProfile migrateLegacyPresetResolutionsToNativeWidth:2622 height:1206 defaults:defaults];
    check([[defaults objectForKey:marker] isEqual:@YES], "successful native migration records completion");
    for (NSString *key in eligible) {
        NSMutableDictionary *expected = [eligible[key] mutableCopy];
        expected[@"width"] = @2622; expected[@"height"] = @1206; expected[@"usesNativeResolution"] = @YES;
        check([[defaults objectForKey:key] isEqual:expected],
              "legacy presets migrate across 2D/Host global, PC and app scopes without losing any extra fields");
    }
    for (NSString *key in retained) {
        check([[defaults objectForKey:key] isEqual:retained[key]],
              "migration preserves explicit choices, custom sizes, Raw, reset markers, malformed records and other preferences");
    }
    NSDictionary *onceMigrated = [defaults persistentDomainForName:suite];
    [SunlightStreamQualityProfile migrateLegacyPresetResolutionsToNativeWidth:2732 height:2048 defaults:defaults];
    check([[defaults persistentDomainForName:suite] isEqualToDictionary:onceMigrated],
          "migration is idempotent and never rewrites persisted profiles for a second device");
    NSString *lateKey = @"sunlight.streamQuality.2d.pc.imported-later";
    [defaults setObject:legacyRecord(1920, 1080) forKey:lateKey];
    [SunlightStreamQualityProfile migrateLegacyPresetResolutionsToNativeWidth:2732 height:2048 defaults:defaults];
    check([[defaults objectForKey:lateKey] isEqual:legacyRecord(1920, 1080)], "completed migration does not reinterpret later fixed imports");

    SunlightStreamQualityProfile *(^loadApp)(NSString *, NSString *) = ^(NSString *uuid, NSString *appID) {
        return [SunlightStreamQualityProfile profileForMode:SunlightStreamMode2D hostUUID:uuid appID:appID defaults:defaults fallback:fallback];
    };
    SunlightStreamQualityProfile *appNative = loadApp(@"pc-2", @"100");
    [appNative resolveNativeWidth:2732 height:2048];
    check(appNative.usesNativeResolution && appNative.width == 2732 && appNative.height == 2048 &&
          appNative.frameRate == 90 && appNative.bitRate == 500 && loadApp(@"pc-2", @"100").width == 2622,
          "migrated app profiles re-resolve for another device without rewriting shared stored data");
    check([SunlightStreamQualityProfile removeForMode:SunlightStreamMode2D hostUUID:@"pc-2" appID:@"100" defaults:defaults],
          "native app override can be reset using the existing inheritance marker");
    SunlightStreamQualityProfile *reset = loadApp(@"pc-2", @"100");
    [reset resolveNativeWidth:2732 height:2048];
    check(reset.usesNativeResolution && reset.width == 2732 &&
          ![SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamMode2D hostUUID:@"pc-2" appID:@"100" defaults:defaults],
          "reset app inherits and resolves native global quality without becoming another override");
    check([SunlightStreamQualityProfile removeForMode:SunlightStreamMode2D hostUUID:@"pc-3" defaults:defaults],
          "legacy PC native override can be removed independently");
    SunlightStreamQualityProfile *pcInherited = [SunlightStreamQualityProfile profileForMode:SunlightStreamMode2D
        hostUUID:@"pc-3" defaults:defaults fallback:fallback];
    [pcInherited resolveNativeWidth:2732 height:2048];
    check(pcInherited.usesNativeResolution && pcInherited.width == 2732,
          "PC reset follows native global defaults on the current device");
    check([fixed saveForMode:SunlightStreamMode2D hostUUID:@"pc-2" appID:@"100" defaults:defaults] &&
          !loadApp(@"pc-2", @"100").usesNativeResolution && loadApp(@"pc-2", @"100").width == 1920,
          "explicit fixed selection replaces native inheritance and remains fixed");

    // The global keys can also contain new explicit choices before the first
    // migration; a preset dimension alone must never override their flag.
    [defaults removePersistentDomainForName:suite];
    [fixed saveForMode:SunlightStreamMode2D defaults:defaults];
    [native saveForMode:SunlightStreamModeHost3D defaults:defaults];
    [SunlightStreamQualityProfile migrateLegacyPresetResolutionsToNativeWidth:2622 height:1206 defaults:defaults];
    check(load().width == 1920 && !load().usesNativeResolution &&
          [SunlightStreamQualityProfile profileForMode:SunlightStreamModeHost3D defaults:defaults fallback:fallback].width == 1920,
          "first migration preserves both explicitly fixed and explicitly native global records");
    [defaults removePersistentDomainForName:suite];
}

int main(void) {
    @autoreleasepool {
        NSString *suite = [@"sunlight-quality-tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        [defaults removePersistentDomainForName:suite];
        SunlightStreamQualityProfile *fallback = profile(1919, 1081, 60, 20000);
        SunlightStreamQualityProfile *(^load)(SunlightStreamMode) = ^(SunlightStreamMode mode) {
            return [SunlightStreamQualityProfile profileForMode:mode defaults:defaults fallback:fallback];
        };
        SunlightStreamQualityProfile *flat = load(SunlightStreamMode2D);
        check(flat != fallback && [flat isEqualToProfile:fallback], "missing profile returns an isolated fallback copy");
        check([defaults persistentDomainForName:suite].count == 0, "loading does not commit fallback settings");
        flat.frameRate = 120;
        check(fallback.frameRate == 60 && ![flat isEqualToProfile:fallback], "draft edits cannot mutate the fallback");
        check([flat saveForMode:SunlightStreamMode2D defaults:defaults], "odd existing phone dimensions can be saved");
        SunlightStreamQualityProfile *host = profile(2622, 1206, 60, 42000);
        SunlightStreamQualityProfile *raw = profile(3840, 1080, 30, 42500);
        check([host saveForMode:SunlightStreamModeHost3D defaults:defaults], "Host 3D profile saves separately");
        check([raw saveForMode:SunlightStreamModeRawFullSBS defaults:defaults], "Raw saves complete packed dimensions");
        check([load(SunlightStreamMode2D) isEqualToProfile:flat], "saving stereo profiles preserves 2D quality");
        check([load(SunlightStreamModeHost3D) isEqualToProfile:host], "Host 3D reload preserves its own native quality");
        check([load(SunlightStreamModeRawHalfSBS) isEqualToProfile:raw], "legacy Half loads canonical Raw profile");
        SunlightStreamQualityProfile *legacy = [raw copy]; legacy.frameRate = 90;
        check([legacy saveForMode:SunlightStreamModeRawHalfSBS defaults:defaults] &&
              [load(SunlightStreamModeRawFullSBS) isEqualToProfile:legacy], "legacy Half saves to the one Raw key");
        check([defaults persistentDomainForName:suite].count == 3, "exactly three supported profile keys are persisted");

        SunlightStreamQualityProfile *draft = load(SunlightStreamModeHost3D);
        draft.bitRate = 50000;
        check(![draft isEqualToProfile:host] && [load(SunlightStreamModeHost3D) isEqualToProfile:host],
              "a dirty draft is detectable and remains uncommitted");
        check([draft saveForMode:SunlightStreamModeHost3D defaults:defaults] &&
              [load(SunlightStreamModeHost3D) isEqualToProfile:draft], "explicit save commits the exact draft");
        SunlightStreamQualityProfile *copy = [draft copy]; copy.width = 1280;
        check(draft.width == 2622 && ![copy isEqualToProfile:draft], "copying a loaded draft isolates later edits");
        check(![draft isEqualToProfile:nil], "nil is never an equal quality profile");
        check([draft isEqualToProfile:[draft copy]], "unchanged copied draft compares equal");

        NSString *key = @"sunlight.streamQuality.2d";
        NSDictionary *valid = @{ @"width": @1919, @"height": @1081, @"frameRate": @120, @"bitRate": @20000 };
        for (id invalidRecord in @[@"bad", @[], @{}, @{@"width": @1920}]) {
            [defaults setObject:invalidRecord forKey:key];
            check([load(SunlightStreamMode2D) isEqualToProfile:fallback], "malformed or incomplete record uses the complete fallback");
        }
        NSDictionary *invalidValues = @{
            @"width": @[@0, @(-1), @16385, @1920.5, @YES, @"1920", @(NAN), @(INFINITY)],
            @"height": @[@0, @16385, @1080.5, @NO],
            @"frameRate": @[@0, @241, @59.5, @"60"],
            @"bitRate": @[@499, @800001, @20000.5, @"20000"]
        };
        for (NSString *field in invalidValues) {
            for (id invalidValue in invalidValues[field]) {
                NSMutableDictionary *record = [valid mutableCopy]; record[field] = invalidValue;
                [defaults setObject:record forKey:key];
                SunlightStreamQualityProfile *loaded = load(SunlightStreamMode2D);
                check(loaded != fallback && [loaded isEqualToProfile:fallback],
                      "invalid stored field rejects the whole record without mixing settings");
            }
        }
        check([flat saveForMode:SunlightStreamMode2D defaults:defaults], "restore a valid record after invalid-default tests");
        const int invalidDrafts[][4] = {
            {0, 1080, 60, 20000}, {16385, 1080, 60, 20000}, {1920, 0, 60, 20000},
            {1920, 16385, 60, 20000}, {1920, 1080, 0, 20000}, {1920, 1080, 241, 20000},
            {1920, 1080, 60, 499}, {1920, 1080, 60, 800001}
        };
        for (size_t i = 0; i < sizeof(invalidDrafts) / sizeof(invalidDrafts[0]); i++) {
            const int *v = invalidDrafts[i];
            SunlightStreamQualityProfile *invalidDraft = profile(v[0], v[1], v[2], v[3]);
            check(![invalidDraft isValid], "draft preflight detects every invalid dimension, frame rate and bitrate before teardown");
            check(![invalidDraft saveForMode:SunlightStreamMode2D defaults:defaults] &&
                  [load(SunlightStreamMode2D) isEqualToProfile:flat], "invalid draft cannot overwrite a committed profile");
        }
        NSDictionary *beforeUnknownMode = [defaults persistentDomainForName:suite];
        check(![host saveForMode:(SunlightStreamMode)4 defaults:defaults] &&
              [load((SunlightStreamMode)4) isEqualToProfile:fallback], "future client placeholder cannot acquire an active quality key");
        check(![host saveForMode:(SunlightStreamMode)-1 defaults:defaults] &&
              [[defaults persistentDomainForName:suite] isEqualToDictionary:beforeUnknownMode], "unknown modes never write defaults");
        SunlightStreamQualityProfile *minimum = profile(1, 1, 1, 500);
        SunlightStreamQualityProfile *maximum = profile(16384, 16384, 240, 800000);
        check([minimum isValid] && [maximum isValid] && [flat isValid],
              "draft preflight accepts inclusive bounds and valid odd phone sizes");
        check([minimum saveForMode:SunlightStreamMode2D defaults:defaults] &&
              [load(SunlightStreamMode2D) isEqualToProfile:minimum], "inclusive minimum values survive round trip");
        check([maximum saveForMode:SunlightStreamMode2D defaults:defaults] &&
              [load(SunlightStreamMode2D) isEqualToProfile:maximum], "inclusive maximum values survive round trip");

        SunlightStreamQualityProfile *(^loadPC)(SunlightStreamMode, NSString *) = ^(SunlightStreamMode mode, NSString *uuid) {
            return [SunlightStreamQualityProfile profileForMode:mode hostUUID:uuid defaults:defaults fallback:fallback];
        };
        SunlightStreamQualityProfile *legacyLowBitrate = profile(1280, 720, 60, 500);
        check([legacyLowBitrate isValid] && [legacyLowBitrate saveForMode:SunlightStreamMode2D hostUUID:@"pc-low-bitrate" defaults:defaults],
              "legacy 500Kbps setting is a valid scoped profile");
        SunlightStreamQualityProfile *lowBitrateDraft = loadPC(SunlightStreamMode2D, @"pc-low-bitrate");
        check([lowBitrateDraft isEqualToProfile:legacyLowBitrate], "500Kbps survives scoped profile round trip");
        lowBitrateDraft.frameRate = 30;
        check([lowBitrateDraft isValid] && [lowBitrateDraft saveForMode:SunlightStreamMode2D hostUUID:@"pc-low-bitrate" defaults:defaults] &&
              [loadPC(SunlightStreamMode2D, @"pc-low-bitrate") isEqualToProfile:lowBitrateDraft] && lowBitrateDraft.bitRate == 500,
              "editing only FPS preserves a legacy 500Kbps profile");
        lowBitrateDraft.bitRate = 499;
        check(![lowBitrateDraft isValid] && ![lowBitrateDraft saveForMode:SunlightStreamMode2D hostUUID:@"pc-low-bitrate" defaults:defaults] &&
              loadPC(SunlightStreamMode2D, @"pc-low-bitrate").bitRate == 500,
              "499Kbps cannot replace a valid scoped profile");
        SunlightStreamQualityProfile *legacyHighBitrate = profile(1920, 1080, 60, 300000);
        check([legacyHighBitrate isValid], "existing 300Mbps draft passes validation before reconnect");
        check([legacyHighBitrate saveForMode:SunlightStreamModeHost3D hostUUID:@"pc-high-bitrate" defaults:defaults],
              "existing 300Mbps setting can be retained in a scoped mode profile");
        SunlightStreamQualityProfile *highBitrateDraft = loadPC(SunlightStreamModeHost3D, @"pc-high-bitrate");
        highBitrateDraft.frameRate = 30;
        check([highBitrateDraft saveForMode:SunlightStreamModeHost3D hostUUID:@"pc-high-bitrate" defaults:defaults] &&
              [loadPC(SunlightStreamModeHost3D, @"pc-high-bitrate") isEqualToProfile:highBitrateDraft] &&
              highBitrateDraft.bitRate == 300000, "editing only FPS preserves an existing 300Mbps profile");
        highBitrateDraft.bitRate = 250000;
        check([highBitrateDraft saveForMode:SunlightStreamModeHost3D hostUUID:@"pc-high-bitrate" defaults:defaults] &&
              loadPC(SunlightStreamModeHost3D, @"pc-high-bitrate").bitRate == 250000,
              "high-current-bitrate slider can save a reviewed 250Mbps choice");
        highBitrateDraft.bitRate = 800001;
        check(![highBitrateDraft isValid] && ![highBitrateDraft saveForMode:SunlightStreamModeHost3D hostUUID:@"pc-high-bitrate" defaults:defaults] &&
              loadPC(SunlightStreamModeHost3D, @"pc-high-bitrate").bitRate == 250000,
              "bitrate beyond the legacy 800Mbps maximum cannot overwrite a valid PC profile");
        SunlightStreamQualityProfile *global2D = profile(1920, 1080, 60, 30000);
        check([global2D saveForMode:SunlightStreamMode2D defaults:defaults], "global mode profile is the inheritance baseline");
        check([loadPC(SunlightStreamMode2D, @"pc-a") isEqualToProfile:global2D], "new PC inherits the matching global mode");
        SunlightStreamQualityProfile *pcA = profile(2560, 1440, 120, 60000);
        SunlightStreamQualityProfile *pcB = profile(1280, 720, 30, 10000);
        check([pcA saveForMode:SunlightStreamMode2D hostUUID:@"  PC-A\n" defaults:defaults], "PC key trims and normalizes UUID case");
        check([pcB saveForMode:SunlightStreamMode2D hostUUID:@"pc-b" defaults:defaults], "another PC can save distinct quality");
        check([loadPC(SunlightStreamMode2D, @"pc-a") isEqualToProfile:pcA] &&
              [loadPC(SunlightStreamMode2D, @"PC-B") isEqualToProfile:pcB] &&
              [load(SunlightStreamMode2D) isEqualToProfile:global2D], "PC quality commits never overwrite another PC or global settings");
        check([SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamMode2D hostUUID:@" PC-A " defaults:defaults] &&
              ![SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamModeHost3D hostUUID:@"pc-a" defaults:defaults],
              "override indicator distinguishes inherited and committed modes");
        check([loadPC(SunlightStreamModeHost3D, @"pc-a") isEqualToProfile:load(SunlightStreamModeHost3D)],
              "one PC's 2D override does not affect its Host 3D profile");
        check([raw saveForMode:SunlightStreamModeRawHalfSBS hostUUID:@"pc-a" defaults:defaults] &&
              [loadPC(SunlightStreamModeRawFullSBS, @"pc-a") isEqualToProfile:raw] &&
              [SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamModeRawHalfSBS hostUUID:@"pc-a" defaults:defaults],
              "PC-scoped legacy Half aliases the canonical Raw profile");
        global2D.bitRate = 35000;
        [global2D saveForMode:SunlightStreamMode2D defaults:defaults];
        check([loadPC(SunlightStreamMode2D, @"pc-c") isEqualToProfile:global2D] &&
              [loadPC(SunlightStreamMode2D, @"pc-a") isEqualToProfile:pcA],
              "global edits reach inheriting PCs without replacing explicit overrides");
        NSString *pcKey = @"sunlight.streamQuality.2d.pc.pc-a";
        [defaults setObject:@{@"width": @2560, @"height": @1440, @"frameRate": @120, @"bitRate": @(-1)} forKey:pcKey];
        check(![SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamMode2D hostUUID:@"pc-a" defaults:defaults] &&
              [loadPC(SunlightStreamMode2D, @"pc-a") isEqualToProfile:global2D],
              "corrupt PC override falls back to valid global tuple and is not reported as active");
        [defaults setObject:@"invalid global" forKey:key];
        SunlightStreamQualityProfile *doubleFallback = loadPC(SunlightStreamMode2D, @"pc-a");
        check(doubleFallback != fallback && [doubleFallback isEqualToProfile:fallback],
              "invalid PC and global records return an isolated complete fallback");
        [global2D saveForMode:SunlightStreamMode2D defaults:defaults];
        [pcA saveForMode:SunlightStreamMode2D hostUUID:@"pc-a" defaults:defaults];
        check(![profile(0, 1080, 60, 20000) saveForMode:SunlightStreamMode2D hostUUID:@"pc-a" defaults:defaults] &&
              [loadPC(SunlightStreamMode2D, @"pc-a") isEqualToProfile:pcA], "invalid PC draft preserves its last valid override");
        NSDictionary *beforeBlankScope = [defaults persistentDomainForName:suite];
        for (NSString *blank in @[@"", @" \n\t"]) {
            check(![pcA saveForMode:SunlightStreamMode2D hostUUID:blank defaults:defaults] &&
                  ![SunlightStreamQualityProfile removeForMode:SunlightStreamMode2D hostUUID:blank defaults:defaults] &&
                  ![SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamMode2D hostUUID:blank defaults:defaults] &&
                  [loadPC(SunlightStreamMode2D, blank) isEqualToProfile:global2D],
                  "blank PC identity can inherit but never writes or resets the global scope");
        }
        check(![pcA saveForMode:SunlightStreamMode2D hostUUID:nil defaults:defaults] &&
              ![SunlightStreamQualityProfile removeForMode:(SunlightStreamMode)4 hostUUID:@"pc-a" defaults:defaults] &&
              [[defaults persistentDomainForName:suite] isEqualToDictionary:beforeBlankScope],
              "missing UUID and unsupported mode cannot mutate scoped or global records");
        check([SunlightStreamQualityProfile removeForMode:SunlightStreamMode2D hostUUID:@"PC-A" defaults:defaults] &&
              ![SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamMode2D hostUUID:@"pc-a" defaults:defaults] &&
              [loadPC(SunlightStreamMode2D, @"pc-a") isEqualToProfile:global2D], "reset restores inheritance for exactly one PC mode");
        check([loadPC(SunlightStreamMode2D, @"pc-b") isEqualToProfile:pcB] &&
              [loadPC(SunlightStreamModeRawFullSBS, @"pc-a") isEqualToProfile:raw], "reset leaves other PCs and modes intact");
        check([SunlightStreamQualityProfile removeForMode:SunlightStreamModeRawHalfSBS hostUUID:@"pc-a" defaults:defaults] &&
              ![SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamModeRawFullSBS hostUUID:@"pc-a" defaults:defaults],
              "legacy Half reset removes its canonical Raw override");

        SunlightStreamQualityProfile *(^loadApp)(SunlightStreamMode, NSString *, NSString *) = ^(SunlightStreamMode mode, NSString *uuid, NSString *appID) {
            return [SunlightStreamQualityProfile profileForMode:mode hostUUID:uuid appID:appID defaults:defaults fallback:fallback];
        };
        SunlightStreamQualityProfile *legacyPC = profile(2560, 1440, 90, 55000);
        [legacyPC saveForMode:SunlightStreamMode2D hostUUID:@"app-pc-a" defaults:defaults];
        NSDictionary *beforeAppLoad = [defaults persistentDomainForName:suite];
        check([loadApp(SunlightStreamMode2D, @"app-pc-a", @"100") isEqualToProfile:legacyPC] &&
              [loadApp(SunlightStreamMode2D, @"app-pc-a", @"200") isEqualToProfile:legacyPC],
              "apps without records read the legacy PC mode without migration");
        check([[defaults persistentDomainForName:suite] isEqualToDictionary:beforeAppLoad],
              "app loads never fan out legacy PC records or write defaults");
        SunlightStreamQualityProfile *appA = profile(1920, 1080, 60, 500);
        SunlightStreamQualityProfile *appB = profile(1280, 720, 30, 22000);
        SunlightStreamQualityProfile *otherPCApp = profile(3840, 2160, 60, 100000);
        check([appA saveForMode:SunlightStreamMode2D hostUUID:@" APP-PC-A \n" appID:@" 100 " defaults:defaults],
              "app save normalizes PC UUID and trims app ID");
        check([appB saveForMode:SunlightStreamMode2D hostUUID:@"app-pc-a" appID:@"200" defaults:defaults] &&
              [otherPCApp saveForMode:SunlightStreamMode2D hostUUID:@"app-pc-b" appID:@"100" defaults:defaults],
              "different apps and PCs save independent picture profiles");
        check([loadApp(SunlightStreamMode2D, @"APP-PC-A", @"100") isEqualToProfile:appA] &&
              [loadApp(SunlightStreamMode2D, @"app-pc-a", @"200") isEqualToProfile:appB] &&
              [loadApp(SunlightStreamMode2D, @"app-pc-b", @"100") isEqualToProfile:otherPCApp],
              "PC and app identity both participate in mode quality lookup");
        check([loadPC(SunlightStreamMode2D, @"app-pc-a") isEqualToProfile:legacyPC] &&
              [load(SunlightStreamMode2D) isEqualToProfile:global2D],
              "app commits do not rewrite the legacy PC or global tuple");
        check([host saveForMode:SunlightStreamModeHost3D hostUUID:@"app-pc-a" appID:@"100" defaults:defaults] &&
              [loadApp(SunlightStreamModeHost3D, @"app-pc-a", @"100") isEqualToProfile:host] &&
              [loadApp(SunlightStreamMode2D, @"app-pc-a", @"100") isEqualToProfile:appA],
              "one app retains separate 2D and Host 3D profiles");
        check([raw saveForMode:SunlightStreamModeRawHalfSBS hostUUID:@"app-pc-a" appID:@"100" defaults:defaults] &&
              [loadApp(SunlightStreamModeRawFullSBS, @"app-pc-a", @"100") isEqualToProfile:raw] &&
              [SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamModeRawFullSBS hostUUID:@"app-pc-a" appID:@"100" defaults:defaults],
              "legacy Raw Half aliases the same app-scoped Raw profile");
        check([SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamMode2D hostUUID:@"app-pc-a" appID:@"100" defaults:defaults] &&
              ![SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamMode2D hostUUID:@"app-pc-a" appID:@"300" defaults:defaults],
              "app override indicator distinguishes explicit records from legacy fallback");
        SunlightStreamQualityProfile *detachedApp = loadApp(SunlightStreamMode2D, @"app-pc-a", @"100");
        detachedApp.frameRate = 30;
        check([loadApp(SunlightStreamMode2D, @"app-pc-a", @"100") isEqualToProfile:appA],
              "loaded app drafts are detached until explicitly committed");
        check([SunlightStreamQualityProfile removeForMode:SunlightStreamMode2D hostUUID:@"app-pc-a" appID:@"100" defaults:defaults] &&
              ![SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamMode2D hostUUID:@"app-pc-a" appID:@"100" defaults:defaults] &&
              [loadApp(SunlightStreamMode2D, @"app-pc-a", @"100") isEqualToProfile:global2D],
              "app reset restores global defaults without reviving legacy PC mode");
        check([loadApp(SunlightStreamMode2D, @"app-pc-a", @"200") isEqualToProfile:appB] &&
              [loadApp(SunlightStreamMode2D, @"app-pc-b", @"100") isEqualToProfile:otherPCApp] &&
              [loadApp(SunlightStreamModeHost3D, @"app-pc-a", @"100") isEqualToProfile:host] &&
              [loadPC(SunlightStreamMode2D, @"app-pc-a") isEqualToProfile:legacyPC],
              "app reset preserves other apps, PCs, modes and the read-only legacy profile");
        global2D.bitRate = 42000;
        [global2D saveForMode:SunlightStreamMode2D defaults:defaults];
        check([loadApp(SunlightStreamMode2D, @"app-pc-a", @"100") isEqualToProfile:global2D] &&
              [loadApp(SunlightStreamMode2D, @"app-pc-a", @"300") isEqualToProfile:legacyPC],
              "reset app follows later global edits while untouched app retains legacy fallback");
        [defaults setObject:@{} forKey:key];
        check([loadApp(SunlightStreamMode2D, @"app-pc-a", @"100") isEqualToProfile:fallback],
              "reset app with invalid global record inherits the supplied global fallback");
        [global2D saveForMode:SunlightStreamMode2D defaults:defaults];
        check([SunlightStreamQualityProfile removeForMode:SunlightStreamMode2D hostUUID:@"app-pc-a" appID:@"300" defaults:defaults] &&
              [loadApp(SunlightStreamMode2D, @"app-pc-a", @"300") isEqualToProfile:global2D],
              "restore defaults works without a prior explicit app override");
        check([appA saveForMode:SunlightStreamMode2D hostUUID:@"app-pc-a" appID:@"100" defaults:defaults] &&
              [loadApp(SunlightStreamMode2D, @"app-pc-a", @"100") isEqualToProfile:appA],
              "explicit app save replaces the inheritance marker");
        NSString *appKey = [@"sunlight.streamQuality.2d.app." stringByAppendingFormat:@"%@.%@",
            [[@"app-pc-a" dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0],
            [[@"100" dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0]];
        NSArray *corruptAppRecords = @[@"broken", @{}, @{@"width": @1920},
            @{@"width": @1920, @"height": @1080, @"frameRate": @60, @"bitRate": @499},
            @{@"version": @2, @"inheritsGlobalDefaults": @YES},
            @{@"version": @1, @"inheritsGlobalDefaults": @"YES"},
            @{@"version": @1, @"inheritsGlobalDefaults": @1},
            @{@"version": @YES, @"inheritsGlobalDefaults": @YES},
            @{@"version": @1, @"inheritsGlobalDefaults": @YES, @"width": @0}];
        for (id record in corruptAppRecords) {
            [defaults setObject:record forKey:appKey];
            check(![SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamMode2D hostUUID:@"app-pc-a" appID:@"100" defaults:defaults] &&
                  [loadApp(SunlightStreamMode2D, @"app-pc-a", @"100") isEqualToProfile:legacyPC],
                  "malformed app tuple or reset marker safely falls through to legacy PC quality");
        }
        [appA saveForMode:SunlightStreamMode2D hostUUID:@"app-pc-a" appID:@"100" defaults:defaults];
        NSDictionary *beforeInvalidAppSaves = [defaults persistentDomainForName:suite];
        for (NSString *blank in @[@"", @" \n\t"]) {
            check(![appA saveForMode:SunlightStreamMode2D hostUUID:@"app-pc-a" appID:blank defaults:defaults] &&
                  ![SunlightStreamQualityProfile removeForMode:SunlightStreamMode2D hostUUID:@"app-pc-a" appID:blank defaults:defaults] &&
                  ![appA saveForMode:SunlightStreamMode2D hostUUID:blank appID:@"100" defaults:defaults] &&
                  ![SunlightStreamQualityProfile removeForMode:SunlightStreamMode2D hostUUID:blank appID:@"100" defaults:defaults],
                  "blank app or PC identity cannot save or reset a picture mode");
        }
        check(![appA saveForMode:(SunlightStreamMode)4 hostUUID:@"app-pc-a" appID:@"100" defaults:defaults] &&
              ![SunlightStreamQualityProfile removeForMode:(SunlightStreamMode)4 hostUUID:@"app-pc-a" appID:@"100" defaults:defaults] &&
              ![appA saveForMode:SunlightStreamMode2D hostUUID:@"app-pc-a" appID:nil defaults:defaults] &&
              ![SunlightStreamQualityProfile removeForMode:SunlightStreamMode2D hostUUID:nil appID:@"100" defaults:defaults] &&
              ![profile(1920,1080,60,499) saveForMode:SunlightStreamMode2D hostUUID:@"app-pc-a" appID:@"100" defaults:defaults] &&
              [[defaults persistentDomainForName:suite] isEqualToDictionary:beforeInvalidAppSaves],
              "invalid identities, modes and quality leave every app, PC and global record untouched");
        [appA saveForMode:SunlightStreamMode2D hostUUID:@"pc.app.a" appID:@"b" defaults:defaults];
        [appB saveForMode:SunlightStreamMode2D hostUUID:@"pc" appID:@"a.app.b" defaults:defaults];
        [otherPCApp saveForMode:SunlightStreamMode2D hostUUID:@"pc" appID:@"A.app.b" defaults:defaults];
        check([loadApp(SunlightStreamMode2D, @"pc.app.a", @"b") isEqualToProfile:appA] &&
              [loadApp(SunlightStreamMode2D, @"pc", @"a.app.b") isEqualToProfile:appB] &&
              [loadApp(SunlightStreamMode2D, @"pc", @"A.app.b") isEqualToProfile:otherPCApp],
              "encoded identity components avoid separator collisions and preserve app ID case");
        check([SunlightStreamQualityProfile removeForMode:SunlightStreamModeRawHalfSBS hostUUID:@"app-pc-a" appID:@"100" defaults:defaults] &&
              ![SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamModeRawFullSBS hostUUID:@"app-pc-a" appID:@"100" defaults:defaults] &&
              [loadApp(SunlightStreamModeRawFullSBS, @"app-pc-a", @"100") isEqualToProfile:load(SunlightStreamModeRawFullSBS)],
              "legacy Half app reset applies to the canonical Raw profile");
        [defaults removePersistentDomainForName:suite];
        testNativeResolution(defaults, suite);
        printf("STREAM_QUALITY_PROFILE_TESTS_RESULT: PASS (%u checks)\n", checks);
    }
    return 0;
}
