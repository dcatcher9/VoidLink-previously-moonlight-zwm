#import "SunlightMoonlightIcons.h"
#import <math.h>

// Path data, stroke widths/caps/joins are copied without alteration from
// moonlight-android/app/src/main/res/drawable/<resource name>.xml.
// This adapter supports the SVG commands used by that fixed vector catalog.
// Android's 24×24 viewport maps directly to UIKit's top-left coordinate space.
static UIBezierPath *SLMoonlightPath(NSString *data) {
    NSScanner *scanner = [NSScanner scannerWithString:data];
    scanner.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@" ,\n\r\t"];
    scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSCharacterSet *commands = [NSCharacterSet characterSetWithCharactersInString:@"MmLlHhVvCcSsAaZz"];
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGPoint current = CGPointZero, start = CGPointZero, previousControl = CGPointZero;
    unichar command = 0, previous = 0;
    while (!scanner.isAtEnd) {
        NSString *commandString;
        if ([scanner scanCharactersFromSet:commands intoString:&commandString]) { command = [commandString characterAtIndex:0]; scanner.scanLocation -= commandString.length - 1; }
        BOOL relative = command >= 'a' && command <= 'z';
        unichar upper = relative ? command - 'a' + 'A' : command;
        if (upper == 'Z') { [path closePath]; current = start; previous = upper; command = 0; continue; }
        NSUInteger count = upper == 'H' || upper == 'V' ? 1 : upper == 'M' || upper == 'L' ? 2 : upper == 'C' ? 6 : upper == 'S' ? 4 : upper == 'A' ? 7 : 0;
        if (!count) return nil;
        double v[7] = {0}; for (NSUInteger index = 0; index < count; index++) if (![scanner scanDouble:&v[index]]) return nil;
        CGPoint origin = relative ? current : CGPointZero;
        if (upper == 'M' || upper == 'L') {
            current = CGPointMake(origin.x + v[0], origin.y + v[1]);
            if (upper == 'M') { [path moveToPoint:current]; start = current; command = relative ? 'l' : 'L'; }
            else [path addLineToPoint:current];
        } else if (upper == 'H') { current.x = origin.x + v[0]; [path addLineToPoint:current]; }
        else if (upper == 'V') { current.y = origin.y + v[0]; [path addLineToPoint:current]; }
        else if (upper == 'C' || upper == 'S') {
            CGPoint first = upper == 'C' ? CGPointMake(origin.x + v[0], origin.y + v[1]) :
                previous == 'C' || previous == 'S' ? CGPointMake(2 * current.x - previousControl.x, 2 * current.y - previousControl.y) : current;
            NSUInteger secondIndex = upper == 'C' ? 2 : 0, endIndex = upper == 'C' ? 4 : 2;
            previousControl = CGPointMake(origin.x + v[secondIndex], origin.y + v[secondIndex + 1]);
            current = CGPointMake(origin.x + v[endIndex], origin.y + v[endIndex + 1]);
            [path addCurveToPoint:current controlPoint1:first controlPoint2:previousControl];
        } else if (upper == 'A') {
            // Every source arc is circular and unrotated. Endpoint-to-center
            // conversion retains the SVG large-arc and sweep flags exactly.
            if (fabs(v[0] - v[1]) > 0.000001 || v[2] != 0) return nil;
            CGPoint end = CGPointMake(origin.x + v[5], origin.y + v[6]);
            double dx = (current.x - end.x) / 2, dy = (current.y - end.y) / 2;
            double distanceSquared = dx * dx + dy * dy;
            if (distanceSquared > 0) {
                double radius = MAX(fabs(v[0]), sqrt(distanceSquared));
                double factor = sqrt(MAX(0, (radius * radius - distanceSquared) / distanceSquared));
                if ((v[3] != 0) == (v[4] != 0)) factor = -factor;
                CGPoint center = CGPointMake((current.x + end.x) / 2 + factor * dy, (current.y + end.y) / 2 - factor * dx);
                [path addArcWithCenter:center radius:radius startAngle:atan2(current.y - center.y, current.x - center.x)
                    endAngle:atan2(end.y - center.y, end.x - center.x) clockwise:v[4] != 0];
            }
            current = end;
        }
        previous = upper;
    }
    return path;
}

