#import <Foundation/Foundation.h>
@interface CommandManager : NSObject
+ (void)presetDefaultCommands;
@end
@interface GenericUtils : NSObject
+ (void)installSegmentedControlPreviousSelectionTracking;
@end
@interface IAPManager : NSObject
+ (instancetype)shared;
@end
