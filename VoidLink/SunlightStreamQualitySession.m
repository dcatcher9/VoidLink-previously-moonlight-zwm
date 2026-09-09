#import "SunlightStreamQualitySession.h"

static SunlightStreamMode SLCanonicalMode(SunlightStreamMode mode) {
    return mode == SunlightStreamModeRawHalfSBS ? SunlightStreamModeRawFullSBS : mode;
}

static BOOL SLValidMode(SunlightStreamMode mode) {
    return mode >= SunlightStreamMode2D && mode <= SunlightStreamModeRawHalfSBS;
}

@implementation SunlightStreamQualitySession {
    NSUserDefaults *_defaults;
    NSString *_hostUUID;
    NSString *_appID;
    SunlightStreamMode _activeMode;
    BOOL _glassesOutputEnabled;
    CGSize _nativeSize;
    SunlightStreamQualityProfile *_activeQuality;
    SunlightStreamQualityProfile *_fallback;
    NSMutableDictionary<NSNumber *, SunlightStreamQualityProfile *> *_baselines;
    NSMutableDictionary<NSNumber *, SunlightStreamQualityProfile *> *_drafts;
    NSMutableSet<NSNumber *> *_resetModes;
}

- (instancetype)initWithConfiguration:(StreamConfiguration *)configuration
                             defaults:(NSUserDefaults *)defaults
                             fallback:(SunlightStreamQualityProfile *)fallback
                           nativeSize:(CGSize)nativeSize
                               drafts:(NSDictionary<NSNumber *, SunlightStreamQualityProfile *> *)drafts
                           resetModes:(NSSet<NSNumber *> *)resetModes {
    self = [super init];
    if (self) {
        _defaults = defaults;
        _hostUUID = [configuration.hostUUID copy];
        _appID = [configuration.appID copy];
        _activeMode = SLCanonicalMode(configuration.streamMode);
        _glassesOutputEnabled = configuration.glassesOutputEnabled;
        _nativeSize = nativeSize;
        _fallback = [fallback copy];
        _activeQuality = [fallback copy];
        _activeQuality.width = configuration.logicalWidth ?: configuration.width;
        _activeQuality.height = configuration.logicalHeight ?: configuration.height;
        _activeQuality.frameRate = configuration.frameRate;
        _activeQuality.bitRate = configuration.bitRate;
        _baselines = [NSMutableDictionary dictionary];
        _drafts = [NSMutableDictionary dictionary];
        _resetModes = [NSMutableSet set];
        for (NSNumber *key in drafts) {
            SunlightStreamQualityProfile *profile = drafts[key];
            if (SLValidMode(key.integerValue) && profile.isValid) {
                _drafts[@(SLCanonicalMode(key.integerValue))] = [profile copy];
            }
        }
        for (NSNumber *key in resetModes) {
            if (SLValidMode(key.integerValue)) [_resetModes addObject:@(SLCanonicalMode(key.integerValue))];
        }
    }
    return self;
}

- (NSDictionary<NSNumber *, SunlightStreamQualityProfile *> *)drafts {
    return [[NSDictionary alloc] initWithDictionary:_drafts copyItems:YES];
}

- (NSSet<NSNumber *> *)resetModes { return [_resetModes copy]; }

- (BOOL)hasPendingChangesForMode:(SunlightStreamMode)mode {
    NSNumber *key = @(SLCanonicalMode(mode));
    return _drafts[key] != nil || [_resetModes containsObject:key];
}

- (SunlightStreamQualityProfile *)profileForMode:(SunlightStreamMode)mode includingPending:(BOOL)includingPending {
    mode = SLCanonicalMode(mode);
    NSNumber *key = @(mode);
    SunlightStreamQualityProfile *baseline = _baselines[key];
    if (!baseline) {
        baseline = [SunlightStreamQualityProfile profileForMode:mode hostUUID:_hostUUID appID:_appID
            defaults:_defaults fallback:_fallback];
        [baseline resolveNativeWidth:(int)_nativeSize.width height:(int)_nativeSize.height];
        if (mode == _activeMode) {
            baseline.width = _activeQuality.width; baseline.height = _activeQuality.height;
            baseline.frameRate = _activeQuality.frameRate; baseline.bitRate = _activeQuality.bitRate;
        }
        if (mode != SunlightStreamMode2D || _glassesOutputEnabled) baseline.frameRate = MIN(60, baseline.frameRate);
        if (mode == SunlightStreamModeRawFullSBS) {
            baseline.usesNativeResolution = NO;
            baseline.width = (int)self.outputSize.width; baseline.height = (int)self.outputSize.height;
        } else if (mode == SunlightStreamModeHost3D) {
            StreamConfiguration *compatible = [StreamConfiguration new];
            compatible.streamMode = mode;
            compatible.width = baseline.width; compatible.height = baseline.height;
            [compatible useCompatibleHost3DResolution];
            baseline.width = compatible.width; baseline.height = compatible.height;
        }
        _baselines[key] = baseline;
    }
    SunlightStreamQualityProfile *profile = [(includingPending ? _drafts[key] ?: baseline : baseline) copy];
    if (mode == SunlightStreamModeRawFullSBS) {
        // A mode transition can change the canvas after the tab was first read.
        profile.usesNativeResolution = NO;
        profile.width = (int)self.outputSize.width; profile.height = (int)self.outputSize.height;
    }
    return profile;
}

