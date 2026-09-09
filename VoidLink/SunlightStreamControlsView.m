#import "SunlightStreamControlsView.h"
#import <math.h>
#import "SunlightUITheme.h"
#import "SunlightMoonlightIcons.h"
#import "SunlightNativeResolution.h"

static UIColor *SLAccent(void) { return SunlightUITheme.accentColor; }
static UIColor *SLSlate(void) { return SunlightUITheme.surfaceColor; }
static UIColor *SLMuted(void) { return SunlightUITheme.secondaryTextColor; }
static UILabel *SLLabel(NSString *text, UIFontTextStyle style) {
    UILabel *label = [UILabel new]; label.text = text; label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:style]; label.adjustsFontForContentSizeCategory = YES;
    label.textColor = SunlightUITheme.primaryTextColor; return label;
}
@interface SLStreamButton : UIControl
@property UILabel *label;
@property UIImageView *icon;
@property (nonatomic) BOOL prominent;
@property (nonatomic) BOOL pillAppearance;
@property (nonatomic) BOOL destructive;
- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol vertical:(BOOL)vertical;
- (void)refreshAppearance;
@end
@implementation SLStreamButton
- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol vertical:(BOOL)vertical {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.isAccessibilityElement = YES; self.accessibilityLabel = title;
        self.layer.cornerRadius = 12;
        _label = SLLabel(title, UIFontTextStyleSubheadline);
        _label.textAlignment = vertical ? NSTextAlignmentCenter : NSTextAlignmentNatural;
        NSMutableArray *items = [NSMutableArray array];
        if (symbol.length) {
            UIImageView *icon = [UIImageView new]; self.icon = icon; icon.contentMode = UIViewContentModeScaleAspectFit;
            if (@available(iOS 13.0, *)) icon.image = [SunlightMoonlightIcons imageNamed:symbol] ?: [UIImage systemImageNamed:symbol];
            [icon.widthAnchor constraintEqualToConstant:18].active = YES;
            [icon.heightAnchor constraintEqualToConstant:18].active = YES;
            [items addObject:icon];
        }
        if (title.length) [items addObject:_label];
        UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:items];
        content.axis = vertical ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
        content.alignment = UIStackViewAlignmentCenter; content.spacing = 8;
        content.userInteractionEnabled = NO; content.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:content];
        [NSLayoutConstraint activateConstraints:@[

            [content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [content.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],

        ]];
        NSLayoutConstraint *minimumHeight = [self.heightAnchor constraintGreaterThanOrEqualToConstant:44]; minimumHeight.priority = 999; minimumHeight.active = YES;
        NSLayoutConstraint *bottom = [content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10]; bottom.priority = 999; bottom.active = YES;
        [self refreshAppearance];
    }
    return self;
}
- (BOOL)accessibilityActivate { if (!self.enabled) return NO; [self sendActionsForControlEvents:UIControlEventTouchUpInside]; return YES; }
- (void)setSelected:(BOOL)selected { [super setSelected:selected]; [self refreshAppearance]; }
- (void)setEnabled:(BOOL)enabled { [super setEnabled:enabled]; [self refreshAppearance]; }
- (void)setHighlighted:(BOOL)highlighted { [super setHighlighted:highlighted]; [self refreshAppearance]; }
- (void)setPillAppearance:(BOOL)value { _pillAppearance = value; self.layer.cornerRadius = value ? 24 : 12; [self refreshAppearance]; }
- (void)setProminent:(BOOL)prominent { _prominent = prominent; [self refreshAppearance]; }
- (void)setDestructive:(BOOL)destructive { _destructive = destructive; [self refreshAppearance]; }
- (void)refreshAppearance {
    BOOL filled = self.prominent;
    self.backgroundColor = filled ? SunlightUITheme.deepAccentColor : self.pillAppearance ? SLSlate() : self.selected ? SunlightUITheme.raisedColor : UIColor.clearColor;
    self.layer.borderWidth = filled ? 1 : 0; self.layer.borderColor = SLAccent().CGColor;
    UIColor *foreground = self.destructive ? SunlightUITheme.dangerColor : SunlightUITheme.primaryTextColor;
    self.label.textColor = foreground; self.tintColor = foreground;
    self.alpha = !self.enabled ? 0.36 : (self.highlighted ? 0.65 : 1);
    self.accessibilityTraits = UIAccessibilityTraitButton | (self.selected ? UIAccessibilityTraitSelected : 0) | (!self.enabled ? UIAccessibilityTraitNotEnabled : 0);
}
@end

