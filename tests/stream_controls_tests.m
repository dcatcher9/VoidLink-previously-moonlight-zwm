#import <UIKit/UIKit.h>
#import "SunlightStreamControlsView.h"
#import "SunlightNativeResolution.h"
#import "SunlightMoonlightIcons.h"
#import "SunlightUITheme.h"
#import "SunlightSharedSettingsViewController.h"

static NSUInteger checks;
static BOOL sharedSettingsOnly;
static BOOL overlayOnly;
static void FinishTests(void) { printf("STREAM_CONTROLS_TESTS_RESULT: PASS %lu checks\n", (unsigned long)checks); fflush(stdout); exit(0); }
static void Require(BOOL condition, NSString *message) {
    if (!condition) { printf("STREAM_CONTROLS_TESTS_RESULT: FAIL %s\n", message.UTF8String); fflush(stdout); exit(1); }
    checks++;
}
static UIView *Find(UIView *view, NSString *identifier) {
    if ([view.accessibilityIdentifier isEqualToString:identifier]) return view;
    for (UIView *child in view.subviews) { UIView *found = Find(child, identifier); if (found) return found; }
    return nil;
}
static NSUInteger CountText(UIView *view, NSString *text) {
    if (view.hidden) return 0;
    NSUInteger count = [view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqualToString:text] ? 1 : 0;
    for (UIView *child in view.subviews) count += CountText(child, text);
    return count;
}
static void Tap(UIView *view, NSString *identifier) {
    UIControl *control = (UIControl *)Find(view, identifier);
    Require([control isKindOfClass:UIControl.class], [@"Missing control: " stringByAppendingString:identifier]);
    [control sendActionsForControlEvents:UIControlEventTouchUpInside];
}
static void OpenPicture(SunlightStreamControlsView *overlay) {
    if (!overlay.expanded) Tap(overlay, @"sunlight.controls.pill");
}
static void Choose(UIView *view, NSString *identifier, NSInteger index) {
    UISegmentedControl *control = (UISegmentedControl *)Find(view, identifier);
    Require([control isKindOfClass:UIControl.class] && [control respondsToSelector:@selector(setSelectedSegmentIndex:)], [@"Missing selector: " stringByAppendingString:identifier]);
    control.selectedSegmentIndex = index; [control sendActionsForControlEvents:UIControlEventValueChanged];
}
static UIAction *MenuAction(UIButton *button, NSString *identifier) {
    for (UIAction *action in button.menu.children) if ([action.identifier isEqualToString:identifier]) return action;
    return nil;
}
static void PerformMenuAction(UIAction *action) {
    Require(action != nil, @"Native menu action exists");
    UIButton *proxy = [UIButton new]; [proxy addAction:action forControlEvents:UIControlEventTouchUpInside];
    [proxy sendActionsForControlEvents:UIControlEventTouchUpInside];
}
static void Layout(UIView *view) { [view setNeedsLayout]; [view layoutIfNeeded]; [view layoutIfNeeded]; }
static void CheckLayout(UIView *view) {
    if (view.hidden) return;
    if (view.hasAmbiguousLayout) {
        NSMutableArray *parts = [NSMutableArray array];
        for (UIView *parent = view; parent; parent = parent.superview) [parts addObject:parent.accessibilityIdentifier ?: NSStringFromClass(parent.class)];
        printf("Ambiguous path: %s frame=%s\n", [parts componentsJoinedByString:@" <- "].UTF8String, NSStringFromCGRect(view.frame).UTF8String);
    }
    Require(!view.hasAmbiguousLayout, [NSString stringWithFormat:@"Ambiguous %@", view.accessibilityIdentifier ?: NSStringFromClass(view.class)]);
    for (UIView *child in view.subviews) CheckLayout(child);
}
static void Save(UIView *view, NSString *name) {
    // Let native navigation bars finish committing their button contents.
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.12]];
    Layout(view);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES];
    }];
    NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:name];
    [UIImagePNGRepresentation(image) writeToFile:path atomically:YES];
}
static void Select(UITableViewController *controller, NSInteger section, NSInteger row) {
    [controller tableView:controller.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
    Layout(controller.navigationController.view ?: controller.view);
}
static UITableViewCell *ShowCell(UITableViewController *controller, NSInteger section, NSInteger row) {
    NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
    [controller.tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    Layout(controller.view);
    UITableViewCell *cell = [controller.tableView cellForRowAtIndexPath:path];
    Require(cell != nil, @"Flat setting row is available in the table"); return cell;
}
static void ChangeFlatChoice(UITableViewController *controller, NSInteger section, NSInteger row, NSString *identifier, NSInteger index) {
    Choose(ShowCell(controller, section, row), identifier, index); Layout(controller.view);
}
static void ChangeFlatSwitch(UITableViewController *controller, NSInteger section, NSInteger row, BOOL on) {
    UISwitch *toggle = (UISwitch *)ShowCell(controller, section, row).accessoryView;
    Require([toggle isKindOfClass:UISwitch.class], @"Inline settings switch exists");
    toggle.on = on; [toggle sendActionsForControlEvents:UIControlEventValueChanged];
}
@interface ControlsTestApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation ControlsTestApp
- (void)runMoonlightIconsTests {
    NSArray *names = @[@"ic_xr_mouse", @"ic_xr_gamepad", @"ic_xr_library", @"ic_computer", @"ic_xr_mode_normal", @"ic_xr_mode_host_sbs", @"ic_xr_mode_client_sbs", @"ic_xr_mode_host_sbs_raw", @"ic_xr_resolution", @"ic_xr_frame_rate", @"ic_xr_bitrate", @"ic_xr_disconnect", @"ic_settings", @"ic_xr_codec", @"ic_xr_hdr", @"ic_xr_video_range", @"ic_xr_frame_pacing", @"ic_xr_audio", @"ic_xr_audio_host", @"ic_xr_diagnostics"];
    NSMutableSet<NSData *> *drawings = [NSMutableSet set];
    for (NSString *name in names) {
        UIImage *icon = [SunlightMoonlightIcons imageNamed:name];
        Require(icon != nil && CGSizeEqualToSize(icon.size, CGSizeMake(24, 24)) && icon.renderingMode == UIImageRenderingModeAlwaysTemplate, [@"Original vector renders as a 24-point template: " stringByAppendingString:name]);
        Require(icon == [SunlightMoonlightIcons imageNamed:name], @"Original vector rasterization is cached");
        [drawings addObject:UIImagePNGRepresentation(icon)];
    }
    Require(drawings.count == names.count && [SunlightMoonlightIcons imageNamed:@"unknown"] == nil, @"The catalog contains distinct original icons and does not invent missing assets");
    CGFloat red, green, blue, alpha; [SunlightUITheme.accentColor getRed:&red green:&green blue:&blue alpha:&alpha];
    Require(fabs(red - 138.0 / 255) < 0.001 && fabs(green - 180.0 / 255) < 0.001 && fabs(blue - 248.0 / 255) < 0.001, @"Shared accent matches Moonlight 3D’s #8AB4F8 token");
}
- (void)runPendingChangesTests {
    SunlightStreamControlsView *overlay = [[SunlightStreamControlsView alloc] initWithFrame:CGRectMake(0, 0, 402, 874)];
    overlay.glasses3DAvailable = YES; overlay.connectionReady = YES;
    __block NSUInteger selections = 0, discards = 0, applies = 0; __block SunlightStreamMode applied;
    __weak SunlightStreamControlsView *weakOverlay = overlay;
    overlay.selectionChangedHandler = ^{ selections++; weakOverlay.qualityWidth = 1920; weakOverlay.qualityHeight = 1080; weakOverlay.qualityFrameRate = 60; };
    overlay.pendingChangesDiscardedHandler = ^{ discards++; };
    overlay.modeApplyHandler = ^(SunlightStreamMode mode) { applies++; applied = mode; };
    __block NSUInteger resets = 0;
    overlay.actionHandler = ^(SunlightStreamControlsAction action) { if (action == SunlightStreamControlsActionModeDefaults) { resets++; weakOverlay.qualityChangesPending = YES; } };
    overlay.activeMode = SunlightStreamMode2D;
    Require(selections == 0, @"Owner mode setters do not echo selection callbacks");
    overlay.expanded = YES; OpenPicture(overlay);
    Require([Find(overlay, @"sunlight.controls.modeDefaults").accessibilityLabel isEqualToString:@"Restore defaults"] && [Find(overlay, @"sunlight.controls.modeDefaults").accessibilityHint containsString:@"global quality defaults for this mode"] && [Find(overlay, @"sunlight.controls.modeDefaults").accessibilityHint containsString:@"Apply & reconnect"], @"Mode reset names global quality, this mode, and its explicit application step");
    Tap(overlay, @"sunlight.controls.modeDefaults");
    Require(resets == 1 && applies == 0 && overlay.qualityChangesPending, @"Restore defaults stages the current mode reset without reconnecting");
    Require(overlay.selectedMode == SunlightStreamMode2D && Find(overlay, @"sunlight.controls.apply") != nil, @"Quality-only edits create Apply inside the 2D tab");
    Tap(overlay, @"sunlight.controls.apply"); Require(applies == 1 && applied == SunlightStreamMode2D, @"Quality-only Reconnect uses selectedMode even when mode is unchanged");
    Choose(overlay, @"sunlight.controls.mode", 1);
    Require(selections == 1 && overlay.selectedMode == SunlightStreamModeHost3D, @"User tab change reports its new selection without callback echoes");
    Require(Find(overlay, @"sunlight.controls.pc") == nil && Find(overlay, @"sunlight.controls.settings") == nil, @"Picture modes do not contain machine input or sound settings");
    Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabRaw3D);
    Require(selections == 2 && Find(overlay, @"sunlight.controls.apply") != nil, @"Raw tab changes report selection and expose their own Apply");
    Tap(overlay, @"sunlight.controls.apply");
    Require(applies == 2 && applied == SunlightStreamModeRawFullSBS && overlay.qualityChangesPending, @"Returning to Raw applies its preserved draft and staged quality");
    UIControl *staleApply = (UIControl *)Find(overlay, @"sunlight.controls.apply");
    Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabClient3D);
    Require(overlay.selectedTab == SunlightStreamControlsTabClient3D && overlay.selectedMode == SunlightStreamModeRawFullSBS && Find(overlay, @"sunlight.controls.apply") == nil && Find(overlay, @"sunlight.controls.resolution") == nil && Find(overlay, @"sunlight.controls.modeDefaults") == nil, @"Client 3D is a browse-only tab retaining the last usable draft");
    Require([((UILabel *)Find(overlay, @"sunlight.controls.modeDetail")).text containsString:@"iOS 27 verification"] && Find(Find(overlay, @"sunlight.controls.scroll"), @"sunlight.controls.disconnect") == nil, @"Client 3D explains verification without owning a session action in its content");
    [staleApply sendActionsForControlEvents:UIControlEventTouchUpInside]; Require(applies == 2, @"Stale Apply cannot activate Client 3D");
    Tap(overlay, @"sunlight.controls.close");
    Require(discards == 1 && !overlay.qualityChangesPending && overlay.selectedMode == SunlightStreamMode2D, @"Close discards mode and quality and notifies their owner once");
    overlay.expanded = YES; overlay.qualityChangesPending = YES; Tap(overlay, @"sunlight.controls.dismiss");
    Require(discards == 2 && !overlay.qualityChangesPending, @"Scrim dismissal also clears staged quality once");
    overlay.expanded = YES; OpenPicture(overlay); Choose(overlay, @"sunlight.controls.mode", 1); NSUInteger beforeLoss = selections;
    overlay.glasses3DAvailable = NO;
    Require(selections == beforeLoss + 1 && overlay.selectedMode == SunlightStreamMode2D, @"Hardware loss notifies the owner after resetting the selected mode");
    overlay.qualityChangesPending = YES; Tap(overlay, @"sunlight.controls.apply");
    Require(applies == 3 && applied == SunlightStreamMode2D, @"2D quality changes remain usable when hardware 3D is unavailable");
    [overlay discardPendingChanges]; Require(discards == 3 && !overlay.qualityChangesPending, @"Owner can explicitly discard the combined pending state");
}
- (void)runGlassesAvailabilityTests {
    SunlightStreamControlsView *overlay = [[SunlightStreamControlsView alloc] initWithFrame:CGRectMake(0, 0, 402, 874)];
    overlay.connectionReady = YES;
    __block NSUInteger applies = 0;
    overlay.modeApplyHandler = ^(SunlightStreamMode mode) { applies++; };
    Require(!overlay.glasses3DAvailable, @"3D hardware availability defaults to false");
    overlay.expanded = YES; OpenPicture(overlay);
    UISegmentedControl *mode = (UISegmentedControl *)Find(overlay, @"sunlight.controls.mode");
    Require(mode.numberOfSegments == 4 && mode.selectedSegmentIndex == 0 && ![mode isEnabledForSegmentAtIndex:SunlightStreamControlsTabHost3D] && ![mode isEnabledForSegmentAtIndex:SunlightStreamControlsTabRaw3D], @"Unavailable glasses show four tabs with 2D selected and Host/Raw disabled");
    Choose(overlay, @"sunlight.controls.mode", 1);
    Require(mode.selectedSegmentIndex == 0 && Find(overlay, @"sunlight.controls.apply") == nil && Find(overlay, @"sunlight.controls.source") == nil, @"Unavailable 3D cannot be staged even by a queued selector action");
    Require([((UILabel *)Find(overlay, @"sunlight.controls.modeDetail")).text containsString:@"Connect your glasses"], @"No output guidance asks for glasses in 3D mode");
    overlay.glasses3DAvailable = YES;
    Require(overlay.activeMode == SunlightStreamMode2D && mode.selectedSegmentIndex == 0 && [mode isEnabledForSegmentAtIndex:1] && applies == 0, @"Hardware becoming ready preserves active 2D without reconnecting");
    Choose(overlay, @"sunlight.controls.mode", 1);
    UIControl *staleApply = (UIControl *)Find(overlay, @"sunlight.controls.apply");
    Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabHost3D);
    overlay.glasses3DAvailable = NO;
    Require(Find(overlay, @"sunlight.controls.mode") == mode && mode.selectedSegmentIndex == 0 && Find(overlay, @"sunlight.controls.back") == nil, @"Losing 3D output returns the selected tab to 2D");
    Require(overlay.activeMode == SunlightStreamMode2D && overlay.selectedMode == SunlightStreamMode2D && applies == 0, @"Hardware loss discards the mode draft without reconnecting");
    mode.selectedSegmentIndex = SunlightStreamControlsTabRaw3D; [mode sendActionsForControlEvents:UIControlEventValueChanged];
    [staleApply sendActionsForControlEvents:UIControlEventTouchUpInside];
    Require(overlay.selectedMode == SunlightStreamMode2D && applies == 0 && Find(overlay, @"sunlight.controls.apply") == nil, @"Stale tab and Apply callbacks cannot change unavailable 3D");
    overlay.glasses3DAvailable = YES;
    Require(mode.selectedSegmentIndex == 0 && Find(overlay, @"sunlight.controls.apply") == nil, @"Restored hardware does not restore a discarded 3D draft");
    Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabRaw3D);
    Require(overlay.selectedMode == SunlightStreamModeRawFullSBS && Find(overlay, @"sunlight.controls.packing") == nil, @"The Raw tab selects its canonical mode without a packing submenu");
    overlay.activeMode = SunlightStreamModeHost3D; overlay.glasses3DAvailable = NO;
    Require(overlay.activeMode == SunlightStreamModeHost3D && mode.selectedSegmentIndex == 0 && applies == 0, @"Hardware status never mutates the owner's active stream mode");
    overlay.expanded = NO; overlay.expanded = YES;
    Require(mode.selectedSegmentIndex == 0 && Find(overlay, @"sunlight.controls.apply") == nil, @"Reopening during output loss cannot create an implicit fallback reconnect");
}
- (void)runActiveModePillTests {
    SunlightStreamControlsView *overlay = [[SunlightStreamControlsView alloc] initWithFrame:CGRectMake(0, 0, 844, 390)];
    overlay.connectionReady = YES; overlay.glasses3DAvailable = YES;
    UIControl *pill = (UIControl *)Find(overlay, @"sunlight.controls.pill");
    UIImageView *icon = (UIImageView *)Find(overlay, @"sunlight.controls.pill.modeIcon");
    Require([pill.accessibilityLabel isEqualToString:@"App settings, 2D"] && CountText(pill, @"2D") == 1 && icon.image == [SunlightMoonlightIcons imageNamed:@"ic_xr_mode_normal"], @"Collapsed 2D pill shows the active mode text and original Moonlight icon");
    overlay.activeMode = SunlightStreamModeHost3D;
    Require([pill.accessibilityLabel isEqualToString:@"App settings, Host 3D"] && CountText(pill, @"Host 3D") == 1 && icon.image == [SunlightMoonlightIcons imageNamed:@"ic_xr_mode_host_sbs"], @"Incoming Host 3D active mode updates pill text and icon");
    overlay.expanded = YES;
    Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabRaw3D);
    Require([pill.accessibilityLabel containsString:@"Host 3D"] && icon.image == [SunlightMoonlightIcons imageNamed:@"ic_xr_mode_host_sbs"], @"Browsing pending Raw does not relabel the connected Host 3D session");
    Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabClient3D);
    Require([pill.accessibilityLabel containsString:@"Host 3D"], @"Deferred Client tab never claims an active Client 3D session");
    overlay.expanded = NO; overlay.glasses3DAvailable = NO;
    Require([pill.accessibilityLabel containsString:@"Host 3D"], @"Hardware loss alone cannot claim that a reconnect has changed the active mode");
    overlay.activeMode = SunlightStreamModeRawFullSBS;
    Require([pill.accessibilityLabel isEqualToString:@"App settings, Raw SBS"] && CountText(pill, @"Raw SBS") == 1 && icon.image == [SunlightMoonlightIcons imageNamed:@"ic_xr_mode_host_sbs_raw"], @"Incoming Raw active mode uses exact shared Raw SBS text and vector");
    overlay.activeMode = SunlightStreamModeRawHalfSBS;
    Require([pill.accessibilityLabel isEqualToString:@"App settings, Raw SBS"], @"Legacy Raw alias keeps the same accurate current-mode pill");
    overlay.activeMode = SunlightStreamMode2D;
    Require([pill.accessibilityLabel isEqualToString:@"App settings, 2D"] && [pill.accessibilityHint containsString:@"stream quality"], @"Completed 2D activation updates the label while preserving the settings action hint");
    Layout(overlay);
    CGPoint center = [pill convertPoint:CGPointMake(CGRectGetMidX(pill.bounds), CGRectGetMidY(pill.bounds)) toView:overlay];
    Require([overlay hitTest:center withEvent:nil] == pill && [overlay hitTest:CGPointMake(20, 20) withEvent:nil] == nil, @"Mode-label changes preserve pill-only input interception");
}
- (void)runNativeQualityTests {
    CGSize native = SunlightNativeLandscapeSize();
    Require(native.width >= native.height && native.height > 0, @"Native resolution uses a valid landscape device canvas");
    SunlightStreamControlsView *overlay = [[SunlightStreamControlsView alloc] initWithFrame:CGRectMake(0, 0, 844, 390)];
    overlay.glasses3DAvailable = YES; overlay.connectionReady = YES;
    overlay.qualityWidth = 2560; overlay.qualityHeight = 1440; overlay.qualityFrameRate = 60;
    overlay.qualityUsesNativeResolution = NO;
    __block NSUInteger edits = 0, applies = 0;
    NSMutableDictionary<NSNumber *, NSArray *> *drafts = [NSMutableDictionary dictionary];
    __weak SunlightStreamControlsView *weak = overlay;
    overlay.qualityChangedHandler = ^(int width, int height, int fps, int bitrate) {
        edits++;
        drafts[@(weak.selectedMode)] = @[@(width), @(height), @(weak.qualityUsesNativeResolution), @(fps), @(bitrate)];
        weak.qualityChangesPending = YES;
    };
    overlay.modeApplyHandler = ^(SunlightStreamMode mode) { applies++; };
    overlay.selectionChangedHandler = ^{
        SunlightStreamControlsView *view = weak;
        NSArray *draft = drafts[@(view.selectedMode)];
        BOOL raw = view.selectedMode == SunlightStreamModeRawFullSBS;
        view.qualityUsesNativeResolution = !raw && [draft[2] boolValue];
        view.qualityWidth = raw ? 3840 : draft ? [draft[0] intValue] : 2560;
        view.qualityHeight = raw ? 1080 : draft ? [draft[1] intValue] : 1440;
        view.qualityFrameRate = draft ? [draft[3] intValue] : 60;
        view.qualityBitrateKbps = draft ? [draft[4] intValue] : 20000;
        view.qualityResolutionLocked = raw;
        view.qualityChangesPending = draft != nil;
    };
    overlay.pendingChangesDiscardedHandler = ^{
        [drafts removeAllObjects]; weak.qualityUsesNativeResolution = NO;
        weak.qualityWidth = 2560; weak.qualityHeight = 1440;
    };
    overlay.expanded = YES;
    UIButton *resolution = (UIButton *)Find(overlay, @"sunlight.controls.resolution");
    UIButton *rates = (UIButton *)Find(overlay, @"sunlight.controls.frameRate");
    UISlider *slider = (UISlider *)Find(overlay, @"sunlight.controls.bitrate");
    UIAction *nativeAction = MenuAction(resolution, @"sunlight.controls.resolution.native");
    Require(nativeAction != nil && nativeAction.image != nil && [nativeAction.title isEqualToString:[NSString stringWithFormat:@"Native · %.0f × %.0f", native.width, native.height]], @"A fixed 2560 canvas still offers labelled device-native resolution with an icon");
    Require(nativeAction.state == UIMenuElementStateOff && edits == 0 && drafts.count == 0, @"Opening fixed quality neither selects Native nor stages a change");
    UIMenu *cached = resolution.menu; overlay.qualityUsesNativeResolution = NO; overlay.touchEnabled = NO;
    Require(resolution.menu == cached, @"Unchanged Native policy reuses the resolution menu");
    PerformMenuAction(nativeAction);
    Require(edits == 1 && applies == 0 && overlay.qualityUsesNativeResolution && overlay.qualityWidth == (int)native.width && overlay.qualityHeight == (int)native.height, @"Native stages the exact phone aspect without reconnecting or selecting a 16:9 preset");
    Require(MenuAction(resolution, @"sunlight.controls.resolution.native").state == UIMenuElementStateOn && [resolution.accessibilityLabel containsString:@"Native"], @"Native policy is visible in the label and checkmark");
    NSString *fixedID = [NSString stringWithFormat:@"sunlight.controls.resolution.%.0fx%.0f", native.width, native.height];
    UIAction *fixedNative = MenuAction(resolution, fixedID);
    Require(fixedNative != nil && fixedNative.state == UIMenuElementStateOff, @"A fixed tuple equal to Native remains a distinct unselected policy");
    NSMutableSet *identifiers = [NSMutableSet set];
    for (UIAction *action in resolution.menu.children) { Require(![identifiers containsObject:action.identifier], @"Resolution menu identifiers do not duplicate"); [identifiers addObject:action.identifier]; }
    PerformMenuAction(MenuAction(resolution, @"sunlight.controls.resolution.native"));
    Require(edits == 1, @"Choosing the already selected Native policy does not emit an edit");
    PerformMenuAction(MenuAction(rates, @"sunlight.controls.frameRate.30"));
    cached = resolution.menu; slider.value = 25; [slider sendActionsForControlEvents:UIControlEventValueChanged];
    Require(edits == 3 && overlay.qualityUsesNativeResolution && resolution.menu == cached, @"FPS and bitrate retain Native and bitrate leaves menus cached");
    PerformMenuAction(MenuAction(resolution, fixedID));
    Require(edits == 4 && !overlay.qualityUsesNativeResolution && overlay.qualityWidth == (int)native.width && MenuAction(resolution, fixedID).state == UIMenuElementStateOn && MenuAction(resolution, @"sunlight.controls.resolution.native").state == UIMenuElementStateOff, @"Choosing the same fixed pixels stages removal of Native policy");
    PerformMenuAction(MenuAction(resolution, @"sunlight.controls.resolution.native"));
    Tap(overlay, @"sunlight.controls.apply"); Require(applies == 1 && edits == 5, @"Only explicit Apply reconnects a staged Native choice");
    UIAction *staleNative = MenuAction(resolution, @"sunlight.controls.resolution.native");
    Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabHost3D);
    Require(!overlay.qualityUsesNativeResolution && overlay.qualityWidth == 2560, @"Owner binding gives another tab its independent fixed baseline");
    PerformMenuAction(staleNative); Require(edits == 5 && !overlay.qualityUsesNativeResolution, @"Native action from a prior tab cannot change the new tab");
    BOOL hostSupportsNative = [StreamConfiguration isSupportedHost3DWidth:(int)native.width height:(int)native.height];
    Require((MenuAction(resolution, @"sunlight.controls.resolution.native") != nil) == hostSupportsNative, @"Host Native availability follows the compatibility helper");
    Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabRaw3D);
    PerformMenuAction(staleNative);
    Require(resolution.menu == nil && !overlay.qualityUsesNativeResolution && overlay.qualityWidth == 3840 && edits == 5, @"Raw remains locked and cannot receive a stale Native selection");
    Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabClient3D);
    PerformMenuAction(staleNative); Require(edits == 5 && Find(overlay, @"sunlight.controls.resolution") == nil, @"Client 3D still cannot edit Native quality");
    Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTab2D);
    Require(overlay.qualityUsesNativeResolution && overlay.qualityWidth == (int)native.width && overlay.qualityFrameRate == 30, @"Returning to 2D restores only that tab’s staged Native policy and quality");
    staleNative = MenuAction(resolution, @"sunlight.controls.resolution.native");
    Tap(overlay, @"sunlight.controls.close"); overlay.expanded = YES;
    PerformMenuAction(staleNative);
    Require(edits == 5 && drafts.count == 0 && !overlay.qualityUsesNativeResolution && overlay.qualityWidth == 2560, @"Close discards Native draft and rejects the abandoned menu action");
}
- (void)runInlineQualityTests {
    SunlightStreamControlsView *overlay = [[SunlightStreamControlsView alloc] initWithFrame:CGRectMake(0, 0, 844, 390)];
    overlay.glasses3DAvailable = YES; overlay.connectionReady = YES;
    __block NSUInteger edits = 0, applies = 0; __block int width, height, fps, bitrate;
    __weak SunlightStreamControlsView *weak = overlay;
    overlay.qualityChangedHandler = ^(int w, int h, int f, int b) { edits++; width = w; height = h; fps = f; bitrate = b; weak.qualityChangesPending = YES; };
    overlay.modeApplyHandler = ^(SunlightStreamMode mode) { applies++; };
    overlay.qualityWidth = 2732; overlay.qualityHeight = 2048; overlay.qualityFrameRate = 75; overlay.qualityBitrateKbps = 17321; overlay.qualityMaxFrameRate = 60;
    overlay.expanded = YES;
    UIButton *resolution = (UIButton *)Find(overlay, @"sunlight.controls.resolution"), *rates = (UIButton *)Find(overlay, @"sunlight.controls.frameRate");
    UISlider *slider = (UISlider *)Find(overlay, @"sunlight.controls.bitrate");
    Require(edits == 0 && overlay.qualityWidth == 2732 && overlay.qualityHeight == 2048 && overlay.qualityFrameRate == 75 && overlay.qualityBitrateKbps == 17321, @"Opening inline controls preserves arbitrary saved values without callbacks or normalization");
    Require(MenuAction(resolution, @"sunlight.controls.resolution.2732x2048").state == UIMenuElementStateOn && MenuAction(rates, @"sunlight.controls.frameRate.75").state == UIMenuElementStateOn, @"Saved tablet resolution and nonpreset FPS appear checked in their native menus");
    Require((MenuAction(rates, @"sunlight.controls.frameRate.75").attributes & UIMenuElementAttributesDisabled) && MenuAction(rates, @"sunlight.controls.frameRate.120") == nil, @"Glasses frame-rate ceiling disables an existing high value and excludes higher presets");
    UIMenu *savedMenu = resolution.menu; overlay.touchEnabled = NO; overlay.statusText = @"Connected"; overlay.qualityWidth = 2732;
    Require(savedMenu == resolution.menu, @"Unchanged quality and unrelated input state reuse native menus");
    PerformMenuAction(MenuAction(resolution, @"sunlight.controls.resolution.1920x1080"));
    Require(edits == 1 && width == 1920 && height == 1080 && fps == 75 && bitrate == 17321 && applies == 0, @"Resolution selection stages exact remaining values without reconnecting");
    PerformMenuAction(MenuAction(rates, @"sunlight.controls.frameRate.60"));
    UIMenu *beforeBitrate = resolution.menu;
    slider.value = 42.5; [slider sendActionsForControlEvents:UIControlEventValueChanged];
    Require(resolution.menu == beforeBitrate, @"Bitrate dragging updates its value without rebuilding resolution menus");
    Require(edits == 3 && fps == 60 && bitrate == 42500 && applies == 0 && overlay.qualityChangesPending, @"Frame rate and bitrate stage directly and reveal this mode’s Apply");
    Tap(overlay, @"sunlight.controls.apply"); Require(applies == 1, @"Only explicit Apply reconnects inline quality");
    UIAction *staleResolution = MenuAction(resolution, @"sunlight.controls.resolution.1280x720");
    Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabHost3D);
    PerformMenuAction(staleResolution); Require(edits == 3 && overlay.qualityWidth == 1920, @"A menu from another tab cannot change this mode’s draft");
    for (UIAction *action in resolution.menu.children) {
        if ([action.identifier isEqualToString:@"sunlight.controls.resolution.native"]) {
            CGSize native = SunlightNativeLandscapeSize();
            Require([StreamConfiguration isSupportedHost3DWidth:(int)native.width height:(int)native.height], @"Host Native choice is supported by the model contract");
        } else {
            NSArray *dimensions = [action.title componentsSeparatedByString:@" × "];
            Require([StreamConfiguration isSupportedHost3DWidth:[dimensions[0] intValue] height:[dimensions[1] intValue]], @"Host preset choices are supported by the host model contract");
        }
    }
    overlay.qualityWidth = 2622; overlay.qualityHeight = 1206;
    Require(MenuAction(resolution, @"sunlight.controls.resolution.2622x1206") != nil && edits == 3, @"Host native phone dimensions remain available unchanged");
    Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabRaw3D); overlay.qualityWidth = 3840; overlay.qualityHeight = 1080;
    Require(!resolution.userInteractionEnabled && resolution.menu == nil && [resolution.accessibilityHint containsString:@"glasses"], @"Raw displays locked full-frame glasses dimensions without a picker");
    PerformMenuAction(staleResolution); Require(edits == 3 && overlay.qualityWidth == 3840, @"A stale resolution menu cannot rewrite Raw’s fixed dimensions");
    slider.value = 35; [slider sendActionsForControlEvents:UIControlEventValueChanged];
    Require(edits == 4 && width == 3840 && height == 1080 && bitrate == 35000, @"Raw inline bitrate edits preserve the full incoming frame");
    Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabClient3D);
    slider.value = 25; [slider sendActionsForControlEvents:UIControlEventValueChanged];
    Require(edits == 4 && Find(overlay, @"sunlight.controls.resolution") == nil, @"Client placeholder contains no editable quality and ignores stale slider events");
    Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTab2D);
    UIAction *staleRate = MenuAction(rates, @"sunlight.controls.frameRate.30"); overlay.expanded = NO; overlay.expanded = YES;
    PerformMenuAction(staleRate); Require(edits == 4, @"A menu retained across Close and reopen cannot stage a late edit");
    overlay.qualityMaxFrameRate = 240;
    Require(MenuAction(rates, @"sunlight.controls.frameRate.240") != nil, @"Device-only 2D can expose its owner-supplied frame-rate ceiling");
    Require(slider.minimumValue == 0.5f, @"The inline slider can select the supported 500 Kbps minimum");
    slider.value = 0.5; [slider sendActionsForControlEvents:UIControlEventValueChanged];
    Require(edits == 5 && bitrate == 500, @"The minimum is staged as exactly 500 Kbps");
    [slider sendActionsForControlEvents:UIControlEventTouchDown];
    Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabHost3D);
    slider.value = 60; [slider sendActionsForControlEvents:UIControlEventValueChanged];
    Require(edits == 5 && overlay.qualityBitrateKbps == 500, @"A bitrate drag started on another tab cannot stage edits after switching");
    [slider sendActionsForControlEvents:UIControlEventTouchDown]; slider.value = 30; [slider sendActionsForControlEvents:UIControlEventValueChanged];
    Require(edits == 6 && bitrate == 30000, @"A new gesture on the selected tab can stage bitrate normally");
    overlay.expanded = NO; overlay.expanded = YES;
    slider.value = 70; [slider sendActionsForControlEvents:UIControlEventValueChanged];
    Require(edits == 6 && overlay.qualityBitrateKbps == 30000, @"A drag cannot continue after Close and reopen");
    [slider accessibilityIncrement];
    Require(edits == 7 && overlay.qualityBitrateKbps > 30000, @"Accessibility increment works after a cancelled physical drag");
}
- (SunlightSharedSettingsViewController *)pcWithShared:(SunlightSharedSettings *)source globals:(SunlightSharedSettings *)globals
                                             controls:(SunlightMachineControlsSettings *)controls globalControls:(SunlightMachineControlsSettings *)globalControls glasses:(BOOL)glasses {
    SunlightSharedSettingsViewController *pc = [[SunlightSharedSettingsViewController alloc] initWithSettings:source globalDefaults:globals hostName:@"Studio PC" glassesOutput:glasses];
    pc.reconnectRequired = NO; pc.machineControls = controls; pc.globalMachineControls = globalControls;
    pc.savedProfileSummary = @"Desktop profile · Direct touch"; return pc;
}
- (void)runSharedSettingsTests {
    SunlightSharedSettings *source = [SunlightSharedSettings new]; source.enableHdr = YES; source.framePacingMode = 3; source.fullColorRange = NO;
    SunlightSharedSettings *globals = [SunlightSharedSettings new]; globals.preferredCodec = 2; globals.playAudioOnPC = YES;
    SunlightMachineControlsSettings *controls = [SunlightMachineControlsSettings new]; controls.controlMode = SunlightMachineControlModeTrackpad; controls.touchEnabled = YES; controls.localVolume = 0.75; controls.statsOverlayLevel = 0;
    SunlightMachineControlsSettings *globalControls = [SunlightMachineControlsSettings new]; globalControls.controlMode = SunlightMachineControlModeSavedTouchProfile; globalControls.touchEnabled = YES; globalControls.localVolume = 0.5; globalControls.statsOverlayLevel = 1;
    SunlightSharedSettings *original = [source copy]; SunlightMachineControlsSettings *originalControls = [controls copy];
    SunlightSharedSettingsViewController *pc = [self pcWithShared:source globals:globals controls:controls globalControls:globalControls glasses:NO];
    __block NSUInteger saves = 0; __block BOOL reset = YES; __block SunlightSharedSettings *result; __block SunlightMachineControlsSettings *resultControls;
    pc.applyMachineSettings = ^(SunlightSharedSettings *shared, BOOL useDefaults, SunlightMachineControlsSettings *machine) { saves++; result = shared; reset = useDefaults; resultControls = machine; };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:pc]; self.window.rootViewController = nav;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        Layout(nav.view);
        Require([pc numberOfSectionsInTableView:pc.tableView] == 6, @"PC settings have six flat sections, including controls, sound, statistics and Save");
        NSArray<NSNumber *> *counts = @[@3, @3, @2, @1, @1, @2];
        for (NSUInteger section = 0; section < counts.count; section++) Require([pc tableView:pc.tableView numberOfRowsInSection:section] == [counts[section] integerValue], @"Each PC setting group has its direct controls");
        UITableViewCell *save = [pc tableView:pc.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:5]];
        Require([save.textLabel.text isEqualToString:@"Save settings"] && [[pc tableView:pc.tableView titleForFooterInSection:5] containsString:@"future connections to Studio PC"], @"App-list PC settings explain Save for future connections to this PC");
        Require(pc.machineControls != controls && pc.globalMachineControls != globalControls, @"Opening the form copies both machine models");
        UIView *videoHeader = Find(pc.view, @"shared.settings.group.0");
        Require(videoHeader != nil && CountText(videoHeader, @"Video") == 1, @"The icon header draws its section title once without UIKit overlap");
        Save(nav.view, @"pc-settings-flat-video-landscape.png");
        ChangeFlatSwitch(pc, 0, 0, NO);
        ChangeFlatChoice(pc, 0, 1, @"shared.settings.range.selector", 1);
        ChangeFlatChoice(pc, 0, 2, @"shared.settings.codec.selector", 3);
        ChangeFlatChoice(pc, 1, 0, @"shared.settings.pacing.selector", 1);
        ChangeFlatChoice(pc, 1, 1, @"shared.settings.audio.selector", 3);
        ChangeFlatSwitch(pc, 1, 2, YES);
        UITableViewCell *modeCell = ShowCell(pc, 2, 1);
        Require(((UISegmentedControl *)Find(modeCell, @"shared.settings.control-mode.selector")).selectedSegmentIndex == SunlightMachineControlModeTrackpad, @"PC input defaults to the actual selected Trackpad mode");
        ChangeFlatSwitch(pc, 2, 0, NO);
        ChangeFlatChoice(pc, 2, 1, @"shared.settings.control-mode.selector", SunlightMachineControlModeGamepad);
        Require(pc.machineControls.controlMode == SunlightMachineControlModeGamepad && !pc.machineControls.touchEnabled, @"Direct PC controls stage Gamepad and paused touch together");
        [pc.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2] atScrollPosition:UITableViewScrollPositionTop animated:NO]; Save(nav.view, @"pc-settings-flat-input-landscape.png");
        UISlider *volume = (UISlider *)Find(ShowCell(pc, 3, 0), @"shared.settings.volume.slider");
        Require(volume != nil, @"PC volume is an inline slider"); volume.value = 0.42; [volume sendActionsForControlEvents:UIControlEventValueChanged];
        ChangeFlatChoice(pc, 4, 0, @"shared.settings.statistics.selector", 2);
        Require(fabs(pc.machineControls.localVolume - 0.42) < 0.000001 && pc.machineControls.statsOverlayLevel == 2, @"Sound and statistics stage directly in their separated groups");
        for (NSInteger section = 0; section < 5; section++) for (NSInteger row = 0; row < counts[section].integerValue; row++) Select(pc, section, row);
        Require(nav.viewControllers.count == 1 && saves == 0 && [source isEqualToSettings:original] && [controls isEqualToSettings:originalControls], @"All PC edits stay flat and detached until Save");
        [pc.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:5] atScrollPosition:UITableViewScrollPositionBottom animated:NO]; Save(nav.view, @"pc-settings-flat-actions-landscape.png");
        Select(pc, 5, 1); Select(pc, 5, 1);
        Require(saves == 1 && !reset && result.preferredCodec == 3 && result.framePacingMode == 1 && result.audioConfig == 8 && !result.enableHdr && result.fullColorRange && result.playAudioOnPC, @"Save submits exact shared settings once");
        Require(result != source && resultControls != controls && resultControls != pc.machineControls && resultControls.controlMode == SunlightMachineControlModeGamepad && !resultControls.touchEnabled && resultControls.statsOverlayLevel == 2 && fabs(resultControls.localVolume - 0.42) < 0.000001, @"One combined Save returns detached machine settings without any app quality");
        ChangeFlatChoice(pc, 0, 2, @"shared.settings.codec.selector", 0); Select(pc, 5, 1);
        Require(saves == 1 && result.preferredCodec == 3, @"Submitted form rejects repeated or queued edits and Save");
        SunlightSharedSettingsViewController *resetPC = [self pcWithShared:source globals:globals controls:controls globalControls:globalControls glasses:NO];
        __block NSUInteger resetSaves = 0; __block BOOL exactReset = NO;
        resetPC.applyMachineSettings = ^(SunlightSharedSettings *shared, BOOL useDefaults, SunlightMachineControlsSettings *machine) { resetSaves++; exactReset = useDefaults && [shared isEqualToSettings:globals] && [machine isEqualToSettings:globalControls] && shared != globals && machine != globalControls; };
        [nav setViewControllers:@[resetPC] animated:NO]; Layout(nav.view); Select(resetPC, 5, 0);
        Require([resetPC.machineControls isEqualToSettings:globalControls] && [controls isEqualToSettings:originalControls], @"Restore stages copies of both global models without touching originals");
        Select(resetPC, 5, 1); Require(resetSaves == 1 && exactReset, @"Saving the reset returns exactly both global defaults with its reset flag");
        SunlightSharedSettingsViewController *edited = [self pcWithShared:source globals:globals controls:controls globalControls:globalControls glasses:NO];
        __block BOOL editedReset = YES;
        edited.applyMachineSettings = ^(SunlightSharedSettings *shared, BOOL useDefaults, SunlightMachineControlsSettings *machine) { editedReset = useDefaults; };
        [nav setViewControllers:@[edited] animated:NO]; Layout(nav.view); Select(edited, 5, 0);
        ChangeFlatChoice(edited, 2, 1, @"shared.settings.control-mode.selector", SunlightMachineControlModeTrackpad); Select(edited, 5, 1);
        Require(!editedReset, @"Editing a control after reset clears whole-PC inheritance");
        SunlightSharedSettingsViewController *sharedEdited = [self pcWithShared:source globals:globals controls:controls globalControls:globalControls glasses:NO];
        __block BOOL sharedEditedReset = YES;
        sharedEdited.applyMachineSettings = ^(SunlightSharedSettings *shared, BOOL useDefaults, SunlightMachineControlsSettings *machine) { sharedEditedReset = useDefaults; };
        [nav setViewControllers:@[sharedEdited] animated:NO]; Layout(nav.view); Select(sharedEdited, 5, 0);
        ChangeFlatChoice(sharedEdited, 0, 2, @"shared.settings.codec.selector", 3); Select(sharedEdited, 5, 1);
        Require(!sharedEditedReset, @"Editing shared video after reset also clears whole-PC inheritance");
        SunlightSharedSettingsViewController *glasses = [self pcWithShared:source globals:globals controls:controls globalControls:globalControls glasses:YES];
        __block SunlightSharedSettings *retained;
        glasses.applyMachineSettings = ^(SunlightSharedSettings *shared, BOOL useDefaults, SunlightMachineControlsSettings *machine) { retained = shared; };
        [nav setViewControllers:@[glasses] animated:NO]; Layout(nav.view);
        UITableViewCell *hdr = ShowCell(glasses, 0, 0), *pacing = ShowCell(glasses, 1, 0);
        Require(hdr.accessoryView == nil && Find(pacing, @"shared.settings.pacing.selector") == nil && [hdr.detailTextLabel.text containsString:@"SDR"] && [pacing.detailTextLabel.text containsString:@"Queue"], @"Glasses constraints remain visible static values without overwriting saved preferences");
        Select(glasses, 5, 1); Require(retained.enableHdr && retained.framePacingMode == 3, @"Glasses Save retains the configured HDR and pacing for future compatible output");
        [self finishFlatPCWithCancel:source globals:globals controls:controls globalControls:globalControls];
    });
}
- (void)finishFlatPCWithCancel:(SunlightSharedSettings *)source globals:(SunlightSharedSettings *)globals controls:(SunlightMachineControlsSettings *)controls globalControls:(SunlightMachineControlsSettings *)globalControls {
    UIViewController *presenter = [UIViewController new]; self.window.rootViewController = presenter;
    SunlightSharedSettings *original = [source copy]; SunlightMachineControlsSettings *originalControls = [controls copy];
    SunlightSharedSettingsViewController *pc = [self pcWithShared:source globals:globals controls:controls globalControls:globalControls glasses:NO];
    __block NSUInteger saves = 0, closes = 0;
    pc.applyMachineSettings = ^(SunlightSharedSettings *shared, BOOL reset, SunlightMachineControlsSettings *machine) { saves++; };
    pc.closed = ^{ closes++; };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:pc]; nav.modalPresentationStyle = UIModalPresentationFullScreen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        [presenter presentViewController:nav animated:NO completion:^{
            ChangeFlatChoice(pc, 2, 1, @"shared.settings.control-mode.selector", SunlightMachineControlModeSavedTouchProfile);
            ChangeFlatSwitch(pc, 2, 0, NO);
            [nav setOverrideTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge] forChildViewController:pc];
            Layout(nav.view); Save(nav.view, @"pc-settings-flat-large-text.png");
            Require(CGRectContainsRect(nav.view.bounds, pc.tableView.frame) && [pc tableView:pc.tableView numberOfRowsInSection:2] == 2, @"Maximum Dynamic Type keeps flat controls in the native scrolling form");
            UISlider *retainedVolume = (UISlider *)Find(ShowCell(pc, 3, 0), @"shared.settings.volume.slider");
            SunlightMachineControlsSettings *cancelledDraft = [pc.machineControls copy];
            UIBarButtonItem *cancel = pc.navigationItem.leftBarButtonItem;
            [UIApplication.sharedApplication sendAction:cancel.action to:cancel.target from:cancel forEvent:nil];
            retainedVolume.value = 0.1; [retainedVolume sendActionsForControlEvents:UIControlEventValueChanged];
            Select(pc, 5, 0); Select(pc, 5, 1);
            [UIApplication.sharedApplication sendAction:cancel.action to:cancel.target from:cancel forEvent:nil];
            Require(saves == 0 && [pc.machineControls isEqualToSettings:cancelledDraft], @"Cancel immediately retires retained slider, reset, Save and repeated Cancel actions");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
                Require(presenter.presentedViewController == nil && closes == 1 && saves == 0 && [source isEqualToSettings:original] && [controls isEqualToSettings:originalControls], @"Cancel dismisses the real PC form once without saving either model");
                SunlightSharedSettingsViewController *swiped = [self pcWithShared:source globals:globals controls:controls globalControls:globalControls glasses:NO];
                swiped.applyMachineSettings = pc.applyMachineSettings;
                __block NSUInteger swipeCloses = 0;
                swiped.closed = ^{ swipeCloses++; };
                [swiped loadViewIfNeeded];
                id<UIAdaptivePresentationControllerDelegate> delegate = (id)swiped;
                [delegate presentationControllerDidDismiss:nav.presentationController];
                [delegate presentationControllerDidDismiss:nav.presentationController];
                Select(swiped, 5, 1);
                Require(swipeCloses == 1 && saves == 0, @"Interactive sheet dismissal retires Save and closes once");
                FinishTests();
            });
        }];
    });
}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    [UIView setAnimationsEnabled:NO];
    sharedSettingsOnly = [NSProcessInfo.processInfo.arguments containsObject:@"--shared-settings-only"];
    overlayOnly = [NSProcessInfo.processInfo.arguments containsObject:@"--overlay-only"];
    if (sharedSettingsOnly) {
        self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; self.window.rootViewController = [UIViewController new]; [self.window makeKeyAndVisible];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{ [self runSharedSettingsTests]; });
        return YES;
    }
    [self runMoonlightIconsTests];
    [self runPendingChangesTests];
    [self runGlassesAvailabilityTests];
    [self runInlineQualityTests];
    [self runNativeQualityTests];
    [self runActiveModePillTests];
    UIViewController *host = [UIViewController new], *fixture = [UIViewController new];
    [host addChildViewController:fixture]; [host.view addSubview:fixture.view]; [fixture didMoveToParentViewController:host];
    fixture.view.backgroundColor = [UIColor colorWithRed:0.035 green:0.065 blue:0.085 alpha:1];
    SunlightStreamControlsView *overlay = [[SunlightStreamControlsView alloc] initWithFrame:CGRectMake(0, 0, 844, 390)];
    [fixture.view addSubview:overlay]; overlay.appName = @"Desktop"; overlay.connectionReady = YES; overlay.externalOutputActive = YES;
    overlay.inputHint = @"Slide to move · Tap to click\nTwo-finger tap to right-click · Two fingers to scroll";
    overlay.statusText = @"Desktop · Glasses connected"; overlay.qualityUsesNativeResolution = YES; overlay.qualityWidth = 2622; overlay.qualityHeight = 1206; overlay.qualityFrameRate = 60; overlay.qualityMaxFrameRate = 60;
    __block NSUInteger expansions = 0, applies = 0, exits = 0, qualityEdits = 0;
    __block SunlightStreamMode applied;
    __weak SunlightStreamControlsView *weakOverlay = overlay;
    overlay.expansionChangedHandler = ^(BOOL expanded) { expansions++; };
    overlay.modeApplyHandler = ^(SunlightStreamMode mode) { applies++; applied = mode; };
    overlay.actionHandler = ^(SunlightStreamControlsAction action) { if (action == SunlightStreamControlsActionDisconnect) exits++; };
    overlay.qualityChangedHandler = ^(int width, int height, int fps, int bitrate) { qualityEdits++; weakOverlay.qualityChangesPending = YES; };
    overlay.selectionChangedHandler = ^{
        SunlightStreamControlsView *controls = weakOverlay;
        controls.qualityUsesNativeResolution = controls.selectedMode == SunlightStreamMode2D;
        controls.qualityWidth = controls.selectedMode == SunlightStreamModeRawFullSBS ? 3840 : controls.selectedMode == SunlightStreamModeHost3D ? 1920 : 2622;
        controls.qualityHeight = controls.selectedMode == SunlightStreamMode2D ? 1206 : 1080;
        controls.qualityFrameRate = 60; controls.qualityBitrateKbps = 20000;
    };
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; self.window.rootViewController = host; [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        fixture.view.frame = CGRectMake(0, 0, 844, 390); overlay.frame = fixture.view.bounds; Layout(overlay);
        UIControl *pill = (UIControl *)Find(overlay, @"sunlight.controls.pill"), *exitButton = (UIControl *)Find(overlay, @"sunlight.controls.disconnect");
        UIView *panel = Find(overlay, @"sunlight.controls.panel"); UIScrollView *scroll = (UIScrollView *)Find(overlay, @"sunlight.controls.scroll");
        CGPoint pillCenter = [pill convertPoint:CGPointMake(CGRectGetMidX(pill.bounds), CGRectGetMidY(pill.bounds)) toView:overlay];
        CGPoint exitCenter = [exitButton convertPoint:CGPointMake(CGRectGetMidX(exitButton.bounds), CGRectGetMidY(exitButton.bounds)) toView:overlay];
        Require([pill.accessibilityLabel containsString:@"App settings"] && [exitButton.accessibilityLabel isEqualToString:@"End session"], @"App settings and session exit have clear accessible names");
        Require(exitButton.bounds.size.width >= 44 && exitButton.bounds.size.height >= 44 && [exitButton isDescendantOfView:panel] && ![exitButton isDescendantOfView:scroll], @"End session has one 44-point common-footer target inside App settings but outside mode content");
        Require([overlay hitTest:pillCenter withEvent:nil] == pill && [overlay hitTest:exitCenter withEvent:nil] == nil, @"Only the settings pill intercepts the collapsed phone surface");
        Require([overlay hitTest:CGPointMake(200, 130) withEvent:nil] == nil && [overlay hitTest:CGPointMake(80, 50) withEvent:nil] == nil, @"Trackpad space including the top-left surface remains pass-through");
        Require(!overlay.accessibilityViewIsModal && [((UILabel *)Find(overlay, @"sunlight.controls.hintDetail")).text containsString:@"Tap to click"], @"Existing tap-to-click guidance remains on the pass-through control surface");
        Save(fixture.view, @"phone-control-surface-landscape.png"); CheckLayout(overlay);
        [exitButton sendActionsForControlEvents:UIControlEventTouchUpInside]; Require(exits == 0 && !overlay.expanded, @"A hidden footer cannot end the stream from a stale callback");
        overlay.touchEnabled = NO; Layout(overlay); Require([((UILabel *)Find(overlay, @"sunlight.controls.hintDetail")).text containsString:@"PC’s settings"], @"Paused touch guidance points to machine settings"); Save(fixture.view, @"picture-paused-hint.png"); overlay.touchEnabled = YES;
        OpenPicture(overlay); Layout(overlay);
        Require(overlay.expanded && expansions == 1 && overlay.accessibilityViewIsModal && [((UILabel *)Find(panel, @"sunlight.controls.title")).text isEqualToString:@"App settings · Desktop"], @"Pill opens this app’s four-tab settings directly and blocks remote input");
        Require([overlay hitTest:CGPointMake(1, 1) withEvent:nil] == Find(overlay, @"sunlight.controls.dismiss"), @"Expanded scrim consumes outside touches without reaching PC");
        Tap(overlay, @"sunlight.controls.disconnect"); Require(exits == 1 && applies == 0, @"The common footer dispatches only the End session action");
        NSArray<NSString *> *excluded = @[@"sunlight.controls.picture", @"sunlight.controls.pc", @"sunlight.controls.settings", @"sunlight.controls.keyboard", @"sunlight.controls.volume", @"sunlight.controls.statistics", @"sunlight.controls.inputSettings", @"sunlight.controls.pcSettings", @"sunlight.controls.globalSettings", @"sunlight.controls.back"];
        for (NSString *identifier in excluded) Require(Find(panel, identifier) == nil, [@"App settings exclude machine settings and hubs: " stringByAppendingString:identifier]);
        Require(Find(scroll, @"sunlight.controls.disconnect") == nil && [exitButton isDescendantOfView:Find(panel, @"sunlight.controls.footer")], @"End session belongs to the shared footer, not any mode’s content");
        Save(fixture.view, @"picture-glasses-2d-landscape.png"); overlay.glasses3DAvailable = YES; Layout(overlay); Save(fixture.view, @"picture-main-landscape.png");
        UISegmentedControl *mode = (UISegmentedControl *)Find(overlay, @"sunlight.controls.mode");
        Require(mode.numberOfSegments == 4 && [[mode titleForSegmentAtIndex:0] isEqualToString:@"2D"] && [[mode titleForSegmentAtIndex:1] isEqualToString:@"Host 3D"] && [[mode titleForSegmentAtIndex:2] isEqualToString:@"Client 3D"] && [[mode titleForSegmentAtIndex:3] isEqualToString:@"Raw SBS"], @"Streaming settings start with exactly the four picture tabs");
        UIButton *hostTab = (UIButton *)Find(mode, @"sunlight.controls.mode.1");
        Require(hostTab.configuration.image != nil && [hostTab.accessibilityLabel isEqualToString:@"Host 3D"], @"Mode tabs expose original icons alongside accessible text");
        Tap(overlay, @"sunlight.controls.mode.1"); Require(overlay.selectedTab == SunlightStreamControlsTabHost3D, @"Tapping the icon-and-text tab stages its mode through the existing callback");
        Tap(overlay, @"sunlight.controls.mode.0");
        Require(CGRectGetMaxY([mode convertRect:mode.bounds toView:overlay]) <= CGRectGetMinY([scroll convertRect:scroll.bounds toView:overlay]), @"Four tabs stay above the scrolling mode content");
        UIScrollView *tabs = (UIScrollView *)Find(overlay, @"sunlight.controls.tabs");
        for (NSUInteger index = 0; index < 4; index++) {
            UIView *tab = Find(mode, [NSString stringWithFormat:@"sunlight.controls.mode.%lu", (unsigned long)index]);
            Require(CGRectContainsRect(tabs.bounds, [tab convertRect:tab.bounds toView:tabs]), @"Every icon-and-label mode tab fits in the normal landscape strip");
        }
        Require(qualityEdits == 0 && Find(panel, @"sunlight.controls.streamSettings") == nil, @"Quality controls appear directly without a second-level editor or setter callbacks");
        Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabHost3D); Require(overlay.activeMode == SunlightStreamMode2D && applies == 0, @"Host 3D remains a draft before Apply");
        Layout(overlay); Save(fixture.view, @"picture-host-landscape.png");
        Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabRaw3D); Layout(overlay); Save(fixture.view, @"picture-raw-landscape.png");
        Require([Find(overlay, @"sunlight.controls.resolution").accessibilityLabel containsString:@"3840"] && Find(panel, @"sunlight.controls.packing") == nil, @"Raw keeps exact supplied resolution without packing options");
        UIControl *apply = (UIControl *)Find(overlay, @"sunlight.controls.apply");
        for (NSString *identifier in @[@"sunlight.controls.modeDetail", @"sunlight.controls.resolution", @"sunlight.controls.frameRate", @"sunlight.controls.bitrate", @"sunlight.controls.modeDefaults", @"sunlight.controls.apply"]) {
            UIView *control = Find(overlay, identifier); Require(control != nil && [control isDescendantOfView:scroll] && CGRectContainsRect(scroll.bounds, [control convertRect:control.bounds toView:scroll]), [@"Landscape mode option fully visible in its tab: " stringByAppendingString:identifier]);
        }
        Require(CGRectGetMinY([exitButton convertRect:exitButton.bounds toView:overlay]) >= CGRectGetMaxY([scroll convertRect:scroll.bounds toView:overlay]), @"The shared End session footer is visually separate below the mode body");
        overlay.connectionReady = NO; Require(!apply.enabled, @"Apply waits for connection readiness"); overlay.connectionReady = YES;
        Tap(overlay, @"sunlight.controls.apply"); Require(applies == 1 && applied == SunlightStreamModeRawFullSBS, @"Explicit Apply carries the selected canonical Raw mode");
        Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabClient3D); Layout(overlay); Save(fixture.view, @"picture-client-landscape.png");
        Require(Find(panel, @"sunlight.controls.apply") == nil && Find(panel, @"sunlight.controls.resolution") == nil && [((UILabel *)Find(panel, @"sunlight.controls.modeDetail")).text containsString:@"iOS 27 verification"], @"Client 3D only explains its unavailable status");
        Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabRaw3D); Layout(overlay); CheckLayout(overlay);
        Tap(overlay, @"sunlight.controls.close"); Require(panel.hidden && !overlay.expanded, @"Close restores the pass-through phone surface and discards unapplied mode changes");
        NSUInteger appliedBeforeClose = applies; [apply sendActionsForControlEvents:UIControlEventTouchUpInside]; mode.selectedSegmentIndex = 1; [mode sendActionsForControlEvents:UIControlEventValueChanged];
        Require(applies == appliedBeforeClose && overlay.selectedMode == SunlightStreamMode2D, @"Queued mode and Apply actions are ignored after the panel closes");
        overlay.activeMode = SunlightStreamModeRawHalfSBS; OpenPicture(overlay); Choose(overlay, @"sunlight.controls.mode", 0); Tap(overlay, @"sunlight.controls.apply");
        Require(applied == SunlightStreamMode2D, @"An active legacy Raw alias can explicitly switch to the 2D tab");
        overlay.expanded = NO; overlay.controlPadEnabled = YES; overlay.externalOutputActive = NO; Layout(overlay);
        CGRect pad = overlay.controlPadLayoutGuide.layoutFrame;
        Require(pad.size.height >= 184 && CGRectGetMaxY(pad) < CGRectGetMinY(pill.frame), @"Gamepad keeps its full area above the settings pill");
        Require([overlay hitTest:CGPointMake(CGRectGetMidX(pad), CGRectGetMidY(pad)) withEvent:nil] == nil, @"Gamepad receives touches through the collapsed overlay");
        OpenPicture(overlay); overlay.controlPadEnabled = NO; fixture.view.frame = CGRectMake(0, 0, 1024, 768); overlay.frame = fixture.view.bounds; Layout(overlay); CheckLayout(overlay); Save(fixture.view, @"picture-main-ipad.png");
        fixture.view.frame = CGRectMake(0, 0, 402, 874); overlay.frame = fixture.view.bounds; Choose(overlay, @"sunlight.controls.mode", SunlightStreamControlsTabRaw3D); Layout(overlay); Save(fixture.view, @"picture-raw-portrait.png");
        [host setOverrideTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge] forChildViewController:fixture];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
            Layout(overlay); CheckLayout(overlay); Save(fixture.view, @"picture-large-text-top.png");
            [scroll setContentOffset:CGPointMake(0, MAX(0, scroll.contentSize.height - scroll.bounds.size.height)) animated:NO]; Save(fixture.view, @"picture-large-text-bottom.png");
            UIView *close = Find(overlay, @"sunlight.controls.close"); Require(CGRectContainsRect(overlay.bounds, [close convertRect:close.bounds toView:overlay]), @"Close remains visible with large mode text");
            Require([overlay accessibilityPerformEscape] && !overlay.expanded && panel.hidden, @"Accessibility escape returns to the pass-through phone control surface");
            if (overlayOnly) FinishTests();
            [self runSharedSettingsTests];
        });
    });
    return YES;
}
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(ControlsTestApp.class)); } }
