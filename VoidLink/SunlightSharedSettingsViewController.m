#import "SunlightSharedSettingsViewController.h"
#import "SunlightUITheme.h"
#import "SunlightMoonlightIcons.h"
#include <math.h>

static void SLSharedConfigureCell(UITableViewCell *cell) {
    cell.backgroundColor = [SunlightUITheme raisedColor];
    cell.tintColor = [SunlightUITheme accentColor];
}

static UIImageView *SLSharedIconView(NSString *name) {
    UIImageView *icon = [[UIImageView alloc] initWithImage:[SunlightMoonlightIcons imageNamed:name]];
    icon.tintColor = [SunlightUITheme accentColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [NSLayoutConstraint activateConstraints:@[[icon.widthAnchor constraintEqualToConstant:24], [icon.heightAnchor constraintEqualToConstant:24]]];
    return icon;
}

static void SLSharedConfigureText(UITableViewCell *cell) {
    SLSharedConfigureCell(cell);
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.textColor = [SunlightUITheme primaryTextColor];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    cell.detailTextLabel.textColor = [SunlightUITheme secondaryTextColor];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.numberOfLines = 0;
}

@interface SunlightSharedSettingsViewController () <UIAdaptivePresentationControllerDelegate>
@end

@implementation SunlightSharedSettingsViewController {
    SunlightSharedSettings *_draft, *_globalDefaults;
    NSString *_hostName;
    BOOL _glassesOutput, _useGlobalDefaults, _submitted;
}
- (instancetype)initWithSettings:(SunlightSharedSettings *)settings
                  globalDefaults:(SunlightSharedSettings *)globalDefaults
                        hostName:(NSString *)hostName glassesOutput:(BOOL)glassesOutput {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _draft = [settings copy]; _globalDefaults = [globalDefaults copy];
        _hostName = [hostName copy] ?: NSLocalizedString(@"This PC", nil); _glassesOutput = glassesOutput;
        _reconnectRequired = YES;
        self.title = NSLocalizedString(@"PC settings", nil);
    }
    return self;
}
- (void)setReconnectRequired:(BOOL)reconnectRequired {
    _reconnectRequired = reconnectRequired;
    if (self.isViewLoaded) [self.tableView reloadData];
}
- (void)setMachineControls:(SunlightMachineControlsSettings *)machineControls {
    _machineControls = [machineControls copy];
    if (self.isViewLoaded) [self.tableView reloadData];
}
- (void)setGlobalMachineControls:(SunlightMachineControlsSettings *)globalMachineControls {
    _globalMachineControls = [globalMachineControls copy];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.tintColor = [SunlightUITheme accentColor];
    self.tableView.backgroundColor = [SunlightUITheme surfaceColor];
    self.tableView.separatorColor = [SunlightUITheme borderColor];
    self.tableView.accessibilityIdentifier = @"shared.settings.pc";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Cancel", nil)
        style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.navigationItem.leftBarButtonItem.accessibilityIdentifier = @"shared.settings.cancel";
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Back", nil)
        style:UIBarButtonItemStylePlain target:nil action:nil];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [SunlightUITheme styleNavigationController:self.navigationController];
    [self.tableView reloadData];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Main presents this editor in a page sheet. Swiping it away cancels the
    // same detached draft as the explicit Cancel action.
    self.navigationController.presentationController.delegate = self;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (self.isViewLoaded) [self.tableView reloadData];
}
- (NSInteger)videoSection { return 0; }
- (NSInteger)deliverySection { return [self videoSection] + 1; }
- (BOOL)hasMachineControls { return _machineControls != nil; }
- (NSInteger)machineSection { return [self hasMachineControls] ? [self videoSection] + 2 : NSNotFound; }
- (NSInteger)soundSection { return [self hasMachineControls] ? [self machineSection] + 1 : NSNotFound; }
- (NSInteger)statisticsSection { return [self hasMachineControls] ? [self machineSection] + 2 : NSNotFound; }
- (NSInteger)actionSection { return [self videoSection] + 2 + ([self hasMachineControls] ? 3 : 0); }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return [self actionSection] + 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == [self machineSection]) return 2;
    if (section == [self soundSection] || section == [self statisticsSection]) return 1;
    if (section == [self actionSection]) return 2;
    return 3;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == [self videoSection]) return NSLocalizedString(@"Video", nil);
    if (section == [self deliverySection]) return NSLocalizedString(@"Delivery", nil);
    if (section == [self machineSection]) return NSLocalizedString(@"PC controls", nil);
    if (section == [self soundSection]) return NSLocalizedString(@"Sound", nil);
    if (section == [self statisticsSection]) return NSLocalizedString(@"Statistics", nil);
    return nil;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self tableView:tableView titleForHeaderInSection:section];
    if (!title.length) return nil;
    NSString *iconName = nil;
    if (section == [self videoSection]) iconName = @"ic_xr_mode_normal";
    else if (section == [self deliverySection]) iconName = @"ic_xr_frame_pacing";
    else if (section == [self machineSection]) iconName = @"ic_xr_mouse";
    else if (section == [self soundSection]) iconName = @"ic_xr_audio";
    else if (section == [self statisticsSection]) iconName = @"ic_xr_diagnostics";
    if (!iconName) return nil; // Let UIKit provide a standard header for an unmapped section.
    UIView *header = [[UIView alloc] init];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[SunlightMoonlightIcons imageNamed:iconName]];
    icon.tintColor = [SunlightUITheme accentColor]; icon.contentMode = UIViewContentModeScaleAspectFit;
    [icon.widthAnchor constraintEqualToConstant:20].active = YES;
    UILabel *label = [[UILabel alloc] init]; label.text = title;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    label.adjustsFontForContentSizeCategory = YES; label.textColor = [SunlightUITheme secondaryTextColor];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, label]];
    stack.spacing = 8; stack.alignment = UIStackViewAlignmentCenter; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8],
        [stack.topAnchor constraintGreaterThanOrEqualToAnchor:header.topAnchor constant:8]
    ]];
    header.accessibilityIdentifier = [NSString stringWithFormat:@"shared.settings.group.%ld", (long)section];
    return header;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [self tableView:tableView titleForHeaderInSection:section].length
        ? [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline].lineHeight + 24 : UITableViewAutomaticDimension;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == [self videoSection]) return _glassesOutput
        ? [NSString stringWithFormat:NSLocalizedString(@"Shared by all apps on %@. Glasses output currently uses SDR and queue buffering; your saved HDR and pacing preferences are retained.", nil), _hostName]
        : [NSString stringWithFormat:NSLocalizedString(@"Shared by all apps on %@. Each app keeps its own Picture settings.", nil), _hostName];
    if (section == [self deliverySection]) return NSLocalizedString(@"Surround sound depends on the device and audio output.", nil);
    if (section == [self machineSection]) return [NSString stringWithFormat:NSLocalizedString(@"Shared by all apps on %@. The saved profile catalog is shared by this device.", nil), _hostName];
    if (section == [self soundSection]) return NSLocalizedString(@"Volume on this device. Stream audio layout and playback on the PC are set above.", nil);
    if (section == [self statisticsSection]) return NSLocalizedString(@"Show performance information over the stream.", nil);
    if (section == [self actionSection]) return _reconnectRequired
        ? NSLocalizedString(@"Apply reconnects this stream with the selected PC settings. Your PC app stays running.", nil)
        : [NSString stringWithFormat:NSLocalizedString(@"Save settings applies to future connections to %@. Other PCs keep their own settings.", nil), _hostName];
    return nil;
}
- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:UITableViewHeaderFooterView.class]) {
        ((UITableViewHeaderFooterView *)view).textLabel.textColor = [SunlightUITheme secondaryTextColor];
    }
}
- (UITableViewCell *)inlineChoiceWithTitle:(NSString *)title choices:(NSArray<NSString *> *)choices selected:(NSInteger)selected
                                    tag:(NSInteger)tag identifier:(NSString *)identifier detail:(NSString *)detail {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    SLSharedConfigureCell(cell);
    cell.selectionStyle = UITableViewCellSelectionStyleNone; cell.accessibilityIdentifier = identifier;
    UILabel *label = [[UILabel alloc] init]; label.text = title; label.textColor = [SunlightUITheme primaryTextColor];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = 0;
    UISegmentedControl *selector = [[UISegmentedControl alloc] initWithItems:choices];
    selector.selectedSegmentIndex = selected; selector.tag = tag;
    selector.accessibilityIdentifier = [identifier stringByAppendingString:@".selector"];
    selector.accessibilityLabel = title; selector.enabled = !_submitted;
    [SunlightUITheme styleChoiceControl:selector];
    [selector addTarget:self action:@selector(inlineChoiceChanged:) forControlEvents:UIControlEventValueChanged];
    NSString *iconName = @{@10: @"ic_xr_video_range", @11: @"ic_xr_codec", @12: @"ic_xr_frame_pacing", @13: @"ic_xr_audio", @21: @"ic_xr_diagnostics"}[@(tag)];
    UIView *titleView = label;
    if (iconName) {
        UIStackView *titleStack = [[UIStackView alloc] initWithArrangedSubviews:@[SLSharedIconView(iconName), label]];
        titleStack.axis = UILayoutConstraintAxisHorizontal; titleStack.alignment = UIStackViewAlignmentCenter; titleStack.spacing = 10;
        titleView = titleStack;
    }
    NSMutableArray *views = [NSMutableArray arrayWithArray:@[titleView, selector]];
    if (detail.length) {
        UILabel *hint = [[UILabel alloc] init]; hint.text = detail; hint.numberOfLines = 0;
        hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; hint.adjustsFontForContentSizeCategory = YES;
        hint.textColor = [SunlightUITheme secondaryTextColor]; [views addObject:hint];
    }
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 8; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-20]
    ]];
    return cell;
}
- (UITableViewCell *)volumeCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    SLSharedConfigureCell(cell);
    cell.selectionStyle = UITableViewCellSelectionStyleNone; cell.accessibilityIdentifier = @"shared.settings.volume";
    UILabel *label = [[UILabel alloc] init]; label.tag = 301;
    label.textColor = [SunlightUITheme primaryTextColor];
    label.text = [NSString stringWithFormat:NSLocalizedString(@"Volume · %ld%%", nil), (long)lround(_machineControls.localVolume * 100)];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; label.adjustsFontForContentSizeCategory = YES;
    UISlider *slider = [[UISlider alloc] init]; slider.minimumValue = 0; slider.maximumValue = 1; slider.value = _machineControls.localVolume;
    slider.tintColor = [SunlightUITheme accentColor];
    [SunlightUITheme styleSlider:slider];
    slider.minimumValueImage = [UIImage systemImageNamed:@"speaker.fill"];
    slider.maximumValueImage = [UIImage systemImageNamed:@"speaker.wave.3.fill"];
    slider.accessibilityLabel = NSLocalizedString(@"Volume", nil); slider.accessibilityIdentifier = @"shared.settings.volume.slider";
    slider.enabled = !_submitted; [slider addTarget:self action:@selector(inlineVolumeChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[label, slider]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 8; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-20]
    ]];
    return cell;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == [self videoSection] && indexPath.row == 1) return [self inlineChoiceWithTitle:NSLocalizedString(@"Video range", nil)
        choices:@[NSLocalizedString(@"Limited", nil), NSLocalizedString(@"Full", nil)] selected:_draft.fullColorRange ? 1 : 0 tag:10 identifier:@"shared.settings.range" detail:nil];
    if (indexPath.section == [self videoSection] && indexPath.row == 2) return [self inlineChoiceWithTitle:NSLocalizedString(@"Codec", nil)
        choices:@[NSLocalizedString(@"Auto", nil), @"H.264", @"HEVC", @"AV1"] selected:_draft.preferredCodec tag:11 identifier:@"shared.settings.codec" detail:NSLocalizedString(@"The PC and device negotiate a compatible format.", nil)];
    if (indexPath.section == [self deliverySection] && indexPath.row == 0 && !_glassesOutput) {
        NSArray *choices = @[NSLocalizedString(@"Off", nil), NSLocalizedString(@"Legacy", nil), NSLocalizedString(@"Queue", nil)];
        if (_draft.framePacingMode == 3) choices = [choices arrayByAddingObject:NSLocalizedString(@"Interpolation", nil)];
        return [self inlineChoiceWithTitle:NSLocalizedString(@"Frame pacing", nil) choices:choices selected:_draft.framePacingMode tag:12 identifier:@"shared.settings.pacing" detail:nil];
    }
    if (indexPath.section == [self deliverySection] && indexPath.row == 1) {
        NSInteger selected = [@[@2, @3, @6, @8] indexOfObject:@(_draft.audioConfig)];
        return [self inlineChoiceWithTitle:NSLocalizedString(@"Audio layout", nil)
            choices:@[NSLocalizedString(@"Stereo", nil), NSLocalizedString(@"Compatibility", nil), @"5.1", @"7.1"] selected:selected == NSNotFound ? 0 : selected tag:13 identifier:@"shared.settings.audio" detail:NSLocalizedString(@"Compatibility uses the alternate stereo audio engine.", nil)];
    }
    if (indexPath.section == [self machineSection] && indexPath.row == 1) {
        NSString *hint = _machineControls.controlMode == SunlightMachineControlModeTrackpad ? NSLocalizedString(@"Tap to click, slide to move. Two-finger tap right-clicks.", nil)
            : _machineControls.controlMode == SunlightMachineControlModeGamepad ? NSLocalizedString(@"Use the on-screen sticks and buttons to control the PC.", nil)
            : self.savedProfileSummary.length ? self.savedProfileSummary : NSLocalizedString(@"Uses the profile selected in Pad settings on this device.", nil);
        return [self inlineChoiceWithTitle:NSLocalizedString(@"Control mode", nil)
            choices:@[NSLocalizedString(@"Trackpad", nil), NSLocalizedString(@"Saved profile", nil), NSLocalizedString(@"Gamepad", nil)]
            selected:_machineControls.controlMode tag:20 identifier:@"shared.settings.control-mode" detail:hint];
    }
    if (indexPath.section == [self soundSection]) return [self volumeCell];
    if (indexPath.section == [self statisticsSection]) return [self inlineChoiceWithTitle:NSLocalizedString(@"Statistics overlay", nil)
        choices:@[NSLocalizedString(@"Off", nil), NSLocalizedString(@"Simplified", nil), NSLocalizedString(@"Detailed", nil)]
        selected:_machineControls.statsOverlayLevel tag:21 identifier:@"shared.settings.statistics" detail:nil];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    SLSharedConfigureText(cell);
    if (indexPath.section == [self machineSection]) {
        cell.textLabel.text = NSLocalizedString(@"Touch enabled", nil);
        cell.detailTextLabel.text = NSLocalizedString(@"Finger and Pencil input. Hardware mouse and keyboard remain available.", nil);
        cell.accessibilityIdentifier = @"shared.settings.touch-enabled";
        [self addSwitchToCell:cell on:_machineControls.touchEnabled tag:2];
    } else if (indexPath.section == [self actionSection]) {
        BOOL reset = indexPath.row == 0;
        cell.textLabel.text = reset ? NSLocalizedString(@"Use global defaults", nil)
            : _reconnectRequired ? NSLocalizedString(@"Apply & reconnect", nil) : NSLocalizedString(@"Save settings", nil);
        cell.textLabel.textColor = _submitted ? [SunlightUITheme disabledTextColor] : [SunlightUITheme accentColor];
        cell.accessibilityIdentifier = reset ? @"shared.settings.reset" : @"shared.settings.apply";
        cell.imageView.image = [UIImage systemImageNamed:reset ? @"arrow.counterclockwise" : _reconnectRequired ? @"arrow.triangle.2.circlepath" : @"checkmark.circle"];
        cell.imageView.tintColor = cell.textLabel.textColor;
        cell.accessibilityTraits = UIAccessibilityTraitButton;
        if (reset && _useGlobalDefaults) cell.detailTextLabel.text = _reconnectRequired
            ? NSLocalizedString(@"Global defaults selected. Apply to use them on this PC.", nil)
            : NSLocalizedString(@"Global defaults selected. Save to use them on this PC.", nil);
        if (_submitted) { cell.selectionStyle = UITableViewCellSelectionStyleNone; cell.accessibilityTraits |= UIAccessibilityTraitNotEnabled; }
    } else if (indexPath.section == [self videoSection]) {
        cell.textLabel.text = NSLocalizedString(@"HDR", nil); cell.accessibilityIdentifier = @"shared.settings.hdr";
        cell.imageView.image = [SunlightMoonlightIcons imageNamed:@"ic_xr_hdr"];
        if (_glassesOutput) cell.detailTextLabel.text = NSLocalizedString(@"SDR for glasses", nil);
        else [self addSwitchToCell:cell on:_draft.enableHdr tag:0];
    } else if (indexPath.row == 0) {
        cell.textLabel.text = NSLocalizedString(@"Frame pacing", nil); cell.accessibilityIdentifier = @"shared.settings.pacing";
        cell.imageView.image = [SunlightMoonlightIcons imageNamed:@"ic_xr_frame_pacing"];
        cell.detailTextLabel.text = NSLocalizedString(@"Queue buffering for glasses", nil);
    } else {
        cell.textLabel.text = NSLocalizedString(@"Play audio on PC", nil); cell.accessibilityIdentifier = @"shared.settings.host-audio";
        cell.imageView.image = [SunlightMoonlightIcons imageNamed:@"ic_xr_audio_host"];
        [self addSwitchToCell:cell on:_draft.playAudioOnPC tag:1];
    }
    if (indexPath.section != [self actionSection]) cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}
