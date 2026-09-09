#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(13.0))
@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>

@property (strong, nonatomic, nullable) UIWindow *window;

+ (void)setExternalDisplayRenderView:(UIView *)renderView;
+ (void)clearExternalDisplayRenderView;
+ (void)clearExternalDisplayRenderView:(UIView *)renderView;
+ (BOOL)isExternalDisplayAvailable;
+ (BOOL)isExternalDisplayRenderView:(UIView * _Nullable)renderView;
+ (UIScreen * _Nullable)externalDisplayScreen;
+ (BOOL)isExternalDisplaySessionRole:(UISceneSessionRole)role;

@end

NS_ASSUME_NONNULL_END