// Android's white icon/label, raised inactive tile and deep-blue active tile.
// A direct tab control keeps the original vector and text together at every size.
@interface SLModeTabs : UIControl
@property (nonatomic) NSInteger selectedSegmentIndex;
@property (nonatomic, readonly) NSUInteger numberOfSegments;
- (instancetype)initWithItems:(NSArray<NSString *> *)items;
- (NSString *)titleForSegmentAtIndex:(NSUInteger)index;
- (void)setEnabled:(BOOL)enabled forSegmentAtIndex:(NSUInteger)index;
- (BOOL)isEnabledForSegmentAtIndex:(NSUInteger)index;
- (void)setModeFont:(UIFont *)font;
@end
@implementation SLModeTabs {
    NSArray<NSString *> *_titles;
    NSArray<UIButton *> *_buttons;
    UIFont *_modeFont;
}
- (instancetype)initWithItems:(NSArray<NSString *> *)items {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _titles = items.copy; _selectedSegmentIndex = 0;
        NSArray *icons = @[@"ic_xr_mode_normal", @"ic_xr_mode_host_sbs", @"ic_xr_mode_client_sbs", @"ic_xr_mode_host_sbs_raw"];
        NSMutableArray *buttons = [NSMutableArray array];
        for (NSUInteger index = 0; index < items.count; index++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.tag = index; button.accessibilityIdentifier = [NSString stringWithFormat:@"sunlight.controls.mode.%lu", (unsigned long)index];
            button.accessibilityLabel = items[index];
            UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
            configuration.title = items[index]; configuration.image = [SunlightMoonlightIcons imageNamed:icons[index]];
            configuration.imagePadding = 6; configuration.contentInsets = NSDirectionalEdgeInsetsMake(8, 8, 8, 8);
            configuration.titleLineBreakMode = NSLineBreakByClipping; button.configuration = configuration;
            [button addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
            [buttons addObject:button];
        }
        _buttons = buttons.copy;
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:_buttons];
        row.distribution = UIStackViewDistributionFillEqually; row.spacing = 8; row.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:row];
        [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor], [row.topAnchor constraintEqualToAnchor:self.topAnchor], [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]]];
        [self setModeFont:[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]];
    }
    return self;
}
- (NSUInteger)numberOfSegments { return _buttons.count; }
- (NSString *)titleForSegmentAtIndex:(NSUInteger)index { return _titles[index]; }
- (void)setSelectedSegmentIndex:(NSInteger)index { if (_selectedSegmentIndex == index) return; _selectedSegmentIndex = index; [self refreshTabs]; }
- (void)setEnabled:(BOOL)enabled forSegmentAtIndex:(NSUInteger)index { if (_buttons[index].userInteractionEnabled == enabled) return; _buttons[index].userInteractionEnabled = enabled; [self refreshTabs]; }
- (BOOL)isEnabledForSegmentAtIndex:(NSUInteger)index { return _buttons[index].userInteractionEnabled; }
- (void)setModeFont:(UIFont *)font { if ([_modeFont isEqual:font]) return; _modeFont = font; [self refreshTabs]; }
- (void)refreshTabs {
    for (NSUInteger index = 0; index < _buttons.count; index++) {
        UIButton *button = _buttons[index]; BOOL selected = (NSInteger)index == _selectedSegmentIndex;
        UIButtonConfiguration *configuration = button.configuration;
        configuration.baseForegroundColor = SunlightUITheme.primaryTextColor;
        UIFont *font = _modeFont;
        configuration.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
            NSMutableDictionary *result = [attributes mutableCopy]; result[NSFontAttributeName] = font; return result;
        };
        button.configuration = configuration; button.layer.cornerRadius = 10;
        button.backgroundColor = selected ? SunlightUITheme.deepAccentColor : SunlightUITheme.raisedColor;
        button.layer.borderColor = (selected ? SunlightUITheme.accentColor : SunlightUITheme.tileBorderColor).CGColor;
        button.layer.borderWidth = selected ? 2 : 1;
        button.alpha = button.userInteractionEnabled ? 1 : 0.4;
        button.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0) | (button.userInteractionEnabled ? 0 : UIAccessibilityTraitNotEnabled);
    }
}
- (void)tabTapped:(UIButton *)button {
    if (!button.userInteractionEnabled) return; self.selectedSegmentIndex = button.tag;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
@end

@interface SLQualitySlider : UISlider
@property (nonatomic) BOOL accessibilityEditing;
@end
@implementation SLQualitySlider
- (void)adjustAccessibilityValue:(float)delta {
    self.accessibilityEditing = YES;
    self.value = MIN(self.maximumValue, MAX(self.minimumValue, self.value + delta));
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    self.accessibilityEditing = NO;
}
- (void)accessibilityIncrement { [self adjustAccessibilityValue:1]; }
- (void)accessibilityDecrement { [self adjustAccessibilityValue:-1]; }
@end

@implementation SunlightStreamControlsView {
    UIView *_hint;
    UILabel *_hintTitle, *_hintDetail, *_hintStatus;
    SLStreamButton *_pill;
    UIControl *_scrim;
    UIView *_panel;
    UIScrollView *_scroll, *_tabScroll;
    UIStackView *_content, *_pictureControls, *_modeActions, *_qualityControls, *_pictureGroup, *_navigation, *_footer;
    SLModeTabs *_modeSelector;
    NSLayoutConstraint *_modeSelectorHeight, *_tabContentWidth;
    SLStreamButton *_apply, *_modeDefaults, *_endSession, *_close;
    UIButton *_resolutionButton, *_frameRateButton;
    SLQualitySlider *_bitrateSlider;
    BOOL _bitrateGestureActive, _bitrateGestureCancelled;
    NSUInteger _bitrateGestureGeneration;
    SunlightStreamControlsTab _bitrateGestureTab;
    UILabel *_bitrateValue;
    UIStackView *_qualityFields;
    UILabel *_modeDetail, *_headerTitle;
    SunlightStreamControlsTab _selectedTab;
    BOOL _compact, _notifyingSelectionChange;
    NSUInteger _qualityInteractionGeneration;
    NSString *_qualityControlsKey;
    SunlightStreamMode _draftMode;
    NSLayoutConstraint *_preferredPanelHeight, *_maximumPanelWidth;
    NSLayoutConstraint *_navigationTop, *_bodyTop, *_bodyBottom, *_scrollBottom, *_footerBottom;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _activeMode = SunlightStreamMode2D; _draftMode = _activeMode; _touchEnabled = YES;
        _inputHint = @""; _statusText = @""; _appName = @"";
        _qualityWidth = 1920; _qualityHeight = 1080; _qualityFrameRate = 60; _qualityBitrateKbps = 20000; _qualityMaxFrameRate = 240;
        self.backgroundColor = UIColor.clearColor;
        self.accessibilityIdentifier = @"sunlight.controls.overlay";
        if (@available(iOS 13.0, *)) self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        [self buildCollapsedControls]; [self buildExpandedControls]; [self updateState];
    }
    return self;
}

