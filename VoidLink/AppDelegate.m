//
//  AppDelegate.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/17/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//
//  Modified by True砖家 since 2024.7.12
//  Copyright © 2024 True砖家 @ Bilibili. All rights reserved.
//

#import "AppDelegate.h"
#import "VoidLink-Swift.h"
#import "SceneDelegate.h"
#import "SunlightUITheme.h"

NSNotificationName const SunlightPersistentStoreReadyNotification = @"SunlightPersistentStoreReady";

@interface SunlightStorageErrorViewController : UIViewController
@property (nonatomic, copy) void (^retryHandler)(void);
@end

@implementation SunlightStorageErrorViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SunlightUITheme surfaceColor];
    self.view.accessibilityIdentifier = @"sunlight.storage.error";
    UILabel *title = [UILabel new];
    title.text = NSLocalizedString(@"Cannot open saved data", nil);
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    UILabel *detail = [UILabel new];
    detail.text = NSLocalizedString(@"Sunlight could not open its local database. Your saved PCs and settings have not been reset. Check available storage and try again.", nil);
    detail.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    for (UILabel *label in @[title, detail]) {
        label.textColor = [SunlightUITheme primaryTextColor]; label.numberOfLines = 0;
        label.adjustsFontForContentSizeCategory = YES;
    }
    UIButton *retry = [UIButton buttonWithType:UIButtonTypeSystem];
    [retry setTitle:NSLocalizedString(@"Retry", nil) forState:UIControlStateNormal];
    retry.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    retry.titleLabel.adjustsFontForContentSizeCategory = YES;
    retry.accessibilityIdentifier = @"sunlight.storage.retry";
    retry.tintColor = [SunlightUITheme accentColor];
    [retry.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [retry addTarget:self action:@selector(retry:) forControlEvents:UIControlEventTouchUpInside];
    UIScrollView *scroll = [UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[title, detail, retry]];
    content.axis = UILayoutConstraintAxisVertical; content.spacing = 20; content.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24],
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-24],
        [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
    ]];
}
- (void)retry:(UIButton *)sender {
    void (^retry)(void) = self.retryHandler;
    self.retryHandler = nil;
    sender.enabled = NO;
    if (retry) retry();
}
@end

@implementation AppDelegate {
    NSError *_persistentStoreLoadError;
    BOOL _applicationServicesStarted;
}

@synthesize managedObjectContext = _managedObjectContext;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;

#if TARGET_OS_TV
static NSString* DB_NAME = @"Moonlight_tvOS.bin";
#else
static NSString* DB_NAME = @"Limelight_iOS.sqlite";
#endif

#pragma mark - UISceneSession lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options API_AVAILABLE(ios(13.0)){
    NSString *name = [SceneDelegate isExternalDisplaySessionRole:connectingSceneSession.role]
        ? @"External Display Configuration" : @"Default Configuration";
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:name sessionRole:connectingSceneSession.role];
    configuration.delegateClass = SceneDelegate.class;
    return configuration;
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions API_AVAILABLE(ios(13.0)){
}


#if !TARGET_OS_TV

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // iOS 13 scenes own their windows. Older iOS uses the same storage gate.
    if (@available(iOS 13.0, *)) {
    } else {
        self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        [self installRootViewControllerInWindow:self.window];
    }

    return YES;
}


- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL succeeded))completionHandler {
    _pcUuidToLoad = (NSString*)[shortcutItem.userInfo objectForKey:@"UUID"];
    _shortcutCompletionHandler = completionHandler;
}
#endif

// Kept separate from storage opening so no app controller or service can
// construct a DataManager against a coordinator with no attached store.
- (UIViewController *)applicationRootViewController {
    NSString *name = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"iPad" : @"iPhone";
    return [[UIStoryboard storyboardWithName:name bundle:nil] instantiateInitialViewController];
}

- (void)installRootViewControllerInWindow:(UIWindow *)window {
    NSAssert(NSThread.isMainThread, @"Root presentation belongs to main");
    if (self.managedObjectContext) {
#if !TARGET_OS_TV
        if (!_applicationServicesStarted) {
            _applicationServicesStarted = YES;
            [CommandManager presetDefaultCommands];
            [GenericUtils installSegmentedControlPreviousSelectionTracking];
            [IAPManager shared];
        }
#endif
        window.rootViewController = [self applicationRootViewController];
        [window makeKeyAndVisible];
        [NSNotificationCenter.defaultCenter postNotificationName:SunlightPersistentStoreReadyNotification object:self];
        return;
    }
    SunlightStorageErrorViewController *failure = [SunlightStorageErrorViewController new];
    __weak typeof(self) weakSelf = self;
    __weak UIWindow *weakWindow = window;
    failure.retryHandler = ^{
        typeof(self) self = weakSelf;
        UIWindow *window = weakWindow;
        if (!self || !window) return;
        @synchronized (self) { self->_persistentStoreLoadError = nil; }
        [self installRootViewControllerInWindow:window];
    };
    window.rootViewController = failure;
    [window makeKeyAndVisible];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Saves changes in the application's managed object context before the application terminates.
    [self saveContext];
}

