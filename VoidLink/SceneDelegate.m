#import "SceneDelegate.h"
#import "DataManager.h"
#import "ExternalDisplayCoordinator.h"
#import "ExternalDisplayViewController.h"

API_AVAILABLE(ios(13.0))
@implementation SceneDelegate

+ (BOOL)isExternalDisplaySessionRole:(UISceneSessionRole)role {
    if (@available(iOS 16.0, *)) {
        if ([role isEqualToString:UIWindowSceneSessionRoleExternalDisplayNonInteractive]) {
            return YES;
        }
    } else {
        return [role isEqualToString:UIWindowSceneSessionRoleExternalDisplay];
    }
    // The legacy manifest role remains supported on iOS 13–15.
    return [role isEqualToString:@"UIWindowSceneSessionRoleExternalDisplay"];
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) {
        return;
    }
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    if ([session.role isEqualToString:UIWindowSceneSessionRoleApplication]) {
        self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
        [(AppDelegate *)UIApplication.sharedApplication.delegate installRootViewControllerInWindow:self.window];
        Log(LOG_I, @"SceneDelegate: Main app scene connected.");
    } else if ([SceneDelegate isExternalDisplaySessionRole:session.role]) {
        self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
        self.window.rootViewController = [[ExternalDisplayViewController alloc] init];
        [self refreshExternalDisplayPreference];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(externalDisplaySettingsClosed:)
                                                     name:@"SettingsViewClosedNotification"
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(externalDisplaySettingsClosed:)
                                                     name:SunlightExternalDisplayPreferenceChangedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(externalDisplaySettingsClosed:)
                                                     name:SunlightPersistentStoreReadyNotification
                                                   object:nil];
        [[ExternalDisplayCoordinator sharedCoordinator] registerWindow:self.window];
        [self logExternalDisplay:windowScene event:@"connected"];
    }
}

- (void)refreshExternalDisplayPreference {
    AppDelegate *app = (AppDelegate *)UIApplication.sharedApplication.delegate;
    if (!app.managedObjectContext) {
        [ExternalDisplayCoordinator sharedCoordinator].enabled = NO;
        return;
    }
    NSNumber *mode = [[[DataManager alloc] init] getSettings].externalDisplayMode;
    // Mode 1 is the existing fullscreen wired/AirPlay path. Preserve Stage Manager and Disabled.
    [ExternalDisplayCoordinator sharedCoordinator].enabled = mode == nil || mode.integerValue == 1;
}

- (void)externalDisplaySettingsClosed:(NSNotification *)notification {
    [self refreshExternalDisplayPreference];
}

- (void)logExternalDisplay:(UIWindowScene *)scene event:(NSString *)event {
    UIScreen *screen = scene.screen;
    NSMutableArray<NSString *> *modes = [NSMutableArray array];
    for (UIScreenMode *mode in screen.availableModes) {
        [modes addObject:NSStringFromCGSize(mode.size)];
    }
    Log(LOG_I, @"Sunlight external display %@: role=%@, points=%@, nativePixels=%@, currentMode=%@, scale=%.2f, nativeScale=%.2f, maxFPS=%ld, availableModes=%@",
        event, scene.session.role, NSStringFromCGRect(screen.bounds), NSStringFromCGRect(screen.nativeBounds),
        NSStringFromCGSize(screen.currentMode.size), screen.scale, screen.nativeScale,
        (long)screen.maximumFramesPerSecond, [modes componentsJoinedByString:@", "]);
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    [self logSceneLifecycle:scene event:@"active"];
    if ([SceneDelegate isExternalDisplaySessionRole:scene.session.role]) {
        if (self.window) {
            [self refreshExternalDisplayPreference];
            [[ExternalDisplayCoordinator sharedCoordinator] windowDidUpdate:self.window];
        }
        [self logExternalDisplay:(UIWindowScene *)scene event:@"active"];
    }
}

- (void)logSceneLifecycle:(UIScene *)scene event:(NSString *)event {
    // A connected external screen does not prove that our scene remains visible
    // when the phone switches apps. Record both states for hardware diagnosis.
    Log(LOG_I, @"Sunlight scene %@: role=%@, sceneState=%ld, appState=%ld",
        event, scene.session.role, (long)scene.activationState,
        (long)UIApplication.sharedApplication.applicationState);
}

- (void)sceneWillResignActive:(UIScene *)scene {
    [self logSceneLifecycle:scene event:@"resigning active"];
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    [self logSceneLifecycle:scene event:@"background"];
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    [self logSceneLifecycle:scene event:@"foreground"];
}

- (void)windowScene:(UIWindowScene *)windowScene didUpdateCoordinateSpace:(id<UICoordinateSpace>)previousCoordinateSpace interfaceOrientation:(UIInterfaceOrientation)previousInterfaceOrientation traitCollection:(UITraitCollection *)previousTraitCollection {
    if ([SceneDelegate isExternalDisplaySessionRole:windowScene.session.role]) {
        if (self.window) [[ExternalDisplayCoordinator sharedCoordinator] windowDidUpdate:self.window];
        [self logExternalDisplay:windowScene event:@"updated"];
    }
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    if ([SceneDelegate isExternalDisplaySessionRole:scene.session.role]) {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [[ExternalDisplayCoordinator sharedCoordinator] unregisterWindow:self.window];
        self.window = nil;
        Log(LOG_I, @"Sunlight external display disconnected.");
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (void)setExternalDisplayRenderView:(UIView *)renderView {
    [[ExternalDisplayCoordinator sharedCoordinator] setRenderView:renderView];
}

+ (void)clearExternalDisplayRenderView {
    [[ExternalDisplayCoordinator sharedCoordinator] clearRenderView];
}

+ (void)clearExternalDisplayRenderView:(UIView *)renderView {
    [[ExternalDisplayCoordinator sharedCoordinator] clearRenderView:renderView];
}

+ (BOOL)isExternalDisplayAvailable {
    return [ExternalDisplayCoordinator sharedCoordinator].isAvailable;
}

+ (BOOL)isExternalDisplayRenderView:(UIView *)renderView {
    return [[ExternalDisplayCoordinator sharedCoordinator] isPresentingView:renderView];
}

+ (UIScreen *)externalDisplayScreen {
    return [ExternalDisplayCoordinator sharedCoordinator].externalScreen;
}

@end
