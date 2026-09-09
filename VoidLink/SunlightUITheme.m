#import "SunlightUITheme.h"

static UIColor *SLXRColor(unsigned rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0
        green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}

@implementation SunlightUITheme
+ (UIColor *)surfaceColor { return SLXRColor(0x16181E); }
+ (UIColor *)raisedColor { return SLXRColor(0x22262B); }
+ (UIColor *)sunkenColor { return SLXRColor(0x0C0F14); }
+ (UIColor *)borderColor { return SLXRColor(0x3C4043); }
+ (UIColor *)accentColor { return SLXRColor(0x8AB4F8); }
+ (UIColor *)brightAccentColor { return SLXRColor(0xD7E5FF); }
+ (UIColor *)deepAccentColor { return SLXRColor(0x36587F); }
+ (UIColor *)primaryTextColor { return SLXRColor(0xFFFFFF); }
+ (UIColor *)secondaryTextColor { return SLXRColor(0xB0B9C6); }
+ (UIColor *)disabledTextColor { return SLXRColor(0x71808F); }
+ (UIColor *)dangerColor { return SLXRColor(0xFFB4AB); }
+ (UIColor *)dangerContainerColor { return SLXRColor(0x6D3A3E); }
+ (UIColor *)tileBorderColor { return SLXRColor(0x455466); }
+ (UIColor *)panelBorderColor { return SLXRColor(0x34485D); }
+ (UIColor *)statusOKColor { return SLXRColor(0x5CD65C); }
+ (UIColor *)statusWarningColor { return SLXRColor(0xE0B020); }
+ (void)styleNavigationController:(UINavigationController *)navigation {
    navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    navigation.view.tintColor = self.accentColor;
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = self.surfaceColor;
    appearance.shadowColor = self.borderColor;
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName:self.primaryTextColor};
    appearance.largeTitleTextAttributes = appearance.titleTextAttributes;
    navigation.navigationBar.standardAppearance = appearance;
    navigation.navigationBar.scrollEdgeAppearance = appearance;
    navigation.navigationBar.compactAppearance = appearance;
    navigation.navigationBar.tintColor = self.accentColor;
}
+ (void)styleChoiceControl:(UISegmentedControl *)control {
    control.backgroundColor = self.raisedColor;
    control.selectedSegmentTintColor = self.deepAccentColor;
    control.layer.borderWidth = 1;
    control.layer.borderColor = self.tileBorderColor.CGColor;
    [control setTitleTextAttributes:@{NSForegroundColorAttributeName:self.primaryTextColor} forState:UIControlStateNormal];
    [control setTitleTextAttributes:@{NSForegroundColorAttributeName:self.primaryTextColor} forState:UIControlStateSelected];
    [control setTitleTextAttributes:@{NSForegroundColorAttributeName:self.disabledTextColor} forState:UIControlStateDisabled];
}
+ (void)styleSwitch:(UISwitch *)control { control.onTintColor = self.deepAccentColor; control.thumbTintColor = self.accentColor; }
+ (void)styleSlider:(UISlider *)control { control.minimumTrackTintColor = self.accentColor; control.maximumTrackTintColor = self.borderColor; control.thumbTintColor = self.primaryTextColor; }
@end
