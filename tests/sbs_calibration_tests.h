#import <UIKit/UIKit.h>

typedef void (^SunlightCalibrationCaseRunner)(NSString *name, void (^body)(void));
void SunlightRunSBSCalibrationTests(UIWindow *primaryWindow, SunlightCalibrationCaseRunner runCase);
