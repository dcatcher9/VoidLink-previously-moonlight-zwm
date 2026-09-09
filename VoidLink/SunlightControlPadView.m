#import "SunlightControlPadView.h"
#import "SunlightUITheme.h"
#import <Limelight.h>
#import <math.h>

static UIColor *PadSurface(void) {
    return SunlightUITheme.surfaceColor;
}
static UIColor *PadAccent(void) {
    return SunlightUITheme.accentColor;
}

@interface SunlightPadButton : UIControl
@property (nonatomic, copy) void (^changed)(BOOL down);
- (instancetype)initWithTitle:(NSString *)title label:(NSString *)label;
- (void)releaseControl;
@end

@implementation SunlightPadButton {
    UILabel *_title;
    BOOL _pressed;
    BOOL _acceptingTouch;
}
- (instancetype)initWithTitle:(NSString *)title label:(NSString *)label {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.multipleTouchEnabled = NO;
        self.exclusiveTouch = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.accessibilityLabel = label;
        self.layer.cornerRadius = 14;
        self.layer.borderWidth = 1;
        _title = [[UILabel alloc] init];
        _title.text = title;
        _title.textAlignment = NSTextAlignmentCenter;
        _title.font = [UIFont systemFontOfSize:title.length > 2 ? 12 : 17 weight:UIFontWeightSemibold];
        _title.adjustsFontSizeToFitWidth = YES;
        _title.minimumScaleFactor = 0.8;
        _title.userInteractionEnabled = NO;
        _title.isAccessibilityElement = NO;
        [self addSubview:_title];
        [self refreshAppearance];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _title.frame = CGRectInset(self.bounds, 3, 0);
}
- (void)refreshAppearance {
    self.backgroundColor = _pressed ? PadAccent() : PadSurface();
    self.layer.borderColor = (_pressed ? PadAccent() : SunlightUITheme.borderColor).CGColor;
    _title.textColor = _pressed ? PadSurface() : SunlightUITheme.primaryTextColor;
    self.accessibilityValue = _pressed ? NSLocalizedString(@"Pressed", @"Gamepad button state") : nil;
}
- (void)setPressed:(BOOL)pressed {
    if (_pressed == pressed) return;
    _pressed = pressed;
    [self refreshAppearance];
    if (self.changed) self.changed(pressed);
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (!self.enabled || !self.userInteractionEnabled) return NO;
    _acceptingTouch = YES;
    [self setPressed:YES];
    return _acceptingTouch;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (!_acceptingTouch) return NO;
    if (!CGRectContainsPoint(self.bounds, [touch locationInView:self])) {
        [self releaseControl];
        return NO;
    }
    return YES;
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { [self releaseControl]; }
- (void)cancelTrackingWithEvent:(UIEvent *)event { [self releaseControl]; }
- (void)releaseControl {
    _acceptingTouch = NO;
    [self setPressed:NO];
}
- (BOOL)accessibilityActivate {
    if (!self.enabled || !self.userInteractionEnabled || self.hidden) return NO;
    [self setPressed:YES];
    [self releaseControl];
    return YES;
}
@end

@interface SunlightPadStick : UIControl
@property (nonatomic, copy) void (^changed)(CGPoint position);
- (instancetype)initWithLabel:(NSString *)label;
- (void)releaseControl;
@end

@implementation SunlightPadStick {
    UIView *_ring;
    UIView *_thumb;
    UILabel *_label;
    CGPoint _position;
    BOOL _acceptingTouch;
}
- (instancetype)initWithLabel:(NSString *)label {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.multipleTouchEnabled = NO;
        self.exclusiveTouch = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = label;
        self.accessibilityHint = NSLocalizedString(@"Use the actions to move or stop the stick.", @"Gamepad stick accessibility hint");
        _ring = [[UIView alloc] init];
        _ring.backgroundColor = [PadSurface() colorWithAlphaComponent:0.9];
        _ring.layer.borderColor = SunlightUITheme.borderColor.CGColor;
        _ring.layer.borderWidth = 1;
        _ring.userInteractionEnabled = NO;
        [self addSubview:_ring];
        _label = [[UILabel alloc] init];
        _label.text = label;
        _label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        _label.textColor = SunlightUITheme.secondaryTextColor;
        _label.textAlignment = NSTextAlignmentCenter;
        _label.userInteractionEnabled = NO;
        [self addSubview:_label];
        _thumb = [[UIView alloc] init];
        _thumb.backgroundColor = SunlightUITheme.deepAccentColor;
        _thumb.layer.borderColor = [PadAccent() colorWithAlphaComponent:0.7].CGColor;
        _thumb.layer.borderWidth = 1.5;
        _thumb.userInteractionEnabled = NO;
        [self addSubview:_thumb];
        self.accessibilityCustomActions = @[
            [[UIAccessibilityCustomAction alloc] initWithName:NSLocalizedString(@"Up", @"Stick direction") target:self selector:@selector(accessibilityUp)],
            [[UIAccessibilityCustomAction alloc] initWithName:NSLocalizedString(@"Down", @"Stick direction") target:self selector:@selector(accessibilityDown)],
            [[UIAccessibilityCustomAction alloc] initWithName:NSLocalizedString(@"Left", @"Stick direction") target:self selector:@selector(accessibilityLeft)],
            [[UIAccessibilityCustomAction alloc] initWithName:NSLocalizedString(@"Right", @"Stick direction") target:self selector:@selector(accessibilityRight)],
            [[UIAccessibilityCustomAction alloc] initWithName:NSLocalizedString(@"Stop", @"Release stick") target:self selector:@selector(accessibilityStop)]
        ];
    }
    return self;
}
- (CGFloat)travelRadius {
    return MAX(1, (MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds)) - 44) / 2);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat diameter = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    _ring.bounds = CGRectMake(0, 0, diameter, diameter);
    _ring.center = center;
    _ring.layer.cornerRadius = diameter / 2;
    _thumb.bounds = CGRectMake(0, 0, 44, 44);
    _thumb.layer.cornerRadius = 22;
    _thumb.center = CGPointMake(center.x + _position.x * self.travelRadius, center.y - _position.y * self.travelRadius);
    _label.frame = CGRectMake(0, CGRectGetHeight(self.bounds) - 18, CGRectGetWidth(self.bounds), 14);
}
- (void)setPosition:(CGPoint)position {
    if (CGPointEqualToPoint(_position, position)) return;
    _position = position;
    [self setNeedsLayout];
    _thumb.backgroundColor = CGPointEqualToPoint(position, CGPointZero)
        ? SunlightUITheme.deepAccentColor : PadAccent();
    if (self.changed) self.changed(position);
}
- (void)updateTouch:(UITouch *)touch {
    CGPoint location = [touch locationInView:self];
    CGFloat radius = self.travelRadius;
    CGPoint position = CGPointMake((location.x - CGRectGetMidX(self.bounds)) / radius,
                                  (CGRectGetMidY(self.bounds) - location.y) / radius);
    CGFloat magnitude = hypot(position.x, position.y);
    if (!isfinite(magnitude) || magnitude < 0.08) {
        position = CGPointZero;
    } else if (magnitude > 1) {
        position.x /= magnitude;
        position.y /= magnitude;
    }
    [self setPosition:position];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (!self.enabled || !self.userInteractionEnabled) return NO;
    _acceptingTouch = YES;
    [self updateTouch:touch];
    return _acceptingTouch;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (!_acceptingTouch) return NO;
    if (!CGRectContainsPoint(self.bounds, [touch locationInView:self])) {
        [self releaseControl];
        return NO;
    }
    [self updateTouch:touch];
    return YES;
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { [self releaseControl]; }
- (void)cancelTrackingWithEvent:(UIEvent *)event { [self releaseControl]; }
- (void)releaseControl {
    _acceptingTouch = NO;
    [self setPosition:CGPointZero];
}
- (BOOL)accessibilityPosition:(CGPoint)position {
    if (!self.enabled || !self.userInteractionEnabled || self.hidden) return NO;
    [self releaseControl];
    [self setPosition:position];
    return YES;
}
- (BOOL)accessibilityUp { return [self accessibilityPosition:CGPointMake(0, 1)]; }
- (BOOL)accessibilityDown { return [self accessibilityPosition:CGPointMake(0, -1)]; }
- (BOOL)accessibilityLeft { return [self accessibilityPosition:CGPointMake(-1, 0)]; }
- (BOOL)accessibilityRight { return [self accessibilityPosition:CGPointMake(1, 0)]; }
- (BOOL)accessibilityStop { [self releaseControl]; return YES; }
@end

@implementation SunlightControlPadView {
    NSArray<SunlightPadButton *> *_topButtons;
    NSArray<SunlightPadButton *> *_dpad;
    NSArray<SunlightPadButton *> *_faceButtons;
    SunlightPadStick *_leftStick;
    SunlightPadStick *_rightStick;
    BOOL _releasingControls;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self buildControls];
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) [self buildControls];
    return self;
}
- (SunlightPadButton *)button:(NSString *)title label:(NSString *)label flag:(int)flag identifier:(NSString *)identifier {
    SunlightPadButton *button = [[SunlightPadButton alloc] initWithTitle:title label:label];
    button.accessibilityIdentifier = [@"sunlight.controlPad." stringByAppendingString:identifier];
    __weak typeof(self) weakSelf = self;
    button.changed = ^(BOOL down) {
        SunlightControlPadView *owner = weakSelf;
        if (owner.buttonChangedHandler) owner.buttonChangedHandler(flag, down);
    };
    [self addSubview:button];
    return button;
}
- (void)buildControls {
    self.multipleTouchEnabled = YES;
    self.backgroundColor = UIColor.clearColor;
    self.accessibilityIdentifier = @"sunlight.controlPad";
    SunlightPadButton *leftShoulder = [self button:@"L1" label:NSLocalizedString(@"Left shoulder", @"Gamepad button") flag:LB_FLAG identifier:@"leftShoulder"];
    SunlightPadButton *rightShoulder = [self button:@"R1" label:NSLocalizedString(@"Right shoulder", @"Gamepad button") flag:RB_FLAG identifier:@"rightShoulder"];
    SunlightPadButton *leftTrigger = [self button:@"L2" label:NSLocalizedString(@"Left trigger", @"Gamepad button") flag:0 identifier:@"leftTrigger"];
    SunlightPadButton *rightTrigger = [self button:@"R2" label:NSLocalizedString(@"Right trigger", @"Gamepad button") flag:0 identifier:@"rightTrigger"];
    SunlightPadButton *back = [self button:NSLocalizedString(@"Back", @"Gamepad Back button") label:NSLocalizedString(@"Back", @"Gamepad Back button") flag:BACK_FLAG identifier:@"back"];
    SunlightPadButton *menu = [self button:NSLocalizedString(@"Menu", @"Gamepad Menu button") label:NSLocalizedString(@"Menu", @"Gamepad Menu button") flag:PLAY_FLAG identifier:@"menu"];
    __weak typeof(self) weakSelf = self;
    leftTrigger.changed = ^(BOOL down) {
        SunlightControlPadView *owner = weakSelf;
        if (owner.leftTriggerChangedHandler) owner.leftTriggerChangedHandler(down ? 1 : 0);
    };
    rightTrigger.changed = ^(BOOL down) {
        SunlightControlPadView *owner = weakSelf;
        if (owner.rightTriggerChangedHandler) owner.rightTriggerChangedHandler(down ? 1 : 0);
    };
    _topButtons = @[leftShoulder, leftTrigger, back, menu, rightTrigger, rightShoulder];
    _dpad = @[
        [self button:@"↑" label:NSLocalizedString(@"D-pad up", @"Gamepad button") flag:UP_FLAG identifier:@"up"],
        [self button:@"←" label:NSLocalizedString(@"D-pad left", @"Gamepad button") flag:LEFT_FLAG identifier:@"left"],
        [self button:@"→" label:NSLocalizedString(@"D-pad right", @"Gamepad button") flag:RIGHT_FLAG identifier:@"right"],
        [self button:@"↓" label:NSLocalizedString(@"D-pad down", @"Gamepad button") flag:DOWN_FLAG identifier:@"down"]
    ];
    _faceButtons = @[
        [self button:@"Y" label:@"Y" flag:Y_FLAG identifier:@"y"],
        [self button:@"X" label:@"X" flag:X_FLAG identifier:@"x"],
        [self button:@"B" label:@"B" flag:B_FLAG identifier:@"b"],
        [self button:@"A" label:@"A" flag:A_FLAG identifier:@"a"]
    ];
    _leftStick = [[SunlightPadStick alloc] initWithLabel:NSLocalizedString(@"Left stick", @"Gamepad control")];
    _leftStick.accessibilityIdentifier = @"sunlight.controlPad.leftStick";
    _leftStick.changed = ^(CGPoint position) {
        SunlightControlPadView *owner = weakSelf;
        if (owner.leftStickChangedHandler) owner.leftStickChangedHandler(position);
    };
    _rightStick = [[SunlightPadStick alloc] initWithLabel:NSLocalizedString(@"Right stick", @"Gamepad control")];
    _rightStick.accessibilityIdentifier = @"sunlight.controlPad.rightStick";
    _rightStick.changed = ^(CGPoint position) {
        SunlightControlPadView *owner = weakSelf;
        if (owner.rightStickChangedHandler) owner.rightStickChangedHandler(position);
    };
    [self addSubview:_leftStick];
    [self addSubview:_rightStick];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(releaseAllControls)
        name:UIApplicationWillResignActiveNotification object:nil];
}
+ (CGFloat)preferredHeightForWidth:(CGFloat)width { return width >= 560 ? 184 : 304; }
- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, [self.class preferredHeightForWidth:CGRectGetWidth(self.bounds)]);
}
- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(size.width, [self.class preferredHeightForWidth:size.width]);
}
- (void)layoutDiamond:(NSArray<SunlightPadButton *> *)buttons origin:(CGPoint)origin {
    const CGPoint offsets[] = {{44, 0}, {0, 44}, {88, 44}, {44, 88}};
    for (NSUInteger i = 0; i < buttons.count; i++) {
        buttons[i].frame = CGRectMake(origin.x + offsets[i].x, origin.y + offsets[i].y, 44, 44);
    }
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MIN(CGRectGetWidth(self.bounds), 860);
    CGFloat inset = (CGRectGetWidth(self.bounds) - width) / 2;
    CGFloat top = MAX(0, (CGRectGetHeight(self.bounds) - [self.class preferredHeightForWidth:width]) / 2);
    CGFloat headerGap = width >= 560 ? 12 : 4;
    CGFloat headerWidth = MIN(64, floor((width - headerGap * 5) / 6));
    CGFloat headerStart = inset + (width - headerWidth * 6 - headerGap * 5) / 2;
    for (NSUInteger i = 0; i < _topButtons.count; i++) {
        _topButtons[i].frame = CGRectMake(headerStart + i * (headerWidth + headerGap), top, headerWidth, 44);
    }
    if (width >= 560) {
        CGFloat gap = (width - 472) / 3;
        CGFloat y = top + 52;
        [self layoutDiamond:_dpad origin:CGPointMake(inset, y)];
        _leftStick.frame = CGRectMake(inset + 132 + gap, y + 14, 104, 104);
        _rightStick.frame = CGRectMake(inset + 236 + gap * 2, y + 14, 104, 104);
        [self layoutDiamond:_faceButtons origin:CGPointMake(inset + width - 132, y)];
    } else {
        _leftStick.frame = CGRectMake(inset + 14, top + 52, 104, 104);
        _rightStick.frame = CGRectMake(inset + width - 118, top + 52, 104, 104);
        [self layoutDiamond:_dpad origin:CGPointMake(inset + 4, top + 172)];
        [self layoutDiamond:_faceButtons origin:CGPointMake(inset + width - 136, top + 172)];
    }
}
- (void)releaseAllControls {
    if (_releasingControls) return;
    _releasingControls = YES;
    for (SunlightPadButton *button in _topButtons) [button releaseControl];
    for (SunlightPadButton *button in _dpad) [button releaseControl];
    for (SunlightPadButton *button in _faceButtons) [button releaseControl];
    [_leftStick releaseControl];
    [_rightStick releaseControl];
    _releasingControls = NO;
}
- (void)setHidden:(BOOL)hidden {
    if (hidden) [self releaseAllControls];
    [super setHidden:hidden];
}
- (void)setUserInteractionEnabled:(BOOL)enabled {
    if (!enabled) [self releaseAllControls];
    [super setUserInteractionEnabled:enabled];
}
- (void)willMoveToSuperview:(UIView *)newSuperview {
    if (!newSuperview) [self releaseAllControls];
    [super willMoveToSuperview:newSuperview];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self releaseAllControls];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self releaseAllControls];
}
@end