- (SLStreamButton *)button:(NSString *)title symbol:(NSString *)symbol identifier:(NSString *)identifier action:(SEL)action {
    SLStreamButton *button = [[SLStreamButton alloc] initWithTitle:title symbol:symbol vertical:NO];
    button.accessibilityIdentifier = identifier;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return button;
}
- (UIStackView *)row:(NSArray<UIView *> *)items {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:items];
    row.axis = UILayoutConstraintAxisHorizontal; row.distribution = UIStackViewDistributionFillEqually; row.spacing = 10;
    return row;
}
- (void)buildCollapsedControls {
    _hint = [UIView new]; _hint.translatesAutoresizingMaskIntoConstraints = NO; _hint.userInteractionEnabled = NO;
    [self addSubview:_hint];
    _hintTitle = SLLabel(NSLocalizedString(@"Touch paused", nil), UIFontTextStyleSubheadline); _hintTitle.textAlignment = NSTextAlignmentCenter; _hintTitle.accessibilityIdentifier = @"sunlight.controls.hintTitle";
    _hintDetail = SLLabel(@"", UIFontTextStyleFootnote); _hintDetail.textColor = SLMuted(); _hintDetail.textAlignment = NSTextAlignmentCenter; _hintDetail.accessibilityIdentifier = @"sunlight.controls.hintDetail";
    _hintStatus = SLLabel(@"", UIFontTextStyleFootnote); _hintStatus.textColor = SLMuted(); _hintStatus.textAlignment = NSTextAlignmentCenter;
    UIStackView *hintText = [[UIStackView alloc] initWithArrangedSubviews:@[_hintTitle, _hintDetail, _hintStatus]];
    hintText.axis = UILayoutConstraintAxisVertical; hintText.spacing = 8; hintText.translatesAutoresizingMaskIntoConstraints = NO;
    [_hint addSubview:hintText];
    [NSLayoutConstraint activateConstraints:@[
        [hintText.centerXAnchor constraintEqualToAnchor:_hint.centerXAnchor], [hintText.centerYAnchor constraintEqualToAnchor:_hint.centerYAnchor],
        [hintText.widthAnchor constraintLessThanOrEqualToConstant:440],
        [hintText.leadingAnchor constraintGreaterThanOrEqualToAnchor:_hint.leadingAnchor constant:24],
        [hintText.trailingAnchor constraintLessThanOrEqualToAnchor:_hint.trailingAnchor constant:-24],
    ]];
    NSLayoutConstraint *hintWidth = [hintText.widthAnchor constraintEqualToAnchor:_hint.widthAnchor constant:-48]; hintWidth.priority = 750; hintWidth.active = YES;

    _pill = [self button:@"2D" symbol:@"ic_settings" identifier:@"sunlight.controls.pill" action:@selector(expandTapped)];
    _pill.pillAppearance = YES; [self addSubview:_pill];
    UILayoutGuide *safe = self.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_pill.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12],
        [_pill.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_pill.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:12],
        [_pill.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-12],
    ]];
    _controlPadLayoutGuide = [UILayoutGuide new]; _controlPadLayoutGuide.identifier = @"sunlight.controls.gamepadArea"; [self addLayoutGuide:_controlPadLayoutGuide];
    [NSLayoutConstraint activateConstraints:@[
        [_controlPadLayoutGuide.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [_controlPadLayoutGuide.bottomAnchor constraintEqualToAnchor:_pill.topAnchor constant:-12],
        [_controlPadLayoutGuide.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12], [_controlPadLayoutGuide.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [_hint.leadingAnchor constraintEqualToAnchor:_controlPadLayoutGuide.leadingAnchor], [_hint.trailingAnchor constraintEqualToAnchor:_controlPadLayoutGuide.trailingAnchor],
        [_hint.topAnchor constraintEqualToAnchor:_controlPadLayoutGuide.topAnchor], [_hint.bottomAnchor constraintEqualToAnchor:_controlPadLayoutGuide.bottomAnchor],
    ]];
}
- (UIStackView *)column:(NSArray<UIView *> *)items spacing:(CGFloat)spacing {
    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:items]; column.axis = UILayoutConstraintAxisVertical; column.spacing = spacing; return column;
}
- (void)buildExpandedControls {
    _scrim = [UIControl new]; _scrim.translatesAutoresizingMaskIntoConstraints = NO; _scrim.backgroundColor = [SunlightUITheme.sunkenColor colorWithAlphaComponent:0.9];
    _scrim.accessibilityIdentifier = @"sunlight.controls.dismiss"; _scrim.accessibilityLabel = NSLocalizedString(@"Close stream controls", nil); _scrim.accessibilityTraits = UIAccessibilityTraitButton;
    [_scrim addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside]; [self addSubview:_scrim];
    _panel = [UIView new]; _panel.translatesAutoresizingMaskIntoConstraints = NO; _panel.backgroundColor = SLSlate(); _panel.layer.cornerRadius = 22; _panel.clipsToBounds = YES;
    _panel.accessibilityIdentifier = @"sunlight.controls.panel"; [self addSubview:_panel];
    UILayoutGuide *safe = self.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_scrim.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [_scrim.trailingAnchor constraintEqualToAnchor:self.trailingAnchor], [_scrim.topAnchor constraintEqualToAnchor:self.topAnchor], [_scrim.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_panel.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor], [_panel.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [_panel.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:12], [_panel.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-12],
        [_panel.topAnchor constraintGreaterThanOrEqualToAnchor:safe.topAnchor constant:12], [_panel.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-12],
        [_panel.heightAnchor constraintLessThanOrEqualToConstant:720],
    ]];
    _maximumPanelWidth = [_panel.widthAnchor constraintLessThanOrEqualToConstant:560]; _maximumPanelWidth.active = YES;
    NSLayoutConstraint *width = [_panel.widthAnchor constraintEqualToAnchor:safe.widthAnchor constant:-24]; width.priority = 999; width.active = YES;
    _preferredPanelHeight = [_panel.heightAnchor constraintEqualToConstant:720]; _preferredPanelHeight.priority = 750; _preferredPanelHeight.active = YES;

    _headerTitle = SLLabel(NSLocalizedString(@"App settings", nil), UIFontTextStyleHeadline); _headerTitle.accessibilityTraits = UIAccessibilityTraitHeader; _headerTitle.accessibilityIdentifier = @"sunlight.controls.title";
    _headerTitle.numberOfLines = 2; _headerTitle.lineBreakMode = NSLineBreakByTruncatingTail;
    _close = [self button:@"" symbol:@"xmark" identifier:@"sunlight.controls.close" action:@selector(closeTapped)]; _close.accessibilityLabel = NSLocalizedString(@"Close stream controls", nil);
    [_close.widthAnchor constraintEqualToConstant:44].active = YES;
    UIStackView *headerRow = [[UIStackView alloc] initWithArrangedSubviews:@[_headerTitle, _close]]; headerRow.spacing = 12; headerRow.alignment = UIStackViewAlignmentCenter;
    _navigation = [self column:@[headerRow] spacing:8]; _navigation.translatesAutoresizingMaskIntoConstraints = NO; [_panel addSubview:_navigation];
    _scroll = [UIScrollView new]; _scroll.translatesAutoresizingMaskIntoConstraints = NO; _scroll.alwaysBounceVertical = YES; _scroll.accessibilityIdentifier = @"sunlight.controls.scroll"; [_panel addSubview:_scroll];
    _content = [self column:@[] spacing:0]; _content.translatesAutoresizingMaskIntoConstraints = NO; [_scroll addSubview:_content];
    UIView *divider = [UIView new]; divider.backgroundColor = SunlightUITheme.borderColor; [divider.heightAnchor constraintEqualToConstant:1].active = YES;
    _endSession = [self button:NSLocalizedString(@"End session", nil) symbol:@"ic_xr_disconnect" identifier:@"sunlight.controls.disconnect" action:@selector(actionTapped:)];
    _endSession.tag = SunlightStreamControlsActionDisconnect; _endSession.destructive = YES;
    _footer = [self column:@[divider, _endSession] spacing:8]; _footer.translatesAutoresizingMaskIntoConstraints = NO; _footer.accessibilityIdentifier = @"sunlight.controls.footer"; [_panel addSubview:_footer];
    [NSLayoutConstraint activateConstraints:@[
        [_navigation.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:20], [_navigation.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor constant:-20], (_navigationTop = [_navigation.topAnchor constraintEqualToAnchor:_panel.topAnchor constant:16]),
        [_scroll.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor], [_scroll.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor], [_scroll.topAnchor constraintEqualToAnchor:_navigation.bottomAnchor constant:8],
        [_content.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor constant:20], [_content.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor constant:-20],
        (_bodyTop = [_content.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor constant:12]), (_bodyBottom = [_content.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor constant:-12]),
        [_content.widthAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.widthAnchor constant:-40],
        [_footer.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:20], [_footer.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor constant:-20], (_footerBottom = [_footer.bottomAnchor constraintEqualToAnchor:_panel.bottomAnchor constant:-16]),
        (_scrollBottom = [_scroll.bottomAnchor constraintEqualToAnchor:_footer.topAnchor constant:-8]),
    ]];

    _modeSelector = [[SLModeTabs alloc] initWithItems:@[@"2D", @"Host 3D", @"Client 3D", @"Raw SBS"]];
    _modeSelector.accessibilityIdentifier = @"sunlight.controls.mode"; _modeSelector.accessibilityLabel = NSLocalizedString(@"Picture mode", nil);
    [_modeSelector addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    _tabScroll = [UIScrollView new]; _tabScroll.accessibilityIdentifier = @"sunlight.controls.tabs"; _tabScroll.showsHorizontalScrollIndicator = NO;
    _modeSelector.translatesAutoresizingMaskIntoConstraints = NO; [_tabScroll addSubview:_modeSelector];
    [NSLayoutConstraint activateConstraints:@[
        [_modeSelector.leadingAnchor constraintEqualToAnchor:_tabScroll.contentLayoutGuide.leadingAnchor], [_modeSelector.trailingAnchor constraintEqualToAnchor:_tabScroll.contentLayoutGuide.trailingAnchor],
        [_modeSelector.topAnchor constraintEqualToAnchor:_tabScroll.contentLayoutGuide.topAnchor], [_modeSelector.bottomAnchor constraintEqualToAnchor:_tabScroll.contentLayoutGuide.bottomAnchor],
        [_modeSelector.heightAnchor constraintEqualToAnchor:_tabScroll.frameLayoutGuide.heightAnchor],
        [_modeSelector.widthAnchor constraintGreaterThanOrEqualToAnchor:_tabScroll.frameLayoutGuide.widthAnchor],
    ]];
    NSLayoutConstraint *tabWidth = [_modeSelector.widthAnchor constraintEqualToAnchor:_tabScroll.frameLayoutGuide.widthAnchor]; tabWidth.priority = 750; tabWidth.active = YES;
    _tabContentWidth = [_modeSelector.widthAnchor constraintGreaterThanOrEqualToConstant:0]; _tabContentWidth.active = YES;
    _modeSelectorHeight = [_tabScroll.heightAnchor constraintEqualToConstant:48]; _modeSelectorHeight.active = YES;
    _modeDetail = SLLabel(@"", UIFontTextStyleFootnote); _modeDetail.textColor = SLMuted(); _modeDetail.accessibilityIdentifier = @"sunlight.controls.modeDetail";
    _pictureControls = [self column:@[_modeDetail] spacing:8];
    _pictureGroup = [self column:@[_pictureControls] spacing:12];
    _apply = [self button:NSLocalizedString(@"Apply & reconnect", nil) symbol:@"arrow.clockwise" identifier:@"sunlight.controls.apply" action:@selector(applyTapped)]; _apply.prominent = YES;
    _modeDefaults = [self button:NSLocalizedString(@"Restore defaults", nil) symbol:@"arrow.uturn.backward" identifier:@"sunlight.controls.modeDefaults" action:@selector(actionTapped:)]; _modeDefaults.tag = SunlightStreamControlsActionModeDefaults;
    _modeDefaults.accessibilityHint = NSLocalizedString(@"Restore global quality defaults for this mode of this app on this PC. Apply & reconnect applies the change.", nil);
    _modeActions = [self column:@[_modeDefaults] spacing:8];
    _resolutionButton = [self qualityMenuButton:@"sunlight.controls.resolution"];
    _frameRateButton = [self qualityMenuButton:@"sunlight.controls.frameRate"];
    _bitrateSlider = [SLQualitySlider new]; _bitrateSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _bitrateSlider.accessibilityIdentifier = @"sunlight.controls.bitrate";
    _bitrateSlider.accessibilityLabel = NSLocalizedString(@"Max bitrate", nil);
    _bitrateSlider.minimumTrackTintColor = SLAccent();
    [_bitrateSlider.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [_bitrateSlider addTarget:self action:@selector(bitrateChanged:) forControlEvents:UIControlEventValueChanged];
    [_bitrateSlider addTarget:self action:@selector(bitrateTouchBegan) forControlEvents:UIControlEventTouchDown];
    [_bitrateSlider addTarget:self action:@selector(bitrateTouchEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    _bitrateValue = SLLabel(@"", UIFontTextStyleFootnote); _bitrateValue.textColor = SLMuted();
    UIStackView *bitrateHeading = [[UIStackView alloc] initWithArrangedSubviews:@[[self qualityHeading:NSLocalizedString(@"Max bitrate", nil) symbol:@"ic_xr_bitrate"], _bitrateValue]];
    bitrateHeading.spacing = 8; bitrateHeading.alignment = UIStackViewAlignmentCenter;
    [_bitrateValue setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *resolution = [self column:@[[self qualityHeading:NSLocalizedString(@"Resolution", nil) symbol:@"ic_xr_resolution"], _resolutionButton] spacing:0];
    UIStackView *frameRate = [self column:@[[self qualityHeading:NSLocalizedString(@"Max frame rate", nil) symbol:@"ic_xr_frame_rate"], _frameRateButton] spacing:0];
    UIStackView *bitrate = [self column:@[bitrateHeading, _bitrateSlider] spacing:0];
    _qualityFields = [self row:@[resolution, frameRate, bitrate]]; _qualityFields.spacing = 20;
    UIView *qualityDivider = [UIView new]; qualityDivider.backgroundColor = SunlightUITheme.borderColor;
    [qualityDivider.heightAnchor constraintEqualToConstant:1].active = YES;
    _qualityControls = [self column:@[qualityDivider, _qualityFields] spacing:8];
    [_pictureGroup insertArrangedSubview:_qualityControls atIndex:1];
    [_pictureGroup insertArrangedSubview:_modeActions atIndex:2];
    [_content addArrangedSubview:_pictureGroup];
    [_navigation addArrangedSubview:_tabScroll];

}

- (void)layoutSubviews {
    BOOL compact = self.bounds.size.height < 500;
    if (_compact != compact) { _compact = compact; [self updateState]; }
    [super layoutSubviews];
    CGSize fitting = CGSizeMake(MAX(1, _panel.bounds.size.width - 40), UILayoutFittingCompressedSize.height);
    CGFloat body = [_content systemLayoutSizeFittingSize:fitting withHorizontalFittingPriority:1000 verticalFittingPriority:50].height;
    CGFloat footer = [_footer systemLayoutSizeFittingSize:fitting withHorizontalFittingPriority:1000 verticalFittingPriority:50].height;
    CGFloat navigation = [_navigation systemLayoutSizeFittingSize:fitting withHorizontalFittingPriority:1000 verticalFittingPriority:50].height;
    CGFloat verticalSpacing = _navigationTop.constant + 8 + _bodyTop.constant - _bodyBottom.constant - _scrollBottom.constant - _footerBottom.constant;
    _preferredPanelHeight.constant = MIN(720, MAX(180, ceil(body + footer + navigation + verticalSpacing)));
    CGFloat tabWidth = _modeSelector.bounds.size.width / MAX(1, _modeSelector.numberOfSegments);
    [_tabScroll scrollRectToVisible:CGRectMake(tabWidth * _selectedTab, 0, tabWidth, _modeSelector.bounds.size.height) animated:NO];
    _hint.hidden = _expanded || !_externalOutputActive || _controlPadEnabled || _controlPadLayoutGuide.layoutFrame.size.height < 130;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection { [super traitCollectionDidChange:previousTraitCollection]; [self updateState]; }
- (void)setActiveMode:(SunlightStreamMode)value {
    if (value == SunlightStreamModeRawHalfSBS) value = SunlightStreamModeRawFullSBS;
    _activeMode = value >= SunlightStreamMode2D && value <= SunlightStreamModeRawHalfSBS ? value : SunlightStreamMode2D;
    _draftMode = _glasses3DAvailable ? _activeMode : SunlightStreamMode2D;
    _selectedTab = [self tabForMode:_draftMode];
    [self updateState];
}
- (SunlightStreamControlsTab)tabForMode:(SunlightStreamMode)mode { return mode == SunlightStreamMode2D ? SunlightStreamControlsTab2D : mode == SunlightStreamModeHost3D ? SunlightStreamControlsTabHost3D : SunlightStreamControlsTabRaw3D; }
- (SunlightStreamControlsTab)selectedTab { return _selectedTab; }
- (void)discardPictureDraft { _draftMode = _glasses3DAvailable ? _activeMode : SunlightStreamMode2D; _selectedTab = [self tabForMode:_draftMode]; }
- (SunlightStreamMode)selectedMode { return _glasses3DAvailable ? _draftMode : SunlightStreamMode2D; }
- (void)setQualityChangesPending:(BOOL)value { _qualityChangesPending = value; [self updateState]; }
- (void)discardPendingChanges {
    [self discardPictureDraft]; _qualityChangesPending = NO; [self updateState];
    if (self.pendingChangesDiscardedHandler) self.pendingChangesDiscardedHandler();
}
- (void)notifySelectionChangedFrom:(SunlightStreamControlsTab)previous {
    if (previous == self.selectedTab || _notifyingSelectionChange || !self.selectionChangedHandler) return;
    _notifyingSelectionChange = YES; self.selectionChangedHandler(); _notifyingSelectionChange = NO;
}
- (void)setExpanded:(BOOL)expanded {
    if (_expanded == expanded) return;
    [self invalidateQualityInteractions];
    if (expanded) { _draftMode = _glasses3DAvailable ? _activeMode : SunlightStreamMode2D; _selectedTab = [self tabForMode:_draftMode]; [_scroll setContentOffset:CGPointZero animated:NO]; }
    else [self discardPendingChanges];
    _expanded = expanded;
    [self updateState];
    if (self.expansionChangedHandler) self.expansionChangedHandler(expanded);
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, expanded ? _headerTitle : _pill);
}
- (void)setExternalOutputActive:(BOOL)value { _externalOutputActive = value; [self updateState]; }
- (void)setGlasses3DAvailable:(BOOL)value {
    if (_glasses3DAvailable == value) return;
    SunlightStreamControlsTab previous = self.selectedTab;
    _glasses3DAvailable = value;
    [self invalidateQualityInteractions];
    [self discardPictureDraft];
    [self updateState];
    if (!value) [self notifySelectionChangedFrom:previous];
}
- (void)setTouchEnabled:(BOOL)value { _touchEnabled = value; [self updateState]; }
- (void)setConnectionReady:(BOOL)value { _connectionReady = value; [self updateState]; }
- (void)setControlPadEnabled:(BOOL)value { _controlPadEnabled = value; [self updateState]; }
- (void)setUsesSavedTouchProfile:(BOOL)value { _usesSavedTouchProfile = value; [self updateState]; }
- (void)setAppName:(NSString *)value { _appName = [value copy] ?: @""; [self updateState]; }
- (void)setQualityWidth:(int)value { if (_qualityWidth == value) return; _qualityWidth = value; [self updateQualityControls]; }
- (void)setQualityHeight:(int)value { if (_qualityHeight == value) return; _qualityHeight = value; [self updateQualityControls]; }
- (void)setQualityFrameRate:(int)value { if (_qualityFrameRate == value) return; _qualityFrameRate = value; [self updateQualityControls]; }
- (void)setQualityBitrateKbps:(int)value { if (_qualityBitrateKbps == value) return; _qualityBitrateKbps = value; [self updateQualityControls]; }
- (void)setQualityMaxFrameRate:(int)value { value = MAX(1, value); if (_qualityMaxFrameRate == value) return; _qualityMaxFrameRate = value; [self updateQualityControls]; }
- (void)setQualityResolutionLocked:(BOOL)value { if (_qualityResolutionLocked == value) return; _qualityResolutionLocked = value; [self updateQualityControls]; }
- (void)setQualityUsesNativeResolution:(BOOL)value { if (_qualityUsesNativeResolution == value) return; _qualityUsesNativeResolution = value; [self updateQualityControls]; }
- (void)setInputHint:(NSString *)value { _inputHint = [value copy] ?: @""; [self updateState]; }
- (void)setStatusText:(NSString *)value { _statusText = [value copy] ?: @""; [self updateState]; }
- (void)updateState {
    if (!_panel) return;
    BOOL large = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    BOOL compactOptions = _compact && !large;
    _panel.hidden = !_expanded; _scrim.hidden = !_expanded; _pill.hidden = _expanded;
    _hint.hidden = _expanded || !_externalOutputActive || _controlPadEnabled;
    _hintTitle.hidden = _touchEnabled;
    _hintDetail.text = _touchEnabled ? _inputHint : NSLocalizedString(@"Enable touch input in this PC’s settings.", nil);
    _hintDetail.hidden = _touchEnabled && _inputHint.length == 0;
    _hintStatus.text = _statusText; _hintStatus.hidden = _statusText.length == 0;
    // Report the connected mode, never an unsubmitted tab or a hardware event.
    NSString *picture = @"2D", *pictureIcon = @"ic_xr_mode_normal";
    switch (_activeMode) {
        case SunlightStreamModeHost3D: picture = @"Host 3D"; pictureIcon = @"ic_xr_mode_host_sbs"; break;
        case SunlightStreamModeRawFullSBS:
        case SunlightStreamModeRawHalfSBS: picture = @"Raw SBS"; pictureIcon = @"ic_xr_mode_host_sbs_raw"; break;
        default: break;
    }
    _pill.icon.image = [SunlightMoonlightIcons imageNamed:pictureIcon];
    _pill.icon.accessibilityIdentifier = @"sunlight.controls.pill.modeIcon";
    _pill.label.text = picture; _pill.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"App settings, %@", nil), picture];
    _pill.accessibilityHint = NSLocalizedString(@"Choose a picture mode and stream quality", nil);
    _headerTitle.text = _appName.length && ![_appName isEqualToString:@"App settings"] ? [NSString stringWithFormat:NSLocalizedString(@"App settings · %@", nil), _appName] : NSLocalizedString(@"App settings", nil);
    [_modeSelector setEnabled:_glasses3DAvailable forSegmentAtIndex:SunlightStreamControlsTabHost3D];
    [_modeSelector setEnabled:_glasses3DAvailable forSegmentAtIndex:SunlightStreamControlsTabRaw3D];
    _modeSelector.selectedSegmentIndex = _selectedTab;
    BOOL client = _selectedTab == SunlightStreamControlsTabClient3D;
    switch (_draftMode) {
        case SunlightStreamModeHost3D: _modeDetail.text = NSLocalizedString(@"Convert the PC picture to 3D. Adjust 3D strength on your PC.", nil); break;
        case SunlightStreamModeRawFullSBS:
        case SunlightStreamModeRawHalfSBS: _modeDetail.text = NSLocalizedString(@"Shows the incoming side-by-side picture as supplied. It must match the glasses’ resolution.", nil); break;
        default: _modeDetail.text = NSLocalizedString(@"View the original PC picture.", nil); break;
    }
    if (!_glasses3DAvailable && !client) _modeDetail.text = _externalOutputActive ? NSLocalizedString(@"Switch your glasses to 3D mode to enable 3D.", nil) : NSLocalizedString(@"Connect your glasses and switch them to 3D mode.", nil);
    if (client) _modeDetail.text = NSLocalizedString(@"Available after iOS 27 verification. Client 3D conversion is not available in this version.", nil);
    BOOL draftChanged = (_glasses3DAvailable && _draftMode != _activeMode) || _qualityChangesPending;
    if (draftChanged && !client && !_apply.superview) [_modeActions addArrangedSubview:_apply];
    else if ((!draftChanged || client) && _apply.superview) { [_modeActions removeArrangedSubview:_apply]; [_apply removeFromSuperview]; }
    NSMutableArray *pictureContents = [NSMutableArray arrayWithObject:_pictureControls];
    if (!client) { [pictureContents addObject:_qualityControls]; if (_modeActions.arrangedSubviews.count) [pictureContents addObject:_modeActions]; }
    if (![_pictureGroup.arrangedSubviews isEqualToArray:pictureContents]) {
        for (UIView *child in _pictureGroup.arrangedSubviews.copy) { [_pictureGroup removeArrangedSubview:child]; [child removeFromSuperview]; }
        for (UIView *child in pictureContents) [_pictureGroup addArrangedSubview:child];
    }
    _apply.enabled = _expanded && _connectionReady && draftChanged && !client;
    _qualityFields.axis = compactOptions ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical;
    _qualityFields.distribution = compactOptions ? UIStackViewDistributionFillEqually : UIStackViewDistributionFill;
    _qualityFields.spacing = compactOptions ? 20 : 12;
    [self updateQualityControls];
    _modeActions.axis = _compact && !large ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical;
    _modeActions.distribution = _compact && !large ? UIStackViewDistributionFillEqually : UIStackViewDistributionFill;
    UIFont *modeFont = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline compatibleWithTraitCollection:self.traitCollection];
    [_modeSelector setModeFont:modeFont];
    _modeSelectorHeight.constant = MAX(44, modeFont.lineHeight + 16);
    CGFloat widestTab = 0;
    for (NSUInteger index = 0; index < _modeSelector.numberOfSegments; index++) widestTab = MAX(widestTab, [[_modeSelector titleForSegmentAtIndex:index] sizeWithAttributes:@{NSFontAttributeName:modeFont}].width);
    _tabContentWidth.constant = ceil((widestTab + 52) * _modeSelector.numberOfSegments + 24);
    _pictureControls.axis = _compact && !large ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical;
    _pictureControls.alignment = UIStackViewAlignmentFill;
    _pictureControls.distribution = _compact && !large ? UIStackViewDistributionFillEqually : UIStackViewDistributionFill;
    _modeDetail.hidden = NO;
    _pictureGroup.spacing = _compact ? 4 : 12;
    _maximumPanelWidth.constant = _compact ? 680 : 520;
    _navigationTop.constant = _compact ? 8 : 16; _bodyTop.constant = _compact ? 6 : 12; _bodyBottom.constant = _compact ? -6 : -12;
    _scrollBottom.constant = _compact ? -6 : -8; _footerBottom.constant = _compact ? -12 : -16;
    self.accessibilityViewIsModal = _expanded; _panel.accessibilityViewIsModal = _expanded;
    [self setNeedsLayout];
}
- (UIView *)qualityHeading:(NSString *)title symbol:(NSString *)symbol {
    UIImageView *icon = [[UIImageView alloc] initWithImage:[SunlightMoonlightIcons imageNamed:symbol] ?: [UIImage systemImageNamed:symbol]];
    icon.tintColor = SLMuted(); icon.contentMode = UIViewContentModeScaleAspectFit;
    [icon.widthAnchor constraintEqualToConstant:16].active = YES; [icon.heightAnchor constraintEqualToConstant:16].active = YES;
    UILabel *label = SLLabel(title, UIFontTextStyleFootnote); label.textColor = SLMuted();
    UIStackView *heading = [[UIStackView alloc] initWithArrangedSubviews:@[icon, label]];
    heading.spacing = 6; heading.alignment = UIStackViewAlignmentCenter; return heading;
}
- (UIButton *)qualityMenuButton:(NSString *)identifier {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO; button.accessibilityIdentifier = identifier;
    button.showsMenuAsPrimaryAction = YES; button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return button;
}
- (void)configureQualityButton:(UIButton *)button title:(NSString *)title locked:(BOOL)locked {
    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.title = title; configuration.baseForegroundColor = locked ? SLMuted() : UIColor.whiteColor;
    configuration.image = [UIImage systemImageNamed:locked ? @"lock" : @"chevron.down"];
    configuration.imagePlacement = NSDirectionalRectEdgeTrailing; configuration.imagePadding = 6;
    configuration.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:11];
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(8, 0, 8, 0);
    UIFont *font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline compatibleWithTraitCollection:self.traitCollection];
    configuration.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
        NSMutableDictionary *result = [attributes mutableCopy]; result[NSFontAttributeName] = font; return result;
    };
    button.configuration = configuration;
    button.enabled = YES; button.userInteractionEnabled = !locked; button.showsMenuAsPrimaryAction = !locked;
    button.accessibilityTraits = locked ? UIAccessibilityTraitStaticText : UIAccessibilityTraitButton;
}
- (BOOL)canEditQualityForTab:(SunlightStreamControlsTab)tab {
    return _expanded && _selectedTab == tab && tab != SunlightStreamControlsTabClient3D &&
        (tab == SunlightStreamControlsTab2D || _glasses3DAvailable);
}
- (void)updateQualityControls {
    if (!_resolutionButton) return;
    _bitrateSlider.minimumValue = 0.5f;
    _bitrateSlider.maximumValue = MAX(150, _qualityBitrateKbps / 1000.0f);
    _bitrateSlider.value = _qualityBitrateKbps / 1000.0f;
    _bitrateValue.text = [NSString stringWithFormat:NSLocalizedString(@"%.1f Mbps", nil), _qualityBitrateKbps / 1000.0];
    _bitrateSlider.accessibilityValue = _bitrateValue.text;
    CGSize nativeSize = SunlightNativeLandscapeSize();
    NSString *key = [NSString stringWithFormat:@"%d/%d/%d/%d/%d/%d/%.0fx%.0f/%ld/%lu/%@", _qualityWidth, _qualityHeight, _qualityFrameRate, _qualityMaxFrameRate, _qualityResolutionLocked, _qualityUsesNativeResolution, nativeSize.width, nativeSize.height, (long)_selectedTab, (unsigned long)_qualityInteractionGeneration, self.traitCollection.preferredContentSizeCategory];
    if ([_qualityControlsKey isEqualToString:key]) return;
    _qualityControlsKey = key;
    BOOL locked = _qualityResolutionLocked || self.selectedMode == SunlightStreamModeRawFullSBS;
    NSString *resolution = [NSString stringWithFormat:@"%d × %d", _qualityWidth, _qualityHeight];
    if (_qualityUsesNativeResolution && !locked) resolution = [NSString stringWithFormat:NSLocalizedString(@"Native · %@", nil), resolution];
    [self configureQualityButton:_resolutionButton title:resolution locked:locked];
    _resolutionButton.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"Resolution, %@", nil), resolution];
    _resolutionButton.accessibilityHint = locked ? NSLocalizedString(@"Matches the complete picture supplied for your glasses.", nil) : NSLocalizedString(@"Choose this app’s resolution for the selected mode.", nil);
    [self configureQualityButton:_frameRateButton title:[NSString stringWithFormat:NSLocalizedString(@"%d FPS", nil), _qualityFrameRate] locked:NO];
    _frameRateButton.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"Max frame rate, %d frames per second", nil), _qualityFrameRate];
    _frameRateButton.accessibilityHint = [NSString stringWithFormat:NSLocalizedString(@"Available frame rates up to %d frames per second.", nil), _qualityMaxFrameRate];
    SunlightStreamControlsTab tab = _selectedTab;
    NSUInteger generation = _qualityInteractionGeneration;
    __weak typeof(self) weakSelf = self;
    NSMutableArray<UIAction *> *resolutionActions = [NSMutableArray array];
    BOOL nativeSupported = nativeSize.width > 0 && nativeSize.height > 0 &&
        (tab == SunlightStreamControlsTab2D || (tab == SunlightStreamControlsTabHost3D &&
         [StreamConfiguration isSupportedHost3DWidth:(int)nativeSize.width height:(int)nativeSize.height]));
    if (!locked && nativeSupported) {
        UIAction *native = [UIAction actionWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Native · %.0f × %.0f", nil), nativeSize.width, nativeSize.height]
            image:[UIImage systemImageNamed:@"display"] identifier:@"sunlight.controls.resolution.native" handler:^(__kindof UIAction *action) {
                typeof(self) self = weakSelf;
                if (!self || generation != self->_qualityInteractionGeneration || ![self canEditQualityForTab:tab] || self.qualityResolutionLocked || self.selectedMode == SunlightStreamModeRawFullSBS) return;
                if (self->_qualityUsesNativeResolution && self->_qualityWidth == (int)nativeSize.width && self->_qualityHeight == (int)nativeSize.height) return;
                self->_qualityUsesNativeResolution = YES;
                self->_qualityWidth = (int)nativeSize.width; self->_qualityHeight = (int)nativeSize.height;
                [self qualityEdited];
            }];
        native.state = _qualityUsesNativeResolution ? UIMenuElementStateOn : UIMenuElementStateOff;
        [resolutionActions addObject:native];
    }
    NSMutableArray<NSValue *> *sizes = [NSMutableArray arrayWithObject:[NSValue valueWithCGSize:CGSizeMake(_qualityWidth, _qualityHeight)]];
    for (NSValue *candidate in @[[NSValue valueWithCGSize:CGSizeMake(1280, 720)], [NSValue valueWithCGSize:CGSizeMake(1920, 1080)], [NSValue valueWithCGSize:CGSizeMake(2560, 1440)]]) {
        CGSize size = candidate.CGSizeValue;
        if (![sizes containsObject:candidate] && (tab != SunlightStreamControlsTabHost3D || [StreamConfiguration isSupportedHost3DWidth:size.width height:size.height])) [sizes addObject:candidate];
    }
    for (NSValue *value in sizes) {
        CGSize size = value.CGSizeValue;
        UIAction *action = [UIAction actionWithTitle:[NSString stringWithFormat:@"%.0f × %.0f", size.width, size.height] image:nil identifier:[NSString stringWithFormat:@"sunlight.controls.resolution.%.0fx%.0f", size.width, size.height] handler:^(__kindof UIAction *action) {
            typeof(self) self = weakSelf;
            if (!self || generation != self->_qualityInteractionGeneration || ![self canEditQualityForTab:tab] || self.qualityResolutionLocked || self.selectedMode == SunlightStreamModeRawFullSBS) return;
            if (!self->_qualityUsesNativeResolution && self->_qualityWidth == (int)size.width && self->_qualityHeight == (int)size.height) return;
            self->_qualityUsesNativeResolution = NO;
            self->_qualityWidth = size.width; self->_qualityHeight = size.height; [self qualityEdited];
        }];
        action.state = !_qualityUsesNativeResolution && size.width == _qualityWidth && size.height == _qualityHeight ? UIMenuElementStateOn : UIMenuElementStateOff;
        [resolutionActions addObject:action];
    }
    _resolutionButton.menu = locked ? nil : [UIMenu menuWithTitle:NSLocalizedString(@"Resolution", nil) children:resolutionActions];
    NSMutableArray<NSNumber *> *rates = [NSMutableArray arrayWithObject:@(_qualityFrameRate)];
    for (NSNumber *rate in @[@30, @60, @90, @120, @144, @165, @240]) if (rate.intValue <= _qualityMaxFrameRate && ![rates containsObject:rate]) [rates addObject:rate];
    NSMutableArray<UIAction *> *rateActions = [NSMutableArray array];
    for (NSNumber *rate in rates) {
        UIAction *action = [UIAction actionWithTitle:[NSString stringWithFormat:NSLocalizedString(@"%d FPS", nil), rate.intValue] image:nil identifier:[NSString stringWithFormat:@"sunlight.controls.frameRate.%d", rate.intValue] handler:^(__kindof UIAction *action) {
            typeof(self) self = weakSelf;
            if (!self || generation != self->_qualityInteractionGeneration || ![self canEditQualityForTab:tab] || rate.intValue > self.qualityMaxFrameRate || self->_qualityFrameRate == rate.intValue) return;
            self->_qualityFrameRate = rate.intValue; [self qualityEdited];
        }];
        action.state = rate.intValue == _qualityFrameRate ? UIMenuElementStateOn : UIMenuElementStateOff;
        if (rate.intValue > _qualityMaxFrameRate) action.attributes = UIMenuElementAttributesDisabled;
        [rateActions addObject:action];
    }
    _frameRateButton.menu = [UIMenu menuWithTitle:NSLocalizedString(@"Max frame rate", nil) children:rateActions];
    [self setNeedsLayout];
}
- (void)qualityEdited {
    [self updateQualityControls];
    if (self.qualityChangedHandler) self.qualityChangedHandler(_qualityWidth, _qualityHeight, _qualityFrameRate, _qualityBitrateKbps);
}
- (void)invalidateQualityInteractions {
    _qualityInteractionGeneration++;
    if (_bitrateGestureActive) {
        _bitrateGestureCancelled = YES;
        [_bitrateSlider cancelTrackingWithEvent:nil];
        _bitrateGestureActive = NO;
    }
}
- (void)bitrateTouchBegan {
    _bitrateGestureActive = YES; _bitrateGestureCancelled = NO;
    _bitrateGestureGeneration = _qualityInteractionGeneration; _bitrateGestureTab = _selectedTab;
}
- (void)bitrateTouchEnded { _bitrateGestureActive = NO; }
- (void)bitrateChanged:(UISlider *)sender {
    if (![self canEditQualityForTab:_selectedTab] || (!_bitrateSlider.accessibilityEditing && (_bitrateGestureCancelled || (_bitrateGestureActive && (_bitrateGestureGeneration != _qualityInteractionGeneration || _bitrateGestureTab != _selectedTab))))) {
        [self updateQualityControls]; return;
    }
    int bitrate = (int)lroundf(sender.value * 10) * 100;
    if (_qualityBitrateKbps == bitrate) return;
    _qualityBitrateKbps = bitrate; [self qualityEdited];
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (_expanded) return [super pointInside:point withEvent:event];
    return !_pill.hidden && [_pill pointInside:[self convertPoint:point toView:_pill] withEvent:event];
}

