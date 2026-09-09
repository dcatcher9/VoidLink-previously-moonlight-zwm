#import "ExternalDisplayViewController.h"

/// Drawn with UIKit so the alignment reference remains sharp at any display size.
@interface ExternalDisplayReadinessView : UIView
@end

@implementation ExternalDisplayReadinessView {
    UIView *_messagePanel;
    UILabel *_titleLabel;
    UILabel *_statusLabel;
    UILabel *_guidanceLabel;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.blackColor;
        self.opaque = YES;
        self.contentMode = UIViewContentModeRedraw;
        self.isAccessibilityElement = NO;

        _messagePanel = [[UIView alloc] initWithFrame:CGRectZero];
        _messagePanel.backgroundColor = UIColor.blackColor;
        [self addSubview:_messagePanel];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.text = @"Sunlight 3D";
        _titleLabel.textColor = [UIColor colorWithWhite:0.72 alpha:1.0];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.5;
        _titleLabel.accessibilityTraits |= UIAccessibilityTraitHeader;
        [_messagePanel addSubview:_titleLabel];

        _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _statusLabel.text = NSLocalizedString(@"Sunlight ready", @"Connected display readiness status");
        _statusLabel.textColor = [UIColor colorWithRed:0.40 green:0.63 blue:0.57 alpha:1.0];
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.adjustsFontSizeToFitWidth = YES;
        _statusLabel.minimumScaleFactor = 0.5;
        [_messagePanel addSubview:_statusLabel];

        _guidanceLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _guidanceLabel.text = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad
            ? NSLocalizedString(@"Your external display is connected.\nControl Sunlight from your iPad.", @"Connected display guidance on iPad")
            : NSLocalizedString(@"Your external display is connected.\nControl Sunlight from your iPhone.", @"Connected display guidance on iPhone");
        _guidanceLabel.textColor = [UIColor colorWithWhite:0.43 alpha:1.0];
        _guidanceLabel.textAlignment = NSTextAlignmentCenter;
        _guidanceLabel.numberOfLines = 2;
        _guidanceLabel.adjustsFontSizeToFitWidth = YES;
        _guidanceLabel.minimumScaleFactor = 0.5;
        [_messagePanel addSubview:_guidanceLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat scale = MIN(1.5, MIN(width / 640.0, height / 480.0));
    if (scale <= 0.0) {
        return;
    }

    CGFloat panelWidth = MIN(width * 0.80, 760.0 * scale);
    CGFloat panelHeight = 224.0 * scale;
    _messagePanel.frame = CGRectMake((width - panelWidth) / 2.0,
                                    (height - panelHeight) / 2.0,
                                    panelWidth, panelHeight);

    CGFloat textInset = 16.0 * scale;
    CGFloat textWidth = MAX(0.0, panelWidth - textInset * 2.0);
    _titleLabel.font = [UIFont systemFontOfSize:40.0 * scale weight:UIFontWeightMedium];
    _titleLabel.frame = CGRectMake(textInset, 28.0 * scale, textWidth, 52.0 * scale);
    _statusLabel.font = [UIFont systemFontOfSize:20.0 * scale weight:UIFontWeightMedium];
    _statusLabel.frame = CGRectMake(textInset, 91.0 * scale, textWidth, 28.0 * scale);
    _guidanceLabel.font = [UIFont systemFontOfSize:17.0 * scale weight:UIFontWeightRegular];
    _guidanceLabel.frame = CGRectMake(textInset, 139.0 * scale, textWidth, 53.0 * scale);
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];

    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat inset = MIN(width, height) * 0.06;
    CGRect borderRect = CGRectInset(self.bounds, inset, inset);
    if (CGRectIsEmpty(borderRect)) {
        return;
    }

    CGFloat lineWidth = 1.0 / MAX(self.contentScaleFactor, 1.0);
    UIBezierPath *grid = [UIBezierPath bezierPath];
    grid.lineWidth = lineWidth;
    for (NSUInteger index = 1; index < 4; index++) {
        CGFloat x = CGRectGetMinX(borderRect) + CGRectGetWidth(borderRect) * index / 4.0;
        CGFloat y = CGRectGetMinY(borderRect) + CGRectGetHeight(borderRect) * index / 4.0;
        [grid moveToPoint:CGPointMake(x, CGRectGetMinY(borderRect))];
        [grid addLineToPoint:CGPointMake(x, CGRectGetMaxY(borderRect))];
        [grid moveToPoint:CGPointMake(CGRectGetMinX(borderRect), y)];
        [grid addLineToPoint:CGPointMake(CGRectGetMaxX(borderRect), y)];
    }
    [[UIColor colorWithRed:0.065 green:0.090 blue:0.085 alpha:1.0] setStroke];
    [grid stroke];

    UIBezierPath *border = [UIBezierPath bezierPathWithRect:borderRect];
    border.lineWidth = lineWidth;
    [[UIColor colorWithRed:0.12 green:0.17 blue:0.16 alpha:1.0] setStroke];
    [border stroke];

    // Short, brighter corners make clipping and display orientation easy to see.
    CGFloat markerLength = MIN(width, height) * 0.035;
    UIBezierPath *corners = [UIBezierPath bezierPath];
    corners.lineWidth = MAX(lineWidth, 1.0);
    for (NSUInteger corner = 0; corner < 4; corner++) {
        BOOL right = (corner & 1) != 0;
        BOOL bottom = (corner & 2) != 0;
        CGFloat x = right ? CGRectGetMaxX(borderRect) : CGRectGetMinX(borderRect);
        CGFloat y = bottom ? CGRectGetMaxY(borderRect) : CGRectGetMinY(borderRect);
        [corners moveToPoint:CGPointMake(x + (right ? -markerLength : markerLength), y)];
        [corners addLineToPoint:CGPointMake(x, y)];
        [corners addLineToPoint:CGPointMake(x, y + (bottom ? -markerLength : markerLength))];
    }
    [[UIColor colorWithRed:0.22 green:0.33 blue:0.30 alpha:1.0] setStroke];
    [corners stroke];
}

@end

@implementation ExternalDisplayViewController {
    UIView *_contentHostView;
    ExternalDisplayReadinessView *_readinessView;
}

- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:CGRectZero];
    self.view.backgroundColor = UIColor.blackColor;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _readinessView = [[ExternalDisplayReadinessView alloc] initWithFrame:self.view.bounds];
    _readinessView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_readinessView];

    _contentHostView = [[UIView alloc] initWithFrame:self.view.bounds];
    _contentHostView.backgroundColor = UIColor.blackColor;
    _contentHostView.clipsToBounds = YES;
    _contentHostView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _contentHostView.hidden = YES;
    _contentHostView.accessibilityElementsHidden = YES;
    [self.view addSubview:_contentHostView];
}

- (UIView *)contentHostView {
    [self loadViewIfNeeded];
    return _contentHostView;
}

- (void)setPresentingContent:(BOOL)presentingContent {
    [self loadViewIfNeeded];
    _contentHostView.hidden = !presentingContent;
    _contentHostView.accessibilityElementsHidden = !presentingContent;
    _readinessView.hidden = presentingContent;
    _readinessView.accessibilityElementsHidden = presentingContent;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

@end