- (StreamConfiguration *)configurationForMode:(SunlightStreamMode)mode includingPending:(BOOL)includingPending {
    mode = SLCanonicalMode(mode);
    SunlightStreamQualityProfile *profile = [self profileForMode:mode includingPending:includingPending];
    StreamConfiguration *quality = [StreamConfiguration new];
    quality.streamMode = mode;
    quality.width = profile.width; quality.height = profile.height;
    quality.frameRate = mode != SunlightStreamMode2D || _glassesOutputEnabled ? MIN(60, profile.frameRate) : profile.frameRate;
    quality.bitRate = profile.bitRate;
    [quality useCompatibleHost3DResolution];
    quality.logicalWidth = quality.width; quality.logicalHeight = quality.height;
    return quality;
}

- (void)stageWidth:(int)width height:(int)height frameRate:(int)frameRate bitRate:(int)bitRate
    usesNativeResolution:(BOOL)native forMode:(SunlightStreamMode)mode {
    if (!SLValidMode(mode)) return;
    mode = SLCanonicalMode(mode);
    StreamConfiguration *presented = [self configurationForMode:mode includingPending:YES];
    SunlightStreamQualityProfile *baseline = [self profileForMode:mode includingPending:NO];
    SunlightStreamQualityProfile *draft = [self profileForMode:mode includingPending:YES];
    if (mode == SunlightStreamModeRawFullSBS) {
        width = presented.width; height = presented.height; native = NO;
    }
    BOOL nativeChanged = draft.usesNativeResolution != native;
    draft.width = width; draft.height = height; draft.usesNativeResolution = native;
    draft.frameRate = frameRate; draft.bitRate = bitRate;
    if (!draft.isValid) return;
    NSNumber *key = @(mode);
    if (nativeChanged || width != presented.width || height != presented.height ||
        frameRate != presented.frameRate || bitRate != presented.bitRate) [_resetModes removeObject:key];
    if ([draft isEqualToProfile:baseline]) [_drafts removeObjectForKey:key];
    else _drafts[key] = draft;
}

- (void)restoreDefaultsForMode:(SunlightStreamMode)mode globalFallback:(SunlightStreamQualityProfile *)fallback {
    if (!SLValidMode(mode)) return;
    mode = SLCanonicalMode(mode);
    SunlightStreamQualityProfile *quality = [SunlightStreamQualityProfile profileForMode:mode defaults:_defaults fallback:fallback];
    [quality resolveNativeWidth:(int)_nativeSize.width height:(int)_nativeSize.height];
    if (mode == SunlightStreamModeRawFullSBS) {
        quality.usesNativeResolution = NO;
        quality.width = (int)self.outputSize.width; quality.height = (int)self.outputSize.height;
    }
    _drafts[@(mode)] = quality;
    [_resetModes addObject:@(mode)];
}

- (BOOL)commitMode:(SunlightStreamMode)mode {
    return [self commitActionForMode:mode]();
}

- (BOOL (^)(void))commitActionForMode:(SunlightStreamMode)mode {
    if (!SLValidMode(mode)) return ^BOOL{ return NO; };
    mode = SLCanonicalMode(mode);
    BOOL reset = [_resetModes containsObject:@(mode)];
    SunlightStreamQualityProfile *draft = [_drafts[@(mode)] copy];
    NSString *hostUUID = _hostUUID, *appID = _appID;
    NSUserDefaults *defaults = _defaults;
    return ^BOOL{
        if (reset) return [SunlightStreamQualityProfile removeForMode:mode hostUUID:hostUUID appID:appID defaults:defaults];
        return !draft || [draft saveForMode:mode hostUUID:hostUUID appID:appID defaults:defaults];
    };
}

- (void)discardPendingChanges {
    [_drafts removeAllObjects];
    [_resetModes removeAllObjects];
}
@end
