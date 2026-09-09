#import "AppDelegate.h"
#import "DataManager.h"
#import "StreamConfiguration.h"
#import "ExternalDisplayCoordinator.h"
#import "SunlightNativeResolution.h"
#import "SunlightStreamQualityProfile.h"

// Networking is intentionally absent. This utility is referenced by TemporaryHost
// but is not used by the fixture's plain host name.
@implementation Utils
+ (NSString *)addressAndPortToAddressPortString:(NSString *)address port:(unsigned short)port { return address; }
@end

@interface OutputTestContext : NSManagedObjectContext
@property BOOL failSave;
@property NSUInteger synchronousOperations;
@end
@implementation OutputTestContext
- (void)performBlockAndWait:(void (^)(void))block {
    self.synchronousOperations++;
    [super performBlockAndWait:block];
}
- (BOOL)save:(NSError **)error {
    if (self.failSave) {
        if (error) *error = [NSError errorWithDomain:@"OutputTests" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Injected store failure"}];
        return NO;
    }
    return [super save:error];
}
@end

@interface OutputTestMode : UIScreenMode
@property CGSize testSize;
@end
@implementation OutputTestMode
- (CGSize)size { return self.testSize; }
@end
@interface OutputTestScreen : UIScreen
@property OutputTestMode *testMode;
@end
@implementation OutputTestScreen
- (UIScreenMode *)currentMode { return self.testMode; }
@end
@interface OutputTestCoordinator : ExternalDisplayCoordinator
@property BOOL connected;
@property BOOL compatible;
@property OutputTestScreen *testScreen;
@end
@implementation OutputTestCoordinator
- (BOOL)isAvailable { return self.enabled && self.connected; }
- (BOOL)calibrationOutputCompatible { return self.enabled && self.connected && self.compatible; }
- (UIScreen *)externalScreen { return self.isAvailable ? self.testScreen : nil; }
@end

static NSUInteger checks;
static void Expect(BOOL condition, NSString *message) {
    if (!condition) { printf("SETTINGS_PERSISTENCE_TESTS_RESULT: FAIL %s\n", message.UTF8String); fflush(stdout); exit(1); }
    checks++;
}
static void SaveResolution(int width, int height) {
    DataManager *data = [[DataManager alloc] init];
    Settings *settings = [data retrieveSettings];
    settings.width = @(width);
    settings.height = @(height);
    settings.resolutionSelected = @5; // This helper deliberately selects a fixed/custom tuple.
    [data saveData];
}

@interface AppDelegate ()
@property(readwrite, strong) NSManagedObjectContext *managedObjectContext;
@property(readwrite, strong) NSManagedObjectModel *managedObjectModel;
@property(readwrite, strong) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@end
@implementation AppDelegate
- (void)saveContext { [self.managedObjectContext performBlockAndWait:^{ [self.managedObjectContext save:nil]; }]; }
- (NSURL *)applicationDocumentsDirectory { return [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject; }
- (NSURL *)getStoreURL { return [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"output-tests.sqlite"]; }

- (NSInteger)persistedMode {
    NSManagedObjectContext *reader = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    reader.persistentStoreCoordinator = self.persistentStoreCoordinator;
    __block NSInteger mode;
    [reader performBlockAndWait:^{
        Settings *saved = [reader executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Settings"] error:nil].firstObject;
        mode = saved.externalDisplayMode.integerValue;
    }];
    return mode;
}

// Read through a separate store-connected context, not the DataManager child
// cache, so migration and no-op assertions describe committed settings.
- (NSDictionary *)persistedSettings {
    NSManagedObjectContext *reader = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    reader.persistentStoreCoordinator = self.persistentStoreCoordinator;
    __block NSDictionary *snapshot;
    [reader performBlockAndWait:^{
        NSArray *records = [reader executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Settings"] error:nil];
        Expect(records.count <= 1, @"Native migration does not duplicate the settings record");
        Settings *settings = records.firstObject;
        snapshot = settings ? [settings dictionaryWithValuesForKeys:settings.entity.attributesByName.allKeys] : @{};
    }];
    return snapshot;
}

- (void)writeStoreFields:(NSDictionary *)fields {
    [self.managedObjectContext performBlockAndWait:^{
        Settings *settings = [self.managedObjectContext executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Settings"] error:nil].firstObject;
        Expect(settings != nil, @"Seed an existing settings record");
        [settings setValuesForKeysWithDictionary:fields];
        NSError *error = nil;
        Expect([self.managedObjectContext save:&error], [NSString stringWithFormat:@"Save fixture fields: %@", error]);
    }];
}

- (void)testNativeDefaults {
    Expect(NSThread.isMainThread, @"Native screen resolution is inspected on main");
    CGSize physical = UIScreen.mainScreen.nativeBounds.size;
    CGSize native = SunlightNativeLandscapeSize();
    Expect(native.width == MAX(physical.width, physical.height) && native.height == MIN(physical.width, physical.height),
           @"Native uses the complete physical main-screen pixels in landscape order");
    Expect(native.width >= native.height && native.height > 0, @"Native is a valid landscape tuple");
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *globalMarker = @"sunlight.nativeResolutionDefaults.v1";
    NSString *profileMarker = @"sunlight.nativeResolutionProfiles.v1";
    Expect(![defaults boolForKey:globalMarker] && ![defaults boolForKey:profileMarker], @"Isolated fresh install has no native migration markers");
    Expect([self persistedSettings].count == 0, @"Fresh install has no settings record");
    DataManager *fresh = [DataManager new];
    TemporarySettings *effective = [fresh getSettings];
    Expect(![defaults boolForKey:globalMarker] && [self persistedSettings].count == 0,
           @"Fresh initialization defers saving the required identity without marking migration complete");
    Expect(effective.width.intValue == (int)native.width && effective.height.intValue == (int)native.height,
           @"The first fresh-install settings snapshot resolves native dimensions");
    // The app supplies its required client identity during normal startup.
    [fresh updateUniqueId:@"native-defaults-test"];
    (void)[DataManager new];
    NSDictionary *freshStored = [self persistedSettings];
    Expect([freshStored[@"width"] intValue] == (int)native.width && [freshStored[@"height"] intValue] == (int)native.height &&
           [freshStored[@"resolutionSelected"] intValue] == 4, @"Fresh startup commits native dimensions and native preset");
    Expect([defaults boolForKey:globalMarker] && [defaults boolForKey:profileMarker], @"Successful startup commits both one-time markers");

    // Simulate an existing installation with unrelated settings deliberately
    // unlike defaults, plus legacy and explicit app quality records.
    [self writeStoreFields:@{@"width": @2560, @"height": @1440, @"resolutionSelected": @3,
        @"framerate": @90, @"bitrate": @300000, @"preferredCodec": @0,
        @"externalDisplayMode": @1, @"localVolume": @0.375, @"redirectMic": @YES,
        @"statsOverlayEnabled": @YES, @"touchMode": @2}];
    NSDictionary *before = [self persistedSettings];
    NSDictionary *legacy = @{@"width": @2560, @"height": @1440, @"frameRate": @90,
                             @"bitRate": @500, @"futureMetadata": @"retain"};
    NSString *globalKey = @"sunlight.streamQuality.2d";
    NSString *pcKey = @"sunlight.streamQuality.host3d.pc.native-pc";
    NSString *encodedPC = [[@"native-pc" dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    NSString *(^appKey)(NSString *, NSString *) = ^NSString *(NSString *mode, NSString *app) {
        NSString *encodedApp = [[app dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
        return [NSString stringWithFormat:@"sunlight.streamQuality.%@.app.%@.%@", mode, encodedPC, encodedApp];
    };
    NSString *legacyAppKey = appKey(@"host3d", @"legacy-app");
    NSString *fixedAppKey = appKey(@"2d", @"fixed-app");
    NSString *rawAppKey = appKey(@"raw3d", @"raw-app");
    NSMutableDictionary *fixed = [legacy mutableCopy]; fixed[@"usesNativeResolution"] = @NO;
    NSDictionary *raw = @{@"width": @3840, @"height": @1080, @"frameRate": @60, @"bitRate": @42500};
    for (NSString *key in @[globalKey, pcKey, legacyAppKey]) [defaults setObject:legacy forKey:key];
    [defaults setObject:fixed forKey:fixedAppKey];
    [defaults setObject:raw forKey:rawAppKey];
    [defaults removeObjectForKey:globalMarker]; [defaults removeObjectForKey:profileMarker];

    OutputTestContext *store = (OutputTestContext *)self.managedObjectContext;
    store.failSave = YES;
    (void)[DataManager new];
    Expect([[self persistedSettings] isEqual:before], @"A failed native migration leaves every committed settings field intact");
    Expect(![defaults boolForKey:globalMarker] && ![defaults boolForKey:profileMarker], @"Failure leaves both migrations retryable");
    Expect([[defaults dictionaryForKey:legacyAppKey] isEqual:legacy], @"Profiles wait for successful Core Data migration");
    store.failSave = NO;
    (void)[DataManager new];
    NSMutableDictionary *expected = [before mutableCopy];
    expected[@"width"] = @((int)native.width); expected[@"height"] = @((int)native.height); expected[@"resolutionSelected"] = @4;
    Expect([[self persistedSettings] isEqual:expected], @"Migration changes only width, height and preset; preserves every other Core Data field");
    for (NSString *key in @[globalKey, pcKey, legacyAppKey]) {
        NSMutableDictionary *expectedProfile = [legacy mutableCopy];
        expectedProfile[@"width"] = @((int)native.width); expectedProfile[@"height"] = @((int)native.height);
        expectedProfile[@"usesNativeResolution"] = @YES;
        Expect([[defaults dictionaryForKey:key] isEqual:expectedProfile], @"DataManager migrates legacy global, PC and app profiles while preserving FPS, bitrate and metadata");
    }
    Expect([[defaults dictionaryForKey:fixedAppKey] isEqual:fixed], @"Explicit fixed app profile survives migration");
    Expect([[defaults dictionaryForKey:rawAppKey] isEqual:raw], @"Raw retains its complete glasses-sized canvas");

    // A stale stored tuple for the Native preset is resolved only in the
    // detached settings; merely opening and closing settings must not write it.
    [self writeStoreFields:@{@"width": @1280, @"height": @720, @"resolutionSelected": @4}];
    NSDictionary *nativeStaleStored = [self persistedSettings];
    NSDictionary *preferencesBefore = defaults.dictionaryRepresentation;
    DataManager *reader = [DataManager new];
    effective = [reader getSettings];
    Expect(effective.width.intValue == (int)native.width && effective.height.intValue == (int)native.height,
           @"Native preset resolves current screen instead of stale saved pixels");
    Expect(effective.framerate.intValue == 90 && effective.bitrate.intValue == 300000,
           @"Effective native resolution preserves unusual saved frame rate and bitrate");
    [reader saveData];
    Expect([[self persistedSettings] isEqual:nativeStaleStored] && [defaults.dictionaryRepresentation isEqual:preferencesBefore],
           @"A no-op settings read/save changes neither quality nor scoped preferences");

    [self writeStoreFields:@{@"width": @2560, @"height": @1440, @"resolutionSelected": @3, @"bitrate": @500}];
    SunlightStreamQualityProfile *chosen = [SunlightStreamQualityProfile new];
    chosen.width = 1920; chosen.height = 1080; chosen.frameRate = 30; chosen.bitRate = 250000;
    Expect([chosen saveForMode:SunlightStreamModeHost3D hostUUID:@"native-pc" appID:@"legacy-app" defaults:defaults],
           @"A later fixed app choice saves successfully");
    NSDictionary *chosenStore = [self persistedSettings];
    NSDictionary *chosenPreferences = defaults.dictionaryRepresentation;
    for (NSUInteger i = 0; i < 3; i++) {
        NSUInteger priorStoreOperations = store.synchronousOperations;
        DataManager *reopened = [DataManager new];
        Expect(store.synchronousOperations == priorStoreOperations,
               @"Completed migration does not synchronously enter the store on each DataManager construction");
        TemporarySettings *settings = [reopened getSettings];
        Expect(settings.width.intValue == 2560 && settings.height.intValue == 1440 && settings.bitrate.intValue == 500,
               @"Later fixed global preset and legacy 500 Kbps survive reopens");
        [reopened saveData];
    }
    SunlightStreamQualityProfile *loaded = [SunlightStreamQualityProfile profileForMode:SunlightStreamModeHost3D
        hostUUID:@"native-pc" appID:@"legacy-app" defaults:defaults fallback:chosen];
    Expect([loaded isEqualToProfile:chosen] && !loaded.usesNativeResolution, @"Later fixed app profile survives without re-migration");
    Expect([[self persistedSettings] isEqual:chosenStore] && [defaults.dictionaryRepresentation isEqual:chosenPreferences],
           @"Completed migration is idempotent across repeated DataManager instances");
    SaveResolution(1206, 2622);
    effective = [[DataManager new] getSettings];
    Expect(effective.width.intValue == 1206 && effective.height.intValue == 2622 && effective.resolutionSelected.intValue == 5,
           @"Explicit custom portrait tuple remains fixed instead of being rotated to native");

    for (NSNumber *mode in @[@(SunlightStreamModeRawFullSBS), @(SunlightStreamModeRawHalfSBS)]) {
        StreamConfiguration *configuration = [StreamConfiguration new];
        configuration.streamMode = mode.integerValue;
        configuration.appID = @"1"; configuration.appName = @"Desktop";
        configuration.logicalWidth = 3840; configuration.logicalHeight = 1080;
        NSString *error = [configuration prepareSunlightStreamWithHostSessionSupport:NO virtualDisplayCapable:NO virtualDisplayReady:NO];
        Expect(error == nil && configuration.streamMode == SunlightStreamModeRawFullSBS,
               @"Raw and legacy Half normalize to passthrough without host virtual-display support");
        Expect(configuration.width == 3840 && configuration.height == 1080 && configuration.expectedPackedWidth == 3840 &&
               configuration.expectedPackedHeight == 1080 && !configuration.requestVirtualDisplay,
               @"Raw requests exact glasses pixels without native replacement or width doubling");
    }
    printf("SETTINGS_PERSISTENCE_NATIVE_RESULT: PASS %lu cumulative checks; native %.0f x %.0f\n", (unsigned long)checks, native.width, native.height);
    fflush(stdout);
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSURL *modelURL = [NSBundle.mainBundle URLForResource:@"Limelight" withExtension:@"momd"];
    self.managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    self.persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.managedObjectModel];
    NSError *error = nil;
    [self.persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:[self getStoreURL] options:nil error:&error];
    Expect(error == nil, @"Create isolated Core Data store");
    OutputTestContext *context = [[OutputTestContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    context.persistentStoreCoordinator = self.persistentStoreCoordinator;
    self.managedObjectContext = context;
    [self testNativeDefaults];

    DataManager *writer = [[DataManager alloc] init];
    // Normal app startup creates the required client identity before setup.
    [writer updateUniqueId:@"isolated-output-test"];
    __block NSUInteger notifications = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SunlightExternalDisplayPreferenceChangedNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        Expect(NSThread.isMainThread, @"Preference notification runs on main");
        Expect([note.userInfo[@"externalDisplayMode"] isKindOfClass:NSNumber.class], @"Preference notification includes mode");
        notifications++;
    }];
    BOOL didSave = [writer updateExternalDisplayMode:2 error:&error];
    Expect(didSave, [NSString stringWithFormat:@"Save device output: %@", error]);
    Expect([self persistedMode] == 2, @"Output saved to store before return");
    NSUInteger before = notifications;
    Expect([writer updateExternalDisplayMode:2 error:&error] && notifications == before, @"Unchanged output does not notify");
    Expect(![writer updateExternalDisplayMode:4 error:&error] && notifications == before, @"Invalid mode rejected without notification");
    DataManager *staleSidebar = [[DataManager alloc] init];
    Settings *draft = [staleSidebar retrieveSettings];
    NSNumber *savedBitrate = draft.bitrate;
    draft.bitrate = @12345;
    Expect([writer updateExternalDisplayMode:1 error:&error], @"Update alongside stale sidebar draft");
    Expect([self persistedMode] == 1, @"New output persists while sidebar retained");
    Expect([[[[DataManager alloc] init] getSettings].bitrate isEqualToNumber:savedBitrate], @"Output update does not save another context's pending settings");
    context.failSave = YES;
    before = notifications;
    Expect(![writer updateExternalDisplayMode:2 error:&error] && error != nil, @"Store failure returned");
    Expect(notifications == before && [self persistedMode] == 1, @"Failed save neither announces nor changes persisted output");
    Expect([[[DataManager alloc] init] getSettings].externalDisplayMode.integerValue == 1, @"Failed save restores in-memory output");
    context.failSave = NO;
    [NSNotificationCenter.defaultCenter removeObserver:observer];

    OutputTestCoordinator *coordinator = [[OutputTestCoordinator alloc] init];
    coordinator.testScreen = [[OutputTestScreen alloc] init];
    coordinator.testScreen.testMode = [[OutputTestMode alloc] init];
    coordinator.testScreen.testMode.testSize = CGSizeMake(1920, 1080);
    // Mirror the app's routing observer without starting a stream.
    [NSNotificationCenter.defaultCenter addObserverForName:SunlightExternalDisplayPreferenceChangedNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        coordinator.enabled = [note.userInfo[@"externalDisplayMode"] integerValue] == 1;
    }];
    // Keep routing and Native-resolution isolation coverage independent of the
    // deleted setup screen. The production coordinator still consumes this preference.
    Expect([writer updateExternalDisplayMode:2 error:&error] && !coordinator.enabled,
           @"Device-only preference disables the observed display coordinator");
    Expect([writer updateExternalDisplayMode:1 error:&error] && coordinator.enabled,
           @"Glasses preference enables the observed display coordinator");
    coordinator.connected = YES;
    coordinator.compatible = YES;
    coordinator.testScreen.testMode.testSize = CGSizeMake(3840, 1080);
    [self writeStoreFields:@{@"width": @3840, @"height": @1080, @"resolutionSelected": @4}];
    CGSize native = SunlightNativeLandscapeSize();
    TemporarySettings *nativeWithGlasses = [[DataManager new] getSettings];
    Expect(nativeWithGlasses.width.intValue == (int)native.width && nativeWithGlasses.height.intValue == (int)native.height,
           @"A connected SBS glasses canvas cannot override the phone's Native preset");
    for (NSArray<NSNumber *> *dimensions in @[@[@2622, @1206], @[@2732, @2048], @[@1206, @2622], @[@1920, @1536]]) {
        int width = dimensions[0].intValue, height = dimensions[1].intValue;
        SaveResolution(width, height);
        StreamConfiguration *configuration = [StreamConfiguration new];
        configuration.streamMode = SunlightStreamModeHost3D;
        configuration.width = width; configuration.height = height;
        BOOL fallback = [configuration useCompatibleHost3DResolution];
        BOOL supported = [StreamConfiguration isSupportedHost3DWidth:width height:height];
        Expect(fallback == !supported && configuration.width == (supported ? width : 1920) &&
               configuration.height == (supported ? height : 1080), @"Host 3D keeps supported native geometry and bounds unsupported fallback");
        TemporarySettings *unchanged = [[DataManager new] getSettings];
        Expect(unchanged.width.intValue == width && unchanged.height.intValue == height,
               @"Effective Host 3D fallback never rewrites stored fixed resolution");
    }
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.window layoutIfNeeded];
        CGSize physical = UIScreen.mainScreen.nativeBounds.size;
        Expect(native.width == MAX(physical.width, physical.height) && native.height == MIN(physical.width, physical.height),
               @"Native resolution remains the full panel after UIKit establishes its safe area");
        UIEdgeInsets insets = self.window.safeAreaInsets;
        if (insets.top + insets.bottom + insets.left + insets.right > 0) {
            CGSize safePoints = UIEdgeInsetsInsetRect(self.window.bounds, insets).size;
            CGFloat safeLongPixels = MAX(safePoints.width, safePoints.height) * UIScreen.mainScreen.nativeScale;
            Expect(fabs(native.width - safeLongPixels) > 1, @"Native does not subtract safe-area bars or the camera cutout");
        }
        [self writeStoreFields:@{@"width": @1280, @"height": @720, @"resolutionSelected": @4}];
        __block BOOL backgroundCompleted = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            DataManager *backgroundManager = [DataManager new];
            TemporarySettings *backgroundSettings = [backgroundManager getSettings];
            dispatch_async(dispatch_get_main_queue(), ^{
                backgroundCompleted = YES;
                Expect(backgroundSettings.width.intValue == (int)native.width && backgroundSettings.height.intValue == (int)native.height,
                       @"Background DataManager construction resolves Native without a store/main deadlock");
                printf("SETTINGS_PERSISTENCE_TESTS_RESULT: PASS %lu checks\n", (unsigned long)checks); fflush(stdout); exit(0);
            });
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            Expect(backgroundCompleted, @"Background native settings operation completes within the bounded deadline");
        });
    });
    return YES;
}
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class)); } }
