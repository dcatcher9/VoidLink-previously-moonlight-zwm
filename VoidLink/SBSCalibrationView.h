#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Offline, full side-by-side eye-assignment and geometry calibration pattern.
/// The caller owns selection and verification of the physical display mode.
@interface SBSCalibrationView : UIView

/// Swaps the logical eye patterns without changing their physical geometry.
/// Defaults to NO: LEFT occupies the left half and RIGHT the right half.
@property (nonatomic) BOOL eyesSwapped;

/// Physical canvas halves in view coordinates, independent of eyesSwapped.
@property (nonatomic, readonly) CGRect leftEyeRect;
@property (nonatomic, readonly) CGRect rightEyeRect;

/// Circular alignment targets, centered within each physical eye rectangle.
@property (nonatomic, readonly) CGRect leftEyeCircleRect;
@property (nonatomic, readonly) CGRect rightEyeCircleRect;

@end

NS_ASSUME_NONNULL_END
