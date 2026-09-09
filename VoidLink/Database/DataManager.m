//
//  DataManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/28/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//
//  Modified by True砖家 since 2024.6.1
//  Copyright © 2024 True砖家 @ Bilibili. All rights reserved.
//

#import "DataManager.h"
#import "TemporaryApp.h"
#import "TemporarySettings.h"
#import "SunlightNativeResolution.h"
#import "SunlightStreamQualityProfile.h"

NSNotificationName const SunlightExternalDisplayPreferenceChangedNotification = @"SunlightExternalDisplayPreferenceChanged";

@implementation DataManager {
    NSManagedObjectContext *_managedObjectContext;
    AppDelegate *_appDelegate;
}

- (id) init {
    self = [super init];
    
    // HACK: Avoid calling [UIApplication delegate] off the UI thread to keep
    // Main Thread Checker happy.
    if ([NSThread isMainThread]) {
        _appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    }
    else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            self->_appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
        });
    }
    
    _managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [_managedObjectContext setParentContext:[_appDelegate managedObjectContext]];

#if !TARGET_OS_TV
    [self adoptNativeResolutionDefaults];
#endif
    
    return self;
}

#if !TARGET_OS_TV
- (void)adoptNativeResolutionDefaults {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *migrationKey = @"sunlight.nativeResolutionDefaults.v1";
    // DataManager is constructed during discovery and settings reads too. Once
    // both migrations finish, avoid a second UIKit hop and private-store wait.
    if ([defaults boolForKey:migrationKey] &&
        ![SunlightStreamQualityProfile needsNativeResolutionMigrationInDefaults:defaults]) return;
    NSManagedObjectContext *context = _appDelegate.managedObjectContext;
    if (!context) return;
    // The store context is private. Read UIKit before entering it so it never
    // waits for main while a main-thread caller waits for the store operation.
    __block CGSize native;
    if (NSThread.isMainThread) native = SunlightNativeLandscapeSize();
    else dispatch_sync(dispatch_get_main_queue(), ^{ native = SunlightNativeLandscapeSize(); });
    if (native.width < 1 || native.height < 1) return;
    [context performBlockAndWait:^{
        if (![defaults boolForKey:migrationKey]) {
            NSError *error = nil;
            NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Settings"];
            request.fetchLimit = 1;
            NSArray *records = [context executeFetchRequest:request error:&error];
            if (!records) return;
            // Fresh settings are initialized natively in retrieveSettings and
            // saved by normal identity setup, which supplies required uniqueId.
            // Do not create an incomplete persistent row just for migration.
            if (records.count == 0) return;
            Settings *settings = records.firstObject;
            NSNumber *previousWidth = settings.width, *previousHeight = settings.height;
            NSNumber *previousSelection = settings.resolutionSelected;
            settings.width = @((int)native.width);
            settings.height = @((int)native.height);
            settings.resolutionSelected = @4; // Native, resolved again for each device.
            if (![context save:&error]) {
                settings.width = previousWidth; settings.height = previousHeight;
                settings.resolutionSelected = previousSelection;
                Log(LOG_E, @"Unable to save native resolution defaults: %@", error);
                return;
            }
            [defaults setBool:YES forKey:migrationKey];
        }
        [SunlightStreamQualityProfile migrateLegacyPresetResolutionsToNativeWidth:(int)native.width
            height:(int)native.height defaults:defaults];
    }];
}
#endif

- (void) updateUniqueId:(NSString*)uniqueId {
    [_managedObjectContext performBlockAndWait:^{
        [self retrieveSettings].uniqueId = uniqueId;
        [self saveData];
    }];
}

- (NSString*) getUniqueId {
    __block NSString *uid;
    
    [_managedObjectContext performBlockAndWait:^{
        uid = [self retrieveSettings].uniqueId;
    }];

    return uid;
}

