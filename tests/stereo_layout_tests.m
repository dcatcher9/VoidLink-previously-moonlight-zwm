#import <Foundation/Foundation.h>
#import "SunlightStereoLayout.h"
#include <assert.h>

static void closeTo(CGFloat a, CGFloat b) { assert(fabs(a - b) < 0.0001); }
int main(void) {
    @autoreleasepool {
        SunlightEyeRegion eyes[2], swapped[2];
        SunlightEyeRegion raw;
        assert(SunlightRawPassthroughRegion(CGSizeMake(3840, 1080), CGSizeMake(3840, 1080), &raw));
        assert(CGRectEqualToRect(raw.destination, CGRectMake(0, 0, 3840, 1080)));
        assert(CGRectEqualToRect(raw.texture, CGRectMake(0, 0, 1, 1)));
        // Full-range UVs align output pixel centers to source pixel centers;
        // even a half-texel eye inset would resample this already packed image.
        for (int pixel = 0; pixel < 3840; pixel++) {
            CGFloat u = raw.texture.origin.x + ((pixel + 0.5) / raw.destination.size.width) * raw.texture.size.width;
            closeTo(u * 3840 - 0.5, pixel);
        }
        assert(!SunlightRawPassthroughRegion(CGSizeMake(1920, 1080), CGSizeMake(3840, 1080), &raw));
        assert(!SunlightRawPassthroughRegion(CGSizeMake(7680, 2160), CGSizeMake(3840, 1080), &raw));
        assert(!SunlightRawPassthroughRegion(CGSizeMake(3840, 1080), CGSizeMake(1920, 540), &raw));
        assert(!SunlightRawPassthroughRegion(CGSizeMake(3840, 1082), CGSizeMake(3840, 1080), &raw));
        assert(!SunlightRawPassthroughRegion(CGSizeMake(3840, 1080), CGSizeMake(3840.5, 1080), &raw));
        assert(!SunlightRawPassthroughRegion(CGSizeMake(3839, 1080), CGSizeMake(3839, 1080), &raw));
        assert(!SunlightRawPassthroughRegion(CGSizeMake(3840, 1079), CGSizeMake(3840, 1079), &raw));
        assert(!SunlightRawPassthroughRegion(CGSizeZero, CGSizeZero, &raw));
        assert(!SunlightRawPassthroughRegion(CGSizeMake(NAN, 1080), CGSizeMake(NAN, 1080), &raw));
        assert(!SunlightRawPassthroughRegion(CGSizeMake(INFINITY, 1080), CGSizeMake(INFINITY, 1080), &raw));
        assert(!SunlightRawPassthroughRegion(CGSizeMake(3840, 1080), CGSizeMake(3840, 1080), NULL));
        assert(SunlightMonoRegions(CGSizeMake(1920, 1080), CGSizeMake(3840, 1080), eyes));
        assert(CGRectEqualToRect(eyes[0].destination, CGRectMake(0, 0, 1920, 1080)));
        assert(CGRectEqualToRect(eyes[1].destination, CGRectMake(1920, 0, 1920, 1080)));
        assert(CGRectEqualToRect(eyes[0].texture, CGRectMake(0, 0, 1, 1)));
        assert(CGRectEqualToRect(eyes[1].texture, eyes[0].texture));
        assert(SunlightMonoRegions(CGSizeMake(1440, 1080), CGSizeMake(3840, 1080), eyes));
        assert(CGRectEqualToRect(eyes[0].destination, CGRectMake(240, 0, 1440, 1080)));
        assert(CGRectEqualToRect(eyes[1].destination, CGRectMake(2160, 0, 1440, 1080)));
        assert(!SunlightMonoRegions(CGSizeMake(NAN, 1080), CGSizeMake(3840, 1080), eyes));
        assert(SunlightStereoRegions(CGSizeMake(3840, 1080), CGSizeMake(3840, 1080), false, eyes));
        assert(CGRectEqualToRect(eyes[0].destination, CGRectMake(0, 0, 1920, 1080)));
        assert(CGRectEqualToRect(eyes[1].destination, CGRectMake(1920, 0, 1920, 1080)));
        assert(CGRectGetMaxX(eyes[0].texture) < 0.5 && CGRectGetMinX(eyes[1].texture) > 0.5);
        // Host 3D preserves narrow eye source proportions when fitting.
        assert(SunlightStereoRegions(CGSizeMake(1920, 1080), CGSizeMake(3840, 1080), false, eyes));
        assert(CGRectEqualToRect(eyes[0].destination, CGRectMake(480, 0, 960, 1080)));
        assert(CGRectEqualToRect(eyes[1].destination, CGRectMake(2400, 0, 960, 1080)));
        // A 4:3 picture is centered within each eye, including its own side bars.
        assert(SunlightStereoRegions(CGSizeMake(2880, 1080), CGSizeMake(3840, 1080), false, eyes));
        assert(CGRectEqualToRect(eyes[0].destination, CGRectMake(240, 0, 1440, 1080)));
        assert(CGRectEqualToRect(eyes[1].destination, CGRectMake(2160, 0, 1440, 1080)));
        assert(SunlightStereoRegions(CGSizeMake(2880, 1080), CGSizeMake(3840, 1080), true, swapped));
        for (int i=0; i<2; i++) {
            assert(CGRectEqualToRect(eyes[i].destination, swapped[i].destination));
            assert(CGRectEqualToRect(eyes[1-i].texture, swapped[i].texture));
        }
        // Very wide eye images letterbox vertically in BOTH eye canvases.
        assert(SunlightStereoRegions(CGSizeMake(7680, 1080), CGSizeMake(3840, 1080), false, eyes));
        closeTo(eyes[0].destination.origin.y, 270);
        closeTo(eyes[1].destination.origin.y, 270);
        closeTo(CGRectGetMidX(eyes[0].destination), 960);
        closeTo(CGRectGetMidX(eyes[1].destination), 2880);
        assert(!SunlightStereoRegions(CGSizeZero, CGSizeMake(3840,1080), false, eyes));
        assert(!SunlightStereoRegions(CGSizeMake(3840,1080), CGSizeZero, false, eyes));
        assert(!SunlightStereoRegions(CGSizeMake(NAN,1080), CGSizeMake(3840,1080), false, eyes));
        puts("Stereo layout: exact Raw passthrough/no resampling/mismatch refusal, mono duplication, Host 3D eye fit, eye swap and seam isolation passed");
    }
    return 0;
}
