//
//  HttpResponse.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/30/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "HttpResponse.h"
#import <libxml2/libxml/xmlreader.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>

@implementation HttpResponse {
    NSMutableDictionary* _elements;
}
@synthesize data, statusCode, statusMessage;

- (id) init {
    self = [super init];
    if (self) {
        self.statusCode = 502;
        self.statusMessage = @"No response received from host.";
    }
    return self;
}

- (void) populateWithData:(NSData*)xml {
    self.data = xml;
    [self parseData];
}

- (NSString*) getStringTag:(NSString*)tag {
    return [_elements objectForKey:tag];
}

- (BOOL) getIntTag:(NSString *)tag value:(NSInteger*)value {
    NSString* stringVal = [self getStringTag:tag];
    if (stringVal != nil) {
        *value = [stringVal integerValue];
        return true;
    } else {
        return false;
    }
}

- (BOOL) isStatusOk {
    return self.statusCode == 200;
}

- (BOOL) getUInt64Tag:(NSString*)tag value:(uint64_t*)value {
    NSString* stringVal = [[self getStringTag:tag] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (stringVal.length == 0 || value == NULL) {
        return NO;
    }

    uint64_t parsed = 0;
    for (NSUInteger i = 0; i < stringVal.length; i++) {
        unichar character = [stringVal characterAtIndex:i];
        if (character < '0' || character > '9') {
            return NO;
        }
        unsigned int digit = character - '0';
        if (parsed > (UINT64_MAX - digit) / 10) {
            return NO;
        }
        parsed = parsed * 10 + digit;
    }

    *value = parsed;
    return YES;
}

- (void) parseData {
    _elements = [[NSMutableDictionary alloc] init];
    // A reused response must not retain a previous successful status or message.
    self.statusCode = 502;
    self.statusMessage = @"Malformed XML response from host.";
    if (self.data.length == 0) {
        self.statusMessage = @"Empty response from host.";
        return;
    }
    if (self.data.length > INT_MAX) {
        self.statusMessage = @"Response from host is too large to parse.";
        return;
    }
    xmlDocPtr docPtr = xmlParseMemory([self.data bytes], (int)[self.data length]);
    if (docPtr == NULL) {
        Log(LOG_W, @"An error occured trying to parse xml.");
        return;
    }
    
    xmlNodePtr node = xmlDocGetRootElement(docPtr);
    if (node == NULL) {
        self.statusMessage = @"Host response has no root XML element.";
        Log(LOG_W, @"No root XML element.");
        xmlFreeDoc(docPtr);
        return;
    }

    xmlChar* statusStr = xmlGetProp(node, (const xmlChar*)[TAG_STATUS_CODE UTF8String]);
    if (statusStr == NULL) {
        self.statusMessage = @"Host response is missing its status code.";
        xmlFreeDoc(docPtr);
        return;
    }
    NSString* statusString = [[NSString stringWithUTF8String:(const char*)statusStr] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    xmlFree(statusStr);
    const char* statusBytes = [statusString UTF8String];
    char* statusEnd = NULL;
    errno = 0;
    long long status = statusBytes ? strtoll(statusBytes, &statusEnd, 10) : 0;
    if (statusBytes == NULL || statusEnd == statusBytes || *statusEnd != '\0' ||
        errno == ERANGE || status < NSIntegerMin || status > NSIntegerMax) {
        self.statusMessage = @"Host response contains an invalid status code.";
        xmlFreeDoc(docPtr);
        return;
    }
    self.statusCode = (NSInteger)status;
    
    xmlChar* statusMsgXml = xmlGetProp(node, (const xmlChar*)[TAG_STATUS_MESSAGE UTF8String]);
    NSString* hostStatusMessage = nil;
    if (statusMsgXml != NULL) {
        hostStatusMessage = [NSString stringWithUTF8String:(const char*)statusMsgXml];
        xmlFree(statusMsgXml);
    }
    if ([hostStatusMessage stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0) {
        self.statusMessage = hostStatusMessage;
    }
    else {
        self.statusMessage = self.statusCode == 200 ? @"OK" : [NSString stringWithFormat:@"Host returned status code %ld.", (long)self.statusCode];
    }
    
    if (self.statusCode == -1 && [self.statusMessage isEqualToString:@"Invalid"]) {
        // Special case handling an audio capture error which GFE doesn't
        // provide any useful status message for.
        self.statusCode = 418;
        self.statusMessage = @"Missing audio capture device. Reinstalling GeForce Experience should resolve this error.";
    }

    node = node->children;
    
    while (node != NULL) {
        xmlChar* nodeVal = xmlNodeListGetString(docPtr, node->xmlChildrenNode, 1);
        
        NSString* value;
        if (nodeVal == NULL) {
            value = @"";
        } else {
            value = [[NSString alloc] initWithCString:(const char*)nodeVal encoding:NSUTF8StringEncoding];
        }
        NSString* key = [[NSString alloc] initWithCString:(const char*)node->name encoding:NSUTF8StringEncoding];
        [_elements setObject:value forKey:key];
        xmlFree(nodeVal);
        node = node->next;
    }
    
    xmlFreeDoc(docPtr);
    
    Log(LOG_D, @"Parsed XML data: %@", _elements);
}

@end