- (BOOL)updateExternalDisplayMode:(NSInteger)mode error:(NSError **)error {
    if (mode < 0 || mode > 2) {
        if (error) *error = [NSError errorWithDomain:@"SunlightSettings" code:1
                                          userInfo:@{NSLocalizedDescriptionKey: @"Choose a valid output destination."}];
        return NO;
    }

    // Write on the store-owning context so this operation does not save a stale
    // sidebar child context or announce success before the disk save completes.
    NSManagedObjectContext *context = _appDelegate.managedObjectContext;
    if (!context) {
        if (error) *error = [NSError errorWithDomain:@"SunlightSettings" code:2
                                          userInfo:@{NSLocalizedDescriptionKey: @"Settings are not available yet."}];
        return NO;
    }
    __block NSError *saveError = nil;
    __block BOOL saved = NO;
    __block BOOL changed = NO;
    [context performBlockAndWait:^{
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Settings"];
        request.fetchLimit = 1;
        NSArray *records = [context executeFetchRequest:request error:&saveError];
        if (!records) return;
        BOOL inserted = records.count == 0;
        Settings *settings = inserted ? [NSEntityDescription insertNewObjectForEntityForName:@"Settings" inManagedObjectContext:context] : records.firstObject;
        NSNumber *previous = settings.externalDisplayMode;
        changed = ![previous isEqualToNumber:@(mode)];
        settings.externalDisplayMode = @(mode);
        saved = !context.hasChanges || [context save:&saveError];
        if (!saved) {
            // Restore this field without discarding other pending settings.
            if (inserted) [context deleteObject:settings];
            else settings.externalDisplayMode = previous;
        }
    }];
    if (!saved) {
        if (error) *error = saveError;
        return NO;
    }
    if (changed) {
        dispatch_block_t notify = ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SunlightExternalDisplayPreferenceChangedNotification
                                                                object:self userInfo:@{@"externalDisplayMode": @(mode)}];
        };
        if (NSThread.isMainThread) notify();
        else dispatch_async(dispatch_get_main_queue(), notify);
    }
    return YES;
}

