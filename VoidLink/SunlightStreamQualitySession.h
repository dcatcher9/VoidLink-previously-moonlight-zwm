#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "SunlightStreamQualityProfile.h"

NS_ASSUME_NONNULL_BEGIN

// Main-thread state for one app's picture tabs. Owns detached quality snapshots
// and drafts; it neither controls a connection nor reads UIKit or Core Data.
// Only commitMode: writes preferences, after the controller accepts reconnect.
@interface SunlightStreamQualitySession : NSObject
- (instancetype)initWithConfiguration:(StreamConfiguration *)configuration
                             defaults:(NSUserDefaults *)defaults
                             fallback:(SunlightStreamQualityProfile *)fallback
                           nativeSize:(CGSize)nativeSize
                               drafts:(nullable NSDictionary<NSNumber *, SunlightStreamQualityProfile *> *)drafts
                           resetModes:(nullable NSSet<NSNumber *> *)resetModes;

// The current settled glasses canvas. Unknown output is CGSizeZero. Raw always
// projects onto this canvas; it never adopts the device's Native policy.
@property (nonatomic) CGSize outputSize;
// Reconnect handoff returns deep copies, so retiring and replacement sessions
// cannot mutate each other's per-tab drafts.
@property (nonatomic, readonly) NSDictionary<NSNumber *, SunlightStreamQualityProfile *> *drafts;
@property (nonatomic, readonly) NSSet<NSNumber *> *resetModes;
- (BOOL)hasPendingChangesForMode:(SunlightStreamMode)mode;
- (SunlightStreamQualityProfile *)profileForMode:(SunlightStreamMode)mode includingPending:(BOOL)includingPending;
- (StreamConfiguration *)configurationForMode:(SunlightStreamMode)mode includingPending:(BOOL)includingPending;
- (void)stageWidth:(int)width height:(int)height frameRate:(int)frameRate bitRate:(int)bitRate
    usesNativeResolution:(BOOL)native forMode:(SunlightStreamMode)mode;
- (void)restoreDefaultsForMode:(SunlightStreamMode)mode globalFallback:(SunlightStreamQualityProfile *)fallback;
- (BOOL)commitMode:(SunlightStreamMode)mode;
// Capture before reconnect tears down the panel and discards its drafts. Invoke
// only when reconnect is accepted; rejected actions leave preferences unchanged.
- (BOOL (^)(void))commitActionForMode:(SunlightStreamMode)mode;
- (void)discardPendingChanges;
@end

NS_ASSUME_NONNULL_END
