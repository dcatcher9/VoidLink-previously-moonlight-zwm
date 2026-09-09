#import "AppDelegate.h"
#import "SceneDelegate.h"
#import "VoidLink-Swift.h"
#import <errno.h>

static NSUInteger checks, attempts, services, roots, dataManagers;
static NSInteger injectedCode = ENOSPC;
static void Expect(BOOL value, NSString *message) {
    if (!value) { printf("STARTUP_STORAGE_TESTS_RESULT: FAIL %s\n", message.UTF8String); fflush(stdout); exit(1); }
    checks++;
}
@implementation CommandManager
+ (void)presetDefaultCommands { services++; }
@end
@implementation GenericUtils
+ (void)installSegmentedControlPreviousSelectionTracking { services++; }
@end
@implementation IAPManager
+ (instancetype)shared { services++; return [self new]; }
@end

@class FixtureSettings;
@interface DataManager : NSObject
- (FixtureSettings *)getSettings;
@end
@interface FixtureSettings : NSObject
@property NSNumber *externalDisplayMode;
@end
@implementation FixtureSettings
@end
@implementation DataManager
- (instancetype)init { if ((self = [super init])) dataManagers++; return self; }
- (FixtureSettings *)getSettings { FixtureSettings *settings = [FixtureSettings new]; settings.externalDisplayMode = @1; return settings; }
@end
@interface ExternalDisplayCoordinator : NSObject
@property BOOL enabled;
+ (instancetype)sharedCoordinator;
@end
@implementation ExternalDisplayCoordinator
+ (instancetype)sharedCoordinator { static id coordinator; if (!coordinator) coordinator = [self new]; return coordinator; }
@end
@implementation SceneDelegate
+ (BOOL)isExternalDisplaySessionRole:(UISceneSessionRole)role { return NO; }
// SUNLIGHT_ACTUAL_STORAGE_PREFERENCE_METHOD
@end

