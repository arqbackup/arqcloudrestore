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

#import "Encryptor.h"
#import "NSString_extra.h"
#import "KeySet.h"


#define ENCRYPTED_BLOB_HEADER "ARQO"
#define ENCRYPTED_BLOB_HEADER_LEN (4)
#define IV_LEN kCCBlockSizeAES128
#define SYMMETRIC_KEY_LEN kCCKeySizeAES256
#define DATA_IV_AND_SYMMETRIC_KEY_LEN (IV_LEN + SYMMETRIC_KEY_LEN)
#define ENCRYPTED_DATA_IV_AND_SYMMETRIC_KEY_LEN (DATA_IV_AND_SYMMETRIC_KEY_LEN + kCCBlockSizeAES128)
#define MAX_ENCRYPTIONS_PER_SYMMETRIC_KEY (256)


@interface Encryptor() {
    KeySet *_keySet;
    int _encryptCount;

}
@end


@implementation Encryptor
+ (int)encryptedBlobHeaderLength {
    return ENCRYPTED_BLOB_HEADER_LEN + kCCKeySizeAES256 + IV_LEN + ENCRYPTED_DATA_IV_AND_SYMMETRIC_KEY_LEN;
}
- (instancetype)initWithKeySet:(KeySet *)theKeySet {
    if (self = [super init]) {
        _keySet = theKeySet;
    }
    return self;
}
+ (NSString *)errorDomain {
    return @"EncryptorErrorDomain";
}

