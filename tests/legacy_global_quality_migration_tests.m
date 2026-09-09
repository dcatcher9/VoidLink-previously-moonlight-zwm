// Compiled after the exact migration helper extracted from SettingsViewController.m.
#include <stdio.h>
#include <stdlib.h>

static unsigned checks;
static void check(BOOL passed, const char *message) {
    checks++;
    if (!passed) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
int main(void) {
    @autoreleasepool {
        NSString *suite = [@"sunlight-legacy-quality-tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        NSArray *globalKeys = @[@"sunlight.streamQuality.2d", @"sunlight.streamQuality.host3d", @"sunlight.streamQuality.raw3d"];
        NSDictionary *protectedRecords = @{
            @"sunlight.streamQuality.2d.pc.pc-a": @{@"width": @2560, @"height": @1440},
            @"sunlight.streamQuality.host3d.pc.pc-a": @{@"frameRate": @30},
            @"sunlight.streamQuality.raw3d.pc.pc-b": @{@"bitRate": @42500},
            @"sunlight.pc.shared.pc-a": @{@"preferredCodec": @1},
            @"sunlight.streamQuality.2d-extra": @"unrelated similar prefix",
            @"sunlight.preferTrackpad": @YES
        };
        void (^seed)(void) = ^{
            [defaults removePersistentDomainForName:suite];
            for (NSString *key in globalKeys) [defaults setObject:@{@"width": @1920, @"height": @1080} forKey:key];
            for (NSString *key in protectedRecords) [defaults setObject:protectedRecords[key] forKey:key];
        };
        NSArray *opening = @[@1, @0, @0, @1, @20000];
        NSArray *stored = @[@1920, @1080, @60, @20000];
        seed();
        NSDictionary *untouched = [defaults persistentDomainForName:suite];
        check(!SLClearLegacyGlobalQualityOverridesIfEdited(defaults, nil, opening, stored, stored),
              "initial UI construction cannot remove legacy profiles before a displayed baseline exists");
        check(!SLClearLegacyGlobalQualityOverridesIfEdited(defaults, opening, opening, stored, stored),
              "opening and closing without a quality change preserves legacy profiles");
        check(!SLClearLegacyGlobalQualityOverridesIfEdited(defaults, opening, opening, stored, @[@1920, @1080, @60, @21000]),
              "automatic value normalization without edited controls does not migrate");
        check(!SLClearLegacyGlobalQualityOverridesIfEdited(defaults, opening, opening, stored, @[@3840, @1080, @60, @20000]),
              "display geometry changes without quality edits do not migrate");
        check(!SLClearLegacyGlobalQualityOverridesIfEdited(defaults, opening, @[@5, @1920, @1080, @1, @20000], stored, stored),
              "switching to an equivalent custom resolution does not migrate unchanged saved quality");
        check([[defaults persistentDomainForName:suite] isEqualToDictionary:untouched],
              "unrelated settings saves preserve all existing keys exactly");
        NSArray *changedSelections = @[
            @[@2, @0, @0, @1, @20000], @[@5, @1920, @1200, @1, @20000],
            @[@1, @0, @0, @0, @20000], @[@1, @0, @0, @1, @25000]
        ];
        NSArray *changedQuality = @[
            @[@2560, @1440, @60, @20000], @[@1920, @1200, @60, @20000],
            @[@1920, @1080, @30, @20000], @[@1920, @1080, @60, @25000]
        ];
        for (NSUInteger i = 0; i < changedSelections.count; i++) {
            seed();
            check(SLClearLegacyGlobalQualityOverridesIfEdited(defaults, opening, changedSelections[i], stored, changedQuality[i]),
                  "an actual edited resolution, FPS or bitrate migrates legacy global defaults");
            for (NSString *key in globalKeys) check([defaults objectForKey:key] == nil, "exact old global mode key is removed");
            for (NSString *key in protectedRecords) check([[defaults objectForKey:key] isEqual:protectedRecords[key]],
                  "every PC-scoped or unrelated preference remains unchanged");
            check(!SLClearLegacyGlobalQualityOverridesIfEdited(defaults, changedSelections[i], changedSelections[i], changedQuality[i], changedQuality[i]),
                  "a later unrelated save using the updated baseline does not migrate again");
        }
        [defaults removePersistentDomainForName:suite];
        printf("LEGACY_GLOBAL_QUALITY_MIGRATION_TESTS_RESULT: PASS (%u checks)\n", checks);
    }
    return 0;
}
