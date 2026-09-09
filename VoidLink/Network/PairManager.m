//
//  PairManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "PairManager.h"
#import "CryptoManager.h"
#import "Utils.h"
#import "HttpResponse.h"
#import "HttpRequest.h"
#import "ServerInfoResponse.h"

#include <dispatch/dispatch.h>
#include <limits.h>

static NSData *PairingHexData(NSString *hex) {
    if (hex.length == 0 || hex.length % 2 != 0) return nil;
    NSMutableData *bytes = [NSMutableData dataWithLength:hex.length / 2];
    uint8_t *output = bytes.mutableBytes;
    for (NSUInteger i = 0; i < hex.length; i++) {
        unichar c = [hex characterAtIndex:i];
        int nibble = c >= '0' && c <= '9' ? c - '0' :
            c >= 'a' && c <= 'f' ? c - 'a' + 10 :
            c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
        if (nibble < 0) return nil;
        if ((i & 1) == 0) output[i / 2] = (uint8_t)(nibble << 4);
        else output[i / 2] |= (uint8_t)nibble;
    }
    return bytes;
}

@implementation PairManager {
    HttpManager* _httpManager;
    NSData* _clientCert;
    id<PairCallback> _callback;
}

- (id) initWithManager:(HttpManager*)httpManager clientCert:(NSData*)clientCert callback:(id<PairCallback>)callback {
    self = [super init];
    _httpManager = httpManager;
    _clientCert = clientCert;
    _callback = callback;
    return self;
}

- (void) main {
    // We have to call startPairing before calling any other _callback functions
    NSString* PIN = [self generatePIN];
    [_callback startPairing:PIN];
    
    ServerInfoResponse* serverInfoResp = [[ServerInfoResponse alloc] init];
    [_httpManager executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[_httpManager newServerInfoRequest:false]
                                               fallbackError:401 fallbackRequest:[_httpManager newHttpServerInfoRequest]]];
    if ([serverInfoResp isStatusOk]) {
        if (![[serverInfoResp getStringTag:@"PairStatus"] isEqual:@"1"]) {
            NSString* appversion = [serverInfoResp getStringTag:@"appversion"];
            NSString *majorVersion = [appversion componentsSeparatedByString:@"."].firstObject;
            NSScanner *scanner = majorVersion ? [NSScanner scannerWithString:majorVersion] : nil;
            NSInteger major = 0;
            if (![scanner scanInteger:&major] || !scanner.isAtEnd || major < 1 || major > INT_MAX) {
                [_callback pairFailed:@"Host returned an invalid app version."];
                return;
            }
            [self initiatePairWithPin:PIN forServerMajorVersion:(int)major withState:[serverInfoResp getStringTag:@"state"]];
        } else {
            [_callback alreadyPaired];
        }
    }
    else {
        [_callback pairFailed:serverInfoResp.statusMessage];
    }
}

- (void) finishPairing:(UIBackgroundTaskIdentifier)bgId
           forResponse:(HttpResponse*)resp
     withFallbackError:(NSString*)errorMsg {
    [_httpManager executeRequestSynchronously:[HttpRequest requestWithUrlRequest:[_httpManager newUnpairRequest]]];
    
    if (bgId != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:bgId];
    }
    
    if (![resp isStatusOk]) {
        // Use the response error if the request failed
        errorMsg = resp.statusMessage;
    }
    
    [_callback pairFailed:errorMsg];
}

- (void) finishPairing:(UIBackgroundTaskIdentifier)bgId withSuccess:(NSData*)derCertBytes {
    if (bgId != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:bgId];
    }
    
    [_callback pairSuccessful:derCertBytes];
}

