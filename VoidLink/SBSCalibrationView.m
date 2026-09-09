#import "SBSCalibrationView.h"

static CGRect SBSCalibrationCircleRect(CGRect eyeRect) {
    CGFloat diameter = MIN(CGRectGetWidth(eyeRect), CGRectGetHeight(eyeRect)) * 0.40;
    return CGRectMake(CGRectGetMidX(eyeRect) - diameter / 2.0,
                      CGRectGetMidY(eyeRect) - diameter / 2.0,
                      diameter, diameter);
}

@implementation SBSCalibrationView

@synthesize eyesSwapped = _eyesSwapped;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self configureCalibrationView];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self configureCalibrationView];
    }
    return self;
}

- (void)configureCalibrationView {
    self.backgroundColor = UIColor.blackColor;
    self.opaque = YES;
    self.contentMode = UIViewContentModeRedraw;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitImage;
    self.accessibilityLabel = NSLocalizedString(@"Sunlight side-by-side calibration", @"Stereo display calibration accessibility label");
    [self updateAccessibilityValue];
}

- (CGRect)leftEyeRect {
    CGRect bounds = self.bounds;
    return CGRectMake(CGRectGetMinX(bounds), CGRectGetMinY(bounds),
                      CGRectGetWidth(bounds) / 2.0, CGRectGetHeight(bounds));
}

- (CGRect)rightEyeRect {
    CGRect bounds = self.bounds;
    return CGRectMake(CGRectGetMidX(bounds), CGRectGetMinY(bounds),
                      CGRectGetWidth(bounds) / 2.0, CGRectGetHeight(bounds));
}

- (CGRect)leftEyeCircleRect {
    return SBSCalibrationCircleRect(self.leftEyeRect);
}

- (CGRect)rightEyeCircleRect {
    return SBSCalibrationCircleRect(self.rightEyeRect);
}

- (void)setEyesSwapped:(BOOL)eyesSwapped {
    if (_eyesSwapped == eyesSwapped) {
        return;
    }
    _eyesSwapped = eyesSwapped;
    [self updateAccessibilityValue];
    [self setNeedsDisplay];
}

- (void)updateAccessibilityValue {
    self.accessibilityValue = _eyesSwapped
        ? NSLocalizedString(@"Eyes swapped. RIGHT is on the left half; LEFT is on the right half.", @"Swapped stereo calibration accessibility value")
        : NSLocalizedString(@"LEFT is on the left half; RIGHT is on the right half.", @"Standard stereo calibration accessibility value");
}

- (void)drawRect:(CGRect)rect {
    [UIColor.blackColor setFill];
    UIRectFill(self.bounds);
    [self drawEyeInRect:self.leftEyeRect logicalLeft:!_eyesSwapped];
    [self drawEyeInRect:self.rightEyeRect logicalLeft:_eyesSwapped];
}