- (void) saveSettings:(Settings*)settings
                     withBitrate:(NSInteger)bitrate
                       framerate:(NSInteger)framerate
                          height:(NSInteger)height
                           width:(NSInteger)width
                     audioConfig:(NSInteger)audioConfig
                onscreenControls:(NSInteger)onscreenControls
                        gyroMode:(NSInteger)gyroMode
          emulatedControllerType:(NSInteger)emulatedControllerType
           keyboardToggleFingers:(NSInteger)keyboardToggleFingers
            oscLayoutToolFingers:(NSInteger)oscLayoutToolFingers
       slideToSettingsScreenEdge:(NSInteger)slideToSettingsScreenEdge
         slideToSettingsDistance:(CGFloat)slideToSettingsDistance
      pointerVelocityModeDivider:(CGFloat)pointerVelocityModeDivider
      touchPointerVelocityFactor:(CGFloat)touchPointerVelocityFactor
      mousePointerVelocityFactor:(CGFloat)mousePointerVelocityFactor
                 gyroSensitivity:(CGFloat)gyroSensitivity
                     localVolume:(CGFloat)localVolume
                       micVolume:(CGFloat)micVolume
          touchMoveEventInterval:(NSInteger)touchMoveEventInterval
      reverseMouseWheelDirection:(BOOL)reverseMouseWheelDirection
        asyncNativeTouchPriority:(NSInteger)asyncNativeTouchPriority
       liftStreamViewForKeyboard:(BOOL)liftStreamViewForKeyboard
             showKeyboardToolbar:(BOOL)showKeyboardToolbar
                   optimizeGames:(BOOL)optimizeGames
                 multiController:(BOOL)multiController
            buttonVisualFeedback:(BOOL)buttonVisualFeedback
              touchPointTracking:(BOOL)touchPointTracking
                 swapABXYButtons:(BOOL)swapABXYButtons
                       audioOnPC:(BOOL)audioOnPC
                     redirectMic:(BOOL)redirectMic
                   useBuiltinMic:(BOOL)useBuiltinMic
                  preferredCodec:(uint32_t)preferredCodec
                    enableYUV444:(BOOL)enableYUV444
                       enablePIP:(BOOL)enablePIP
                       fullColorRange:(BOOL)fullColorRange
                       enableHdr:(BOOL)enableHdr
                  btMouseSupport:(BOOL)btMouseSupport
               // absoluteTouchMode:(BOOL)absoluteTouchMode
                       touchMode:(NSInteger)touchMode
               statsOverlayLevel:(NSInteger)statsOverlayLevel
             statsOverlayEnabled:(BOOL)statsOverlayEnabled
        unlockDisplayOrientation:(BOOL)unlockDisplayOrientation
              resolutionSelected:(NSInteger)resolutionSelected
             externalDisplayMode:(NSInteger)externalDisplayMode
           localMousePointerMode:(NSInteger)localMousePointerMode
                  frameQueueSize:(NSInteger)frameQueueSize
                    enableGraphs:(BOOL)enableGraphs
                    graphOpacity:(NSInteger)graphOpacity
                renderingBackend:(NSInteger)renderingBackend
                 framePacingMode:(NSInteger)framePacingMode
   interpolationMaximumDimension:(NSInteger)interpolationMaximumDimension
  interpolationMaximumPixelCount:(NSInteger)interpolationMaximumPixelCount
            streamDimensionScale:(CGFloat)streamDimensionScale
                  sendDummyEvent:(BOOL)sendDummyEvent
               rememberFoldState:(BOOL)rememberFoldState
              singleTapSensitivy:(CGFloat)singleTapSensitivy
                    hapticEngine:(NSInteger)hapticEngine
          edgeSlidingSensitivity:(CGFloat)edgeSlidingSensitivity
                     audioEngine:(NSInteger)audioEngine
                 delayLeftClick:(BOOL)delayLeftClick
                   duckOtherApps:(BOOL)duckOtherApps
                muteInBackground:(BOOL)muteInBackground
     relativeTouchSlideThreshold:(CGFloat)relativeTouchSlideThreshold
                     enablePinch:(BOOL)enablePinch
               scrollSensitivity:(CGFloat)scrollSensitivity
                pinchSensitivity:(CGFloat)pinchSensitivity
                ctrlDownForPinch:(BOOL)ctrlDownForPinch
                leftClickDelayMs:(CGFloat)leftClickDelayMs
              settingsMenuOffset:(CGFloat)settingsMenuOffset
             passthroughGestures:(BOOL)passthroughGestures
      enableControllerNavigation:(BOOL)enableControllerNavigation
  controllerMousePointerVelocity:(CGFloat)controllerMousePointerVelocity
             controllerMouseExpo:(CGFloat)controllerMouseExpo
        controllerGyroSwitchMode:(NSInteger)controllerGyroSwitchMode
             enableFrameTimebase:(BOOL)enableFrameTimebase
               asyncFrameDequeue:(BOOL)asyncFrameDequeue
        sdrPerformanceWorkaround:(BOOL)sdrPerformanceWorkaround
              softKeyboardHeight:(CGFloat)softKeyboardHeight
                   globeAsEscape:(BOOL)globeAsEscape
        streamingRadialMenuDelay:(CGFloat)streamingRadialMenuDelay
          backgroundSessionTimer:(NSInteger)backgroundSessionTimer{
    
    __block Settings* settingsToSave = settings;
    [_managedObjectContext performBlockAndWait:^{
        if(!settingsToSave) settingsToSave = [self retrieveSettings];
        settingsToSave.framerate = [NSNumber numberWithInteger:framerate];
        settingsToSave.bitrate = [NSNumber numberWithInteger:bitrate];
        settingsToSave.height = [NSNumber numberWithInteger:height];
        settingsToSave.width = [NSNumber numberWithInteger:width];
        settingsToSave.audioConfig = [NSNumber numberWithInteger:audioConfig];
        settingsToSave.onscreenControls = [NSNumber numberWithInteger:onscreenControls];
        settingsToSave.gyroMode = [NSNumber numberWithInteger:gyroMode];
        settingsToSave.emulatedControllerType = [NSNumber numberWithInteger:emulatedControllerType];
        settingsToSave.keyboardToggleFingers = [NSNumber numberWithInteger:(uint16_t)keyboardToggleFingers];
        settingsToSave.oscLayoutToolFingers = [NSNumber numberWithInteger:(uint16_t)oscLayoutToolFingers];
        settingsToSave.slideToSettingsScreenEdge = [NSNumber numberWithInteger:(uint32_t)slideToSettingsScreenEdge];
        settingsToSave.slideToSettingsDistance = [NSNumber numberWithFloat:slideToSettingsDistance];
        settingsToSave.pointerVelocityModeDivider = [NSNumber numberWithFloat:pointerVelocityModeDivider];
        settingsToSave.touchPointerVelocityFactor = [NSNumber numberWithFloat:touchPointerVelocityFactor];
        settingsToSave.mousePointerVelocityFactor = [NSNumber numberWithFloat:mousePointerVelocityFactor];
        settingsToSave.gyroSensitivity = [NSNumber numberWithFloat:gyroSensitivity];
        settingsToSave.localVolume = [NSNumber numberWithFloat:localVolume];
        settingsToSave.micVolume = [NSNumber numberWithFloat:micVolume];
        settingsToSave.touchMoveEventInterval = [NSNumber numberWithInteger:touchMoveEventInterval];
        settingsToSave.reverseMouseWheelDirection = reverseMouseWheelDirection;
        settingsToSave.asyncNativeTouchPriority = [NSNumber numberWithInteger:asyncNativeTouchPriority];
        settingsToSave.liftStreamViewForKeyboard = liftStreamViewForKeyboard;
        settingsToSave.showKeyboardToolbar = showKeyboardToolbar;
        settingsToSave.optimizeGames = optimizeGames;
        settingsToSave.multiController = multiController;
        settingsToSave.buttonVisualFeedback = buttonVisualFeedback;
        settingsToSave.touchPointTracking = touchPointTracking;
        settingsToSave.swapABXYButtons = swapABXYButtons;
        settingsToSave.playAudioOnPC = audioOnPC;
        settingsToSave.redirectMic = redirectMic;
        settingsToSave.useBuiltinMic = useBuiltinMic;
        settingsToSave.preferredCodec = preferredCodec;
        settingsToSave.enableYUV444 = enableYUV444;
        settingsToSave.sdrPerformanceWorkaround = sdrPerformanceWorkaround;
        settingsToSave.enablePIP = enablePIP;
        settingsToSave.fullColorRange = fullColorRange;
        settingsToSave.enableHdr = enableHdr;
        settingsToSave.btMouseSupport = btMouseSupport;
        // settingsToSave.absoluteTouchMode = absoluteTouchMode;
        settingsToSave.touchMode = [NSNumber numberWithInteger:(uint16_t)touchMode];
        settingsToSave.statsOverlayEnabled = statsOverlayEnabled;
        settingsToSave.statsOverlayLevel = [NSNumber numberWithInteger:(uint16_t)statsOverlayLevel];
        settingsToSave.unlockDisplayOrientation = unlockDisplayOrientation;
        settingsToSave.resolutionSelected = [NSNumber numberWithInteger:resolutionSelected];
        settingsToSave.externalDisplayMode = [NSNumber numberWithInteger:externalDisplayMode];
        settingsToSave.localMousePointerMode = [NSNumber numberWithInteger:localMousePointerMode];
        settingsToSave.backroundSessionTimer = [NSNumber numberWithInteger:backgroundSessionTimer];

        settingsToSave.frameQueueSize = [NSNumber numberWithInteger:frameQueueSize];
        settingsToSave.enableFrameTimebase = enableFrameTimebase;
        settingsToSave.asyncFrameDequeue = asyncFrameDequeue;
        settingsToSave.enableGraphs = enableGraphs;
        settingsToSave.graphOpacity = [NSNumber numberWithInteger:graphOpacity];
        settingsToSave.renderingBackend = [NSNumber numberWithInteger:renderingBackend];
        settingsToSave.framePacingMode = [NSNumber numberWithInteger:framePacingMode];
        settingsToSave.interpolationMaximumDimension = [NSNumber numberWithInteger:interpolationMaximumDimension];
        settingsToSave.interpolationMaximumPixelCount = [NSNumber numberWithInteger:interpolationMaximumPixelCount];
        settingsToSave.streamDimensionScale = [NSNumber numberWithDouble:streamDimensionScale];
        settingsToSave.sendDummyEvent = sendDummyEvent;
        settingsToSave.singleTapSensitivity = [NSNumber numberWithDouble:singleTapSensitivy];
        settingsToSave.hapticEngine = [NSNumber numberWithInteger:hapticEngine];
        settingsToSave.edgeSlidingSensitivity = [NSNumber numberWithFloat:edgeSlidingSensitivity];
        settingsToSave.audioEngine = [NSNumber numberWithInteger:audioEngine];
        settingsToSave.delayLeftClick = delayLeftClick;
        settingsToSave.duckOtherApps = duckOtherApps;
        settingsToSave.muteInBackground = muteInBackground;
        settingsToSave.relativeTouchSlideThreshold = [NSNumber numberWithFloat:relativeTouchSlideThreshold];
        settingsToSave.enablePinch = enablePinch;
        settingsToSave.scrollSensitivity = [NSNumber numberWithFloat:scrollSensitivity];
        settingsToSave.pinchSensitivity = [NSNumber numberWithFloat:pinchSensitivity];
        settingsToSave.ctrlDownForPinch = ctrlDownForPinch;
        settingsToSave.leftClickDelayMs = [NSNumber numberWithFloat:leftClickDelayMs];
        settingsToSave.settingsMenuOffset = [NSNumber numberWithFloat:settingsMenuOffset];
        settingsToSave.passthroughGestures = passthroughGestures;
        settingsToSave.enableControllerNavigation = enableControllerNavigation;
        settingsToSave.controllerMousePointerVelocity = [NSNumber numberWithFloat:controllerMousePointerVelocity];
        settingsToSave.controllerMouseExpo = [NSNumber numberWithFloat:controllerMouseExpo];
        settingsToSave.softKeyboardHeight = softKeyboardHeight;
        settingsToSave.globeAsEscape = globeAsEscape;
        settingsToSave.streamingRadialMenuDelay = @(streamingRadialMenuDelay);
        settingsToSave.rememberFoldState = rememberFoldState;
        [self saveData];
    }];
}