- (void)expandTapped { self.expanded = YES; }
- (void)closeTapped { self.expanded = NO; }
- (BOOL)accessibilityPerformEscape { if (!_expanded) return NO; self.expanded = NO; return YES; }
- (void)modeChanged {
    if (!_expanded) return;
    SunlightStreamControlsTab previous = self.selectedTab;
    NSInteger tab = _modeSelector.selectedSegmentIndex;
    if (tab < SunlightStreamControlsTab2D || tab > SunlightStreamControlsTabRaw3D) return;
    if (!_glasses3DAvailable && (tab == SunlightStreamControlsTabHost3D || tab == SunlightStreamControlsTabRaw3D)) tab = SunlightStreamControlsTab2D;
    if (_selectedTab != tab) [self invalidateQualityInteractions];
    _selectedTab = tab;
    if (tab != SunlightStreamControlsTabClient3D) {
        _draftMode = tab == SunlightStreamControlsTab2D ? SunlightStreamMode2D : tab == SunlightStreamControlsTabHost3D ? SunlightStreamModeHost3D : SunlightStreamModeRawFullSBS;
    }
    [self updateState]; [_scroll setContentOffset:CGPointZero animated:NO]; [self notifySelectionChangedFrom:previous];
}
- (void)applyTapped { if (_expanded && _selectedTab != SunlightStreamControlsTabClient3D && (self.selectedMode == SunlightStreamMode2D || _glasses3DAvailable) && _apply.enabled && self.modeApplyHandler) self.modeApplyHandler(self.selectedMode); }
- (void)actionTapped:(UIControl *)sender { if (!sender.enabled || !_expanded || (sender.tag == SunlightStreamControlsActionModeDefaults && _selectedTab == SunlightStreamControlsTabClient3D)) return; if (self.actionHandler) self.actionHandler(sender.tag); }
@end
