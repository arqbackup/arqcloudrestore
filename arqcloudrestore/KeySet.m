/*
 Copyright © 2018 Haystack Software LLC. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 
 * Neither the names of PhotoMinds LLC or Haystack Software, nor the names of 
 their contributors may be used to endorse or promote products derived from
 this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */ 

#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>
#import "KeySet.h"
#import "S3Service.h"


#define KEY_DERIVATION_ROUNDS (200000)
#define HEADER "ARQ_ENCRYPTED_MASTER_KEYS"
#define SALT_LENGTH (8)
#define IV_LENGTH (16)


@implementation KeySet
- (instancetype)initWithEncryptionKey:(NSData *)theEncryptionKey hmacKey:(NSData *)theHmacKey blobIdSalt:(NSData *)theBlobIdSalt {
    if (self = [super init]) {
        NSAssert([theEncryptionKey length] == kCCKeySizeAES256, @"encryption key must be 32 bytes");
        NSAssert([theHmacKey length] == kCCKeySizeAES256, @"hmac key must be 32 bytes");
        NSAssert([theBlobIdSalt length] > 0, @"blob id salt must be non-zero length");
        _encryptionKey = theEncryptionKey;
        _hmacKey = theHmacKey;
        _blobIdSalt = theBlobIdSalt;
    }
    return self;
}
- (instancetype)initWithEncryptedRepresentation:(NSData *)theEncryptedRepresentation encryptionPassword:(NSString *)theEncryptionPassword error:(NSError * __autoreleasing *)error {
    if (self = [super init]) {
        NSData *keyData = [self decrypt:theEncryptedRepresentation withPassword:theEncryptionPassword error:error];
        if (keyData == nil) {
            return nil;
        }
        NSUInteger expectedKeysLen = kCCKeySizeAES256 * 3;
        if ([keyData length] != expectedKeysLen) {
            SETNSERROR_ARC([self errorDomain], -1, @"unexpected decrypted key set length: %ld", [keyData length]);
            return nil;
        }
        [self setKeysFromData:keyData];
    }
    return self;
}

- (void)setKeysFromData:(NSData *)theKeyData {
    NSAssert([theKeyData length] == kCCKeySizeAES256 * 3, @"key data must be 96 bytes");
    _encryptionKey = [theKeyData subdataWithRange:NSMakeRange(0, kCCKeySizeAES256)];
    _hmacKey = [theKeyData subdataWithRange:NSMakeRange(kCCKeySizeAES256, kCCKeySizeAES256)];
    _blobIdSalt = [theKeyData subdataWithRange:NSMakeRange(kCCKeySizeAES256 * 2, kCCKeySizeAES256)];
}

- (NSString *)errorDomain {
    return @"KeySetErrorDomain";
}



#pragma mark internal
- (NSData *)decrypt:(NSData *)theEncryptedKeySet withPassword:(NSString *)thePassword error:(NSError * __autoreleasing *)error {
    if ([theEncryptedKeySet length] < (strlen(HEADER) + SALT_LENGTH + CC_SHA256_DIGEST_LENGTH + IV_LENGTH + 1)) {
        SETNSERROR_ARC([self errorDomain], -1, @"not enough bytes in encrypted key set data");
        return nil;
    }
    const unsigned char *bytes = (const unsigned char *)[theEncryptedKeySet bytes];
    
    if (strncmp((const char *)bytes, HEADER, strlen(HEADER))) {
        SETNSERROR_ARC([self errorDomain], -1, @"invalid header for encrypted key set data");
        return nil;
    }
    
    // Derive 64-byte encryption key from thePassword.
    NSData *thePasswordData = [thePassword dataUsingEncoding:NSUTF8StringEncoding];
    void *derivedEncryptionKey = malloc(kCCKeySizeAES256 * 2);
    const unsigned char *salt = bytes + strlen(HEADER);
    CCKeyDerivationPBKDF(kCCPBKDF2, [thePasswordData bytes], [thePasswordData length], salt, SALT_LENGTH, kCCPRFHmacAlgSHA1, KEY_DERIVATION_ROUNDS, derivedEncryptionKey, kCCKeySizeAES256 * 2);
    void *derivedHMACKey = derivedEncryptionKey + kCCKeySizeAES256;
    
    // Calculate HMACSHA256 of IV + encrypted master keys, using derivedHMACKey.
    unsigned char hmacSHA256[CC_SHA256_DIGEST_LENGTH];
    CCHmacContext hmacContext;
    CCHmacInit(&hmacContext, kCCHmacAlgSHA256, derivedHMACKey, kCCKeySizeAES256);
    const unsigned char *dataToHMAC = bytes + strlen(HEADER) + SALT_LENGTH + CC_SHA256_DIGEST_LENGTH;
    unsigned long dataToHMACLen = [theEncryptedKeySet length] - (strlen(HEADER) + SALT_LENGTH + CC_SHA256_DIGEST_LENGTH);
    CCHmacUpdate(&hmacContext, dataToHMAC, dataToHMACLen);
    CCHmacFinal(&hmacContext, hmacSHA256);
    
    // Compare to the HMAC stored in the data.
    if (memcmp(hmacSHA256, bytes + strlen(HEADER) + SALT_LENGTH, CC_SHA256_DIGEST_LENGTH)) {
        free(derivedEncryptionKey);
        HSLogDebug(@"HMACSHA256 of key set doesn't match the one we calculated");
        SETNSERROR_ARC([self errorDomain], ERROR_KEYSET_DECRYPT_FAILED, @"incorrect password");
        return nil;
    }
    
    // Decrypt master keys.
    NSUInteger expectedKeysLen = kCCKeySizeAES256 * 3;
    size_t theMasterKeysLen = expectedKeysLen + kCCBlockSizeAES128;
    NSMutableData *theMasterKeys = [NSMutableData dataWithLength:theMasterKeysLen];
    const unsigned char *iv = bytes + strlen(HEADER) + SALT_LENGTH + CC_SHA256_DIGEST_LENGTH;
    size_t theMasterKeysActualLen = 0;
    const unsigned char *encryptedMasterKeys = bytes + strlen(HEADER) + SALT_LENGTH + CC_SHA256_DIGEST_LENGTH + IV_LENGTH;
    size_t encryptedMasterKeysLen = [theEncryptedKeySet length] - strlen(HEADER) - SALT_LENGTH - CC_SHA256_DIGEST_LENGTH - IV_LENGTH;
    CCCryptorStatus status = CCCrypt(kCCDecrypt,
                                     kCCAlgorithmAES128,
                                     kCCOptionPKCS7Padding,
                                     derivedEncryptionKey,
                                     kCCKeySizeAES256,
                                     iv,
                                     encryptedMasterKeys,
                                     encryptedMasterKeysLen,
                                     [theMasterKeys mutableBytes],
                                     theMasterKeysLen,
                                     &theMasterKeysActualLen);
    if (status != kCCSuccess) {
        free(derivedEncryptionKey);
        SETNSERROR_ARC([self errorDomain], ERROR_KEYSET_DECRYPT_FAILED, @"failed to decrypt the encrypted master key data");
        return nil;
    }
    [theMasterKeys setLength:theMasterKeysActualLen];
    
    free(derivedEncryptionKey);
    
    if ([theMasterKeys length] != expectedKeysLen) {
        SETNSERROR_ARC([self errorDomain], ERROR_KEYSET_DECRYPT_FAILED, @"unexpected master keys length %ld (expected %ld)", [theMasterKeys length], expectedKeysLen);
        return nil;
    }
    
    return theMasterKeys;
}
@end