- (void) updateHost:(TemporaryHost *)host {
    [_managedObjectContext performBlockAndWait:^{
        // Add a new persistent managed object if one doesn't exist
        Host* parent = [self getHostForTemporaryHost:host withHostRecords:[self fetchRecords:@"Host"]];
        if (parent == nil) {
            NSEntityDescription* entity = [NSEntityDescription entityForName:@"Host" inManagedObjectContext:self->_managedObjectContext];
            parent = [[Host alloc] initWithEntity:entity insertIntoManagedObjectContext:self->_managedObjectContext];
        }
        
        // Push changes from the temp host to the persistent one
        [host propagateChangesToParent:parent];
        
        [self saveData];
    }];
}

- (void) updateAppsForExistingHost:(TemporaryHost *)host {
    [_managedObjectContext performBlockAndWait:^{
        Host* parent = [self getHostForTemporaryHost:host withHostRecords:[self fetchRecords:@"Host"]];
        if (parent == nil) {
            // The host must exist to be updated
            return;
        }
        
        NSMutableSet *applist = [[NSMutableSet alloc] init];
        NSArray *appRecords = [self fetchRecords:@"App"];
        for (TemporaryApp* app in host.appList) {
            // Add a new persistent managed object if one doesn't exist
            App* parentApp = [self getAppForTemporaryApp:app withAppRecords:appRecords];
            if (parentApp == nil) {
                NSEntityDescription* entity = [NSEntityDescription entityForName:@"App" inManagedObjectContext:self->_managedObjectContext];
                parentApp = [[App alloc] initWithEntity:entity insertIntoManagedObjectContext:self->_managedObjectContext];
            }
            
            [app propagateChangesToParent:parentApp withHost:parent];
            
            [applist addObject:parentApp];
        }
        
        parent.appList = applist;
        
        [self saveData];
    }];
}

