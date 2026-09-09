#include <stdio.h>
#include <stdlib.h>
#import <CoreMedia/CoreMedia.h>

// Foundation-only boundaries for the actual SettingsViewController methods
// copied by the runner. These controls store state; they do not duplicate the
// production decision about Native, interpolation or the enabled scale control.
@interface UISwitch : NSObject
@property(getter=isOn) BOOL on;
@end
@implementation UISwitch @end

@interface UISegmentedControl : NSObject
@property NSInteger selectedSegmentIndex;
@end
@implementation UISegmentedControl @end

@interface UISlider : NSObject
@property float value;
@property BOOL enabled;
@property(copy) NSString *accessibilityHint;
@end
@implementation UISlider @end

@interface UILabel : NSObject
@property(copy) NSString *text;
@end
@implementation UILabel @end

@interface UIStackView : NSObject @end
@implementation UIStackView @end

@interface TemporarySettings : NSObject
@property NSNumber *width;
@property NSNumber *height;
@end
@implementation TemporarySettings @end

@interface InterpolationResolutionConfiguration : NSObject
@property CMVideoDimensions dimensions;
@end
@implementation InterpolationResolutionConfiguration @end

// The existing Swift FrameInterpolator is a controlled boundary. Record exact
// delegation to its public API and return a distinctive scaled/rounded result.
// This does not claim to retest that separate interpolation algorithm.
static unsigned interpolationConfigurationCalls, interpolationScaleCalls;
static CMVideoDimensions receivedPreset, receivedInterpolation;
static float receivedScale, receivedLevel;
@interface FrameInterpolator : NSObject
+ (InterpolationResolutionConfiguration *)resolutionConfigurationForDimensions:(CMVideoDimensions)dimensions level:(float)level;
+ (CMVideoDimensions)scaledStreamDimensionsWithPresetDimensions:(CMVideoDimensions)preset
                                      interpolationDimensions:(CMVideoDimensions)interpolation scale:(float)scale;
@end
@implementation FrameInterpolator
+ (InterpolationResolutionConfiguration *)resolutionConfigurationForDimensions:(CMVideoDimensions)dimensions level:(float)level {
    interpolationConfigurationCalls++;
    receivedPreset = dimensions; receivedLevel = level;
    InterpolationResolutionConfiguration *value = [InterpolationResolutionConfiguration new];
    value.dimensions = (CMVideoDimensions){1280, 720};
    return value;
}
+ (CMVideoDimensions)scaledStreamDimensionsWithPresetDimensions:(CMVideoDimensions)preset
                                      interpolationDimensions:(CMVideoDimensions)interpolation scale:(float)scale {
    interpolationScaleCalls++;
    receivedPreset = preset; receivedInterpolation = interpolation; receivedScale = scale;
    return (CMVideoDimensions){736, 416};
}
@end

enum { FramePacingModeInterpolation = 3, RESOLUTION_TABLE_CUSTOM_INDEX = 5 };
@interface SettingsViewController : NSObject {
@public
    CMVideoDimensions resolutionTable[6];
    TemporarySettings *tempSettings;
}
@property UISwitch *customResolutionSwitch;
@property UISegmentedControl *resolutionSelector;
@property UISegmentedControl *framePacingModeSelector;
@property UISlider *streamDimensionScaleSlider;
@property UISlider *interpolationLevelSlider;
@property UIStackView *streamDimensionScaleStack;
@property UILabel *scaleLabel;
- (CMVideoDimensions)getChosenPresetStreamDimensions;
- (CMVideoDimensions)getChosenStreamDimensions;
- (InterpolationResolutionConfiguration *)getCurrentInterpolationResolutionConfiguration;
- (void)streamDimensionScaleSliderMoved:(UISlider *)sender;
- (UILabel *)findDynamicLabelFromStack:(UIStackView *)stack;
@end
@implementation SettingsViewController
- (UILabel *)findDynamicLabelFromStack:(UIStackView *)stack { (void)stack; return self.scaleLabel; }
// SUNLIGHT_ACTUAL_NATIVE_RESOLUTION_METHODS
@end

