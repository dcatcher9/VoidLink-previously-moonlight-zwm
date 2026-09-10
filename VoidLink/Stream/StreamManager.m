//
//  StreamManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//
//  Modified by True砖家 since 2024.7.9
//  Copyright © 2024 True砖家 @ Bilibili. All rights reserved.
//

#import "StreamManager.h"
#import "CryptoManager.h"
#import "HttpManager.h"
#import "Plot.h"
#import "Utils.h"
#import "DataManager.h"

#import "StreamView.h"
#import "ServerInfoResponse.h"
#import "HttpResponse.h"
#import "HttpRequest.h"
#import "IdManager.h"
#import "LocalizationHelper.h"
#import "VoidLink-Swift.h"

#include <Limelight.h>

@implementation StreamManager {
    StreamConfiguration* _config;

    UIView* _renderView;
    id<ConnectionCallbacks> _callbacks;
    Connection* _connection;
    VideoDecoderRenderer* _videoRenderer;
    BOOL _stopRequested;
    BOOL _resumeStillActive;
    dispatch_semaphore_t _retryWake;
}

- (id) initWithConfig:(StreamConfiguration*)config renderView:(UIView*)view connectionCallbacks:(id<ConnectionCallbacks>)callbacks {
    self = [super init];
    _config = config;
    _renderView = view;
    _callbacks = callbacks;
    _config.riKey = [Utils randomBytes:16];
    _config.riKeyId = arc4random();
    _retryWake = dispatch_semaphore_create(0);
    return self;
}

- (void)main {
    if (![self isStartupActive]) return;
    if (_config.isStereoStream) {
        if (@available(iOS 13.0, tvOS 13.0, *)) {
            // Stereo's single-consumer Metal presentation uses iOS 13 APIs.
        } else {
            [self notifyLaunchFailed:@"Stereo streaming requires iOS 13 or later. Choose 2D on this device."];
            return;
        }
    }
    [CryptoManager generateKeyPairUsingSSL];
    if (![self isStartupActive]) return;
    
    HttpManager* hMan = [[HttpManager alloc] initWithAddress:_config.host httpsPort:_config.httpsPort
                                                     serverCert:_config.serverCert];
    
    NSString *sessionUrl = nil;
    NSUInteger retries = 0;
    for (;;) {
        if (![self isStartupActive]) return;
        _resumeStillActive = NO;
        if ([self prepareHostSession:hMan receiveSessionUrl:&sessionUrl]) break;
        if (!_resumeStillActive || ![self isStartupActive]) return;
        if (retries >= 6) {
            [self notifyLaunchFailed:@"The PC is still ending the previous stream. Try connecting again."];
            return;
        }
        // Allow the remote process to observe the closed control connection.
        // Every retry starts with fresh serverinfo and revalidates app + token.
        NSTimeInterval delay = retries == 0 ? 0.25 : retries == 1 ? 0.5 : 1.0;
        retries++;
        dispatch_semaphore_wait(_retryWake, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)));
    }

    if (![self isStartupActive]) return;
    // Populate RTSP session URL from launch/resume response
    _config.rtspSessionUrl = sessionUrl;

    // Initializing the renderer must be done on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized (self) {
            // stopStream may have run while HTTP was pending or while this
            // block waited for main. Publish and enqueue atomically with stop.
            if (![self isStartupActive]) return;
            self->_videoRenderer = [[VideoDecoderRenderer alloc] initWithView:self->_renderView callbacks:self->_callbacks
                streamAspectRatio:(float)self->_config.expectedPackedWidth / (float)self->_config.expectedPackedHeight
                presentationSettings:self->_config.presentationSettings];
            self->_videoRenderer.stereoPresentation = self->_config.requiresMetalPresentation;

            self->_connection = [[Connection alloc] initWithConfig:self->_config renderer:self->_videoRenderer connectionCallbacks:self->_callbacks];
            NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
            [opQueue addOperation:self->_connection];
        }
    });
}

