#import "CryptoManager.h"
#import "PairManager.h"
#import "ServerInfoResponse.h"
#import "mkcert.h"
#import <objc/runtime.h>
#include <openssl/pem.h>
#include <openssl/rsa.h>

static unsigned checks;
static NSData *certificate, *privateKey, *localP12;
static void Check(BOOL okay, NSString *message) {
    checks++;
    if (!okay) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static NSData *Hex(NSString *text) {
    NSMutableData *data = [NSMutableData data];
    for (NSUInteger i = 0; i + 1 < text.length; i += 2) {
        unsigned int value = 0;
        [[NSScanner scannerWithString:[text substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&value];
        uint8_t byte = (uint8_t)value; [data appendBytes:&byte length:1];
    }
    return data;
}
static NSData *Join(NSData *a, NSData *b) { NSMutableData *result = [a mutableCopy]; [result appendData:b]; return result; }
static NSData *BIOData(BIO *bio) {
    BUF_MEM *buffer = NULL; BIO_get_mem_ptr(bio, &buffer);
    return [NSData dataWithBytes:buffer->data length:buffer->length];
}
// Key generation/storage are deliberately not invoked by this harness. All
// certificates are ephemeral fixtures, and no user's Documents/keychain is read.
struct CertKeyPair generateCertKeyPair(void) { abort(); }
void freeCertKeyPair(struct CertKeyPair pair) { X509_free(pair.x509); EVP_PKEY_free(pair.pkey); PKCS12_free(pair.p12); }
static void MakeCertificate(void) {
    EVP_PKEY_CTX *context = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, NULL);
    EVP_PKEY *key = NULL;
    Check(context && EVP_PKEY_keygen_init(context) == 1 && EVP_PKEY_CTX_set_rsa_keygen_bits(context, 2048) == 1 &&
          EVP_PKEY_keygen(context, &key) == 1, @"Create ephemeral RSA fixture");
    EVP_PKEY_CTX_free(context);
    X509 *cert = X509_new();
    X509_set_version(cert, 2); ASN1_INTEGER_set(X509_get_serialNumber(cert), 1);
    X509_gmtime_adj(X509_getm_notBefore(cert), 0); X509_gmtime_adj(X509_getm_notAfter(cert), 3600);
    X509_set_pubkey(cert, key);
    X509_NAME *name = X509_get_subject_name(cert);
    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, (const unsigned char *)"Pairing fixture", -1, -1, 0);
    X509_set_issuer_name(cert, name); Check(X509_sign(cert, key, EVP_sha256()) > 0, @"Sign ephemeral fixture certificate");
    BIO *bio = BIO_new(BIO_s_mem()); PEM_write_bio_X509(bio, cert); certificate = BIOData(bio); BIO_free(bio);
    bio = BIO_new(BIO_s_mem()); PEM_write_bio_PrivateKey(bio, key, NULL, NULL, 0, NULL, NULL); privateKey = BIOData(bio); BIO_free(bio);
    X509_free(cert); EVP_PKEY_free(key);
    method_setImplementation(class_getClassMethod(CryptoManager.class, @selector(readKeyFromFile)),
                             imp_implementationWithBlock(^NSData *(id object) { (void)object; return privateKey; }));
    method_setImplementation(class_getClassMethod(CryptoManager.class, @selector(readP12FromFile)),
                             imp_implementationWithBlock(^NSData *(id object) { (void)object; return localP12; }));
}
@implementation Utils
+ (NSData *)randomBytes:(NSUInteger)length { NSMutableData *data = [NSMutableData dataWithLength:length]; arc4random_buf(data.mutableBytes, length); return data; }
+ (NSString *)bytesToHex:(NSData *)data {
    NSMutableString *hex = [NSMutableString string]; const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) [hex appendFormat:@"%02x", bytes[i]];
    return hex;
}
+ (NSString *)addressPortStringToAddress:(NSString *)address { (void)address; return @"fixture.invalid"; }
+ (unsigned short)addressPortStringToPort:(NSString *)address { (void)address; return 47989; }
@end
@implementation TemporaryHost @end
@implementation ServerInfoResponse
- (void)populateWithData:(NSData *)data { [super populateWithData:data]; }
- (void)populateHost:(TemporaryHost *)host { host.httpsPort = 47984; }
@end
const char *LiGetLaunchUrlQueryParameters(void) { return ""; }
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *app; static dispatch_once_t once; dispatch_once(&once, ^{ app = [self new]; }); return app; }
- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithName:(NSString *)name expirationHandler:(dispatch_block_t)handler { (void)name; (void)handler; return ++self.begun; }
- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)identifier { (void)identifier; self.ended++; }
@end

