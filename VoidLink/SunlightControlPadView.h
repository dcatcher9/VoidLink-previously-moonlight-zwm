#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A local, multitouch gamepad. Callbacks run on the main thread; owners should
/// capture themselves weakly and route input through their active-session gate.
@interface SunlightControlPadView : UIView
@property (nonatomic, copy, nullable) void (^buttonChangedHandler)(int flag, BOOL down);
/// Stick coordinates are -1...1, with positive Y pointing up.
@property (nonatomic, copy, nullable) void (^leftStickChangedHandler)(CGPoint position);
@property (nonatomic, copy, nullable) void (^rightStickChangedHandler)(CGPoint position);
/// The touch trigger buttons send 1 when held and 0 when released.
@property (nonatomic, copy, nullable) void (^leftTriggerChangedHandler)(float value);
@property (nonatomic, copy, nullable) void (^rightTriggerChangedHandler)(float value);

/// Cancels current touches and releases held input once. Old touches cannot
/// reactivate controls; a new touch is required after cancellation.
- (void)releaseAllControls;
/// Preserves 44-point buttons in both the two-row and wide layouts.
+ (CGFloat)preferredHeightForWidth:(CGFloat)width;
@end

NS_ASSUME_NONNULL_END
