#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Moonlight 3D Android vectors, rendered at their original 24-point viewport.
// Names are the original drawable resource names. Images are cached templates.
@interface SunlightMoonlightIcons : NSObject
+ (nullable UIImage *)imageNamed:(NSString *)name;
@end

NS_ASSUME_NONNULL_END