static unsigned checks;
static void check(BOOL passed, const char *message) {
    checks++;
    if (!passed) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}

static void testNativeInterpolationControls(void) {
    SettingsViewController *settings = [SettingsViewController new];
    settings.customResolutionSwitch = [UISwitch new];
    settings.resolutionSelector = [UISegmentedControl new];
    settings.framePacingModeSelector = [UISegmentedControl new];
    settings.streamDimensionScaleSlider = [UISlider new];
    settings.interpolationLevelSlider = [UISlider new];
    settings.streamDimensionScaleStack = [UIStackView new];
    settings.scaleLabel = [UILabel new];
    settings->tempSettings = [TemporarySettings new];
    settings->tempSettings.width = @2560; settings->tempSettings.height = @1440;
    settings->resolutionTable[1] = (CMVideoDimensions){1920, 1080};
    settings->resolutionTable[4] = (CMVideoDimensions){2622, 1206};
    settings->resolutionTable[5] = (CMVideoDimensions){2000, 1000};
    settings.resolutionSelector.selectedSegmentIndex = 4;
    settings.framePacingModeSelector.selectedSegmentIndex = FramePacingModeInterpolation;
    settings.interpolationLevelSlider.value = 0.25f;
    const float scales[] = {0, 0.05f, 0.5f, 1};
    for (size_t i = 0; i < sizeof(scales) / sizeof(scales[0]); i++) {
        settings.streamDimensionScaleSlider.value = scales[i];
        CMVideoDimensions native = [settings getChosenStreamDimensions];
        check(native.width == 2622 && native.height == 1206,
              "Native keeps exact non-aligned device pixels at every interpolation scale");
        [settings streamDimensionScaleSliderMoved:settings.streamDimensionScaleSlider];
        check(interpolationConfigurationCalls == 0 && interpolationScaleCalls == 0,
              "Native bypasses interpolation dimension calculation and scale/rounding APIs");
        check(!settings.streamDimensionScaleSlider.enabled && settings.streamDimensionScaleSlider.value == scales[i],
              "Native disables the scale control without discarding its remembered value");
        check([settings.scaleLabel.text isEqualToString:@"Native · 2622 × 1206"] &&
              [settings.streamDimensionScaleSlider.accessibilityHint containsString:@"full device resolution"],
              "Native explains exact dimensions and why scaling is unavailable");
    }

    settings.streamDimensionScaleSlider.value = 0.05f;
    settings.resolutionSelector.selectedSegmentIndex = 1;
    [settings streamDimensionScaleSliderMoved:settings.streamDimensionScaleSlider];
    check(settings.streamDimensionScaleSlider.enabled && settings.streamDimensionScaleSlider.value == 0.05f &&
          settings.streamDimensionScaleSlider.accessibilityHint == nil,
          "Native to fixed immediately re-enables scaling and retains the previous low scale");
    check(interpolationConfigurationCalls == 1 && interpolationScaleCalls == 1 &&
          receivedPreset.width == 1920 && receivedPreset.height == 1080 &&
          receivedInterpolation.width == 1280 && receivedInterpolation.height == 720 &&
          receivedLevel == 0.25f && receivedScale == 0.05f,
          "fixed interpolation delegates its preset, level, configured dimensions and retained scale to existing APIs");
    check([settings.scaleLabel.text containsString:@"736 × 416"] && ![settings.scaleLabel.text containsString:@"Native"],
          "fixed label displays the result returned by the existing interpolation scaler");

    settings.resolutionSelector.selectedSegmentIndex = 4;
    [settings streamDimensionScaleSliderMoved:settings.streamDimensionScaleSlider];
    check(!settings.streamDimensionScaleSlider.enabled && interpolationScaleCalls == 1,
          "returning to Native restores exact-pixel behavior without another interpolation call");
    settings.customResolutionSwitch.on = YES;
    [settings streamDimensionScaleSliderMoved:settings.streamDimensionScaleSlider];
    check(settings.streamDimensionScaleSlider.enabled && settings.streamDimensionScaleSlider.value == 0.05f &&
          settings.streamDimensionScaleSlider.accessibilityHint == nil,
          "custom resolution overrides the selected Native segment and restores scaling");
    check(interpolationConfigurationCalls == 2 && interpolationScaleCalls == 2 &&
          receivedPreset.width == 2000 && receivedPreset.height == 1000 && receivedScale == 0.05f,
          "custom interpolation forwards the custom canvas through the unchanged scaling API");

    settings.framePacingModeSelector.selectedSegmentIndex = 2;
    CMVideoDimensions unscaledCustom = [settings getChosenStreamDimensions];
    check(unscaledCustom.width == 2000 && unscaledCustom.height == 1000 && interpolationScaleCalls == 2,
          "non-interpolated custom resolution remains unscaled");
    settings.customResolutionSwitch.on = NO;
    settings.resolutionSelector.selectedSegmentIndex = 1;
    CMVideoDimensions unscaledFixed = [settings getChosenStreamDimensions];
    check(unscaledFixed.width == 1920 && unscaledFixed.height == 1080 && interpolationScaleCalls == 2,
          "non-interpolated fixed resolution remains unscaled");
    settings.framePacingModeSelector.selectedSegmentIndex = FramePacingModeInterpolation;
    settings.streamDimensionScaleSlider = nil;
    CMVideoDimensions legacyScaled = [settings getChosenStreamDimensions];
    check(legacyScaled.width == 736 && legacyScaled.height == 416 && interpolationScaleCalls == 3 &&
          interpolationConfigurationCalls == 2 && receivedScale == 1 &&
          receivedPreset.width == 1920 && receivedInterpolation.width == 1920,
          "fixed interpolation without a scale control retains its existing scale-one fallback");
    settings.resolutionSelector.selectedSegmentIndex = 4;
    CMVideoDimensions nativeWithoutSlider = [settings getChosenStreamDimensions];
    check(nativeWithoutSlider.width == 2622 && nativeWithoutSlider.height == 1206 && interpolationScaleCalls == 3,
          "Native remains exact even before the scale control is constructed");
}