@interface InjectedStoreCoordinator : NSPersistentStoreCoordinator
@end
@implementation InjectedStoreCoordinator
- (NSPersistentStore *)addPersistentStoreWithType:(NSString *)storeType configuration:(NSString *)configuration URL:(NSURL *)storeURL options:(NSDictionary *)options error:(NSError **)error {
    attempts++;
    if (injectedCode) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:injectedCode userInfo:nil];
        return nil;
    }
    return [super addPersistentStoreWithType:storeType configuration:configuration URL:storeURL options:options error:error];
}
@end
static UIView *Find(UIView *view, NSString *identifier) {
    if ([view.accessibilityIdentifier isEqualToString:identifier]) return view;
    for (UIView *child in view.subviews) { UIView *found = Find(child, identifier); if (found) return found; }
    return nil;
}
@interface StartupTestDelegate : AppDelegate
@property NSManagedObjectModel *testModel;
@end
@implementation StartupTestDelegate
- (NSManagedObjectModel *)managedObjectModel {
    if (!_testModel) {
        NSEntityDescription *entity = [NSEntityDescription new]; entity.name = @"SavedHost"; entity.managedObjectClassName = @"NSManagedObject";
        NSAttributeDescription *name = [NSAttributeDescription new]; name.name = @"name"; name.attributeType = NSStringAttributeType;
        entity.properties = @[name]; _testModel = [NSManagedObjectModel new]; _testModel.entities = @[entity];
    }
    return _testModel;
}
- (NSPersistentStoreCoordinator *)newPersistentStoreCoordinator { return [[InjectedStoreCoordinator alloc] initWithManagedObjectModel:self.managedObjectModel]; }
- (UIViewController *)applicationRootViewController { roots++; UIViewController *root = [UIViewController new]; root.view.accessibilityIdentifier = @"fixture.ready"; return root; }
- (NSURL *)getStoreURL { return [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"saved-hosts.sqlite"]; }
- (void)seedStore {
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.managedObjectModel];
    NSError *error;
    NSPersistentStore *store = [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:self.getStoreURL options:@{NSSQLitePragmasOption:@{@"journal_mode":@"DELETE"}} error:&error];
    Expect(store != nil, @"Seed the actual SQLite database");
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType]; context.persistentStoreCoordinator = coordinator;
    NSManagedObject *host = [NSEntityDescription insertNewObjectForEntityForName:@"SavedHost" inManagedObjectContext:context]; [host setValue:@"Saved PC survives" forKey:@"name"];
    Expect([context save:&error], @"Commit saved host");
    Expect([coordinator removePersistentStore:store error:&error], @"Close fixture seed store");
}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    [UIView setAnimationsEnabled:NO]; [self seedStore];
    NSString *path = self.getStoreURL.path;
    NSArray<NSString *> *paths = @[path, [path stringByAppendingString:@"-wal"], [path stringByAppendingString:@"-shm"]];
    // Sidecars are sentinels during injected failures (the failing coordinator
    // never opens SQLite). The fixture removes its own sentinels before success.
    for (NSString *sidecar in paths) if (![sidecar isEqualToString:path]) [@"sidecar-preserved" writeToFile:sidecar atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray<NSData *> *originals = [NSMutableArray array]; for (NSString *file in paths) [originals addObject:[NSData dataWithContentsOfFile:file]];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    [self installRootViewControllerInWindow:self.window];
    dispatch_async(dispatch_get_main_queue(), ^{
        Expect(attempts == 1 && roots == 0 && services == 0, @"Storage failure never instantiates normal UI or app services");
        Expect(self.managedObjectContext == nil && self.persistentStoreCoordinator == nil && attempts == 1, @"Failed store publishes no partial context and repeated getters do not retry");
        SceneDelegate *external = [SceneDelegate new];
        [external performSelector:@selector(refreshExternalDisplayPreference)];
        Expect(dataManagers == 0 && !ExternalDisplayCoordinator.sharedCoordinator.enabled, @"External scene cannot initialize DataManager while storage is unavailable");
        UIViewController *failure = self.window.rootViewController; [failure.view layoutIfNeeded];
        Expect([failure.view.accessibilityIdentifier isEqualToString:@"sunlight.storage.error"] && Find(failure.view, @"sunlight.storage.retry") != nil, @"Failure exposes a visible Retry screen");
        for (NSUInteger i = 0; i < paths.count; i++) Expect([[NSData dataWithContentsOfFile:paths[i]] isEqual:originals[i]], @"Failed opening preserves SQLite and sidecar bytes");
        injectedCode = EACCES;
        [(UIControl *)Find(failure.view, @"sunlight.storage.retry") sendActionsForControlEvents:UIControlEventTouchUpInside];
        Expect(attempts == 2 && roots == 0 && self.managedObjectContext == nil, @"Retry attempts once and permission failure stays recoverable");
        for (NSUInteger i = 0; i < paths.count; i++) Expect([[NSData dataWithContentsOfFile:paths[i]] isEqual:originals[i]], @"Repeated failure still preserves every database file");
        for (NSString *sidecar in paths) if (![sidecar isEqualToString:path]) [NSFileManager.defaultManager removeItemAtPath:sidecar error:nil];
        __block NSUInteger ready = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:SunlightPersistentStoreReadyNotification object:self queue:nil usingBlock:^(NSNotification *note) {
            ready++; Expect(self.managedObjectContext != nil, @"Ready notification follows a valid context");
            [external performSelector:@selector(refreshExternalDisplayPreference)];
        }];
        injectedCode = 0;
        UIControl *successfulRetry = (UIControl *)Find(self.window.rootViewController.view, @"sunlight.storage.retry");
        [successfulRetry sendActionsForControlEvents:UIControlEventTouchUpInside];
        [successfulRetry sendActionsForControlEvents:UIControlEventTouchUpInside];
        Expect(attempts == 3 && roots == 1 && services == 3 && ready == 1, @"Successful Retry opens UI and initializes services once");
        Expect(dataManagers == 1 && ExternalDisplayCoordinator.sharedCoordinator.enabled, @"Waiting external preference can recover after storage is ready");
        Expect([self.window.rootViewController.view.accessibilityIdentifier isEqualToString:@"fixture.ready"], @"Success replaces the error screen");
        [self.managedObjectContext performBlockAndWait:^{
            NSArray *hosts = [self.managedObjectContext executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"SavedHost"] error:nil];
            Expect(hosts.count == 1 && [[hosts.firstObject valueForKey:@"name"] isEqualToString:@"Saved PC survives"], @"Retry reads the original saved host instead of resetting it");
        }];
        Expect(self.persistentStoreCoordinator.persistentStores.count == 1 && attempts == 3, @"Repeated successful reads reuse one attached store");
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        printf("STARTUP_STORAGE_TESTS_RESULT: PASS %lu checks\n", (unsigned long)checks); fflush(stdout); exit(0);
    });
    return YES;
}
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(StartupTestDelegate.class)); } }
