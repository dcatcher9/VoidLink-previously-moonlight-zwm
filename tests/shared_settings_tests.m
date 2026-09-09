#import <Foundation/Foundation.h>
#import "SunlightSharedSettings.h"
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
        NSString *suite = [@"sunlight-shared-tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        [defaults removePersistentDomainForName:suite];
        SunlightSharedSettings *global = [SunlightSharedSettings new];
        global.preferredCodec = 2; global.framePacingMode = 2; global.audioConfig = 2;
        global.enableHdr = NO; global.fullColorRange = YES; global.playAudioOnPC = NO;
        SunlightSharedSettings *(^load)(NSString *) = ^(NSString *uuid) {
            return [SunlightSharedSettings settingsForHostUUID:uuid defaults:defaults globalDefaults:global];
        };
        SunlightSharedSettings *pcA = load(@"pc-a");
        check(pcA != global && [pcA isEqualToSettings:global], "new PC returns detached global defaults");
        check([defaults persistentDomainForName:suite].count == 0, "loading never writes inherited settings");
        pcA.preferredCodec = 1;
        check(global.preferredCodec == 2 && ![pcA isEqualToSettings:global], "editing PC draft cannot change global object");
        check([pcA saveForHostUUID:@"  PC-A\n" defaults:defaults globalDefaults:global], "PC save trims and lowercases stable UUID");
        NSString *keyA = @"sunlight.pc.shared.pc-a";
        check([[defaults dictionaryForKey:keyA] isEqualToDictionary:@{@"preferredCodec": @1}],
              "save persists only differing fields so other values continue inheriting");
        check([load(@"pc-a") isEqualToSettings:pcA] && [load(@"pc-b") isEqualToSettings:global],
              "saved PC override does not affect another PC");
        global.framePacingMode = 1; global.audioConfig = 8; global.enableHdr = YES;
        global.fullColorRange = NO; global.playAudioOnPC = YES; global.preferredCodec = 3;
        SunlightSharedSettings *inherited = load(@"PC-A");
        check(inherited.preferredCodec == 1 && inherited.framePacingMode == 1 && inherited.audioConfig == 8 &&
              inherited.enableHdr && !inherited.fullColorRange && inherited.playAudioOnPC,
              "later global edits reach each inherited field while explicit codec stays fixed");
        check([load(@"pc-b") isEqualToSettings:global], "PC without overrides follows every global change");
        SunlightSharedSettings *pcB = [global copy]; pcB.audioConfig = 6; pcB.enableHdr = NO;
        check([pcB saveForHostUUID:@"pc-b" defaults:defaults globalDefaults:global], "second PC saves independent audio and HDR overrides");
        check([[defaults dictionaryForKey:@"sunlight.pc.shared.pc-b"] isEqualToDictionary:@{@"audioConfig": @6, @"enableHdr": @NO}],
              "second PC record also contains only explicit differences");
        SunlightSharedSettings *copy = [pcB copy]; copy.playAudioOnPC = NO;
        check(pcB.playAudioOnPC && ![pcB isEqualToSettings:copy] && [pcB isEqualToSettings:[pcB copy]] &&
              ![pcB isEqualToSettings:nil], "copy isolation and equality cover independent mutable drafts");

        NSDictionary *validOverride = @{@"preferredCodec": @1, @"framePacingMode": @3, @"audioConfig": @3,
                                        @"enableHdr": @NO, @"fullColorRange": @YES, @"playAudioOnPC": @NO};
        [defaults setObject:validOverride forKey:keyA];
        SunlightSharedSettings *all = load(@"pc-a");
        check(all.preferredCodec == 1 && all.framePacingMode == 3 && all.audioConfig == 3 && !all.enableHdr &&
              all.fullColorRange && !all.playAudioOnPC, "all six supported fields load, including alternate stereo value3");
        NSDictionary *badValues = @{
            @"preferredCodec": @[@(-1), @4, @1.5, @YES, @"2", @(NAN)],
            @"framePacingMode": @[@(-1), @4, @1.5, @NO],
            @"audioConfig": @[@1, @4, @5, @7, @9, @6.5, @YES, @"6"],
            @"enableHdr": @[@(-1), @2, @0.5, @"true", @(INFINITY)],
            @"fullColorRange": @[@(-1), @2, @0.5, @"false"],
            @"playAudioOnPC": @[@(-1), @2, @0.5, @"1"]
        };
        for (NSString *field in badValues) {
            for (id bad in badValues[field]) {
                NSMutableDictionary *record = [validOverride mutableCopy]; record[field] = bad;
                [defaults setObject:record forKey:keyA];
                SunlightSharedSettings *expected = [all copy];
                [expected setValue:[global valueForKey:field] forKey:field];
                check([load(@"pc-a") isEqualToSettings:expected],
                      "invalid stored field inherits its global value without rejecting other valid overrides");
            }
        }
        for (id badRecord in @[@"bad", @[], @23]) {
            [defaults setObject:badRecord forKey:keyA];
            check([load(@"pc-a") isEqualToSettings:global], "invalid shared container inherits complete globals");
        }
        [defaults setObject:@{@"localVolume": @0, @"touchMode": @3, @"hostSessionId": @1234} forKey:keyA];
        check([load(@"pc-a") isEqualToSettings:global], "unlisted fields cannot override settings or add session expiration");
        [defaults setObject:validOverride forKey:keyA];
        NSDictionary *beforeInvalidSave = [defaults persistentDomainForName:suite];
        for (NSString *field in @[@"preferredCodec", @"framePacingMode", @"audioConfig"]) {
            SunlightSharedSettings *invalid = [global copy]; [invalid setValue:@99 forKey:field];
            check(![invalid saveForHostUUID:@"pc-a" defaults:defaults globalDefaults:global] &&
                  [[defaults persistentDomainForName:suite] isEqualToDictionary:beforeInvalidSave],
                  "invalid draft enum cannot replace committed PC fields");
        }
        for (NSString *blank in @[@"", @" \n\t"]) {
            check(![all saveForHostUUID:blank defaults:defaults globalDefaults:global] &&
                  ![SunlightSharedSettings removeForHostUUID:blank defaults:defaults] &&
                  [load(blank) isEqualToSettings:global], "blank identity reads globals but cannot save or reset");
        }
        check(![all saveForHostUUID:nil defaults:defaults globalDefaults:global] &&
              ![SunlightSharedSettings removeForHostUUID:nil defaults:defaults] &&
              [[defaults persistentDomainForName:suite] isEqualToDictionary:beforeInvalidSave], "missing UUID cannot mutate global or PC records");
        check([SunlightSharedSettings removeForHostUUID:@" PC-A " defaults:defaults] &&
              [load(@"pc-a") isEqualToSettings:global] && [load(@"pc-b") isEqualToSettings:pcB],
              "reset restores inheritance for one PC without altering another");
        check([global saveForHostUUID:@"pc-b" defaults:defaults globalDefaults:global] &&
              [defaults objectForKey:@"sunlight.pc.shared.pc-b"] == nil,
              "saving values equal to globals removes the override rather than pinning inherited fields");
        for (NSInteger codec = 0; codec <= 3; codec++) {
            for (NSInteger pacing = 0; pacing <= 3; pacing++) {
                SunlightSharedSettings *settings = [global copy]; settings.preferredCodec = codec; settings.framePacingMode = pacing;
                check([settings saveForHostUUID:@"pc-a" defaults:defaults globalDefaults:global] &&
                      [load(@"pc-a") isEqualToSettings:settings], "all defined codec/pacing values round trip");
            }
        }
        for (NSNumber *audio in @[@2, @3, @6, @8]) {
            SunlightSharedSettings *settings = [global copy]; settings.audioConfig = audio.integerValue;
            check([settings saveForHostUUID:@"pc-a" defaults:defaults globalDefaults:global] &&
                  [load(@"pc-a") isEqualToSettings:settings], "exact Settings UI audio values round trip");
        }
        SunlightSharedSettings *invalidGlobal = [global copy];
        invalidGlobal.preferredCodec = 99; invalidGlobal.framePacingMode = -1; invalidGlobal.audioConfig = 7;
        SunlightSharedSettings *sanitized = [SunlightSharedSettings settingsForHostUUID:@"new-pc" defaults:defaults globalDefaults:invalidGlobal];
        check(sanitized.preferredCodec == 0 && sanitized.framePacingMode == 2 && sanitized.audioConfig == 2 &&
              invalidGlobal.preferredCodec == 99, "malformed inherited enums get safe detached defaults without mutating globals");
        [defaults removePersistentDomainForName:suite];
        printf("SHARED_SETTINGS_TESTS_RESULT: PASS (%u checks)\n", checks);
    }
    return 0;
}
