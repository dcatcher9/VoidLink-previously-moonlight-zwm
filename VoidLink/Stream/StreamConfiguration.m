//
//  StreamConfiguration.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamConfiguration.h"
#include <Limelight.h>
#include <math.h>

@implementation StreamConfiguration
@synthesize host, httpsPort, appID, width, height, frameRate, bitRate, riKeyId, riKey, gamepadMask, appName, optimizeGameSettings, playAudioOnPC, swapABXYButtons, buttonVisualFeedback, gyroMode, emulatedControllerType, hapticEngine,  audioConfiguration, supportedVideoFormats, multiController, serverCert, rtspSessionUrl, serverCodecModeSupport, enableYUV444, enablePIP, fullColorRange, enableHdr, sdrPerformanceWorkaround, localVolume;

- (BOOL)isStereoStream {
    return self.streamMode != SunlightStreamMode2D;
}

- (BOOL)requiresMetalPresentation {
    return self.isStereoStream || self.glassesOutputEnabled;
}

- (BOOL)isRawSbsStream {
    return self.streamMode == SunlightStreamModeRawFullSBS || self.streamMode == SunlightStreamModeRawHalfSBS;
}

- (BOOL)isVirtualDisplayApp {
    NSString* name = [self.appName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString* uuid = [self.appUUID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [name isEqualToString:@"Virtual Display"] ||
        (uuid.length > 0 && [uuid caseInsensitiveCompare:@"8902CB19-674A-403D-A587-41B092E900BA"] == NSOrderedSame);
}

- (int)initialHostSbsMode {
    return self.streamMode == SunlightStreamModeHost3D ? 1 : 0;
}

- (int)stereoCodecAxisLimit {
    BOOL hevc = (self.supportedVideoFormats & (VIDEO_FORMAT_H265 | VIDEO_FORMAT_H265_MAIN10)) != 0 &&
        (self.serverCodecModeSupport & (SCM_HEVC | SCM_HEVC_MAIN10)) != 0;
    BOOL av1 = (self.supportedVideoFormats & (VIDEO_FORMAT_AV1_MAIN8 | VIDEO_FORMAT_AV1_MAIN10)) != 0 &&
        (self.serverCodecModeSupport & (SCM_AV1_MAIN8 | SCM_AV1_MAIN10)) != 0;
    return hevc || av1 ? 8192 : 4096;
}

- (double)hostPackedScale {
    if (self.width <= 0 || self.height <= 0) {
        return 1.0;
    }
    double cap = [self stereoCodecAxisLimit];
    return fmin(1.0, fmin(cap / (2.0 * self.width), cap / self.height));
}

- (int)expectedPackedWidth {
    if (self.streamMode != SunlightStreamModeHost3D) {
        return self.width;
    }
    // Each eye owns whole 4:2:0 chroma cells, so packed width is a multiple of four.
    return MAX(4, ((int)llround(2.0 * self.width * [self hostPackedScale])) & ~3);
}

- (int)expectedPackedHeight {
    if (self.streamMode != SunlightStreamModeHost3D) {
        return self.height;
    }
    return MAX(2, ((int)llround(self.height * [self hostPackedScale])) & ~1);
}

+ (BOOL)isSupportedHost3DWidth:(int)width height:(int)height {
    // Apollo a4cef55b, schema 76: host_sbs_resolution.h and depth_coordinate_v2_contract.h.
    // Match the float32, 14-pixel patch fitter rather than an approximate aspect check.
    if (width < 1 || height < 1 || MAX(width, height) > 5120 ||
        (int64_t)width * height > 5120LL * 2160) {
        return NO;
    }
    float aspect = (float)width / (float)height;
    aspect = aspect >= 1.0f ? fminf(aspect, 4.0f) : 1.0f / fminf(1.0f / aspect, 4.0f);
    int maxWidth = MAX(14, MIN(width, 1036) / 14 * 14);
    int maxHeight = MAX(14, MIN(height, 1036) / 14 * 14);
    int tensorWidth = 14;
    int tensorHeight = 14;
    if (aspect >= 1.0f) {
        for (int candidate = MIN(434, maxHeight); candidate >= 14; candidate -= 14) {
            int other = MAX(14, (int)roundf((float)candidate * aspect / 14.0f) * 14);
            if (other <= maxWidth) {
                tensorWidth = other;
                tensorHeight = candidate;
                break;
            }
        }
    } else {
        for (int candidate = MIN(434, maxWidth); candidate >= 14; candidate -= 14) {
            int other = MAX(14, (int)roundf((float)candidate / aspect / 14.0f) * 14);
            if (other <= maxHeight) {
                tensorWidth = candidate;
                tensorHeight = other;
                break;
            }
        }
    }
    int shortSide = MIN(tensorWidth, tensorHeight);
    int longSide = MAX(tensorWidth, tensorHeight);
    if (shortSide != 434) {
        return NO;
    }
    switch (longSide) {
        case 574: case 616: case 630: case 658: case 700: case 770:
        case 868: case 938: case 966: case 980: case 1022: case 1036:
            return YES;
        default:
            return NO;
    }
}

- (BOOL)useCompatibleHost3DResolution {
    if (self.streamMode != SunlightStreamModeHost3D ||
        self.width < 1 || self.height < 1 || self.width > 16384 || self.height > 16384 ||
        [StreamConfiguration isSupportedHost3DWidth:self.width height:self.height]) {
        return NO;
    }
    self.width = 1920;
    self.height = 1080;
    return YES;
}

- (NSString*)prepareSunlightStreamWithHostSessionSupport:(BOOL)sessionSupport
                                 virtualDisplayCapable:(BOOL)virtualCapable
                                   virtualDisplayReady:(BOOL)virtualReady {
    // Raw presents a PC image that is already correctly packed. It does not
    // create or change the host's physical/virtual display backing.
    (void)virtualCapable;
    (void)virtualReady;
    if (self.streamMode < SunlightStreamMode2D || self.streamMode > SunlightStreamModeRawHalfSBS) {
        return @"Choose 2D, Host 3D, or Raw SBS before connecting.";
    }
    if (self.streamMode == SunlightStreamModeRawHalfSBS) {
        self.streamMode = SunlightStreamModeRawFullSBS;
    }
    int logicalWidth = self.logicalWidth > 0 ? self.logicalWidth : self.width;
    int logicalHeight = self.logicalHeight > 0 ? self.logicalHeight : self.height;
    if (logicalWidth < 1 || logicalHeight < 1 || logicalWidth > 16384 || logicalHeight > 16384) {
        return @"Choose a stream resolution between 1 and 16384 pixels on each side.";
    }
    if (self.isRawSbsStream && ((logicalWidth & 1) != 0 || (logicalHeight & 1) != 0)) {
        return @"Choose an even stream resolution for Raw SBS output.";
    }
    if (self.streamMode == SunlightStreamModeHost3D && !sessionSupport) {
        return @"Host 3D requires Sunshine 3D. This host supports ordinary 2D streaming.";
    }
    if (self.streamMode == SunlightStreamModeHost3D &&
        ![StreamConfiguration isSupportedHost3DWidth:logicalWidth height:logicalHeight]) {
        return @"This resolution is not supported by the host’s 3D model. Choose 1920 × 1080 in stream settings, then reconnect.";
    }
    if (self.isRawSbsStream && (logicalWidth > [self stereoCodecAxisLimit] || logicalHeight > [self stereoCodecAxisLimit])) {
        return @"The glasses’ Raw SBS resolution exceeds the available codec limit. Enable a compatible HEVC codec on both devices.";
    }

    self.logicalWidth = logicalWidth;
    self.logicalHeight = logicalHeight;
    self.width = logicalWidth;
    self.height = logicalHeight;
    self.hostSessionIdSupported = sessionSupport;
    self.requestVirtualDisplay = NO;
    if (self.streamMode == SunlightStreamModeHost3D) {
        self.enableYUV444 = NO;
        self.supportedVideoFormats &= ~VIDEO_FORMAT_MASK_YUV444;
    }
    return nil;
}

+ (NSString*)normalizedHostSessionId:(NSString*)value {
    NSString* trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return nil;
    }
    uint64_t parsed = 0;
    for (NSUInteger i = 0; i < trimmed.length; i++) {
        unichar character = [trimmed characterAtIndex:i];
        if (character < '0' || character > '9') {
            return nil;
        }
        unsigned int digit = character - '0';
        if (parsed > (UINT64_MAX - digit) / 10) {
            return nil;
        }
        parsed = parsed * 10 + digit;
    }
    return parsed == 0 ? nil : [NSString stringWithFormat:@"%llu", (unsigned long long)parsed];
}

- (NSString*)validateResumeWithRunningAppId:(NSString*)runningAppId
                            runningAppUUID:(NSString*)runningAppUUID
                             hostSessionId:(NSString*)hostSessionId {
    NSString* selectedId = [StreamConfiguration normalizedHostSessionId:self.appID];
    NSString* runningId = [StreamConfiguration normalizedHostSessionId:runningAppId];
    // Prefer UUID when both endpoints provide it; app IDs may change when the host list changes.
    BOOL sameApp = self.appUUID.length > 0 && runningAppUUID.length > 0
        ? [self.appUUID caseInsensitiveCompare:runningAppUUID] == NSOrderedSame
        : selectedId != nil && [selectedId isEqualToString:runningId];
    if (!sameApp) {
        return @"A different app is running on this host. Stop it or select that app before connecting.";
    }
    if (self.hostSessionIdSupported) {
        NSString* current = [StreamConfiguration normalizedHostSessionId:hostSessionId];
        NSString* expected = [StreamConfiguration normalizedHostSessionId:self.expectedHostSessionId];
        if (current == nil || (self.expectedHostSessionId.length > 0 && ![current isEqualToString:expected])) {
            return @"The host session changed. Refresh the host and select the app again.";
        }
        // A freshly selected app has no persisted token yet. Bind the verified matching session.
        self.expectedHostSessionId = current;
    }
    return nil;
}

- (NSString*)validateHostSessionResponse:(NSString*)hostSessionId resuming:(BOOL)resuming {
    NSString* received = [StreamConfiguration normalizedHostSessionId:hostSessionId];
    if (self.hostSessionIdSupported &&
        (received == nil || (resuming && ![received isEqualToString:self.expectedHostSessionId]))) {
        return @"The host returned a missing or changed session identifier. Refresh the host and reconnect.";
    }
    self.hostSessionId = received;
    return nil;
}

- (NSArray<NSURLQueryItem*>*)sunlightLaunchQueryItemsForResume:(BOOL)resuming {
    NSMutableArray<NSURLQueryItem*>* items = [NSMutableArray array];
    if (self.appUUID.length > 0) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"appuuid" value:self.appUUID]];
    }
    if (self.requestVirtualDisplay) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"virtualDisplay" value:@"1"]];
    }
    if (self.hostSessionIdSupported) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"sbsMode" value:self.initialHostSbsMode ? @"1" : @"0"]];
        if (resuming && self.expectedHostSessionId.length > 0) {
            [items addObject:[NSURLQueryItem queryItemWithName:@"hostSessionId" value:self.expectedHostSessionId]];
        }
    }
    return items;
}
@end
