#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Presentation surface shared by standalone content and PC streaming.
/// The owner attaches content on the main thread and controls its lifetime.
@interface ExternalDisplayViewController : UIViewController

/// Full-size, black-backed container for the active presentation view.
/// Accessing this property loads the controller's view if necessary.
@property (nonatomic, strong, readonly) UIView *contentHostView;

/// Shows the content container, or the independent Sunlight readiness screen.
/// This does not attach, detach, start, or stop the presentation source.
- (void)setPresentingContent:(BOOL)presentingContent;

@end

NS_ASSUME_NONNULL_END
