#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "SunlightInputGate.h"

#define LOG_D 0
#define Log(...) ((void)0)

@interface StreamView : UIView
@property (nonatomic, strong) UIView *streamFrameTopLayerView;
@property (nonatomic, strong) SunlightInputGate *gate;
@property (nonatomic, readonly) NSUInteger hostInputGeneration;
@property (nonatomic, readonly) BOOL hostInputAllowed;
@property (nonatomic, readonly) BOOL hostTouchInputAllowed;
- (void)performHostInputForGeneration:(NSUInteger)generation action:(dispatch_block_t)action;
- (void)performHostInput:(dispatch_block_t)action;
@end
@interface TemporarySettings : NSObject
@property (nonatomic, strong) NSNumber *singleTapSensitivity;
@property (nonatomic, strong) NSNumber *relativeTouchSlideThreshold;
@property (nonatomic, strong) NSNumber *mousePointerVelocityFactor;
@end
@interface OnScreenControls : NSObject
@property (class, nonatomic, readonly) NSMutableSet *touchesCapturedByOnScreenControls;
@end
@interface UITouchUtil : NSObject
+ (NSSet *)touchesIn:(UIView *)view from:(UIEvent *)event;
+ (CGVector)vectorOf:(UITouch *)touch in:(UIView *)view;
@end
// Scroll is an independent Swift component; this fixture tests mouse gestures.
@interface TouchPadGestureHandler : NSObject
@property (class, nonatomic) BOOL ctrlDown;
+ (void)handleGestureIn:(UIView *)view with:(UIEvent *)event;
+ (void)startInertialScroll;
@end
@interface CommandManager : NSObject
@property (class, nonatomic, readonly) NSDictionary<NSString *, NSNumber *> *keyboardButtonMappings;
@end