@implementation SunlightMoonlightIcons
+ (UIImage *)imageNamed:(NSString *)name {
    static NSDictionary<NSString *, NSArray<NSArray *> *> *catalog;
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        catalog = @{
        @"ic_xr_mouse": @[@[@"M12,1.8a6.2,6.2 0 0,1 6.2,6.2v8a6.2,6.2 0 0,1 -12.4,0v-8a6.2,6.2 0 0,1 6.2,-6.2z", @2.0, @NO, @YES, @YES], @[@"M12,6v4", @2.0, @NO, @YES, @YES]],
        @"ic_xr_gamepad": @[@[@"M6.5,7.5h11a5.5,5.5 0 0,1 0,11h-11a5.5,5.5 0 0,1 0,-11z", @2.0, @NO, @YES, @YES], @[@"M9,10.8v4.4 M6.8,13h4.4", @1.8, @NO, @YES, @YES], @[@"M15.6,11.6a1.35,1.35 0 1,0 0.01,0z M18,15.2a1.35,1.35 0 1,0 0.01,0z", @0, @YES, @NO, @NO]],
        @"ic_xr_library": @[@[@"M4,4h6v6H4zM14,4h6v6h-6zM4,14h6v6H4zM14,14h6v6h-6z", @0, @YES, @NO, @NO]],
        @"ic_computer": @[@[@"M21,2L3,2c-1.1,0 -2,0.9 -2,2v12c0,1.1 0.9,2 2,2h7v2L8,20v2h8v-2h-2v-2h7c1.1,0 2,-0.9 2,-2L23,4c0,-1.1 -0.9,-2 -2,-2zM21,16L3,16L3,4h18v12z", @0, @YES, @NO, @NO]],
        @"ic_xr_mode_normal": @[@[@"M19,5H5C3.9,5 3,5.9 3,7v10c0,1.1 0.9,2 2,2h14c1.1,0 2,-0.9 2,-2V7C21,5.9 20.1,5 19,5zM19,17H5V7h14V17z", @0, @YES, @NO, @NO]],
        @"ic_xr_mode_host_sbs": @[@[@"M2,3.5h13v10h-13z", @2.2, @NO, @YES, @YES], @[@"M9,10.5h13v10h-13z", @2.2, @NO, @YES, @YES], @[@"M20.2,1l0.85,2.15 2.15,0.85 -2.15,0.85 -0.85,2.15 -0.85,-2.15 -2.15,-0.85 2.15,-0.85z", @0, @YES, @NO, @NO]],
        @"ic_xr_mode_client_sbs": @[@[@"M20,6H4c-1.1,0 -2,0.9 -2,2v7c0,1.1 0.9,2 2,2h3.5l1.5,1.5c0.55,0.55 1.45,0.55 2,0L16.5,17H20c1.1,0 2,-0.9 2,-2V8c0,-1.1 -0.9,-2 -2,-2zM8,13.5C6.62,13.5 5.5,12.38 5.5,11S6.62,8.5 8,8.5S10.5,9.62 10.5,11S9.38,13.5 8,13.5zM16,13.5c-1.38,0 -2.5,-1.12 -2.5,-2.5s1.12,-2.5 2.5,-2.5S18.5,9.62 18.5,11S17.38,13.5 16,13.5z", @0, @YES, @NO, @NO]],
        @"ic_xr_mode_host_sbs_raw": @[@[@"M2,5h20v14h-20z", @2.2, @NO, @YES, @YES], @[@"M12,5v14", @2.2, @NO, @YES, @YES]],
        @"ic_xr_resolution": @[@[@"M2.5,4.5h19v15h-19z", @2.0, @NO, @YES, @YES], @[@"M8,10h8v4h-8z", @1.7, @NO, @YES, @YES]],
        @"ic_xr_frame_rate": @[@[@"M10,5.5h11.5v13h-11.5z", @2.0, @NO, @YES, @YES], @[@"M2,9h5 M2,12h5 M2,15h5", @2.0, @NO, @YES, @YES]],
        @"ic_xr_bitrate": @[@[@"M5.3,18.7 A9.5,9.5 0 1 1 18.7,18.7", @2.4, @NO, @YES, @NO], @[@"M12,12 L16.7,7.3", @2.4, @NO, @YES, @NO], @[@"M10.2,12a1.8,1.8 0 1,0 3.6,0a1.8,1.8 0 1,0 -3.6,0z", @0, @YES, @NO, @NO]],
        @"ic_xr_disconnect": @[@[@"M13,3h-2v10h2V3zM17.83,5.17l-1.42,1.42C17.99,7.86 19,9.81 19,12c0,3.87 -3.13,7 -7,7s-7,-3.13 -7,-7c0,-2.19 1.01,-4.14 2.58,-5.42L6.17,5.17C4.23,6.82 3,9.26 3,12c0,4.97 4.03,9 9,9s9,-4.03 9,-9c0,-2.74 -1.23,-5.18 -3.17,-6.83z", @0, @YES, @NO, @NO]],
        @"ic_settings": @[@[@"M19.14,12.94c0.04,-0.3 0.06,-0.61 0.06,-0.94c0,-0.32 -0.02,-0.64 -0.07,-0.94l2.03,-1.58c0.18,-0.14 0.23,-0.41 0.12,-0.61l-1.92,-3.32c-0.12,-0.22 -0.37,-0.29 -0.59,-0.22l-2.39,0.96c-0.5,-0.38 -1.03,-0.7 -1.62,-0.94L14.4,2.81c-0.04,-0.24 -0.24,-0.41 -0.48,-0.41h-3.84c-0.24,0 -0.43,0.17 -0.47,0.41L9.25,5.35C8.66,5.59 8.12,5.92 7.63,6.29L5.24,5.33c-0.22,-0.08 -0.47,0 -0.59,0.22L2.74,8.87C2.62,9.08 2.66,9.34 2.86,9.48l2.03,1.58C4.84,11.36 4.8,11.69 4.8,12s0.02,0.64 0.07,0.94l-2.03,1.58c-0.18,0.14 -0.23,0.41 -0.12,0.61l1.92,3.32c0.12,0.22 0.37,0.29 0.59,0.22l2.39,-0.96c0.5,0.38 1.03,0.7 1.62,0.94l0.36,2.54c0.05,0.24 0.24,0.41 0.48,0.41h3.84c0.24,0 0.44,-0.17 0.47,-0.41l0.36,-2.54c0.59,-0.24 1.13,-0.56 1.62,-0.94l2.39,0.96c0.22,0.08 0.47,0 0.59,-0.22l1.92,-3.32c0.12,-0.22 0.07,-0.47 -0.12,-0.61L19.14,12.94zM12,15.6c-1.98,0 -3.6,-1.62 -3.6,-3.6s1.62,-3.6 3.6,-3.6s3.6,1.62 3.6,3.6S13.98,15.6 12,15.6z", @0, @YES, @NO, @NO]],
        @"ic_xr_codec": @[@[@"M6,6h12v12h-12z", @2.2, @NO, @YES, @YES], @[@"M9.5,9.5h5v5h-5z", @0, @YES, @NO, @NO], @[@"M10,2v4 M14,2v4 M10,18v4 M14,18v4 M2,10h4 M2,14h4 M18,10h4 M18,14h4", @2.2, @NO, @YES, @YES]],
        @"ic_xr_hdr": @[@[@"M12,8.2a3.8,3.8 0 1,0 0.01,0z", @0, @YES, @NO, @NO], @[@"M12,1.5v3 M12,19.5v3 M1.5,12h3 M19.5,12h3 M4.4,4.4l2.1,2.1 M17.5,17.5l2.1,2.1 M19.6,4.4l-2.1,2.1 M6.5,17.5l-2.1,2.1", @2.0, @NO, @YES, @YES]],
        @"ic_xr_video_range": @[@[@"M12,2.5a9.5,9.5 0 1,0 0.01,0z", @2.0, @NO, @YES, @YES], @[@"M12,2.5a9.5,9.5 0 0,1 0,19z", @0, @YES, @NO, @NO]],
        @"ic_xr_frame_pacing": @[@[@"M3.5,6h3.6v12h-3.6z M10.2,6h3.6v12h-3.6z M16.9,6h3.6v12h-3.6z", @0, @YES, @NO, @NO]],
        @"ic_xr_audio": @[@[@"M3.5,9h4l5.5,-5.5v17L7.5,15h-4z", @0, @YES, @NO, @NO], @[@"M17,9.2a4.2,4.2 0 0,1 0,5.6", @2.0, @NO, @YES, @YES]],
        @"ic_xr_audio_host": @[@[@"M2,4.5h20v12h-20z", @2.2, @NO, @YES, @YES], @[@"M8.5,21h7", @2.2, @NO, @YES, @YES], @[@"M8,9h1.8l2.4,-2.4v7.8l-2.4,-2.4h-1.8z", @0, @YES, @NO, @NO], @[@"M15,9.4a3,3 0 0,1 0,4.2", @1.8, @NO, @YES, @YES]],
        @"ic_xr_diagnostics": @[@[@"M1.5,12h4.2l3,-7.5 4.2,15 3,-7.5h6.6", @2.0, @NO, @YES, @YES]],
        };
    });
    UIImage *cached = [cache objectForKey:name]; if (cached) return cached;
    NSArray<NSArray *> *entries = catalog[name]; if (!entries) return nil;
    NSMutableArray<UIBezierPath *> *paths = [NSMutableArray arrayWithCapacity:entries.count];
    for (NSArray *entry in entries) {
        UIBezierPath *path = SLMoonlightPath(entry[0]); if (!path) return nil;
        path.lineWidth = [entry[1] doubleValue];
        path.lineCapStyle = [entry[3] boolValue] ? kCGLineCapRound : kCGLineCapButt;
        path.lineJoinStyle = [entry[4] boolValue] ? kCGLineJoinRound : kCGLineJoinMiter;
        [paths addObject:path];
    }
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24, 24)];
    UIImage *image = [[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.whiteColor set];
        for (NSUInteger index = 0; index < paths.count; index++) {
            if ([entries[index][2] boolValue]) [paths[index] fill];
            if ([entries[index][1] doubleValue] > 0) [paths[index] stroke];
        }
    }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [cache setObject:image forKey:name]; return image;
}
@end