// All codepaths must call finishPairing exactly once before returning!
- (void) initiatePairWithPin:(NSString*)PIN forServerMajorVersion:(int)serverMajorVersion withState:(NSString*)state {
    Log(LOG_I, @"Pairing with generation %d server in state %@", serverMajorVersion, state);
    
    // Start a background task to help prevent the app from being killed
    // while pairing is in progress.
    UIBackgroundTaskIdentifier bgId = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"Pairing PC" expirationHandler:^{
        Log(LOG_W, @"Background pairing time has expired!");
    }];
    
    NSData* salt = [Utils randomBytes:16];
    NSData* saltedPIN = [self concatData:salt with:[PIN dataUsingEncoding:NSUTF8StringEncoding]];

    Log(LOG_I, @"Pairing request started.");
    
    HttpResponse* pairResp = [[HttpResponse alloc] init];
    [_httpManager executeRequestSynchronously:[HttpRequest requestForResponse:pairResp withUrlRequest:[_httpManager newPairRequest:salt clientCert:_clientCert]]];
    if (![self verifyResponseStatus:pairResp]) {
        // GFE does not allow pairing while a server is busy, but Sunshine does. We give it a try and display the busy error if it fails.
        if ([state hasSuffix:@"_SERVER_BUSY"]) {
            [self finishPairing:bgId forResponse:pairResp withFallbackError:@"You cannot pair while a previous session is still running on the host PC. Quit any running games or reboot the host PC, then try pairing again."];
        }
        else {
            [self finishPairing:bgId forResponse:pairResp withFallbackError:@"Pairing was declined by the target."];
        }
        return;
    }
    
    NSString* plainCert = [pairResp getStringTag:@"plaincert"];
    if ([plainCert length] == 0) {
        [self finishPairing:bgId forResponse:pairResp withFallbackError:@"Another pairing attempt is already in progress."];
        return;
    }
    
    NSData *serverCertificate = PairingHexData(plainCert);
    NSData *derCertBytes = [CryptoManager pemToDer:serverCertificate];
    NSData *serverCertificateSignature = [CryptoManager getSignatureFromCert:serverCertificate];
    NSData *clientCertificateSignature = [CryptoManager getSignatureFromCert:_clientCert];
    if (!derCertBytes || !serverCertificateSignature || !clientCertificateSignature) {
        [self finishPairing:bgId forResponse:pairResp withFallbackError:@"Pairing certificate is invalid."];
        return;
    }
    // Pin only a parsed certificate; no malformed pairing response may clear it.
    [_httpManager setServerCert:derCertBytes];
    
    CryptoManager* cryptoMan = [[CryptoManager alloc] init];
    NSData* aesKey;
    
    // Gen 7 servers use SHA256 to get the key
    int hashLength;
    if (serverMajorVersion >= 7) {
        aesKey = [cryptoMan createAESKeyFromSaltSHA256:saltedPIN];
        hashLength = 32;
    }
    else {
        aesKey = [cryptoMan createAESKeyFromSaltSHA1:saltedPIN];
        hashLength = 20;
    }
    
    NSData* randomChallenge = [Utils randomBytes:16];
    NSData* encryptedChallenge = [cryptoMan aesEncrypt:randomChallenge withKey:aesKey];
    
    if (!encryptedChallenge) {
        [self finishPairing:bgId forResponse:pairResp withFallbackError:@"Unable to create pairing challenge."];
        return;
    }
    HttpResponse* challengeResp = [[HttpResponse alloc] init];
    [_httpManager executeRequestSynchronously:[HttpRequest requestForResponse:challengeResp withUrlRequest:[_httpManager newChallengeRequest:encryptedChallenge]]];
    if (![self verifyResponseStatus:challengeResp]) {
        [self finishPairing:bgId forResponse:challengeResp withFallbackError:@"Pairing stage #2 failed"];
        return;
    }
    
    NSData* encServerChallengeResp = PairingHexData([challengeResp getStringTag:@"challengeresponse"]);
    NSData* decServerChallengeResp = [cryptoMan aesDecrypt:encServerChallengeResp withKey:aesKey];
    if (decServerChallengeResp.length < (NSUInteger)hashLength + 16) {
        [self finishPairing:bgId forResponse:challengeResp withFallbackError:@"Host returned an invalid pairing challenge."];
        return;
    }

    NSData* serverResponse = [decServerChallengeResp subdataWithRange:NSMakeRange(0, hashLength)];
    NSData* serverChallenge = [decServerChallengeResp subdataWithRange:NSMakeRange(hashLength, 16)];
    
    NSData* clientSecret = [Utils randomBytes:16];
    NSData* challengeRespHashInput = [self concatData:[self concatData:serverChallenge with:clientCertificateSignature] with:clientSecret];
    NSData* challengeRespHash;
    if (serverMajorVersion >= 7) {
        challengeRespHash = [cryptoMan SHA256HashData: challengeRespHashInput];
    }
    else {
        challengeRespHash = [cryptoMan SHA1HashData: challengeRespHashInput];
    }
    
    assert([challengeRespHash length] <= 32);
    NSMutableData* paddedHash = [NSMutableData dataWithData:challengeRespHash];
    [paddedHash setLength:32];
    
    NSData* challengeRespEncrypted = [cryptoMan aesEncrypt:paddedHash withKey:aesKey];
    
    HttpResponse* secretResp = [[HttpResponse alloc] init];
    [_httpManager executeRequestSynchronously:[HttpRequest requestForResponse:secretResp withUrlRequest:[_httpManager newChallengeRespRequest:challengeRespEncrypted]]];
    if (![self verifyResponseStatus:secretResp]) {
        [self finishPairing:bgId forResponse:secretResp withFallbackError:@"Pairing stage #3 failed"];
        return;
    }
    
    NSData* serverSecretResp = PairingHexData([secretResp getStringTag:@"pairingsecret"]);
    if (serverSecretResp.length <= 16) {
        [self finishPairing:bgId forResponse:secretResp withFallbackError:@"Host returned an invalid pairing secret."];
        return;
    }
    NSData* serverSecret = [serverSecretResp subdataWithRange:NSMakeRange(0, 16)];
    NSData* serverSignature = [serverSecretResp subdataWithRange:NSMakeRange(16, serverSecretResp.length - 16)];
    
    if (![cryptoMan verifySignature:serverSecret withSignature:serverSignature andCert:serverCertificate]) {
        [self finishPairing:bgId forResponse:secretResp withFallbackError:@"Server certificate invalid"];
        return;
    }
    
    NSData* serverChallengeRespHashInput = [self concatData:[self concatData:randomChallenge with:serverCertificateSignature] with:serverSecret];
    NSData* serverChallengeRespHash;
    if (serverMajorVersion >= 7) {
        serverChallengeRespHash = [cryptoMan SHA256HashData: serverChallengeRespHashInput];
    }
    else {
        serverChallengeRespHash = [cryptoMan SHA1HashData: serverChallengeRespHashInput];
    }
    if (![serverChallengeRespHash isEqual:serverResponse]) {
        [self finishPairing:bgId forResponse:secretResp withFallbackError:@"Incorrect PIN"];
        return;
    }
    
    NSData *clientSignature = [cryptoMan signData:clientSecret withKey:[CryptoManager readKeyFromFile]];
    if (!clientSignature) {
        [self finishPairing:bgId forResponse:secretResp withFallbackError:@"Unable to sign the pairing secret."];
        return;
    }
    NSData* clientPairingSecret = [self concatData:clientSecret with:clientSignature];
    HttpResponse* clientSecretResp = [[HttpResponse alloc] init];
    [_httpManager executeRequestSynchronously:[HttpRequest requestForResponse:clientSecretResp withUrlRequest:[_httpManager newClientSecretRespRequest:[Utils bytesToHex:clientPairingSecret]]]];
    if (![self verifyResponseStatus:clientSecretResp]) {
        [self finishPairing:bgId forResponse:clientSecretResp withFallbackError:@"Pairing stage #4 failed"];
        return;
    }
    
    HttpResponse* clientPairChallengeResp = [[HttpResponse alloc] init];
    [_httpManager executeRequestSynchronously:[HttpRequest requestForResponse:clientPairChallengeResp withUrlRequest:[_httpManager newPairChallenge]]];
    if (![self verifyResponseStatus:clientPairChallengeResp]) {
        [self finishPairing:bgId forResponse:clientPairChallengeResp withFallbackError:@"Pairing stage #5 failed"];
        return;
    }
    
    [self finishPairing:bgId withSuccess:derCertBytes];
}

// Caller calls finishPairing for us on failure
- (BOOL) verifyResponseStatus:(HttpResponse*)resp {
    if (![resp isStatusOk]) {
        return false;
    } else {
        NSInteger pairedStatus;
        
        if (![resp getIntTag:@"paired" value:&pairedStatus]) {
            return false;
        }
        
        return pairedStatus == 1;
    }
}

- (NSData*) concatData:(NSData*)data with:(NSData*)moreData {
    NSMutableData* concatData = [[NSMutableData alloc] initWithData:data];
    [concatData appendData:moreData];
    return concatData;
}

- (NSString*) generatePIN {
    NSString* PIN = [NSString stringWithFormat:@"%d%d%d%d",
                     arc4random_uniform(10), arc4random_uniform(10),
                     arc4random_uniform(10), arc4random_uniform(10)];
    return PIN;
}

@end
