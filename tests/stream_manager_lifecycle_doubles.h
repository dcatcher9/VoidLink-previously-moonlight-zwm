#import <Foundation/Foundation.h>
#import "Plot.h"
#import "StreamConfiguration.h"
#import "HttpRequest.h"

// Minimal dependency interfaces for compiling the unchanged production manager
// on macOS. Network responses/configuration use the production implementations.
@interface UIView : NSObject @end
@protocol ConnectionCallbacks <NSObject>
- (void)launchFailed:(NSString *)message;
@end
@interface TestFrameQueue : NSObject
- (void)clear;
@end
@interface VideoDecoderRenderer : NSObject
@property BOOL stereoPresentation;
@property BOOL needRequeuing;
@property int32_t queueSize;
@property TestFrameQueue *frameQueue;
- (id)initWithView:(UIView *)view callbacks:(id<ConnectionCallbacks>)callbacks streamAspectRatio:(float)aspect;
- (id)initWithView:(UIView *)view callbacks:(id<ConnectionCallbacks>)callbacks streamAspectRatio:(float)aspect presentationSettings:(TemporarySettings *)settings;
- (void)cleanup;
- (void)setRequeuingRequired:(BOOL)required;
@end
@interface BandwidthTracker : NSObject
@property double averageMbps;
@property double peakMbps;
@end
@interface Connection : NSOperation
- (id)initWithConfig:(StreamConfiguration *)config renderer:(VideoDecoderRenderer *)renderer connectionCallbacks:(id<ConnectionCallbacks>)callbacks;
- (void)terminate;
- (void)terminateWithCompletion:(dispatch_block_t)completion;
- (BOOL)getVideoStats:(video_stats_t *)stats;
- (BandwidthTracker *)getBwTracker;
- (NSString *)getActiveCodecName;
@end
@interface CryptoManager : NSObject
+ (void)generateKeyPairUsingSSL;
@end
@interface HttpManager : NSObject
- (id)initWithAddress:(NSString *)address httpsPort:(unsigned short)port serverCert:(NSData *)cert;
- (NSURLRequest *)newServerInfoRequest:(BOOL)fastFail;
- (NSURLRequest *)newHttpServerInfoRequest;
- (NSURLRequest *)newLaunchOrResumeRequest:(NSString *)verb config:(StreamConfiguration *)config;
- (void)executeRequestSynchronously:(HttpRequest *)request;
@end
@interface ServerInfoResponse : HttpResponse @end
@interface Utils : NSObject
+ (NSData *)randomBytes:(NSInteger)length;
@end
typedef NS_ENUM(NSInteger, FramePacingMode) {
    FramePacingModeOff, FramePacingModeLegacy, FramePacingModeQueue, FramePacingModeInterpolation
};
@interface TemporarySettings : NSObject
@property NSNumber *framePacingMode;
@end
@interface DataManager : NSObject
- (TemporarySettings *)getSettings;
@end
@interface LocalizationHelper : NSObject
+ (NSString *)localizedStringForKey:(NSString *)key, ... NS_FORMAT_FUNCTION(1, 2);
@end
@interface PublicUtils : NSObject
+ (NSString *)onScreenRuntimeStats;
@end
