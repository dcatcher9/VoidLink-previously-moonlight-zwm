#import "SunlightStreamQualitySession.h"

static int checks;
#define Check(condition) do { checks++; if (!(condition)) { NSLog(@"FAIL line %d: %s", __LINE__, #condition); exit(1); } } while (0)

static SunlightStreamQualityProfile *Quality(int width, int height, int fps, int bitrate, BOOL native) {
    SunlightStreamQualityProfile *p = [SunlightStreamQualityProfile new];
    p.width = width; p.height = height; p.frameRate = fps; p.bitRate = bitrate; p.usesNativeResolution = native;
    return p;
}

static SunlightStreamQualitySession *Session(StreamConfiguration *config, NSUserDefaults *defaults,
    SunlightStreamQualityProfile *fallback, NSDictionary *drafts, NSSet *resets) {
    SunlightStreamQualitySession *s = [[SunlightStreamQualitySession alloc] initWithConfiguration:config defaults:defaults
        fallback:fallback nativeSize:CGSizeMake(2622, 1206) drafts:drafts resetModes:resets];
    s.outputSize = CGSizeMake(3840, 1080);
    return s;
}

int main(void) { @autoreleasepool {
    NSString *suite = [@"sunlight.tests.session." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    StreamConfiguration *config = [StreamConfiguration new];
    config.hostUUID = @"pc-a"; config.appID = @"app-a"; config.streamMode = SunlightStreamMode2D;
    config.width = config.logicalWidth = 2622; config.height = config.logicalHeight = 1206;
    config.frameRate = 120; config.bitRate = 35000;
    SunlightStreamQualityProfile *fallback = Quality(1920, 1080, 120, 35000, YES);
    SunlightStreamQualitySession *session = Session(config, defaults, fallback, nil, nil);
    NSDictionary *before = [defaults persistentDomainForName:suite] ?: @{};
    SunlightStreamQualityProfile *active = [session profileForMode:SunlightStreamMode2D includingPending:NO];
    Check(active.width == 2622 && active.height == 1206 && active.frameRate == 120 && active.usesNativeResolution);
    active.width = 100;
    Check([session profileForMode:SunlightStreamMode2D includingPending:NO].width == 2622);
    config.width = config.logicalWidth = 1280; config.frameRate = 30; fallback.width = 640;
    Check([session profileForMode:SunlightStreamMode2D includingPending:NO].width == 2622);
    StreamConfiguration *host = [session configurationForMode:SunlightStreamModeHost3D includingPending:NO];
    Check(host.width == 2622 && host.height == 1206 && host.frameRate == 60);
    Check(host.logicalWidth == host.width && host.logicalHeight == host.height);
    Check([[defaults persistentDomainForName:suite] ?: @{} isEqual:before]);

    [session stageWidth:1920 height:1080 frameRate:60 bitRate:25000 usesNativeResolution:NO forMode:SunlightStreamMode2D];
    Check([session hasPendingChangesForMode:SunlightStreamMode2D]);
    Check(![session hasPendingChangesForMode:SunlightStreamModeHost3D]);
    Check([session profileForMode:SunlightStreamMode2D includingPending:YES].width == 1920);
    Check([session profileForMode:SunlightStreamMode2D includingPending:NO].width == 2622);
    [session stageWidth:0 height:1080 frameRate:60 bitRate:25000 usesNativeResolution:NO forMode:SunlightStreamMode2D];
    Check([session profileForMode:SunlightStreamMode2D includingPending:YES].width == 1920);
    Check([[defaults persistentDomainForName:suite] ?: @{} isEqual:before]);
    [session stageWidth:2622 height:1206 frameRate:120 bitRate:35000 usesNativeResolution:YES forMode:SunlightStreamMode2D];
    Check(![session hasPendingChangesForMode:SunlightStreamMode2D]);
    [session stageWidth:2622 height:1206 frameRate:120 bitRate:35000 usesNativeResolution:NO forMode:SunlightStreamMode2D];
    Check([session hasPendingChangesForMode:SunlightStreamMode2D]);
    Check(![session profileForMode:SunlightStreamMode2D includingPending:YES].usesNativeResolution);

    [session stageWidth:1000 height:1000 frameRate:60 bitRate:30000 usesNativeResolution:NO forMode:SunlightStreamModeHost3D];
    host = [session configurationForMode:SunlightStreamModeHost3D includingPending:YES];
    Check(host.width == 1920 && host.height == 1080);
    NSDictionary *handoff = session.drafts;
    SunlightStreamQualitySession *replacement = Session(config, defaults, fallback, handoff, session.resetModes);
    ((SunlightStreamQualityProfile *)handoff[@(SunlightStreamModeHost3D)]).width = 1;
    Check([replacement profileForMode:SunlightStreamModeHost3D includingPending:YES].width == 1000);
    Check([session profileForMode:SunlightStreamModeHost3D includingPending:YES].width == 1000);
    [session discardPendingChanges];
    Check(session.drafts.count == 0 && session.resetModes.count == 0);
    Check([replacement hasPendingChangesForMode:SunlightStreamModeHost3D]);
    Check([replacement commitMode:SunlightStreamMode2D]);
    SunlightStreamQualityProfile *saved = [SunlightStreamQualityProfile profileForMode:SunlightStreamMode2D
        hostUUID:@"pc-a" appID:@"app-a" defaults:defaults fallback:fallback];
    Check(saved.width == 2622 && !saved.usesNativeResolution);
    Check(![SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamModeHost3D hostUUID:@"pc-a" appID:@"app-a" defaults:defaults]);
    Check(![SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamMode2D hostUUID:@"pc-b" appID:@"app-a" defaults:defaults]);

    SunlightStreamQualityProfile *global = Quality(2560, 1440, 120, 45000, NO);
    [replacement restoreDefaultsForMode:SunlightStreamMode2D globalFallback:global];
    Check([replacement.resetModes containsObject:@(SunlightStreamMode2D)]);
    Check([replacement profileForMode:SunlightStreamMode2D includingPending:YES].width == 2560);
    [replacement stageWidth:2560 height:1440 frameRate:120 bitRate:45000 usesNativeResolution:NO forMode:SunlightStreamMode2D];
    Check([replacement.resetModes containsObject:@(SunlightStreamMode2D)]);
    [replacement stageWidth:2560 height:1440 frameRate:120 bitRate:46000 usesNativeResolution:NO forMode:SunlightStreamMode2D];
    Check(![replacement.resetModes containsObject:@(SunlightStreamMode2D)]);
    [replacement restoreDefaultsForMode:SunlightStreamMode2D globalFallback:global];
    Check([replacement commitMode:SunlightStreamMode2D]);
    Check(![SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamMode2D hostUUID:@"pc-a" appID:@"app-a" defaults:defaults]);
    global.width = 1920;
    saved = [SunlightStreamQualityProfile profileForMode:SunlightStreamMode2D hostUUID:@"pc-a" appID:@"app-a" defaults:defaults fallback:global];
    Check(saved.width == 1920);

    [replacement stageWidth:10 height:20 frameRate:60 bitRate:40000 usesNativeResolution:YES forMode:SunlightStreamModeRawHalfSBS];
    SunlightStreamQualityProfile *raw = [replacement profileForMode:SunlightStreamModeRawFullSBS includingPending:YES];
    Check(raw.width == 3840 && raw.height == 1080 && !raw.usesNativeResolution);
    Check([replacement hasPendingChangesForMode:SunlightStreamModeRawHalfSBS]);
    Check(replacement.drafts[@(SunlightStreamModeRawHalfSBS)] == nil);
    replacement.outputSize = CGSizeZero;
    Check([replacement configurationForMode:SunlightStreamModeRawFullSBS includingPending:YES].width == 0);
    replacement.outputSize = CGSizeMake(3840, 1080);
    Check([replacement configurationForMode:SunlightStreamModeRawFullSBS includingPending:YES].width == 3840);
    Check([replacement configurationForMode:SunlightStreamModeRawHalfSBS includingPending:YES].streamMode == SunlightStreamModeRawFullSBS);
    Check([replacement commitMode:SunlightStreamModeRawHalfSBS]);
    Check([SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamModeRawFullSBS hostUUID:@"pc-a" appID:@"app-a" defaults:defaults]);

    before = [defaults persistentDomainForName:suite];
    [replacement stageWidth:1920 height:1080 frameRate:60 bitRate:40000 usesNativeResolution:NO forMode:(SunlightStreamMode)99];
    [replacement restoreDefaultsForMode:(SunlightStreamMode)99 globalFallback:global];
    Check(![replacement commitMode:(SunlightStreamMode)99]);
    Check([[defaults persistentDomainForName:suite] isEqual:before]);
    config.hostUUID = @"";
    SunlightStreamQualitySession *missingIdentity = Session(config, defaults, fallback, nil, nil);
    [missingIdentity stageWidth:1920 height:1080 frameRate:60 bitRate:40000 usesNativeResolution:NO forMode:SunlightStreamMode2D];
    Check(![missingIdentity commitMode:SunlightStreamMode2D]);
    Check([[defaults persistentDomainForName:suite] isEqual:before]);
    // Accepted reconnect synchronously closes the old panel and discards all
    // its drafts before persistence runs. Only the captured reviewed tab saves.
    [replacement stageWidth:1920 height:1080 frameRate:60 bitRate:55500 usesNativeResolution:NO forMode:SunlightStreamMode2D];
    BOOL (^acceptedCommit)(void) = [replacement commitActionForMode:SunlightStreamMode2D];
    [replacement discardPendingChanges];
    Check(acceptedCommit());
    saved = [SunlightStreamQualityProfile profileForMode:SunlightStreamMode2D hostUUID:@"pc-a" appID:@"app-a" defaults:defaults fallback:global];
    Check(saved.bitRate == 55500 && saved.width == 1920);
    [replacement restoreDefaultsForMode:SunlightStreamMode2D globalFallback:global];
    BOOL (^acceptedReset)(void) = [replacement commitActionForMode:SunlightStreamMode2D];
    [replacement discardPendingChanges];
    Check(acceptedReset());
    Check(![SunlightStreamQualityProfile hasOverrideForMode:SunlightStreamMode2D hostUUID:@"pc-a" appID:@"app-a" defaults:defaults]);
    config.glassesOutputEnabled = YES;
    Check([Session(config, defaults, fallback, nil, nil) configurationForMode:SunlightStreamMode2D includingPending:NO].frameRate <= 60);
    [defaults removePersistentDomainForName:suite];
    NSLog(@"PASS %d stream quality session checks", checks);
} return 0; }
