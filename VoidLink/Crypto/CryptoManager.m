//
//  CryptoManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/14/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "CryptoManager.h"
#import "mkcert.h"

#include <openssl/sha.h>
#include <openssl/x509.h>
#include <openssl/pem.h>
#include <openssl/evp.h>
#include <limits.h>

@implementation CryptoManager
enum { SHA1_HASH_LENGTH = 20, SHA256_HASH_LENGTH = 32 };
static NSData* key = nil;
static NSData* cert = nil;
static NSData* p12 = nil;

- (NSData*) createAESKeyFromSaltSHA1:(NSData*)saltedPIN {
    return [[self SHA1HashData:saltedPIN] subdataWithRange:NSMakeRange(0, 16)];
}

- (NSData*) createAESKeyFromSaltSHA256:(NSData*)saltedPIN {
    return [[self SHA256HashData:saltedPIN] subdataWithRange:NSMakeRange(0, 16)];
}

- (NSData*) SHA1HashData:(NSData*)data {
    unsigned char sha1[SHA1_HASH_LENGTH];
    SHA1([data bytes], [data length], sha1);
    NSData* bytes = [NSData dataWithBytes:sha1 length:sizeof(sha1)];
    return bytes;
}

- (NSData*) SHA256HashData:(NSData*)data {
    unsigned char sha256[SHA256_HASH_LENGTH];
    SHA256([data bytes], [data length], sha256);
    NSData* bytes = [NSData dataWithBytes:sha256 length:sizeof(sha256)];
    return bytes;
}

// Host-provided PEM and challenge bytes are untrusted until pairing finishes.
// Reject malformed input before calling OpenSSL or slicing a response.
static X509 *ReadCertificate(NSData *bytes) {
    if (bytes.length == 0 || bytes.length > INT_MAX) return NULL;
    BIO *bio = BIO_new_mem_buf(bytes.bytes, (int)bytes.length);
    if (!bio) return NULL;
    X509 *certificate = PEM_read_bio_X509(bio, NULL, NULL, NULL);
    BIO_free(bio);
    return certificate;
}

static NSData *CryptAES(NSData *data, NSData *keyBytes, BOOL encrypt) {
    if (!data || keyBytes.length != 16 || data.length > INT_MAX - EVP_MAX_BLOCK_LENGTH || data.length % 16 != 0) return nil;
    EVP_CIPHER_CTX *cipher = EVP_CIPHER_CTX_new();
    if (!cipher) return nil;
    NSMutableData *output = [NSMutableData dataWithLength:data.length + EVP_MAX_BLOCK_LENGTH];
    int written = 0, finalBytes = 0;
    BOOL okay = EVP_CipherInit_ex(cipher, EVP_aes_128_ecb(), NULL, keyBytes.bytes, NULL, encrypt) == 1 &&
        EVP_CIPHER_CTX_set_padding(cipher, 0) == 1 &&
        EVP_CipherUpdate(cipher, output.mutableBytes, &written, data.bytes, (int)data.length) == 1 &&
        EVP_CipherFinal_ex(cipher, (unsigned char *)output.mutableBytes + written, &finalBytes) == 1 &&
        (NSUInteger)(written + finalBytes) == data.length;
    EVP_CIPHER_CTX_free(cipher);
    if (!okay) return nil;
    output.length = (NSUInteger)(written + finalBytes);
    return output;
}

- (NSData*) aesEncrypt:(NSData*)data withKey:(NSData*)key {
    return CryptAES(data, key, YES);
}

- (NSData*) aesDecrypt:(NSData*)data withKey:(NSData*)key {
    return CryptAES(data, key, NO);
}

+ (NSData*) pemToDer:(NSData*)pemCertBytes {
    X509 *certificate = ReadCertificate(pemCertBytes);
    if (!certificate) return nil;
    unsigned char *encoded = NULL;
    int length = i2d_X509(certificate, &encoded);
    NSData *result = length > 0 ? [NSData dataWithBytes:encoded length:(NSUInteger)length] : nil;
    OPENSSL_free(encoded);
    X509_free(certificate);
    return result;
}

- (bool) verifySignature:(NSData *)data withSignature:(NSData*)signature andCert:(NSData*)cert {
    if (!data || signature.length == 0) return false;
    X509 *certificate = ReadCertificate(cert);
    if (!certificate) return false;
    EVP_PKEY *publicKey = X509_get_pubkey(certificate);
    EVP_MD_CTX *context = EVP_MD_CTX_new();
    BOOL valid = publicKey && context &&
        EVP_DigestVerifyInit(context, NULL, EVP_sha256(), NULL, publicKey) == 1 &&
        EVP_DigestVerifyUpdate(context, data.bytes, data.length) == 1 &&
        EVP_DigestVerifyFinal(context, signature.bytes, signature.length) == 1;
    EVP_MD_CTX_free(context);
    EVP_PKEY_free(publicKey);
    X509_free(certificate);
    return valid;
}

