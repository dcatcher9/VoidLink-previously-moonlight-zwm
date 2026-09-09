//
//  StreamConfiguration.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//
//  Modified by True砖家 since 2024.8.10
//  Copyright © 2024 True砖家 @ Bilibili. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SunlightStreamMode) {
    SunlightStreamMode2D = 0,
    SunlightStreamModeHost3D = 1,
    SunlightStreamModeRawFullSBS = 2,
    // Persisted legacy choice; preflight normalizes this to exact Raw SBS passthrough.
    SunlightStreamModeRawHalfSBS = 3,
};

@class TemporarySettings;
@class SunlightMachineControlsSettings;

@interface StreamConfiguration : NSObject

// Startup-only presentation. Changing mode requires a new connection.
@property SunlightStreamMode streamMode;
// Mono source quality for 2D/Host 3D; complete glasses-sized packed pixels for Raw SBS.
// width/height below become the same HTTP/RTSP source dimensions without Raw width doubling.
@property int logicalWidth;
@property int logicalHeight;
@property NSString* appUUID;
@property BOOL hostSessionIdSupported;
@property NSString* expectedHostSessionId;
// A UI-requested reconnect must retain the selected app/session; it may retry
// only the host's explicit "previous streaming session still active" response.
@property BOOL reconnectRetainedSession;
@property NSString* hostSessionId;
@property BOOL requestVirtualDisplay;
// Capture output preference at connection start so later screen changes keep one decoder consumer.
@property BOOL glassesOutputEnabled;
// Detached effective PC/global preferences captured before connection startup.
// Renderer/pacing consumers must not read new global values mid-session.
@property (nonatomic, strong) TemporarySettings *presentationSettings;
@property (readonly) BOOL requiresMetalPresentation;
@property (readonly) BOOL isStereoStream;
@property (readonly) BOOL isRawSbsStream;
@property (readonly) BOOL isVirtualDisplayApp;
@property (readonly) int initialHostSbsMode;
// Conservative startup layout only. The decoded format description is authoritative.
@property (readonly) int expectedPackedWidth;
@property (readonly) int expectedPackedHeight;

// Pinned Sunshine 3D V2 source/tensor contract, independent of encoder size limits.
+ (BOOL)isSupportedHost3DWidth:(int)width height:(int)height;
// Resolve legacy phone-native quality before freezing logical dimensions. Returns YES on fallback.
- (BOOL)useCompatibleHost3DResolution;

// Returns a user-readable failure, or nil. Safe to repeat without changing geometry.
- (NSString*)prepareSunlightStreamWithHostSessionSupport:(BOOL)sessionSupport
                                 virtualDisplayCapable:(BOOL)virtualCapable
                                   virtualDisplayReady:(BOOL)virtualReady;
- (NSString*)validateResumeWithRunningAppId:(NSString*)runningAppId
                            runningAppUUID:(NSString*)runningAppUUID
                             hostSessionId:(NSString*)hostSessionId;
- (NSString*)validateHostSessionResponse:(NSString*)hostSessionId resuming:(BOOL)resuming;
- (NSArray<NSURLQueryItem*>*)sunlightLaunchQueryItemsForResume:(BOOL)resuming;
+ (NSString*)normalizedHostSessionId:(NSString*)value;

@property NSString* host;
// Stable machine identity scopes shared controls; appID also scopes picture modes.
@property NSString* hostUUID;
@property NSString* hostName;
@property (nonatomic, copy) SunlightMachineControlsSettings *machineControls;
@property unsigned short httpsPort;
@property NSString* appVersion;
@property NSString* gfeVersion;
@property NSString* appID;
@property NSString* appName;
@property NSString* rtspSessionUrl;
@property int serverCodecModeSupport;
@property BOOL enableYUV444;
@property BOOL enablePIP;
@property BOOL fullColorRange;
@property BOOL enableHdr;
@property BOOL sdrPerformanceWorkaround;
@property int width;
@property int height;
@property int frameRate;
@property int frameRateX100;
@property int bitRate;
@property int riKeyId;
@property NSData* riKey;
@property int gamepadMask;
@property BOOL optimizeGameSettings;
@property BOOL playAudioOnPC;
@property BOOL redirectMic;
@property BOOL swapABXYButtons;
@property BOOL buttonVisualFeedback;
@property BOOL asyncNativeTouchPriority;
@property int gyroMode;
@property int emulatedControllerType;
@property int hapticEngine;
@property int audioConfiguration;
@property int supportedVideoFormats;
@property BOOL multiController;
@property NSData* serverCert;
@property int localMousePointerMode;
@property CGFloat localVolume;

@end