- (void)addSwitchToCell:(UITableViewCell *)cell on:(BOOL)on tag:(NSInteger)tag {
    UISwitch *toggle = [[UISwitch alloc] init]; toggle.on = on; toggle.tag = tag;
    [SunlightUITheme styleSwitch:toggle]; toggle.enabled = !_submitted;
    toggle.accessibilityIdentifier = [cell.accessibilityIdentifier stringByAppendingString:@".switch"];
    toggle.accessibilityLabel = cell.textLabel.text;
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle; cell.selectionStyle = UITableViewCellSelectionStyleNone;
}
- (void)toggleChanged:(UISwitch *)toggle {
    if (_submitted || (_glassesOutput && toggle.tag == 0)) return;
    if (toggle.tag == 0) {
        if (_draft.enableHdr == toggle.on) return;
        _draft.enableHdr = toggle.on;
    } else if (toggle.tag == 1) {
        if (_draft.playAudioOnPC == toggle.on) return;
        _draft.playAudioOnPC = toggle.on;
    } else if (toggle.tag == 2 && _machineControls) {
        if (_machineControls.touchEnabled == toggle.on) return;
        _machineControls.touchEnabled = toggle.on;
    } else return;
    _useGlobalDefaults = NO;
}
- (void)inlineChoiceChanged:(UISegmentedControl *)selector {
    if (_submitted || selector.selectedSegmentIndex == UISegmentedControlNoSegment) return;
    NSInteger value = selector.selectedSegmentIndex;
    switch (selector.tag) {
        case 10: if (value > 1 || _draft.fullColorRange == (value == 1)) return; _draft.fullColorRange = value == 1; break;
        case 11: if (value > 3 || _draft.preferredCodec == value) return; _draft.preferredCodec = value; break;
        case 12: if (_glassesOutput || value > 3 || _draft.framePacingMode == value) return; _draft.framePacingMode = value; break;
        case 13: {
            if (value > 3) return;
            value = [@[@2, @3, @6, @8][value] integerValue];
            if (_draft.audioConfig == value) return; _draft.audioConfig = value; break;
        }
        case 20: if (!_machineControls || value > 2 || _machineControls.controlMode == value) return; _machineControls.controlMode = value; break;
        case 21: if (!_machineControls || value > 2 || _machineControls.statsOverlayLevel == value) return; _machineControls.statsOverlayLevel = value; break;
        default: return;
    }
    _useGlobalDefaults = NO;
    [self.tableView reloadData];
}
- (void)inlineVolumeChanged:(UISlider *)slider {
    if (_submitted || !_machineControls) return;
    double value = round(slider.value * 100) / 100;
    if (!isfinite(value) || value < 0 || value > 1 || fabs(value - _machineControls.localVolume) <= 0.000001) return;
    _machineControls.localVolume = value; _useGlobalDefaults = NO;
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:[self soundSection]]];
    UILabel *label = [cell.contentView viewWithTag:301];
    label.text = [NSString stringWithFormat:NSLocalizedString(@"Volume · %ld%%", nil), (long)lround(value * 100)];
    slider.accessibilityValue = [NSString stringWithFormat:@"%ld%%", (long)lround(value * 100)];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_submitted || indexPath.section != [self actionSection]) return;
    if (indexPath.row == 0) {
        _draft = [_globalDefaults copy];
        if (_machineControls && _globalMachineControls) _machineControls = [_globalMachineControls copy];
        _useGlobalDefaults = YES; [self.tableView reloadData];
    } else [self apply];
}
- (void)apply {
    if (_submitted || !_machineControls || !self.applyMachineSettings) return;
    _submitted = YES; [self.tableView reloadData];
    self.applyMachineSettings([_draft copy], _useGlobalDefaults, [_machineControls copy]);
}
- (void)cancel {
    if (_submitted) return;
    // Retire before beginning dismissal: already queued controls or Save must
    // not submit this abandoned draft while the sheet animates away.
    _submitted = YES;
    [self.tableView reloadData];
    [self dismissViewControllerAnimated:YES completion:self.closed];
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    if (_submitted) return;
    _submitted = YES;
    if (self.closed) self.closed();
}
@end