- (TemporarySettings*) getSettings {
    __block TemporarySettings *tempSettings;
    
    [_managedObjectContext performBlockAndWait:^{
        tempSettings = [[TemporarySettings alloc] initFromSettings:[self retrieveSettings]];
    }];
    
    return tempSettings;
}

- (Settings*) retrieveSettings {
    NSArray* fetchedRecords = [self fetchRecords:@"Settings"];
    if (fetchedRecords.count == 0) {
        // create a new settings object with the default values
        NSEntityDescription* entity = [NSEntityDescription entityForName:@"Settings" inManagedObjectContext:_managedObjectContext];
        Settings* settings = [[Settings alloc] initWithEntity:entity insertIntoManagedObjectContext:_managedObjectContext];
#if !TARGET_OS_TV
        CGSize native = SunlightNativeLandscapeSize();
        if (native.width >= 1 && native.height >= 1) {
            settings.width = @((int)native.width); settings.height = @((int)native.height);
            settings.resolutionSelected = @4;
        }
#endif
        
        return settings;
    } else {
        // we should only ever have 1 settings object stored
        return [fetchedRecords objectAtIndex:0];
    }
}

- (void) removeApp:(TemporaryApp*)app {
    [_managedObjectContext performBlockAndWait:^{
        App* managedApp = [self getAppForTemporaryApp:app withAppRecords:[self fetchRecords:@"App"]];
        if (managedApp != nil) {
            [self->_managedObjectContext deleteObject:managedApp];
            [self saveData];
        }
    }];
}

