#import <UIKit/UIKit.h>
#import "SunlightSharedSettings.h"
#import "SunlightMachineControlsSettings.h"

NS_ASSUME_NONNULL_BEGIN

// A local editor. The owner persists only the submitted copies and handles the
// reconnect or dismissal; opening, changing, resetting, and Cancel never save.
@interface SunlightSharedSettingsViewController : UITableViewController
- (instancetype)initWithSettings:(SunlightSharedSettings *)settings
                  globalDefaults:(SunlightSharedSettings *)globalDefaults
                        hostName:(NSString *)hostName
                   glassesOutput:(BOOL)glassesOutput;
// Defaults to YES for an existing stream. App-list PC settings set NO to save
// for future connections; the owner still controls persistence and dismissal.
@property (nonatomic) BOOL reconnectRequired;
// PC editor only. These detached drafts add PC controls and Sound & statistics
// groups. Set both before presentation. A whole-PC reset copies both global defaults; app picture
// profiles remain owned by their separate per-app editor.
@property (nonatomic, copy, nullable) SunlightMachineControlsSettings *machineControls;
@property (nonatomic, copy, nullable) SunlightMachineControlsSettings *globalMachineControls;
@property (nonatomic, copy, nullable) NSString *savedProfileSummary;
// The single PC submission callback; app picture profiles are never returned.
@property (nonatomic, copy, nullable) void (^applyMachineSettings)(SunlightSharedSettings *settings,
                                                               BOOL useGlobalDefaults,
                                                               SunlightMachineControlsSettings *machineControls);
@property (nonatomic, copy, nullable) void (^closed)(void);
@end

NS_ASSUME_NONNULL_END
