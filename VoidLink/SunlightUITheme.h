#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// Shared with Moonlight 3D res/values/colors_xr.xml. Keep these semantic roles
// together so the app, PC, and picture settings use the same visual language.
@interface SunlightUITheme : NSObject
+ (UIColor *)surfaceColor;
+ (UIColor *)raisedColor;
+ (UIColor *)sunkenColor;
+ (UIColor *)borderColor;
+ (UIColor *)accentColor;
+ (UIColor *)brightAccentColor;
+ (UIColor *)deepAccentColor;
+ (UIColor *)primaryTextColor;
+ (UIColor *)secondaryTextColor;
+ (UIColor *)disabledTextColor;
+ (UIColor *)dangerColor;
+ (UIColor *)dangerContainerColor;
+ (UIColor *)tileBorderColor;
+ (UIColor *)panelBorderColor;
+ (UIColor *)statusOKColor;
+ (UIColor *)statusWarningColor;
+ (void)styleNavigationController:(UINavigationController *)navigation;
+ (void)styleChoiceControl:(UISegmentedControl *)control;
+ (void)styleSwitch:(UISwitch *)control;
+ (void)styleSlider:(UISlider *)control;
@end
NS_ASSUME_NONNULL_END