int main(void) {
    @autoreleasepool {
        NSArray *opening = @[@5, @1920, @1080, @3, @300000, @NO, @0.5, @1];
        NSDictionary *candidate = @{@"width": @2560, @"height": @1440, @"resolutionSelected": @2,
            @"framerate": @60, @"bitrate": @20000};
        NSDictionary *stored = @{@"width": @1920, @"height": @1080, @"resolutionSelected": @5,
            @"framerate": @90, @"bitrate": @300000, @"preferredCodec": @0, @"enableHdr": @YES,
            @"fullColorRange": @NO, @"audioConfig": @6, @"unlockDisplayOrientation": @NO};
        check(SLFlatGlobalQualityEdits(nil, opening, candidate).count == 0, "construction cannot save without a baseline");
        check(SLFlatGlobalQualityEdits(@[], opening, candidate).count == 0, "malformed baseline produces no quality writes");
        check(SLFlatGlobalQualityEdits(opening, opening, candidate).count == 0,
              "layout or normalized displayed values never change saved quality without an edited control");
        NSArray *fields = @[@"framerate", @"bitrate"];
        for (NSUInteger i = 0; i < fields.count; i++) {
            NSMutableArray *selection = [opening mutableCopy]; selection[3 + i] = @0;
            NSDictionary *edits = SLFlatGlobalQualityEdits(opening, selection, candidate);
            check(edits.count == 1 && [edits[fields[i]] isEqual:candidate[fields[i]]], "FPS and bitrate edits persist only their own field");
            NSMutableDictionary *saved = [stored mutableCopy]; [saved addEntriesFromDictionary:edits];
            for (NSString *key in stored) if (![key isEqualToString:fields[i]]) check([saved[key] isEqual:stored[key]],
                "one quality field preserves every other quality, codec, HDR, range, audio and orientation value");
        }
        NSMutableArray *resolution = [opening mutableCopy]; resolution[0] = @2;
        NSDictionary *resolutionEdits = SLFlatGlobalQualityEdits(opening, resolution, candidate);
        check(resolutionEdits.count == 3 && [resolutionEdits[@"width"] isEqual:@2560] &&
              [resolutionEdits[@"height"] isEqual:@1440] && [resolutionEdits[@"resolutionSelected"] isEqual:@2],
              "resolution edit writes the canvas and preset identifier only");
        check(!resolutionEdits[@"framerate"] && !resolutionEdits[@"bitrate"], "resolution edit preserves legacy FPS and bandwidth");
        NSMutableArray *custom = [opening mutableCopy]; custom[1] = @1800;
        check(SLFlatGlobalQualityEdits(opening, custom, candidate).count == 3, "editing custom width is a resolution edit");
        NSMutableArray *inactiveInterpolation = [opening mutableCopy]; inactiveInterpolation[6] = @0.7;
        check(SLFlatGlobalQualityEdits(opening, inactiveInterpolation, candidate).count == 0,
              "inactive interpolation normalization does not overwrite canvas");
        NSMutableArray *interpolation = [opening mutableCopy]; interpolation[5] = @YES;
        check(SLFlatGlobalQualityEdits(opening, interpolation, candidate).count == 3,
              "enabling interpolation deliberately updates the effective canvas");
        NSMutableArray *scaled = [interpolation mutableCopy]; scaled[7] = @0.5;
        check(SLFlatGlobalQualityEdits(interpolation, scaled, candidate).count == 3,
              "active interpolation scale edits update the effective canvas");
        check(SLFlatGlobalQualityEdits(scaled, opening, candidate).count == 3,
              "disabling interpolation restores the unscaled canvas");
        NSMutableDictionary *selected = [stored mutableCopy]; selected[@"enableHdr"] = @NO;
        NSDictionary *globalEdits = SLCategoryEditedValues(stored, selected);
        check(globalEdits.count == 1 && [globalEdits[@"enableHdr"] isEqual:@NO], "inline shared field edit has an isolated write set");
        check(SLCategoryEditedValues(selected, selected).count == 0, "saving the same page twice writes nothing twice");
        NSDictionary *controlOpening = @{@"controlMode": @0, @"touchEnabled": @YES};
        NSDictionary *controlSelected = @{@"controlMode": @2, @"touchEnabled": @YES};
        check([SLCategoryEditedValues(controlOpening, controlSelected) isEqualToDictionary:@{@"controlMode": @2}],
              "global gamepad selection preserves inherited touch availability");
        check(SLCategoryEditedValues(@{}, controlSelected).count == 0, "global controls cannot commit before baseline capture");
        NSMutableArray *lowBitrateOpening = [opening mutableCopy]; lowBitrateOpening[4] = @500;
        NSMutableArray *lowBitrateFPS = [lowBitrateOpening mutableCopy]; lowBitrateFPS[3] = @0;
        NSMutableDictionary *lowBitrateStored = [stored mutableCopy]; lowBitrateStored[@"bitrate"] = @500;
        [lowBitrateStored addEntriesFromDictionary:SLFlatGlobalQualityEdits(lowBitrateOpening, lowBitrateFPS, candidate)];
        check([lowBitrateStored[@"bitrate"] isEqual:@500] && [lowBitrateStored[@"width"] isEqual:stored[@"width"]] &&
              [lowBitrateStored[@"height"] isEqual:stored[@"height"]] && [lowBitrateStored[@"framerate"] isEqual:@60],
              "FPS-only edit preserves legacy 500Kbps and the untouched saved canvas");
        NSMutableArray *lowBitrateNewSelection = [lowBitrateOpening mutableCopy]; lowBitrateNewSelection[4] = @20000;
        NSDictionary *lowBitrateEdits = SLFlatGlobalQualityEdits(lowBitrateOpening, lowBitrateNewSelection, candidate);
        check([lowBitrateEdits isEqualToDictionary:@{@"bitrate": @20000}],
              "500Kbps bandwidth edit cannot rewrite native/custom dimensions or legacy 90fps");
        testNativeInterpolationControls();
        printf("FLAT_GLOBAL_SETTINGS_TESTS_RESULT: PASS (%u checks)\n", checks);
    }
    return 0;
}
