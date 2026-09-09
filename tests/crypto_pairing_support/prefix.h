#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "Utils.h"
#define Log(...) do {} while (0)
#define deviceName @"PairingTests"
typedef NSUInteger UIBackgroundTaskIdentifier;
#define UIBackgroundTaskInvalid NSUIntegerMax
@interface UIApplication : NSObject
@property NSUInteger begun;
@property NSUInteger ended;
+ (instancetype)sharedApplication;
- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithName:(NSString *)name expirationHandler:(dispatch_block_t)handler;
- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)identifier;
@end
