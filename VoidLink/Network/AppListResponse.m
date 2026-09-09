//
//  AppListResponse.m
//  Moonlight
//
//  Created by Diego Waxemberg on 2/1/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "AppListResponse.h"
#import "TemporaryApp.h"
#import <libxml2/libxml/xmlreader.h>

@implementation AppListResponse {
    NSMutableSet* _appList;
}

static const char* TAG_APP = "App";
static const char* TAG_APP_TITLE = "AppTitle";
static const char* TAG_APP_ID = "ID";
static const char* TAG_HDR_SUPPORTED = "IsHdrSupported";
static const char* TAG_APP_INSTALL_PATH = "AppInstallPath";

- (void)populateWithData:(NSData *)xml {
    _appList = [[NSMutableSet alloc] init];
    // Share status validation, size limits and payload-free XML diagnostics with
    // all other host responses. A failed refresh cannot retain a stale success.
    [super populateWithData:xml];
    if (self.isStatusOk) [self parseAppData];
}

- (void)parseAppData {
    xmlDocPtr docPtr = xmlReadMemory(self.data.bytes, (int)self.data.length, NULL, NULL,
                                    XML_PARSE_NONET | XML_PARSE_NOERROR | XML_PARSE_NOWARNING);
    xmlNodePtr node = docPtr ? xmlDocGetRootElement(docPtr) : NULL;
    if (!node) {
        self.statusCode = 502;
        self.statusMessage = @"Malformed app list response from host.";
        if (docPtr) xmlFreeDoc(docPtr);
        return;
    }
    node = node->children;
    
    while (node != NULL) {
        //Log(LOG_D, @"node: %s", node->name);
        if (!xmlStrcmp(node->name, (xmlChar*)TAG_APP)) {
            xmlNodePtr appInfoNode = node->xmlChildrenNode;
            NSString* appName = @"";
            NSString* appId = nil;
            NSString* hdrSupported = @"0";
            NSString* appInstallPath = nil;
            while (appInfoNode != NULL) {
                if (!xmlStrcmp(appInfoNode->name, (xmlChar*)TAG_APP_TITLE)) {
                    xmlChar* nodeVal = xmlNodeListGetString(docPtr, appInfoNode->xmlChildrenNode, 1);
                    if (nodeVal != NULL) {
                        appName = [[NSString alloc] initWithCString:(const char*)nodeVal encoding:NSUTF8StringEncoding];
                        xmlFree(nodeVal);
                    }
                } else if (!xmlStrcmp(appInfoNode->name, (xmlChar*)TAG_APP_ID)) {
                    xmlChar* nodeVal = xmlNodeListGetString(docPtr, appInfoNode->xmlChildrenNode, 1);
                    if (nodeVal != NULL) {
                        appId = [[NSString alloc] initWithCString:(const char*)nodeVal encoding:NSUTF8StringEncoding];
                        xmlFree(nodeVal);
                    }
                } else if (!xmlStrcmp(appInfoNode->name, (xmlChar*)TAG_HDR_SUPPORTED)) {
                    xmlChar* nodeVal = xmlNodeListGetString(docPtr, appInfoNode->xmlChildrenNode, 1);
                    if (nodeVal != NULL) {
                        hdrSupported = [[NSString alloc] initWithCString:(const char*)nodeVal encoding:NSUTF8StringEncoding];
                        xmlFree(nodeVal);
                    }
                } else if (!xmlStrcmp(appInfoNode->name, (xmlChar*)TAG_APP_INSTALL_PATH)) {
                    xmlChar* nodeVal = xmlNodeListGetString(docPtr, appInfoNode->xmlChildrenNode, 1);
                    if (nodeVal != NULL) {
                        appInstallPath = [[NSString alloc] initWithCString:(const char*)nodeVal encoding:NSUTF8StringEncoding];
                        xmlFree(nodeVal);
                    }
                }

                appInfoNode = appInfoNode->next;
            }
            if (appId != nil) {
                TemporaryApp* app = [[TemporaryApp alloc] init];
                app.name = appName;
                app.id = appId;
                app.hdrSupported = [hdrSupported intValue] != 0;
                app.installPath = appInstallPath;
                [_appList addObject:app];
            }
        }
        node = node->next;
    }
    
    xmlFreeDoc(docPtr);
    
#ifdef ENABLE_APP_STORE_RESTRICTIONS
    // APP STORE REVIEW COMPLIANCE
    //
    // Remove default Steam entry from the app list to comply with Apple App Store Guideline 4.2.7d:
    //
    // The UI appearing on the client does not resemble an iOS or App Store view, does not provide a store-like interface,
    // or include the ability to browse, select, or purchase software not already owned or licensed by the user.
    //
    // However, if the user manually adds Steam themselves, then we will display it.
    TemporaryApp* officialSteamApp = nil;
    TemporaryApp* manuallyAddedSteamApp = nil;
    for (TemporaryApp* app in _appList) {
        if (app.installPath != nil && [[app.installPath lowercaseString] hasSuffix:@"\\steam\\"]) {
            // The official Steam app is marked as HDR supported, while manually added ones are not.
            if ([app.name isEqualToString:@"Steam"] && app.hdrSupported) {
                officialSteamApp = app;
            }
            else {
                manuallyAddedSteamApp = app;
            }
        }
    }
    
    // To be safe, don't do anything if we didn't find an HDR-enabled Steam app.
    if (officialSteamApp != nil) {
        // If we didn't find a manually added Steam app, remove the official one to
        // comply with the App Store guidelines.
        if (manuallyAddedSteamApp == nil) {
            [_appList removeObject:officialSteamApp];
        }
        else {
            [_appList removeObject:manuallyAddedSteamApp];
        }
    }
#endif
}

- (NSSet*) getAppList {
    return _appList;
}

- (BOOL) isStatusOk {
    return self.statusCode == 200;
}

@end