- (BOOL)prepareHostSession:(HttpManager *)hMan receiveSessionUrl:(NSString **)sessionUrl {
    _config.virtualDisplayOnlySupported = NO;
    ServerInfoResponse* serverInfoResp = [[ServerInfoResponse alloc] init];
    HttpRequest *serverInfoRequest = [HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:false]
                                       fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]];
    [hMan executeRequestSynchronously:serverInfoRequest];
    if (![self isStartupActive]) return NO;
    NSString* pairStatus = [serverInfoResp getStringTag:@"PairStatus"];
    NSString* appversion = [serverInfoResp getStringTag:@"appversion"];
    NSString* gfeVersion = [serverInfoResp getStringTag:@"GfeVersion"];
    NSString* serverState = [serverInfoResp getStringTag:@"state"];
    if (![serverInfoResp isStatusOk]) {
        [self notifyLaunchFailed:serverInfoResp.statusMessage];
        return NO;
    }
    else if (pairStatus == NULL || appversion == NULL || serverState == NULL) {
        [self notifyLaunchFailed:@"Failed to connect to PC"];
        return NO;
    }
    
    if (![pairStatus isEqualToString:@"1"]) {
        // Not paired
        [self notifyLaunchFailed:@"Device not paired to PC"];
        return NO;
    }

    _config.virtualDisplayOnlySupported = serverInfoRequest.authenticatedResponse &&
        [[serverInfoResp getStringTag:@"VirtualDisplayOnlySupported"] isEqualToString:@"1"];

    BOOL sessionSupport = [serverInfoResp getStringTag:@"hostsessionid"] != nil;
    uint64_t hostSessionId = 0;
    if (sessionSupport && ![serverInfoResp getUInt64Tag:@"hostsessionid" value:&hostSessionId]) {
        [self notifyLaunchFailed:@"The host returned an invalid session identifier. Refresh the host and reconnect."];
        return NO;
    }
    if (_config.reconnectRetainedSession) {
        if (![serverState hasSuffix:@"_SERVER_BUSY"]) {
            [self notifyLaunchFailed:@"The previous PC app session ended. Return to the app list and connect again."];
            return NO;
        }
        if ((sessionSupport || _config.expectedHostSessionId.length > 0) &&
            (!sessionSupport || [StreamConfiguration normalizedHostSessionId:_config.expectedHostSessionId] == nil)) {
            [self notifyLaunchFailed:@"The host session changed. Return to the app list and connect again."];
            return NO;
        }
    }
    // Use fresh codec capabilities when validating a packed Raw stream.
    _config.serverCodecModeSupport = [[serverInfoResp getStringTag:@"ServerCodecModeSupport"] intValue];
    NSString* modeFailure = [_config prepareSunlightStreamWithHostSessionSupport:sessionSupport
        virtualDisplayCapable:[[serverInfoResp getStringTag:@"VirtualDisplayCapable"] isEqualToString:@"true"]
        virtualDisplayReady:[[serverInfoResp getStringTag:@"VirtualDisplayDriverReady"] isEqualToString:@"true"]];
    if (modeFailure != nil) {
        [self notifyLaunchFailed:modeFailure];
        return NO;
    }
    if ([StreamConfiguration normalizedHostSessionId:_config.appID] == nil && _config.appUUID.length == 0) {
        [self notifyLaunchFailed:@"Select an app from the host before connecting."];
        return NO;
    }
    
    // Only perform this check on GFE (as indicated by MJOLNIR in state value)
    if ((_config.width > 4096 || _config.height > 4096) && [serverState containsString:@"MJOLNIR"]) {
        // Pascal added support for 8K HEVC encoding support. Maxwell 2 could encode HEVC but only up to 4K.
        // We can't directly identify Pascal, but we can look for HEVC Main10 which was added in the same generation.
        NSString* codecSupport = [serverInfoResp getStringTag:@"ServerCodecModeSupport"];
        if (codecSupport == nil || !([codecSupport intValue] & 0x200)) {
            [self notifyLaunchFailed:@"Your host PC's GPU doesn't support streaming video resolutions over 4K."];
            return NO;
        }
    }
    
    // Populate the config's version fields from serverinfo
    _config.appVersion = appversion;
    _config.gfeVersion = gfeVersion;
    
    // resumeApp and launchApp handle calling launchFailed
    if ([serverState hasSuffix:@"_SERVER_BUSY"]) {
        NSString* resumeFailure = [_config validateResumeWithRunningAppId:[serverInfoResp getStringTag:@"currentgame"]
            runningAppUUID:[serverInfoResp getStringTag:@"currentgameuuid"]
            hostSessionId:[serverInfoResp getStringTag:@"hostsessionid"]];
        if (resumeFailure != nil) {
            [self notifyLaunchFailed:resumeFailure];
            return NO;
        }
        // App already running, resume it
        if (![self resumeApp:hMan receiveSessionUrl:sessionUrl]) {
            return NO;
        }
    } else {
        // Start app
        if (![self launchApp:hMan receiveSessionUrl:sessionUrl]) {
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)isStartupActive {
    @synchronized (self) {
        return !_stopRequested && !self.isCancelled;
    }
}

- (void)notifyLaunchFailed:(NSString *)message {
    @synchronized (self) {
        if ([self isStartupActive]) [_callbacks launchFailed:message];
    }
}

- (VideoDecoderRenderer *)videoRenderer {
    @synchronized (self) {
        return _videoRenderer;
    }
}

- (void) setNeedRequeuing:(bool)needRequeuing{
    [self.videoRenderer setRequeuingRequired:needRequeuing];
}

- (void) stopStream
{
    [self cancel];
}

- (void)stopStreamWithCompletion:(dispatch_block_t)completion {
    [self cancel];
    Connection *connection;
    @synchronized (self) {
        connection = _connection;
    }
    // Publication shares the cancellation lock, so nil here cannot become a
    // live Connection after completion. In-flight HTTP is discarded on return.
    dispatch_block_t completed = ^{ dispatch_async(dispatch_get_main_queue(), completion); };
    if (connection) [connection terminateWithCompletion:completed];
    else completed();
}

- (void)cancel {
    Connection *connection;
    @synchronized (self) {
        if (_stopRequested) return;
        _stopRequested = YES;
        [super cancel];
        connection = _connection;
        _callbacks = nil;
    }
    // Connection termination can call into the streaming library. Keep it out
    // of the publication lock, including when cancel originates in a callback.
    [connection terminate];
    dispatch_semaphore_signal(_retryWake);
}

- (BOOL) launchApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    if (![self isStartupActive]) return NO;
    HttpResponse* launchResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:launchResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"launch" config:_config]]];
    if (![self isStartupActive]) return NO;
    NSString *gameSession = [launchResp getStringTag:@"gamesession"];
    if (![launchResp isStatusOk]) {
        [self notifyLaunchFailed:launchResp.statusMessage];
        Log(LOG_E, @"Failed Launch Response: %@", launchResp.statusMessage);
        return FALSE;
    } else if (gameSession == NULL || [gameSession isEqualToString:@"0"]) {
        [self notifyLaunchFailed:@"Failed to launch app"];
        Log(LOG_E, @"Failed to parse game session");
        return FALSE;
    }
    NSString* sessionFailure = [_config validateHostSessionResponse:[launchResp getStringTag:@"hostsessionid"] resuming:NO];
    if (sessionFailure != nil) {
        [self notifyLaunchFailed:sessionFailure];
        return NO;
    }
    
    *sessionUrl = [launchResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

- (BOOL) resumeApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    if (![self isStartupActive]) return NO;
    HttpResponse* resumeResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:resumeResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"resume" config:_config]]];
    if (![self isStartupActive]) return NO;
    NSString* resume = [resumeResp getStringTag:@"resume"];
    if (![resumeResp isStatusOk]) {
        // This exact response precedes all host reconfiguration and reserves no
        // new handshake. Other 503s (including a pending handshake) are terminal.
        if (_config.reconnectRetainedSession && _config.hostSessionIdSupported &&
            [StreamConfiguration normalizedHostSessionId:_config.expectedHostSessionId] != nil &&
            resumeResp.statusCode == 503 &&
            [resumeResp.statusMessage isEqualToString:@"Another streaming session is already active"]) {
            _resumeStillActive = YES;
            return NO;
        }
        [self notifyLaunchFailed:resumeResp.statusMessage];
        Log(LOG_E, @"Failed Resume Response: %@", resumeResp.statusMessage);
        return FALSE;
    } else if (resume == NULL || [resume isEqualToString:@"0"]) {
        [self notifyLaunchFailed:@"Failed to resume app"];
        Log(LOG_E, @"Failed to parse resume response");
        return FALSE;
    }
    NSString* sessionFailure = [_config validateHostSessionResponse:[resumeResp getStringTag:@"hostsessionid"] resuming:YES];
    if (sessionFailure != nil) {
        [self notifyLaunchFailed:sessionFailure];
        return NO;
    }
    
    *sessionUrl = [resumeResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

- (NSString*) getStatsOverlayText: (uint16_t) overlayLevel {
    video_stats_t stats;
    Connection *connection;
    @synchronized (self) {
        connection = _connection;
    }
    if (!connection) {
        return nil;
    }
    
    if (![connection getVideoStats:&stats]) {
        return nil;
    }
    
    uint32_t rtt, variance;
    NSString* latencyString;
    if (LiGetEstimatedRttInfo(&rtt, &variance)) {
        latencyString = [LocalizationHelper localizedStringForKey:@"%3u ms (var: %3u ms)", rtt, variance];
    }
    else {
        latencyString = @"N/A";
    }
    
    NSString* hostProcessingString;
    if (stats.framesWithHostProcessingLatency != 0) {
        hostProcessingString = [LocalizationHelper localizedStringForKey:@"Host processing latency min/max/avg: %.1f/%.1f/%.1f ms\n",
                                stats.minHostProcessingLatency / 10.f,
                                stats.maxHostProcessingLatency / 10.f,
                                (float)stats.totalHostProcessingLatency / stats.framesWithHostProcessingLatency / 10.f];
    }
    else {
        // If all frames are duplicates this can happen, but let's avoid having the whole stats area change height
        hostProcessingString = @"Host processing latency min/max/avg: -/-/- ms\n";
    }
    
    float interval = stats.endTime - stats.startTime;
    
    // Get frame pacing mode
    TemporarySettings *presentation = _config.presentationSettings ?: [[[DataManager alloc] init] getSettings];
    FramePacingMode framePacingMode = _config.requiresMetalPresentation ? FramePacingModeQueue : presentation.framePacingMode.integerValue;

    // Calculate FPS differently based on pacing mode
    float fps;
    if (framePacingMode == FramePacingModeLegacy || framePacingMode == FramePacingModeOff) {
        fps = stats.totalFrames / interval;
    } else {
        float scalePlotMetrics = stats.frameDropMetrics.nsamples > 0 ? ((float)stats.frameDropMetrics.nsamples / stats.totalFrames) : 1.0f;
        fps = (stats.totalFrames - stats.networkDroppedFrames - (stats.frameDropMetrics.total / scalePlotMetrics)) / interval;
    }
    float interpolatedFps = stats.interpolatedFrames / interval;

    NSString *renderingFpsString;
    if (framePacingMode == FramePacingModeInterpolation) {
        renderingFpsString = [NSString stringWithFormat:@"Rendering FPS: %dx%d %.2f+%.2f",
                              _config.width, _config.height, fps, interpolatedFps];
    }
    else {
        renderingFpsString = [NSString stringWithFormat:@"Rendering FPS: %dx%d %.2f",
                              _config.width, _config.height, fps];
    }

    double avgVideoMbps = [connection getBwTracker].averageMbps;
    double peakVideoMbps = [connection getBwTracker].peakMbps;

    NSString* colorRange = _config.fullColorRange ? @"Full" : @"Limited";

    if (overlayLevel == 1) {
        if (framePacingMode == FramePacingModeInterpolation) {
            return [LocalizationHelper localizedStringForKey:@"simplifiedOsdTextWithInterpolation",
                    fps,
                    interpolatedFps,
                    stats.networkDroppedFrames / interval,
                    avgVideoMbps,
                    latencyString];
        }
        return [LocalizationHelper localizedStringForKey:@"simplifiedOsdText",
                fps,
                stats.networkDroppedFrames / interval,
                avgVideoMbps,
                latencyString];
    }
    else {
        if (framePacingMode == FramePacingModeLegacy || framePacingMode == FramePacingModeOff) {
            NSString* rendererWithPacing = stats.renderingBackendString;
            if ([stats.renderingBackendString isEqualToString:@"AVSampleBuffer"]) {
                if (framePacingMode == FramePacingModeOff) {
                    rendererWithPacing = @"AVSampleBuffer (No Pacing)";
                } else {
                    rendererWithPacing = @"AVSampleBuffer (Legacy Pacing)";
                }
            }
            
            return [LocalizationHelper localizedStringForKey:@"%@ (Codec: %@, %@)\n"
                     "Bitrate: %.1f Mbps, Peak: %.1f\n"
                     "%@"
                     "Renderer: %@\n"
                     "Frames dropped by network: %.1f%%\n"
                     "Average network latency: %@",
                     renderingFpsString,
                     [connection getActiveCodecName],
                     colorRange,
                     avgVideoMbps, peakVideoMbps,
                     hostProcessingString,
                     rendererWithPacing,
                     (stats.networkDroppedFrames / stats.totalFrames) * 100.0,
                     latencyString];
        } else {
            NSString* rendererWithPacing = stats.renderingBackendString;
            if ([stats.renderingBackendString isEqualToString:@"AVSampleBuffer"]) {
                rendererWithPacing = @"AVSampleBuffer (Queue Pacing)";
            }
            
            return [LocalizationHelper localizedStringForKey:@"%@ (Codec: %@, %@)\n"
                     "Bitrate: %.1f Mbps, Peak: %.1f, Frames buffered: %.1f\n"
                     "%@"
                     "Renderer: %@\n"
                     "Frames dropped by network/pacing jitter: %.1f%% / %.1f%%\n"
                     "Average network latency: %@\n"
                     "Decode time: %.2f/%.2f/%.2f ms %@",
                     renderingFpsString,
                     [connection getActiveCodecName],
                     colorRange,
                     avgVideoMbps, peakVideoMbps, stats.frameQueueMetrics.avg,
                     hostProcessingString,
                     rendererWithPacing,
                     (stats.networkDroppedFrames / stats.totalFrames) * 100.0,
                     stats.frameDropMetrics.nsamples > 0 ? (stats.frameDropMetrics.total / stats.frameDropMetrics.nsamples) * 100.0 : 0.0f,
                     latencyString,
                     stats.decodeMetrics.min, stats.decodeMetrics.max, stats.decodeMetrics.avg, PublicUtils.onScreenRuntimeStats];
        }
    }
}

@end
