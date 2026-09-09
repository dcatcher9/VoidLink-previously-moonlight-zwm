#import <Foundation/Foundation.h>
#import "SunlightMachineControlsSettings.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned checks;
static void check(BOOL passed, const char *message) {
    checks++;
    if (!passed) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
int main(void) {
    @autoreleasepool {
        NSString *suite = [@"sunlight-machine-controls-tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        [defaults removePersistentDomainForName:suite];
        SunlightMachineControlsSettings *global = [SunlightMachineControlsSettings new];
        check(global.controlMode == SunlightMachineControlModeTrackpad && global.touchEnabled &&
              global.localVolume == 1 && !global.statsOverlayEnabled, "new defaults match familiar enabled trackpad with full volume and no statistics");
        global.localVolume = 0.67; global.statsOverlayLevel = 2;
        SunlightMachineControlsSettings *(^load)(NSString *) = ^(NSString *uuid) {
            return [SunlightMachineControlsSettings settingsForHostUUID:uuid defaults:defaults globalDefaults:global];
        };
        SunlightMachineControlsSettings *pcA = load(@"pc-a");
        check(pcA != global && [pcA isEqualToSettings:global], "new PC gets a detached copy of global fallback");
        check([defaults persistentDomainForName:suite].count == 0, "reads do not persist implicit overrides");
        pcA.controlMode = SunlightMachineControlModeGamepad;
        check(global.controlMode == SunlightMachineControlModeTrackpad, "draft edits leave globals untouched");
        check([pcA saveForHostUUID:@"  PC-A\n" defaults:defaults globalDefaults:global], "save normalizes host UUID");
        NSString *keyA = @"sunlight.pc.controls.pc-a";
        check([[defaults dictionaryForKey:keyA] isEqualToDictionary:@{@"controlMode": @2}], "only explicit differences are stored");
        check([load(@"pc-a") isEqualToSettings:pcA] && [load(@"pc-b") isEqualToSettings:global], "PC overrides do not leak to other machines");
        global.localVolume = 0.22; global.touchEnabled = NO; global.statsOverlayLevel = 1;
        SunlightMachineControlsSettings *following = load(@"pc-a");
        check(following.controlMode == SunlightMachineControlModeGamepad && following.localVolume == 0.22 &&
              !following.touchEnabled && following.statsOverlayLevel == 1, "unoverridden fields follow later global changes independently");
        check([load(@"pc-b") isEqualToSettings:global], "unconfigured PC follows all global fields");
        SunlightMachineControlsSettings *pcB = [global copy]; pcB.localVolume = 0; pcB.statsOverlayLevel = 0;
        check([pcB saveForHostUUID:@"pc-b" defaults:defaults globalDefaults:global], "second PC saves muted sound and hidden statistics");
        check([load(@"pc-b") isEqualToSettings:pcB] && load(@"pc-a").localVolume == 0.22, "explicit zero volume is valid and host-local");
        SunlightMachineControlsSettings *copy = [pcB copy]; copy.touchEnabled = YES;
        check(!pcB.touchEnabled && ![copy isEqualToSettings:pcB] && [pcB isEqualToSettings:[pcB copy]] &&
              ![pcB isEqualToSettings:nil], "copy and equality cover every primitive without aliasing");
        copy.statsOverlayLevel = 2; copy.statsOverlayEnabled = YES;
        check(copy.statsOverlayLevel == 2 && copy.statsOverlayEnabled, "enabling statistics preserves Detailed level");
        copy.statsOverlayEnabled = NO;
        check(copy.statsOverlayLevel == 0, "disabling statistics selects Off");
        copy.statsOverlayEnabled = YES;
        check(copy.statsOverlayLevel == 1, "enabling statistics from Off selects existing Simplified level");

        NSDictionary *valid = @{@"controlMode": @1, @"touchEnabled": @YES, @"localVolume": @0.5, @"statsOverlayLevel": @2};
        [defaults setObject:valid forKey:keyA];
        SunlightMachineControlsSettings *all = load(@"pc-a");
        check(all.controlMode == SunlightMachineControlModeSavedTouchProfile && all.touchEnabled &&
              all.localVolume == 0.5 && all.statsOverlayLevel == 2, "all valid fields load including the selected saved profile mode");
        NSDictionary *invalidValues = @{
            @"controlMode": @[@(-1), @3, @1.5, @YES, @"1", @(NAN)],
            @"touchEnabled": @[@(-1), @2, @0.5, @"true", @(INFINITY)],
            @"localVolume": @[@(-0.01), @1.01, @YES, @"0.5", @(NAN), @(INFINITY)],
            @"statsOverlayLevel": @[@(-1), @3, @1.5, @NO, @"2", @(NAN)]
        };
        for (NSString *field in invalidValues) {
            for (id invalid in invalidValues[field]) {
                NSMutableDictionary *record = [valid mutableCopy]; record[field] = invalid;
                [defaults setObject:record forKey:keyA];
                SunlightMachineControlsSettings *expected = [all copy];
                [expected setValue:[global valueForKey:field] forKey:field];
                check([load(@"pc-a") isEqualToSettings:expected], "invalid stored field inherits without discarding other valid fields");
            }
        }
        for (id invalidRecord in @[@"bad", @[], @23]) {
            [defaults setObject:invalidRecord forKey:keyA];
            check([load(@"pc-a") isEqualToSettings:global], "invalid container inherits all global defaults");
        }
        [defaults setObject:@{@"profileName": @"invented profile", @"appID": @123, @"bitrate": @90000, @"statsOverlayEnabled": @YES} forKey:keyA];
        check([load(@"pc-a") isEqualToSettings:global], "unknown profile/app/quality fields cannot enter machine controls store");
        [defaults setObject:valid forKey:keyA];
        NSDictionary *beforeBadSave = [defaults persistentDomainForName:suite];
        for (NSString *field in @[@"controlMode", @"statsOverlayLevel", @"localVolume"]) {
            for (NSNumber *invalid in @[@(-1), @99]) {
                SunlightMachineControlsSettings *draft = [global copy]; [draft setValue:invalid forKey:field];
                check(![draft saveForHostUUID:@"pc-a" defaults:defaults globalDefaults:global] &&
                      [[defaults persistentDomainForName:suite] isEqualToDictionary:beforeBadSave], "invalid draft cannot replace the last committed machine settings");
            }
        }
        for (NSNumber *invalid in @[@(NAN), @(INFINITY)]) {
            SunlightMachineControlsSettings *draft = [global copy]; draft.localVolume = invalid.doubleValue;
            check(![draft saveForHostUUID:@"pc-a" defaults:defaults globalDefaults:global], "nonfinite volume cannot be saved");
        }
        for (NSString *blank in @[@"", @" \n\t"]) {
            check(![all saveForHostUUID:blank defaults:defaults globalDefaults:global] &&
                  ![SunlightMachineControlsSettings removeForHostUUID:blank defaults:defaults] &&
                  [load(blank) isEqualToSettings:global], "blank identities may inherit but never save or reset");
        }
        check(![all saveForHostUUID:nil defaults:defaults globalDefaults:global] &&
              ![SunlightMachineControlsSettings removeForHostUUID:nil defaults:defaults] &&
              [load(nil) isEqualToSettings:global], "nil identity has the same safe inheritance contract");

        [defaults setObject:@{@"preferredCodec": @2} forKey:@"sunlight.pc.shared.pc-a"];
        [defaults setObject:@{@"width": @1920} forKey:@"sunlight.picture.pc-a.app-1.host3d"];
        NSDictionary *sharedBefore = [defaults dictionaryForKey:@"sunlight.pc.shared.pc-a"];
        NSDictionary *pictureBefore = [defaults dictionaryForKey:@"sunlight.picture.pc-a.app-1.host3d"];
        check([SunlightMachineControlsSettings removeForHostUUID:@"PC-A" defaults:defaults] && [load(@"pc-a") isEqualToSettings:global], "reset removes only this machine control override");
        check([load(@"pc-b") isEqualToSettings:pcB] &&
              [[defaults dictionaryForKey:@"sunlight.pc.shared.pc-a"] isEqualToDictionary:sharedBefore] &&
              [[defaults dictionaryForKey:@"sunlight.picture.pc-a.app-1.host3d"] isEqualToDictionary:pictureBefore], "machine reset preserves another PC, shared transport and app picture records");
        check([global saveForHostUUID:@"pc-b" defaults:defaults globalDefaults:global] && [defaults objectForKey:@"sunlight.pc.controls.pc-b"] == nil,
              "saving exact global defaults removes redundant machine record");
        global.localVolume = (double)(float)0.67;
        SunlightMachineControlsSettings *rounded = [global copy]; rounded.localVolume = 0.67;
        check([rounded isEqualToSettings:global] && [rounded saveForHostUUID:@"roundtrip-pc" defaults:defaults globalDefaults:global] &&
              [defaults objectForKey:@"sunlight.pc.controls.roundtrip-pc"] == nil,
              "legacy Float roundtrip does not create a volume override or break global inheritance");
        global.localVolume = 0.8;
        check(load(@"roundtrip-pc").localVolume == 0.8, "equivalent displayed volume still follows future global changes");
        global.controlMode = 99; global.localVolume = NAN; global.statsOverlayLevel = 99;
        SunlightMachineControlsSettings *normalized = load(@"new-pc");
        check(normalized.controlMode == SunlightMachineControlModeTrackpad && normalized.localVolume == 1 && normalized.statsOverlayLevel == 0,
              "corrupt inherited values normalize safely without persistence");
        check(global.controlMode == 99 && isnan(global.localVolume) && global.statsOverlayLevel == 99,
              "normalizing fallback never edits its source object");
        SunlightMachineControlsSettings *legacy = [SunlightMachineControlsSettings new];
        legacy.controlMode = SunlightMachineControlModeSavedTouchProfile; legacy.localVolume = 0.81; legacy.statsOverlayLevel = 1;
        SunlightMachineControlsSettings *globalDraft = [legacy copy];
        globalDraft.controlMode = SunlightMachineControlModeGamepad; globalDraft.touchEnabled = NO;
        globalDraft.localVolume = 0.13; globalDraft.statsOverlayLevel = 2;
        NSDictionary *beforeGlobalSave = [defaults persistentDomainForName:suite];
        check([globalDraft saveGlobalControlsToDefaults:defaults], "global input defaults save through a validated model API");
        NSMutableDictionary *expectedGlobalSave = [beforeGlobalSave mutableCopy];
        expectedGlobalSave[@"sunlight.global.controls"] = @{@"controlMode": @2, @"touchEnabled": @NO};
        check([[defaults persistentDomainForName:suite] isEqualToDictionary:expectedGlobalSave],
              "global input save owns exactly two fields and never changes PC/app/volume/statistics records");
        SunlightMachineControlsSettings *resolvedGlobal = [SunlightMachineControlsSettings globalControlsWithDefaults:defaults fallback:legacy];
        check(resolvedGlobal.controlMode == SunlightMachineControlModeGamepad && !resolvedGlobal.touchEnabled &&
              resolvedGlobal.localVolume == legacy.localVolume && resolvedGlobal.statsOverlayLevel == legacy.statsOverlayLevel,
              "global input overrides preserve the current Local audio and statistics fallback");
        check(legacy.controlMode == SunlightMachineControlModeSavedTouchProfile && legacy.touchEnabled,
              "global input reads leave the legacy fallback object unchanged");
        legacy.localVolume = 0.37; legacy.statsOverlayLevel = 0;
        resolvedGlobal = [SunlightMachineControlsSettings globalControlsWithDefaults:defaults fallback:legacy];
        check(resolvedGlobal.localVolume == 0.37 && resolvedGlobal.statsOverlayLevel == 0 && resolvedGlobal.controlMode == SunlightMachineControlModeGamepad,
              "later global audio/statistics edits are never shadowed by global input defaults");
        globalDraft.controlMode = 99;
        check(![globalDraft saveGlobalControlsToDefaults:defaults] && [[defaults persistentDomainForName:suite] isEqualToDictionary:expectedGlobalSave],
              "invalid global control mode cannot replace previously saved defaults");
        for (id invalidMode in @[@YES, @(-1), @3, @1.5, @"2"]) {
            [defaults setObject:@{@"controlMode": invalidMode, @"touchEnabled": @NO, @"localVolume": @0, @"statsOverlayLevel": @2} forKey:@"sunlight.global.controls"];
            resolvedGlobal = [SunlightMachineControlsSettings globalControlsWithDefaults:defaults fallback:legacy];
            check(resolvedGlobal.controlMode == legacy.controlMode && !resolvedGlobal.touchEnabled && resolvedGlobal.localVolume == legacy.localVolume &&
                  resolvedGlobal.statsOverlayLevel == legacy.statsOverlayLevel, "malformed global mode inherits independently and unowned fields are ignored");
        }
        for (id invalidTouch in @[@2, @(-1), @0.5, @"true"]) {
            [defaults setObject:@{@"controlMode": @0, @"touchEnabled": invalidTouch} forKey:@"sunlight.global.controls"];
            resolvedGlobal = [SunlightMachineControlsSettings globalControlsWithDefaults:defaults fallback:legacy];
            check(resolvedGlobal.controlMode == SunlightMachineControlModeTrackpad && resolvedGlobal.touchEnabled == legacy.touchEnabled,
                  "malformed global touch availability inherits without discarding a valid control mode");
        }
        for (id invalidRecord in @[@"bad", @42, @[]]) {
            [defaults setObject:invalidRecord forKey:@"sunlight.global.controls"];
            check([[SunlightMachineControlsSettings globalControlsWithDefaults:defaults fallback:legacy] isEqualToSettings:legacy],
                  "malformed global record falls back to legacy defaults");
        }
        [defaults removeObjectForKey:@"sunlight.global.controls"];
        check([[SunlightMachineControlsSettings globalControlsWithDefaults:defaults fallback:legacy] isEqualToSettings:legacy],
              "existing installations retain legacy control preference until global input is explicitly saved");
        [defaults removePersistentDomainForName:suite];
        printf("PASS %u machine controls settings checks\n", checks);
    }
    return 0;
}
