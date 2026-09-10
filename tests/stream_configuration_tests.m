#import <Foundation/Foundation.h>
#import "StreamConfiguration.h"
#include <Limelight.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned checks;

static void check(BOOL passed, const char* description) {
    checks++;
    if (!passed) {
        fprintf(stderr, "FAIL: %s\n", description);
        exit(1);
    }
}

static StreamConfiguration* configuration(SunlightStreamMode mode) {
    StreamConfiguration* config = [StreamConfiguration new];
    config.streamMode = mode;
    config.width = 1920;
    config.height = 1080;
    config.appID = @"42";
    config.appName = @"Desktop";
    config.supportedVideoFormats = VIDEO_FORMAT_H264 | VIDEO_FORMAT_H265;
    config.serverCodecModeSupport = SCM_H264 | SCM_HEVC;
    return config;
}

static NSDictionary* query(StreamConfiguration* config, BOOL resume) {
    NSMutableDictionary* result = [NSMutableDictionary dictionary];
    for (NSURLQueryItem* item in [config sunlightLaunchQueryItemsForResume:resume]) {
        check(result[item.name] == nil, "query keys are unique");
        result[item.name] = item.value;
    }
    return result;
}

int main(void) {
    @autoreleasepool {
        NSString *suite = [@"sunlight.virtual-display-only-tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        check([StreamConfiguration virtualDisplayOnlyWithDefaults:defaults], "virtual-display-only defaults on for existing and new installs");
        check([defaults persistentDomainForName:suite].count == 0, "reading the new default does not persist an override");
        [StreamConfiguration setVirtualDisplayOnly:NO defaults:defaults];
        check(![StreamConfiguration virtualDisplayOnlyWithDefaults:defaults], "explicit off survives a reload");
        [StreamConfiguration setVirtualDisplayOnly:YES defaults:defaults];
        check([StreamConfiguration virtualDisplayOnlyWithDefaults:defaults], "explicit on survives a reload");
        for (id invalid in @[@"false", @2, @(-1), @0.5, @[], @{}]) {
            [defaults setObject:invalid forKey:@"sunlight.global.virtualDisplayOnly"];
            check([StreamConfiguration virtualDisplayOnlyWithDefaults:defaults], "malformed preference falls back to on");
        }
        [defaults removePersistentDomainForName:suite];

        for (NSNumber *mode in @[@(SunlightStreamMode2D), @(SunlightStreamModeHost3D), @(SunlightStreamModeRawFullSBS)]) {
            StreamConfiguration *display = configuration(mode.integerValue);
            check(display.virtualDisplayOnly && !display.virtualDisplayOnlySupported, "preference defaults on but host capability defaults off");
            for (NSNumber *resume in @[@NO, @YES]) {
                check(query(display, resume.boolValue)[@"virtualDisplayOnly"] == nil, "unsupported host receives no new launch or resume parameter");
            }
            display.virtualDisplayOnlySupported = YES;
            for (NSString *name in @[@"Desktop", @"Virtual Display"]) {
                display.appName = name;
                for (NSNumber *resume in @[@NO, @YES]) {
                    NSDictionary *enabled = query(display, resume.boolValue);
                    check([enabled[@"virtualDisplayOnly"] isEqualToString:@"1"] && enabled[@"virtualDisplay"] == nil,
                          "supported host receives enabled choice independently of app name and virtual creation flag");
                    display.virtualDisplayOnly = NO;
                    check([query(display, resume.boolValue)[@"virtualDisplayOnly"] isEqualToString:@"0"],
                          "supported host receives explicit off for launch and resume in every mode");
                    display.virtualDisplayOnly = YES;
                }
            }
            display.virtualDisplayOnlySupported = NO;
            check(query(display, YES)[@"virtualDisplayOnly"] == nil, "loss of capability suppresses previously enabled policy");
        }

        StreamConfiguration* flat = configuration(SunlightStreamMode2D);
        check(!flat.requiresMetalPresentation, "device-only 2D preserves the selected backend");
        flat.glassesOutputEnabled = YES;
        check(flat.requiresMetalPresentation && !flat.isStereoStream && flat.initialHostSbsMode == 0,
              "2D glasses use one Metal decoder consumer while transport remains mono");
        flat.glassesOutputEnabled = NO;
        check([flat prepareSunlightStreamWithHostSessionSupport:NO virtualDisplayCapable:NO virtualDisplayReady:NO] == nil,
              "ordinary Sunshine supports 2D without extension metadata");
        check(flat.width == 1920 && flat.height == 1080 && flat.logicalWidth == 1920,
              "2D source geometry is unchanged");
        check(!flat.isStereoStream && !flat.isRawSbsStream && flat.initialHostSbsMode == 0,
              "2D uses the ordinary presentation");
        check(query(flat, NO).count == 0, "ordinary host receives no Apollo controls");
        check([flat prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:YES virtualDisplayReady:YES] == nil,
              "Sunshine 3D supports ordinary 2D");
        check([query(flat, NO)[@"sbsMode"] isEqualToString:@"0"], "2D explicitly disables host conversion on capable hosts");
        check(query(flat, NO)[@"virtualDisplay"] == nil, "2D does not request virtual display creation");

        StreamConfiguration* host = configuration(SunlightStreamModeHost3D);
        check([host prepareSunlightStreamWithHostSessionSupport:NO virtualDisplayCapable:YES virtualDisplayReady:YES] != nil,
              "Host 3D cannot use virtual-display support as its conversion capability");
        host.enableYUV444 = YES;
        host.supportedVideoFormats |= VIDEO_FORMAT_H265_REXT8_444;
        check([host prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:NO virtualDisplayReady:NO] == nil,
              "Host 3D can convert a physical desktop");
        check(host.width == 1920 && host.height == 1080 && host.expectedPackedWidth == 3840 && host.expectedPackedHeight == 1080,
              "Host 3D requests mono source dimensions and expects a packed decoder image");
        check(host.initialHostSbsMode == 1 && [query(host, NO)[@"sbsMode"] isEqualToString:@"1"],
              "Host 3D requests exact sbsMode=1");
        check(!host.enableYUV444 && !(host.supportedVideoFormats & VIDEO_FORMAT_MASK_YUV444),
              "Host 3D negotiates the host's 4:2:0 conversion path");
        check(query(host, NO)[@"virtualDisplay"] == nil, "Host 3D does not require virtual display creation");

        StreamConfiguration* capped = configuration(SunlightStreamModeHost3D);
        capped.width = 5120;
        capped.height = 2160;
        check([capped prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:NO virtualDisplayReady:NO] == nil,
              "Host 3D leaves encoder fitting to host");
        check(capped.width == 5120 && capped.expectedPackedWidth == 8192 && capped.expectedPackedHeight == 1728,
              "Host 3D startup fallback scales both packed axes together");
        capped.logicalWidth = 2560;
        capped.logicalHeight = 1440;
        capped.supportedVideoFormats = VIDEO_FORMAT_H264;
        check([capped prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:NO virtualDisplayReady:NO] == nil,
              "Host 3D accepts H.264 within its fitted encoder envelope");
        check(capped.expectedPackedWidth == 4096 && capped.expectedPackedHeight == 1152,
              "H.264 fallback preserves per-eye proportions at the 4096 axis cap");

        const int supportedHostSizes[][2] = {
            {1280, 720}, {1920, 1080}, {2560, 1440}, {3840, 2160},
            {2560, 1080}, {3440, 1440}, {5120, 2160},
            {2160, 1080}, {2340, 1080}, {2400, 1080}, {2424, 1080},
            {1920, 1200}, {2560, 1600}, {2048, 1536}, {2732, 2048},
            {2160, 1440}, {2360, 1640}, {2388, 1668}, {2420, 1668},
            {1280, 800}, {2622, 1206},
        };
        for (size_t i = 0; i < sizeof(supportedHostSizes) / sizeof(supportedHostSizes[0]); i++) {
            int width = supportedHostSizes[i][0], height = supportedHostSizes[i][1];
            check([StreamConfiguration isSupportedHost3DWidth:width height:height],
                  "host calibrated landscape source is accepted");
            check([StreamConfiguration isSupportedHost3DWidth:height height:width],
                  "host calibrated portrait source is accepted");
        }
        const int unsupportedHostSizes[][2] = {
            {1920, 1536}, {1536, 1920}, {1920, 1920}, {3840, 1080},
            {640, 360}, {8192, 2048}, {5120, 2880}, {0, 1080}, {-1, 1080},
        };
        for (size_t i = 0; i < sizeof(unsupportedHostSizes) / sizeof(unsupportedHostSizes[0]); i++) {
            check(![StreamConfiguration isSupportedHost3DWidth:unsupportedHostSizes[i][0]
                height:unsupportedHostSizes[i][1]], "uncalibrated or over-budget Host 3D source is rejected");
        }
        StreamConfiguration* phoneNative = configuration(SunlightStreamModeHost3D);
        phoneNative.width = 2622;
        phoneNative.height = 1206;
        check(![phoneNative useCompatibleHost3DResolution] && phoneNative.width == 2622 && phoneNative.height == 1206,
              "updated host preserves the iPhone native source instead of falling back to 1080p");
        check([phoneNative prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:NO virtualDisplayReady:NO] == nil &&
              phoneNative.logicalWidth == 2622 && phoneNative.logicalHeight == 1206 &&
              phoneNative.expectedPackedWidth == 5244 && phoneNative.expectedPackedHeight == 1206,
              "native phone source is frozen consistently for HTTP, RTSP, and packed presentation");
        check([phoneNative prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:NO virtualDisplayReady:NO] == nil &&
              phoneNative.width == 2622 && phoneNative.height == 1206,
              "repeat native Host 3D preflight preserves source dimensions");
        StreamConfiguration* unsupported = configuration(SunlightStreamModeHost3D);
        unsupported.width = 1920;
        unsupported.height = 1536;
        check([unsupported prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:NO virtualDisplayReady:NO] != nil,
              "uncalibrated custom source still fails before HTTP launch");
        check([unsupported useCompatibleHost3DResolution] && unsupported.width == 1920 && unsupported.height == 1080,
              "uncalibrated custom source retains a compatible fallback");
        check(![unsupported useCompatibleHost3DResolution], "Host 3D fallback remains idempotent");
        phoneNative.streamMode = SunlightStreamMode2D;
        phoneNative.width = 2622;
        phoneNative.height = 1206;
        check(![phoneNative useCompatibleHost3DResolution] && phoneNative.width == 2622 && phoneNative.height == 1206,
              "Host 3D compatibility fallback does not change 2D phone dimensions");
        phoneNative.streamMode = SunlightStreamModeRawFullSBS;
        check(![phoneNative useCompatibleHost3DResolution] && phoneNative.width == 2622,
              "Host 3D compatibility fallback does not change raw desktop dimensions");

        StreamConfiguration* raw = configuration(SunlightStreamModeRawFullSBS);
        raw.logicalWidth = 3840;
        raw.logicalHeight = 1080;
        raw.requestVirtualDisplay = YES;
        check([raw prepareSunlightStreamWithHostSessionSupport:NO virtualDisplayCapable:NO virtualDisplayReady:NO] == nil,
              "already packed Raw content needs no host conversion or virtual-display capabilities");
        check([raw prepareSunlightStreamWithHostSessionSupport:NO virtualDisplayCapable:YES virtualDisplayReady:NO] == nil,
              "Raw physical desktop does not depend on a virtual-display driver");
        check([raw prepareSunlightStreamWithHostSessionSupport:NO virtualDisplayCapable:YES virtualDisplayReady:YES] == nil,
              "Raw works on original Apollo without host conversion controls");
        check(raw.width == 3840 && raw.height == 1080 && raw.logicalWidth == 3840 && raw.logicalHeight == 1080 &&
              raw.expectedPackedWidth == 3840 && raw.expectedPackedHeight == 1080,
              "Raw logical, HTTP, RTSP, input, and packed hints retain complete glasses dimensions");
        check([raw prepareSunlightStreamWithHostSessionSupport:NO virtualDisplayCapable:YES virtualDisplayReady:YES] == nil && raw.width == 3840,
              "repeat preflight never doubles Raw geometry");
        check(raw.initialHostSbsMode == 0 && query(raw, NO)[@"sbsMode"] == nil,
              "legacy Raw does not send host conversion controls");
        check(query(raw, NO).count == 0 && !raw.requestVirtualDisplay,
              "Raw clears stale display creation flags and sends no extensions to ordinary Sunshine");
        check([raw validateResumeWithRunningAppId:@"42" runningAppUUID:nil hostSessionId:nil] == nil,
              "Raw can resume an ordinary matching physical desktop");
        check([raw validateResumeWithRunningAppId:@"99" runningAppUUID:nil hostSessionId:nil] != nil,
              "Raw never bypasses ordinary app identity checks");
        check([raw prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:NO virtualDisplayReady:NO] == nil,
              "Sunshine 3D physical desktop also supports exact Raw passthrough");
        check(query(raw, NO)[@"virtualDisplay"] == nil && [query(raw, NO)[@"sbsMode"] isEqualToString:@"0"],
              "Raw disables capable host conversion without requesting another display");
        check([raw validateResumeWithRunningAppId:@"42" runningAppUUID:nil hostSessionId:@"1234"] == nil,
              "Raw can resume the same capable host app without inferring display backing");
        check([query(raw, YES)[@"hostSessionId"] isEqualToString:@"1234"],
              "resume binds the fresh matching session token");
        check([raw validateResumeWithRunningAppId:@"42" runningAppUUID:nil hostSessionId:@"5678"] != nil,
              "Raw cannot replace its retained host session during reconnect");
        check([raw validateResumeWithRunningAppId:@"99" runningAppUUID:nil hostSessionId:@"1234"] != nil,
              "Raw cannot resume another app even when its token matches");
        check([raw validateHostSessionResponse:@"5678" resuming:YES] != nil,
              "Raw rejects a changed token in the resume response");
        raw.appName = @" Virtual Display ";
        check([raw prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:NO virtualDisplayReady:NO] == nil &&
              query(raw, NO)[@"virtualDisplay"] == nil,
              "explicit Virtual Display app uses the same Raw contract without special capability guards");

        StreamConfiguration* half = configuration(SunlightStreamModeRawHalfSBS);
        half.logicalWidth = 3840;
        half.logicalHeight = 1080;
        check([half prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:NO virtualDisplayReady:NO] == nil,
              "legacy Raw Half accepts supplied glasses dimensions");
        check(half.streamMode == SunlightStreamModeRawFullSBS && half.width == 3840 && half.height == 1080 &&
              half.expectedPackedWidth == 3840 && half.isRawSbsStream,
              "legacy Half normalizes to canonical Raw without squeezing or doubling its complete frame");
        raw.serverCodecModeSupport = SCM_H264;
        check([raw prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:NO virtualDisplayReady:NO] == nil && raw.width == 3840,
              "3840-pixel glasses Raw fits H.264 without artificial width doubling");
        raw.logicalWidth = 7680;
        check([raw prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:YES virtualDisplayReady:YES] != nil,
              "Raw must not silently fit a 7680-pixel glasses frame into an H.264 desktop");
        raw.serverCodecModeSupport = SCM_H264 | SCM_HEVC;
        check([raw prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:YES virtualDisplayReady:YES] == nil && raw.width == 7680,
              "Raw preserves exact packed source width with a compatible HEVC host");
        raw.logicalWidth = 8194;
        check([raw prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:YES virtualDisplayReady:YES] != nil,
              "Raw rejects packed width over 8192 rather than changing source geometry");
        raw.logicalWidth = 3840;
        raw.logicalHeight = 8194;
        check([raw prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:NO virtualDisplayReady:NO] != nil,
              "Raw codec limit also protects packed height");

        StreamConfiguration* invalid = configuration((SunlightStreamMode)99);
        check([invalid prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:YES virtualDisplayReady:YES] != nil,
              "unknown saved mode is rejected");
        invalid.streamMode = SunlightStreamMode2D;
        invalid.width = 0;
        check([invalid prepareSunlightStreamWithHostSessionSupport:NO virtualDisplayCapable:NO virtualDisplayReady:NO] != nil,
              "zero resolution is rejected before request");
        invalid.width = 1919;
        check([invalid prepareSunlightStreamWithHostSessionSupport:NO virtualDisplayCapable:NO virtualDisplayReady:NO] == nil && invalid.width == 1919,
              "ordinary 2D preserves existing odd device resolutions");
        invalid.streamMode = SunlightStreamModeHost3D;
        invalid.logicalWidth = 1919;
        invalid.logicalHeight = 1081;
        check([invalid prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:NO virtualDisplayReady:NO] == nil &&
              invalid.width == 1919 && invalid.height == 1081 &&
              invalid.expectedPackedWidth == 3836 && invalid.expectedPackedHeight == 1080,
              "Host 3D preserves odd logical source while host aligns each encoded eye to chroma cells");
        invalid.streamMode = SunlightStreamModeRawFullSBS;
        check([invalid prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:YES virtualDisplayReady:YES] != nil,
              "Raw still rejects odd complete packed geometry");
        invalid.streamMode = SunlightStreamModeRawHalfSBS;
        check([invalid prepareSunlightStreamWithHostSessionSupport:YES virtualDisplayCapable:YES virtualDisplayReady:YES] != nil,
              "legacy Half normalization preserves Raw even-pixel validation");

        check([StreamConfiguration normalizedHostSessionId:@" 001234 "] != nil &&
              [[StreamConfiguration normalizedHostSessionId:@" 001234 "] isEqualToString:@"1234"],
              "session identifiers normalize decimal whitespace and leading zeroes");
        check([StreamConfiguration normalizedHostSessionId:@"18446744073709551615"] != nil,
              "maximum UInt64 session identifier is preserved");
        for (NSString* token in @[@"0", @"", @"-1", @"1junk", @"18446744073709551616"]) {
            check([StreamConfiguration normalizedHostSessionId:token] == nil,
                  "empty, zero, malformed, and overflowing session identifiers are rejected");
        }
        check([flat validateResumeWithRunningAppId:@"99" runningAppUUID:nil hostSessionId:@"1234"] != nil,
              "resuming a different app is rejected");
        check([flat validateResumeWithRunningAppId:@"42" runningAppUUID:nil hostSessionId:nil] != nil,
              "capable host resume requires its session token");
        check([flat validateResumeWithRunningAppId:@"42" runningAppUUID:nil hostSessionId:@"1234"] == nil,
              "fresh matching app selection binds the server token");
        check([flat validateResumeWithRunningAppId:@"42" runningAppUUID:nil hostSessionId:@"5678"] != nil,
              "a later changed session never replaces the bound token");
        check(query(flat, NO)[@"hostSessionId"] == nil, "launch never includes a retained session token");
        check([flat validateHostSessionResponse:@"5678" resuming:YES] != nil,
              "resume response cannot claim another session");
        check([flat validateHostSessionResponse:nil resuming:NO] != nil,
              "capable launch response must include nonzero session token");
        check([flat validateHostSessionResponse:@"1234" resuming:YES] == nil && [flat.hostSessionId isEqualToString:@"1234"],
              "validated response token is retained for follow-up operations");
        flat.appUUID = @"AbCd";
        check([flat validateResumeWithRunningAppId:@"77" runningAppUUID:@"abcd" hostSessionId:@"1234"] == nil,
              "UUID identifies the same application after numeric app ID reassignment");
        check([flat validateResumeWithRunningAppId:@"42" runningAppUUID:@"other" hostSessionId:@"1234"] != nil,
              "conflicting UUID cannot be hidden by a reused numeric app ID");
        flat.hostSessionIdSupported = NO;
        flat.appUUID = nil;
        check([flat validateResumeWithRunningAppId:@"42" runningAppUUID:nil hostSessionId:nil] == nil &&
              [flat validateHostSessionResponse:nil resuming:YES] == nil,
              "ordinary Sunshine retains legacy app-based resume without tokens");
        printf("STREAM_CONFIGURATION_TESTS_RESULT: PASS (%u checks)\n", checks);
    }
    return 0;
}