@interface ScriptedHost : HttpManager
@property NSString *version;
@property NSString *malformedCertificate;
@property NSString *malformedChallenge;
@property NSString *malformedSecret;
@property NSData *key;
@property NSData *serverSecret;
@property NSUInteger requests;
@property NSUInteger unpairs;
@property NSUInteger pairedCertificates;
@property BOOL clientProofVerified;
@end
@implementation ScriptedHost
- (instancetype)init { self = [super initWithAddress:@"fixture.invalid" httpsPort:47984 serverCert:nil]; if (self) { self.version = @"7.1.2"; self.serverSecret = [Utils randomBytes:16]; } return self; }
- (void)setServerCert:(NSData *)cert { Check(cert.length > 0, @"Only valid DER reaches certificate pinning"); self.pairedCertificates++; [super setServerCert:cert]; }
- (void)executeRequestSynchronously:(HttpRequest *)request {
    self.requests++;
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:request.request.URL resolvingAgainstBaseURL:NO].queryItems) query[item.name] = item.value;
    CryptoManager *crypto = [CryptoManager new];
    NSString *tags = @"<paired>1</paired>";
    if ([request.request.URL.path isEqual:@"/serverinfo"]) {
        tags = [NSString stringWithFormat:@"<PairStatus>0</PairStatus><appversion>%@</appversion><state>FREE</state>", self.version];
    } else if ([request.request.URL.path isEqual:@"/unpair"]) {
        self.unpairs++;
    } else if ([query[@"phrase"] isEqual:@"getservercert"]) {
        NSData *saltedPIN = Join(Hex(query[@"salt"]), [@"1234" dataUsingEncoding:NSUTF8StringEncoding]);
        self.key = self.version.intValue >= 7 ? [crypto createAESKeyFromSaltSHA256:saltedPIN] : [crypto createAESKeyFromSaltSHA1:saltedPIN];
        tags = [tags stringByAppendingFormat:@"<plaincert>%@</plaincert>", self.malformedCertificate ?: [Utils bytesToHex:certificate]];
    } else if (query[@"clientchallenge"]) {
        NSData *challenge = [crypto aesDecrypt:Hex(query[@"clientchallenge"]) withKey:self.key];
        Check(challenge.length == 16, @"Pairing preserves its 16-byte client challenge");
        NSData *input = Join(Join(challenge, [CryptoManager getSignatureFromCert:certificate]), self.serverSecret);
        NSData *hash = self.version.intValue >= 7 ? [crypto SHA256HashData:input] : [crypto SHA1HashData:input];
        NSMutableData *response = [Join(hash, [Utils randomBytes:16]) mutableCopy]; response.length = 48;
        NSString *encrypted = [Utils bytesToHex:[crypto aesEncrypt:response withKey:self.key]];
        tags = [tags stringByAppendingFormat:@"<challengeresponse>%@</challengeresponse>", self.malformedChallenge ?: encrypted];
    } else if (query[@"serverchallengeresp"]) {
        NSData *proof = Join(self.serverSecret, [crypto signData:self.serverSecret withKey:privateKey]);
        tags = [tags stringByAppendingFormat:@"<pairingsecret>%@</pairingsecret>", self.malformedSecret ?: [Utils bytesToHex:proof]];
    } else if (query[@"clientpairingsecret"]) {
        NSData *proof = Hex(query[@"clientpairingsecret"]);
        self.clientProofVerified = proof.length > 16 && [crypto verifySignature:[proof subdataWithRange:NSMakeRange(0, 16)]
            withSignature:[proof subdataWithRange:NSMakeRange(16, proof.length - 16)] andCert:certificate];
    }
    [request.response populateWithData:[[NSString stringWithFormat:@"<root status_code=\"200\">%@</root>", tags] dataUsingEncoding:NSUTF8StringEncoding]];
}
@end
@interface PairResult : NSObject <PairCallback>
@property NSUInteger failures;
@property NSUInteger successes;
@property NSUInteger starts;
@end
@implementation PairResult
- (void)startPairing:(NSString *)pin { Check([pin isEqual:@"1234"], @"Fixture PIN remains only in pairing callback"); self.starts++; }
- (void)pairSuccessful:(NSData *)cert { Check(cert.length > 0, @"Success returns a parsed certificate"); self.successes++; }
- (void)pairFailed:(NSString *)message { Check(message.length > 0, @"Failure returns a usable diagnostic"); self.failures++; }
- (void)alreadyPaired { Check(NO, @"Fixture must execute pairing protocol"); }
@end
@interface FixedPINPair : PairManager @end
@implementation FixedPINPair
- (NSString *)generatePIN { return @"1234"; }
@end
static PairResult *RunPair(ScriptedHost *host) {
    PairResult *result = [PairResult new];
    FixedPINPair *pair = [[FixedPINPair alloc] initWithManager:host clientCert:certificate callback:result];
    [pair main];
    Check(result.starts == 1 && result.failures + result.successes == 1, @"Pairing completes exactly once");
    Check(UIApplication.sharedApplication.begun == UIApplication.sharedApplication.ended, @"Every started background task ends");
    return result;
}
static void CryptoTests(void) {
    CryptoManager *crypto = [CryptoManager new];
    NSData *key = Hex(@"000102030405060708090a0b0c0d0e0f");
    NSData *plain = Hex(@"00112233445566778899aabbccddeeff");
    NSData *cipher = Hex(@"69c4e0d86a7b0430d8cdb78070b4c55a");
    Check([[crypto aesEncrypt:plain withKey:key] isEqual:cipher], @"AES-128 ECB NIST known-answer encryption");
    Check([[crypto aesDecrypt:cipher withKey:key] isEqual:plain], @"AES-128 ECB NIST known-answer decryption");
    for (NSUInteger length = 1; length < 48; length++) {
        if (length % 16 == 0) continue;
        NSData *invalid = [NSMutableData dataWithLength:length];
        Check([crypto aesEncrypt:invalid withKey:key] == nil && [crypto aesDecrypt:invalid withKey:key] == nil,
              @"Reject incomplete AES blocks without assertion or partial bytes");
    }
    Check([crypto aesDecrypt:nil withKey:key] == nil && [crypto aesDecrypt:cipher withKey:[NSData data]] == nil, @"Reject missing ciphertext and key");
    for (NSData *invalid in @[[NSData data], [@"not a certificate" dataUsingEncoding:NSUTF8StringEncoding], [NSData dataWithBytes:"\0\xff\0" length:3]]) {
        Check([CryptoManager pemToDer:invalid] == nil && [CryptoManager getSignatureFromCert:invalid] == nil, @"Reject malformed certificate safely");
        Check([crypto signData:plain withKey:invalid] == nil && ![crypto verifySignature:plain withSignature:cipher andCert:invalid], @"Reject malformed signing/verifying key material");
    }
    NSData *signature = [crypto signData:plain withKey:privateKey];
    Check(signature.length == 256 && [crypto verifySignature:plain withSignature:signature andCert:certificate], @"Valid RSA SHA256 pairing signature round-trips");
    Check(![crypto verifySignature:cipher withSignature:signature andCert:certificate], @"Reject a tampered signed message");
    Check([CryptoManager pemToDer:certificate].length > 0 && [CryptoManager getSignatureFromCert:certificate].length == 256, @"Valid PEM converts and exposes its signature");
}
static void PairingTests(void) {
    for (NSString *version in @[@"5.1", @"7.1", @"10.0"]) {
        ScriptedHost *host = [ScriptedHost new]; host.version = version;
        PairResult *result = RunPair(host);
        Check(result.successes == 1 && host.clientProofVerified && host.unpairs == 0, @"Valid old/current/two-digit generation pairing remains compatible");
    }
    for (NSString *version in @[@"", @"bad", @"0", @"-1", @"9999999999999999999999", @"7junk"]) {
        ScriptedHost *host = [ScriptedHost new]; host.version = version;
        Check(RunPair(host).failures == 1 && host.requests == 1, @"Invalid app versions stop before pairing begins");
    }
    for (NSString *invalid in @[@"0", @"gg", @"１２", @"00", @""]) {
        ScriptedHost *host = [ScriptedHost new]; host.malformedCertificate = invalid;
        Check(RunPair(host).failures == 1 && host.pairedCertificates == 0 && host.unpairs == 1,
              @"Malformed certificate fails safely before clearing or setting TLS pin");
    }
    for (NSString *invalid in @[@"", @"0", @"gg", @"00000000000000000000000000000000", @"0000000000000000000000000000000000000000000000000000000000000000"]) {
        ScriptedHost *host = [ScriptedHost new]; host.malformedChallenge = invalid;
        Check(RunPair(host).failures == 1 && host.unpairs == 1 && host.requests == 4,
              @"Truncated/malformed challenge ends before the next protocol stage");
    }
    for (NSString *invalid in @[@"", @"0", @"gg", @"00", @"00000000000000000000000000000000"]) {
        ScriptedHost *host = [ScriptedHost new]; host.malformedSecret = invalid;
        Check(RunPair(host).failures == 1 && host.unpairs == 1 && host.requests == 5,
              @"Truncated/malformed secret cannot underflow a signature slice");
    }
}
@interface HttpManager (Testing)
- (SecIdentityRef)getClientCertificate;
- (NSArray *)getCertificate:(SecIdentityRef)identity;
@end
@interface TrustSpace : NSURLProtectionSpace
@property SecTrustRef fixtureTrust;
- (SecTrustRef)serverTrust;
@end
@implementation TrustSpace
- (SecTrustRef)serverTrust { return self.fixtureTrust; }
@end
static void TrustTests(void) {
    HttpManager *http = [[HttpManager alloc] initWithAddress:@"fixture.invalid" httpsPort:47984 serverCert:nil];
    localP12 = nil;
    Check([http getClientCertificate] == NULL && [http getCertificate:NULL] == nil, @"Missing client identity cannot reach unsafe Security calls");
    localP12 = [@"corrupt pkcs12" dataUsingEncoding:NSUTF8StringEncoding];
    Check([http getClientCertificate] == NULL, @"Corrupt PKCS12 fails safely without reading a user identity");
    NSArray *pins = @[[NSData data], [@"mismatch" dataUsingEncoding:NSUTF8StringEncoding], [CryptoManager pemToDer:certificate]];
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)[CryptoManager pemToDer:certificate]);
    SecPolicyRef policy = SecPolicyCreateSSL(true, CFSTR("fixture.invalid"));
    SecTrustRef trust = NULL; SecTrustCreateWithCertificates(cert, policy, &trust);
    for (NSUInteger i = 0; i < pins.count; i++) {
        [http setServerCert:pins[i]];
        TrustSpace *space = [[TrustSpace alloc] initWithHost:@"fixture.invalid" port:47984 protocol:@"https" realm:nil authenticationMethod:NSURLAuthenticationMethodServerTrust];
        space.fixtureTrust = trust;
        NSURLAuthenticationChallenge *challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space proposedCredential:nil previousFailureCount:0 failureResponse:nil error:nil sender:(id<NSURLAuthenticationChallengeSender>)[NSObject new]];
        __block NSUInteger calls = 0;
        [http URLSession:NSURLSession.sharedSession didReceiveChallenge:challenge completionHandler:^(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential) {
            calls++;
            Check(disposition == (i == 2 ? NSURLSessionAuthChallengeUseCredential : NSURLSessionAuthChallengeCancelAuthenticationChallenge), @"Only an exact paired certificate admits TLS; missing/mismatched pins never delegate to system trust");
            Check((credential != nil) == (i == 2), @"Only the paired identity receives a credential");
        }];
        Check(calls == 1, @"TLS challenge completes exactly once");
    }
    CFRelease(trust); CFRelease(policy); CFRelease(cert);
}
// Exercise the real synchronous request/fallback control flow with an in-memory
// NSURLSession endpoint. No socket or TLS server is opened by this fixture.
static BOOL markAuthenticationFailure;
static NSUInteger sessionRequests;
static BOOL fixtureHTTPSSucceeds;
static NSURL *fixtureResponseURL;
static NSInteger fixtureHTTPStatus = 200;
static NSString *fixtureResponseXML;
static NSString *fixtureHTTPSResponseXML;
@interface FixtureTask : NSObject
@property (copy) dispatch_block_t completion;
- (void)resume;
@end
@implementation FixtureTask
- (void)resume { self.completion(); }
@end
@interface FixtureSession : NSObject
@property HttpManager *delegate;
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler;
- (void)invalidateAndCancel;
@end
@implementation FixtureSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    FixtureTask *task = [FixtureTask new];
    task.completion = ^{
        sessionRequests++;
        if ([request.URL.scheme isEqual:@"https"] && !fixtureHTTPSSucceeds) {
            if (markAuthenticationFailure) {
                TrustSpace *space = [[TrustSpace alloc] initWithHost:@"fixture.invalid" port:47984 protocol:@"https" realm:nil authenticationMethod:NSURLAuthenticationMethodServerTrust];
                NSURLAuthenticationChallenge *challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space proposedCredential:nil previousFailureCount:0 failureResponse:nil error:nil sender:(id<NSURLAuthenticationChallengeSender>)[NSObject new]];
                [self.delegate URLSession:(id)self didReceiveChallenge:challenge completionHandler:^(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential) {
                    Check(disposition == NSURLSessionAuthChallengeCancelAuthenticationChallenge && !credential, @"The request explicitly fails a missing server identity");
                }];
            }
            handler(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
        } else {
            NSString *xml = ([request.URL.scheme isEqual:@"https"] ? fixtureHTTPSResponseXML : nil) ?:
                fixtureResponseXML ?: @"<root status_code=\"200\"><state>FREE</state><VirtualDisplayOnlySupported>1</VirtualDisplayOnlySupported></root>";
            handler([xml dataUsingEncoding:NSUTF8StringEncoding],
                    [[NSHTTPURLResponse alloc] initWithURL:fixtureResponseURL ?: request.URL statusCode:fixtureHTTPStatus HTTPVersion:@"HTTP/1.1" headerFields:nil], nil);
        }
    };
    return (id)task;
}
- (void)invalidateAndCancel {}
@end
static void RequestAuthenticationTests(void) {
    Method factory = class_getClassMethod(NSURLSession.class, @selector(sessionWithConfiguration:delegate:delegateQueue:));
    IMP original = method_getImplementation(factory);
    IMP replacement = imp_implementationWithBlock(^id(id cls, NSURLSessionConfiguration *configuration, id delegate, NSOperationQueue *queue) {
        (void)cls; (void)configuration; (void)queue; FixtureSession *session = [FixtureSession new]; session.delegate = delegate; return session;
    });
    method_setImplementation(factory, replacement);
    for (NSUInteger scenario = 0; scenario < 3; scenario++) {
        HttpManager *http = [[HttpManager alloc] initWithAddress:@"fixture.invalid" httpsPort:47984 serverCert:nil];
        HttpResponse *response = [HttpResponse new];
        markAuthenticationFailure = scenario != 2; sessionRequests = 0;
        NSURLRequest *https = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://fixture.invalid/serverinfo"]];
        NSURLRequest *fallback = scenario != 0 ? [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://fixture.invalid/serverinfo"]] : nil;
        HttpRequest *request = [HttpRequest requestForResponse:response withUrlRequest:https fallbackError:401 fallbackRequest:fallback];
        [http executeRequestSynchronously:request];
        if (scenario == 1) Check(response.isStatusOk && sessionRequests == 2, @"Explicit certificate cancellation preserves exactly one provided serverinfo fallback");
        else Check(!response.isStatusOk && sessionRequests == 1, @"No fallback is invented, and ordinary cancellation never triggers a plaintext fallback");
        Check([[http valueForKey:@"certificateFailures"] count] == 0, @"Completed request releases its authentication failure/session tracking");
        Check(!request.authenticatedResponse, @"Certificate cancellation or HTTP fallback cannot advertise an authenticated capability");
    }

    fixtureHTTPSSucceeds = YES;
    markAuthenticationFailure = NO;
    NSData *pin = [CryptoManager pemToDer:certificate];
    HttpManager *http = [[HttpManager alloc] initWithAddress:@"fixture.invalid" httpsPort:47984 serverCert:pin];
    HttpResponse *response = [HttpResponse new];
    NSURLRequest *https = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://fixture.invalid:47984/serverinfo"]];
    HttpRequest *request = [HttpRequest requestForResponse:response withUrlRequest:https];
    Check(!request.authenticatedResponse, @"New requests start with no authenticated response");
    [http executeRequestSynchronously:request];
    Check(response.isStatusOk && request.authenticatedResponse, @"Successful pinned HTTPS response retains its transport provenance");

    for (NSString *redirect in @[@"http://fixture.invalid:47984/serverinfo", @"https://other.invalid:47984/serverinfo",
                                @"https://fixture.invalid:47985/serverinfo", @"https://fixture.invalid:47984/unrelated"]) {
        fixtureResponseURL = [NSURL URLWithString:redirect];
        [http executeRequestSynchronously:request];
        Check(response.isStatusOk && !request.authenticatedResponse &&
              [[response getStringTag:@"VirtualDisplayOnlySupported"] isEqual:@"1"],
              @"Redirected discovery fields stay readable but cannot borrow authority from another endpoint");
    }
    fixtureResponseURL = [NSURL URLWithString:@"https://FIXTURE.invalid:47984/serverinfo"];
    [http executeRequestSynchronously:request];
    Check(request.authenticatedResponse, @"DNS host case does not change response origin");

    request.request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://fixture.invalid/serverinfo"]];
    fixtureResponseURL = [NSURL URLWithString:@"https://fixture.invalid:443/serverinfo"];
    [http executeRequestSynchronously:request];
    Check(request.authenticatedResponse, @"Explicit default HTTPS port has the same response origin");
    request.request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://fixture.invalid/serverinfo"]];
    [http executeRequestSynchronously:request];
    Check(!request.authenticatedResponse, @"A plaintext request redirected to HTTPS does not establish capability provenance");

    request.request = https;
    fixtureResponseURL = nil;
    [http setServerCert:nil];
    [http executeRequestSynchronously:request];
    Check(!request.authenticatedResponse, @"An HTTPS URL alone without a paired certificate does not establish authority");
    [http setServerCert:[NSData data]];
    [http executeRequestSynchronously:request];
    Check(!request.authenticatedResponse, @"An empty certificate is not a usable pin");
    [http setServerCert:pin];

    fixtureHTTPStatus = 503;
    [http executeRequestSynchronously:request];
    Check(!request.authenticatedResponse, @"An HTTP failure carrying successful XML does not advertise capabilities");
    fixtureHTTPStatus = 200;
    fixtureResponseXML = @"<root status_code=\"401\"><VirtualDisplayOnlySupported>1</VirtualDisplayOnlySupported></root>";
    [http executeRequestSynchronously:request];
    Check(!request.authenticatedResponse, @"An XML authentication failure cannot advertise capabilities");
    fixtureResponseXML = @"<root status_code=\"200\"><VirtualDisplayOnlySupported>1";
    [http executeRequestSynchronously:request];
    Check(!request.authenticatedResponse, @"Malformed XML cannot retain an earlier successful response's authority");
    fixtureResponseXML = nil;

    [http executeRequestSynchronously:request];
    Check(request.authenticatedResponse, @"A reused request can gain provenance from a new successful response");
    fixtureHTTPSResponseXML = @"<root status_code=\"401\" status_message=\"Unauthorized\"/>";
    request.fallbackError = 401;
    request.fallbackRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://fixture.invalid/serverinfo"]];
    sessionRequests = 0;
    [http executeRequestSynchronously:request];
    Check(sessionRequests == 2 && response.isStatusOk && !request.authenticatedResponse,
          @"An unauthorized HTTPS response preserves discovery fallback without trusting its advertised capabilities");
    fixtureHTTPSResponseXML = nil;
    request.request = https;
    [http executeRequestSynchronously:request];
    Check(request.authenticatedResponse, @"A successful request refreshes provenance after unauthorized fallback");
    fixtureHTTPSSucceeds = NO;
    markAuthenticationFailure = YES;
    request.fallbackError = 401;
    request.fallbackRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://fixture.invalid/serverinfo"]];
    sessionRequests = 0;
    [http executeRequestSynchronously:request];
    Check(sessionRequests == 2 && response.isStatusOk && !request.authenticatedResponse,
          @"A reused authenticated request loses authority when certificate failure selects its legacy HTTP fallback");

    fixtureHTTPSSucceeds = YES;
    markAuthenticationFailure = NO;
    request.request = https;
    [http executeRequestSynchronously:request];
    Check(request.authenticatedResponse, @"Pinned request succeeds again after fallback");
    request.request = nil;
    [http executeRequestSynchronously:request];
    Check(!request.authenticatedResponse && !response.isStatusOk, @"Early missing-request failure clears earlier provenance");

    method_setImplementation(factory, original); imp_removeBlock(replacement);
}

int main(void) { @autoreleasepool { MakeCertificate(); CryptoTests(); PairingTests(); TrustTests(); RequestAuthenticationTests(); printf("Crypto/pairing: %u checks passed\n", checks); } return 0; }