- (NSString *)blobIdForBytes:(unsigned char *)buf length:(unsigned long long)length {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    CC_SHA256_Update(&ctx, [_keySet.blobIdSalt bytes], (CC_LONG)[_keySet.blobIdSalt length]);
    
    unsigned long long offset = 0;
    while (offset < length) {
        unsigned long long lenThisTime = length - offset;
        if (lenThisTime > UINT_MAX) {
            lenThisTime = UINT_MAX;
        }
        CC_SHA256_Update(&ctx, buf + offset, (unsigned int)lenThisTime);
        offset += lenThisTime;
    }
    CC_SHA256_Final(digest, &ctx);
    return [NSString hexStringWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];

}
- (NSData *)decrypt:(NSData *)theObject error:(NSError * __autoreleasing *)error {
    size_t outbufsize = [theObject length] - (ENCRYPTED_BLOB_HEADER_LEN + CC_SHA256_DIGEST_LENGTH + IV_LEN + ENCRYPTED_DATA_IV_AND_SYMMETRIC_KEY_LEN);
    NSMutableData *ret = [NSMutableData dataWithLength:outbufsize];
    NSInteger decryptedLen = [self decrypt:(unsigned char *)[theObject bytes] length:[theObject length] intoOutBuffer:[ret mutableBytes] outBufferLength:[ret length] error:error];
    if (decryptedLen < 0) {
        return nil;
    }
    [ret setLength:decryptedLen];
    return ret;
}
- (NSInteger)decrypt:(unsigned char *)bytes length:(unsigned long long)length intoOutBuffer:(unsigned char *)outbuf outBufferLength:(NSUInteger)outbuflen error:(NSError * __autoreleasing *)error {
    if (length < (ENCRYPTED_BLOB_HEADER_LEN + CC_SHA256_DIGEST_LENGTH + IV_LEN + ENCRYPTED_DATA_IV_AND_SYMMETRIC_KEY_LEN + 1)) {
        SETNSERROR_ARC([Encryptor errorDomain], -1, @"encrypted object is too small");
        return -1;
    }
    
    // Check header.
    if (strncmp((const char *)bytes, ENCRYPTED_BLOB_HEADER, ENCRYPTED_BLOB_HEADER_LEN)) {
        SETNSERROR_ARC([Encryptor errorDomain], -1, @"object header not equal to 'ARQO'");
        return -1;
    }
    
    // Calculate HMACSHA256 of (master IV + encryptedMetadata + ciphertext) using second half of master key.
    unsigned char hmacSHA256[CC_SHA256_DIGEST_LENGTH];
    CCHmacContext hmacContext;
    CCHmacInit(&hmacContext, kCCHmacAlgSHA256, [_keySet.hmacKey bytes], kCCKeySizeAES256);
    CCHmacUpdate(&hmacContext, bytes + ENCRYPTED_BLOB_HEADER_LEN + CC_SHA256_DIGEST_LENGTH, length - ENCRYPTED_BLOB_HEADER_LEN - CC_SHA256_DIGEST_LENGTH);
    CCHmacFinal(&hmacContext, hmacSHA256);
    
    // Compare our calculated HMAC to the one in the data.
    if (memcmp(hmacSHA256, bytes + ENCRYPTED_BLOB_HEADER_LEN, CC_SHA256_DIGEST_LENGTH)) {
        SETNSERROR_ARC([Encryptor errorDomain], -1, @"HMACSHA256 of object does not match");
        return -1;
    }
    
    // Create metadata buffer.
    unsigned char dataIVAndSymmetricKey[DATA_IV_AND_SYMMETRIC_KEY_LEN + kCCBlockSizeAES128];
    
    // Decrypt metadata into metadata buffer.
    size_t metadataBufferDecryptedLen = 0;
    CCCryptorStatus status = CCCrypt(kCCDecrypt,
                                     kCCAlgorithmAES128,
                                     kCCOptionPKCS7Padding,
                                     [_keySet.encryptionKey bytes],
                                     kCCKeySizeAES256,
                                     (bytes + ENCRYPTED_BLOB_HEADER_LEN + CC_SHA256_DIGEST_LENGTH),
                                     (bytes + ENCRYPTED_BLOB_HEADER_LEN + CC_SHA256_DIGEST_LENGTH + IV_LEN),
                                     ENCRYPTED_DATA_IV_AND_SYMMETRIC_KEY_LEN,
                                     dataIVAndSymmetricKey,
                                     DATA_IV_AND_SYMMETRIC_KEY_LEN + kCCBlockSizeAES128,
                                     &metadataBufferDecryptedLen);
    if (status != kCCSuccess) {
        SETNSERROR_ARC([Encryptor errorDomain], -1, @"failed to decrypt session key: %@", [self errorMessageForStatus:status]);
        return -1;
    }
    if (metadataBufferDecryptedLen != DATA_IV_AND_SYMMETRIC_KEY_LEN) {
        SETNSERROR_ARC([Encryptor errorDomain], -1, @"unexpected length for decrypted iv and key: %ld", metadataBufferDecryptedLen);
        return -1;
    }
    
    unsigned char *dataIV = dataIVAndSymmetricKey;
    unsigned char *mySymmetricKey = dataIVAndSymmetricKey + IV_LEN;
    
    // Decrypt the ciphertext.
    size_t preambleLen = ENCRYPTED_BLOB_HEADER_LEN + CC_SHA256_DIGEST_LENGTH + IV_LEN + ENCRYPTED_DATA_IV_AND_SYMMETRIC_KEY_LEN;
    unsigned char *ciphertext = bytes + preambleLen;
    size_t ciphertextLen = length - preambleLen;
    size_t numBytesDecrypted = 0;
    status = CCCrypt(kCCDecrypt,
                     kCCAlgorithmAES128,
                     kCCOptionPKCS7Padding,
                     mySymmetricKey,
                     kCCKeySizeAES256,
                     dataIV,
                     ciphertext,
                     ciphertextLen,
                     outbuf,
                     outbuflen,
                     &numBytesDecrypted);
    if (status != kCCSuccess) {
        SETNSERROR_ARC([Encryptor errorDomain], -1, @"failed to decrypt object data: %@", [self errorMessageForStatus:status]);
        return -1;
    }
    return numBytesDecrypted;
}


#pragma mark internal
- (NSString *)errorMessageForStatus:(CCCryptorStatus)status {
    if (status == kCCBufferTooSmall) {
        return @"buffer too small";
    }
    if (status == kCCAlignmentError) {
        return @"alignment error";
    }
    if (status == kCCDecodeError) {
        return @"decode error";
    }
    return [NSString stringWithFormat:@"CCCryptorStatus error %d", status];
}
@end