- (NSData *)signData:(NSData *)data withKey:(NSData *)key {
    if (!data || key.length == 0 || key.length > INT_MAX) return nil;
    BIO *bio = BIO_new_mem_buf(key.bytes, (int)key.length);
    if (!bio) return nil;
    EVP_PKEY *privateKey = PEM_read_bio_PrivateKey(bio, NULL, NULL, NULL);
    BIO_free(bio);
    if (!privateKey) return nil;
    EVP_MD_CTX *context = EVP_MD_CTX_new();
    size_t length = 0;
    BOOL okay = context && EVP_DigestSignInit(context, NULL, EVP_sha256(), NULL, privateKey) == 1 &&
        EVP_DigestSignUpdate(context, data.bytes, data.length) == 1 &&
        EVP_DigestSignFinal(context, NULL, &length) == 1 && length > 0;
    NSMutableData *signature = okay ? [NSMutableData dataWithLength:length] : nil;
    if (okay) okay = EVP_DigestSignFinal(context, signature.mutableBytes, &length) == 1;
    EVP_MD_CTX_free(context);
    EVP_PKEY_free(privateKey);
    if (!okay) return nil;
    signature.length = length;
    return signature;
}

+ (NSData*) readCryptoObject:(NSString*)item {
#if TARGET_OS_TV
    return [[NSUserDefaults standardUserDefaults] dataForKey:item];
#else
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *file = [documentsDirectory stringByAppendingPathComponent:item];
    return [NSData dataWithContentsOfFile:file];
#endif
}

+ (void) writeCryptoObject:(NSString*)item data:(NSData*)data {
#if TARGET_OS_TV
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:item];
#else
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *file = [documentsDirectory stringByAppendingPathComponent:item];
    [data writeToFile:file atomically:NO];
#endif
}

+ (NSData*) readCertFromFile {
    if (cert == nil) {
        cert = [CryptoManager readCryptoObject:@"client.crt"];
    }
    return cert;
}

+ (NSData*) readP12FromFile {
    if (p12 == nil) {
        p12 = [CryptoManager readCryptoObject:@"client.p12"];
    }
    return p12;
}

+ (NSData*) readKeyFromFile {
    if (key == nil) {
        key = [CryptoManager readCryptoObject:@"client.key"];
    }
    return key;
}

+ (bool) keyPairExists {
    bool keyFileExists = [CryptoManager readCryptoObject:@"client.key"] != nil;
    bool p12FileExists = [CryptoManager readCryptoObject:@"client.p12"] != nil;
    bool certFileExists = [CryptoManager readCryptoObject:@"client.crt"] != nil;
    
    return keyFileExists && p12FileExists && certFileExists;
}

+ (NSData *)getSignatureFromCert:(NSData *)cert {
    X509 *certificate = ReadCertificate(cert);
    if (!certificate) return nil;
    const ASN1_BIT_STRING *signature = NULL;
    X509_get0_signature(&signature, NULL, certificate);
    NSData *result = signature && signature->length > 0
        ? [NSData dataWithBytes:signature->data length:(NSUInteger)signature->length] : nil;
    X509_free(certificate);
    return result;
}

+ (NSData*)getKeyFromCertKeyPair:(CertKeyPair*)certKeyPair {
    BIO* bio = BIO_new(BIO_s_mem());
    
    PEM_write_bio_PrivateKey_traditional(bio, certKeyPair->pkey, NULL, NULL, 0, NULL, NULL);
    
    BUF_MEM* mem;
    BIO_get_mem_ptr(bio, &mem);
    NSData* data = [NSData dataWithBytes:mem->data length:mem->length];
    BIO_free(bio);
    return data;
}

+ (NSData*)getP12FromCertKeyPair:(CertKeyPair*)certKeyPair {
    BIO* bio = BIO_new(BIO_s_mem());
    
    i2d_PKCS12_bio(bio, certKeyPair->p12);
    
    BUF_MEM* mem;
    BIO_get_mem_ptr(bio, &mem);
    NSData* data = [NSData dataWithBytes:mem->data length:mem->length];
    BIO_free(bio);
    return data;
}

+ (NSData*)getCertFromCertKeyPair:(CertKeyPair*)certKeyPair {
    BIO* bio = BIO_new(BIO_s_mem());
    
    PEM_write_bio_X509(bio, certKeyPair->x509);
    
    BUF_MEM* mem;
    BIO_get_mem_ptr(bio, &mem);
    NSData* data = [NSData dataWithBytes:mem->data length:mem->length];
    BIO_free(bio);
    return data;
}

+ (void) generateKeyPairUsingSSL {
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        if (![CryptoManager keyPairExists]) {
            Log(LOG_I, @"Generating Certificate... ");
            CertKeyPair certKeyPair = generateCertKeyPair();
            
            NSData* certData = [CryptoManager getCertFromCertKeyPair:&certKeyPair];
            NSData* p12Data = [CryptoManager getP12FromCertKeyPair:&certKeyPair];
            NSData* keyData = [CryptoManager getKeyFromCertKeyPair:&certKeyPair];
            
            freeCertKeyPair(certKeyPair);
            
            [CryptoManager writeCryptoObject:@"client.crt" data:certData];
            [CryptoManager writeCryptoObject:@"client.p12" data:p12Data];
            [CryptoManager writeCryptoObject:@"client.key" data:keyData];
            
            Log(LOG_I, @"Certificate created");
        }
    });
}

@end
