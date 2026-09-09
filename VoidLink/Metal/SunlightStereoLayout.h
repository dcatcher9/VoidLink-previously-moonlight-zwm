#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdbool.h>

// A decoded frame is shared by both eyes. These rectangles only change its
// presentation; they never allocate another decoder or consume another frame.
typedef struct {
    CGRect destination;
    CGRect texture;
} SunlightEyeRegion;

static inline CGRect SunlightFitVideo(CGSize source, CGRect destination) {
    if (source.width <= 0 || source.height <= 0 || CGRectIsEmpty(destination)) {
        return CGRectZero;
    }
    CGFloat scale = fmin(destination.size.width / source.width,
                         destination.size.height / source.height);
    CGSize size = CGSizeMake(source.width * scale, source.height * scale);
    return CGRectMake(CGRectGetMidX(destination) - size.width / 2,
                      CGRectGetMidY(destination) - size.height / 2,
                      size.width, size.height);
}

// On an SBS scanout, 2D is the complete mono picture repeated in both eyes.
// Keep transport and decode mono; only the draw rectangles are duplicated.
static inline bool SunlightMonoRegions(CGSize source, CGSize output,
                                       SunlightEyeRegion regions[2]) {
    if (!regions || !isfinite(source.width) || !isfinite(source.height) ||
        !isfinite(output.width) || !isfinite(output.height) ||
        source.width < 1 || source.height < 1 || output.width < 2 || output.height < 1) {
        return false;
    }
    for (int i = 0; i < 2; i++) {
        CGRect canvas = CGRectMake(i * output.width / 2, 0, output.width / 2, output.height);
        regions[i].destination = SunlightFitVideo(source, canvas);
        regions[i].texture = CGRectMake(0, 0, 1, 1);
    }
    return true;
}

// Raw contains the complete physical scanout already. Exact pixel dimensions
// are mandatory: do not fit, split, crop, or inset its texture coordinates.
static inline bool SunlightRawPassthroughRegion(CGSize packed, CGSize output,
                                                SunlightEyeRegion *region) {
    if (!region || !isfinite(packed.width) || !isfinite(packed.height) ||
        !isfinite(output.width) || !isfinite(output.height) ||
        packed.width < 2 || packed.height < 2 ||
        fmod(packed.width, 2) != 0 || fmod(packed.height, 2) != 0 ||
        !CGSizeEqualToSize(packed, output)) {
        return false;
    }
    region->destination = (CGRect){CGPointZero, output};
    region->texture = CGRectMake(0, 0, 1, 1);
    return true;
}

// Host 3D may encode a larger image than the glasses' output canvas.
// Fit each eye independently so letterboxing cannot move an eye across the
// physical split in the glasses' scanout canvas.
static inline bool SunlightStereoRegions(CGSize packed, CGSize output,
                                         bool swapEyes,
                                         SunlightEyeRegion regions[2]) {
    if (!regions || !isfinite(packed.width) || !isfinite(packed.height) ||
        !isfinite(output.width) || !isfinite(output.height) ||
        packed.width < 2 || packed.height < 1 || output.width < 2 || output.height < 1) {
        return false;
    }
    CGSize eye = CGSizeMake(packed.width * 0.5, packed.height);
    for (int i = 0; i < 2; i++) {
        CGRect canvas = CGRectMake(i * output.width / 2, 0, output.width / 2, output.height);
        regions[i].destination = SunlightFitVideo(eye, canvas);
        int sourceEye = swapEyes ? 1 - i : i;
        // Clamp sampling to the eye's texel centers to prevent the linear
        // sampler mixing the other eye into the seam when scaling up.
        CGFloat inset = 0.5 / packed.width;
        regions[i].texture = CGRectMake(sourceEye * 0.5 + inset, 0,
                                        0.5 - inset * 2, 1);
    }
    return true;
}