- (void) removeHost:(TemporaryHost*)host {
    [_managedObjectContext performBlockAndWait:^{
        Host* managedHost = [self getHostForTemporaryHost:host withHostRecords:[self fetchRecords:@"Host"]];
        if (managedHost != nil) {
            [self->_managedObjectContext deleteObject:managedHost];
            [self saveData];
        }
    }];
}

- (void) saveData {
    NSError* error;
    if ([_managedObjectContext hasChanges] && ![_managedObjectContext save:&error]) {
        Log(LOG_E, @"Unable to save hosts to database: %@", error);
    }

    [_appDelegate saveContext];
}

- (NSArray*) getHosts {
    __block NSMutableArray *tempHosts = [[NSMutableArray alloc] init];
    
    [_managedObjectContext performBlockAndWait:^{
        NSArray *hosts = [self fetchRecords:@"Host"];
        
        for (Host* host in hosts) {
            [tempHosts addObject:[[TemporaryHost alloc] initFromHost:host]];
        }
    }];
    
    return tempHosts;
}

// Only call from within performBlockAndWait!!!
- (Host*) getHostForTemporaryHost:(TemporaryHost*)tempHost withHostRecords:(NSArray*)hosts {
    for (Host* host in hosts) {
        if ([tempHost.uuid isEqualToString:host.uuid]) {
            return host;
        }
    }
    
    return nil;
}

// Only call from within performBlockAndWait!!!
- (App*) getAppForTemporaryApp:(TemporaryApp*)tempApp withAppRecords:(NSArray*)apps {
    for (App* app in apps) {
        if ([app.id isEqualToString:tempApp.id] &&
            [app.host.uuid isEqualToString:tempApp.host.uuid]) {
            return app;
        }
    }
    
    return nil;
}

- (NSArray*) fetchRecords:(NSString*)entityName {
    NSArray* fetchedRecords;
    
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription* entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:_managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSError* error;
    fetchedRecords = [_managedObjectContext executeFetchRequest:fetchRequest error:&error];
    //TODO: handle errors
    
    return fetchedRecords;
}

@end
