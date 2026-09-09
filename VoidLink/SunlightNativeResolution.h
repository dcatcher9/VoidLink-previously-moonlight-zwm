#pragma once

#import <UIKit/UIKit.h>
#include <math.h>

// Sunlight's control device is always landscape. Native describes its complete
// screen, never the safe area, a scaled UIKit canvas, or the glasses' scanout.
static inline CGSize SunlightNativeLandscapeSize(void) {
    CGSize pixels = UIScreen.mainScreen.nativeBounds.size;
    if (!isfinite(pixels.width) || !isfinite(pixels.height) ||
        pixels.width < 1 || pixels.height < 1 || pixels.width > 16384 || pixels.height > 16384) {
        return CGSizeZero;
    }
    return CGSizeMake(MAX(pixels.width, pixels.height), MIN(pixels.width, pixels.height));
}