- (void)saveContext
{
    NSManagedObjectContext *managedObjectContext = [self managedObjectContext];
    if (managedObjectContext != nil) {
        [managedObjectContext performBlock:^{
            if (![managedObjectContext hasChanges]) {
                return;
            }
            NSError *error = nil;
            if (![managedObjectContext save:&error]) {
                Log(LOG_E, @"Critical database error: %@, %@", error, [error userInfo]);
            }
            
#if TARGET_OS_TV
            NSData* dbData = [NSData dataWithContentsOfURL:[[[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject] URLByAppendingPathComponent:DB_NAME]];
            [[NSUserDefaults standardUserDefaults] setObject:dbData forKey:DB_NAME];
#endif
        }];
    }
}

#pragma mark - Core Data stack

// Returns the managed object context for the application.
// If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
- (NSManagedObjectContext *)managedObjectContext
{
    @synchronized (self) {
        if (_managedObjectContext) return _managedObjectContext;
        NSPersistentStoreCoordinator *coordinator = self.persistentStoreCoordinator;
        if (!coordinator) return nil;
        _managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        _managedObjectContext.persistentStoreCoordinator = coordinator;
        return _managedObjectContext;
    }
}

// Returns the managed object model for the application.
// If the model doesn't already exist, it is created from the application's model.
- (NSManagedObjectModel *)managedObjectModel
{
    if (_managedObjectModel != nil) {
        return _managedObjectModel;
    }
    _managedObjectModel = [NSManagedObjectModel mergedModelFromBundles:nil];
    return _managedObjectModel;
}

// Returns the persistent store coordinator for the application.
// If the coordinator doesn't already exist, it is created and the application's store added to it.
- (NSPersistentStoreCoordinator *)newPersistentStoreCoordinator {
    return [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.managedObjectModel];
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    @synchronized (self) {
        if (_persistentStoreCoordinator) return _persistentStoreCoordinator;
        // A failed open is retried only by the visible Retry action. Never
        // publish an empty coordinator or recursively retry a storage failure.
        if (_persistentStoreLoadError) return nil;
        NSPersistentStoreCoordinator *candidate = [self newPersistentStoreCoordinator];
        NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption: @YES,
                                  NSInferMappingModelAutomaticallyOption: @YES};
#if TARGET_OS_TV
        NSString *storeType = NSBinaryStoreType;
#else
        NSString *storeType = NSSQLiteStoreType;
#endif
        [self preparePersistentStore];
        NSError *error = nil;
        if (![candidate addPersistentStoreWithType:storeType configuration:nil URL:self.getStoreURL options:options error:&error]) {
            _persistentStoreLoadError = error ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOpenError userInfo:nil];
            Log(LOG_E, @"Unable to open saved data (%@ %ld): %@", _persistentStoreLoadError.domain,
                (long)_persistentStoreLoadError.code, _persistentStoreLoadError.localizedDescription);
            return nil;
        }
        _persistentStoreCoordinator = candidate;
        return _persistentStoreCoordinator;
    }
}

#pragma mark - Application's Documents directory

// Returns the URL to the application's Documents directory.
- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

- (void) preparePersistentStore
{
#if TARGET_OS_TV
    // On tvOS, we may need to inflate the DB from NSUserDefaults
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDirectory = [paths objectAtIndex:0];
    NSString *dbPath = [cacheDirectory stringByAppendingPathComponent:DB_NAME];
    
    // Always prefer the on disk version
    if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        // If that is unavailable, inflate it from NSUserDefaults
        NSData* data = [[NSUserDefaults standardUserDefaults] dataForKey:DB_NAME];
        if (data != nil) {
            Log(LOG_I, @"Inflating database from NSUserDefaults");
            [data writeToFile:dbPath atomically:YES];
        }
        else {
            Log(LOG_I, @"No database on disk or in NSUserDefaults");
        }
    }
    else {
        Log(LOG_I, @"Using cached database");
    }
#endif
}

- (NSURL*) getStoreURL {
#if TARGET_OS_TV
    // We use the cache folder to store our database on tvOS
    return [[[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject] URLByAppendingPathComponent:DB_NAME];
#else
    return [[self applicationDocumentsDirectory] URLByAppendingPathComponent:DB_NAME];
#endif
}

@end