- (void)drawEyeInRect:(CGRect)eyeRect logicalLeft:(BOOL)logicalLeft {
    CGFloat shortSide = MIN(CGRectGetWidth(eyeRect), CGRectGetHeight(eyeRect));
    if (shortSide <= 0.0) {
        return;
    }

    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    CGContextClipToRect(context, eyeRect);

    UIColor *accent = logicalLeft
        ? [UIColor colorWithRed:0.28 green:0.65 blue:0.47 alpha:1.0]
        : [UIColor colorWithRed:0.24 green:0.57 blue:0.70 alpha:1.0];
    CGFloat pixel = 1.0 / MAX(self.contentScaleFactor, 1.0);
    CGFloat unit = shortSide / 1080.0;
    CGFloat inset = shortSide * 0.065;
    CGRect safeRect = CGRectInset(eyeRect, inset, inset);

    // Both eyes use identical view-space geometry. In particular, the center
    // target has zero relative disparity and the circle's width equals height.
    UIBezierPath *grid = [UIBezierPath bezierPath];
    grid.lineWidth = MAX(pixel, unit);
    for (NSUInteger index = 1; index < 4; index++) {
        CGFloat x = CGRectGetMinX(safeRect) + CGRectGetWidth(safeRect) * index / 4.0;
        CGFloat y = CGRectGetMinY(safeRect) + CGRectGetHeight(safeRect) * index / 4.0;
        [grid moveToPoint:CGPointMake(x, CGRectGetMinY(safeRect))];
        [grid addLineToPoint:CGPointMake(x, CGRectGetMaxY(safeRect))];
        [grid moveToPoint:CGPointMake(CGRectGetMinX(safeRect), y)];
        [grid addLineToPoint:CGPointMake(CGRectGetMaxX(safeRect), y)];
    }
    [[accent colorWithAlphaComponent:0.22] setStroke];
    [grid stroke];

    UIBezierPath *border = [UIBezierPath bezierPathWithRect:safeRect];
    border.lineWidth = MAX(pixel, 2.0 * unit);
    [[accent colorWithAlphaComponent:0.48] setStroke];
    [border stroke];

    // Inward corner markers make any clipping at the four edges apparent.
    CGFloat markerLength = shortSide * 0.045;
    UIBezierPath *markers = [UIBezierPath bezierPath];
    markers.lineWidth = MAX(pixel, 3.0 * unit);
    for (NSUInteger corner = 0; corner < 4; corner++) {
        BOOL right = (corner & 1) != 0;
        BOOL bottom = (corner & 2) != 0;
        CGFloat x = right ? CGRectGetMaxX(safeRect) : CGRectGetMinX(safeRect);
        CGFloat y = bottom ? CGRectGetMaxY(safeRect) : CGRectGetMinY(safeRect);
        [markers moveToPoint:CGPointMake(x + (right ? -markerLength : markerLength), y)];
        [markers addLineToPoint:CGPointMake(x, y)];
        [markers addLineToPoint:CGPointMake(x, y + (bottom ? -markerLength : markerLength))];
    }
    [accent setStroke];
    [markers stroke];

    CGPoint center = CGPointMake(CGRectGetMidX(eyeRect), CGRectGetMidY(eyeRect));
    UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:SBSCalibrationCircleRect(eyeRect)];
    circle.lineWidth = MAX(pixel, 3.0 * unit);
    [[accent colorWithAlphaComponent:0.80] setStroke];
    [circle stroke];

    CGFloat crossArm = shortSide * 0.025;
    UIBezierPath *cross = [UIBezierPath bezierPath];
    cross.lineWidth = MAX(pixel, 3.0 * unit);
    [cross moveToPoint:CGPointMake(center.x - crossArm, center.y)];
    [cross addLineToPoint:CGPointMake(center.x + crossArm, center.y)];
    [cross moveToPoint:CGPointMake(center.x, center.y - crossArm)];
    [cross addLineToPoint:CGPointMake(center.x, center.y + crossArm)];
    [accent setStroke];
    [cross stroke];

    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    NSDictionary *labelAttributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:72.0 * unit weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: accent,
        NSParagraphStyleAttributeName: paragraph
    };
    // Explicit English eye labels are the physical eye-check identifiers.
    NSString *eyeLabel = logicalLeft ? @"LEFT" : @"RIGHT";
    CGRect labelRect = CGRectMake(CGRectGetMinX(safeRect),
                                  CGRectGetMinY(safeRect) + shortSide * 0.06,
                                  CGRectGetWidth(safeRect), shortSide * 0.10);
    [eyeLabel drawInRect:labelRect withAttributes:labelAttributes];

    NSDictionary *footerAttributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:27.0 * unit weight:UIFontWeightMedium],
        NSForegroundColorAttributeName: [accent colorWithAlphaComponent:0.60],
        NSParagraphStyleAttributeName: paragraph
    };
    CGRect footerRect = CGRectMake(CGRectGetMinX(safeRect),
                                   CGRectGetMaxY(safeRect) - shortSide * 0.10,
                                   CGRectGetWidth(safeRect), shortSide * 0.05);
    [@"SUNLIGHT 3D" drawInRect:footerRect withAttributes:footerAttributes];

    CGContextRestoreGState(context);
}

@end
