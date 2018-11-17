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

#import "PlanRepo.h"
#import "PlanCommit.h"
#import "PlanTree.h"
#import "Encryptor.h"
#import "NSData-LZ4.h"
#import "LZ4Compressor.h"
#import "BufferSet.h"
#import "KeySet.h"
#import "DataInputStream.h"
#import "BufferedInputStream.h"
#import "Item.h"
#import "FileOutputStream.h"
#import "DataTransferDelegate.h"
#import "TargetConnectionDelegate.h"
#import "DataOutputStream.h"
#import "Buffer.h"
#import "FileInputStream.h"
#import "MD5Hash.h"
#import "S3Service.h"
#import "WasabiRegion.h"
#import "PlanCommitVolume.h"
#import "PlanNode.h"
#import "BlobDescriptor.h"


@interface PlanRepo() {
    NSString *_bucketName;
    NSString *_planUUID;
    id <TargetConnectionDelegate> _tcd;
    S3Service *_s3;
    Encryptor *_encryptor;
}
@end


@implementation PlanRepo
- (instancetype)initWithS3:(S3Service *)theS3
                bucketName:(NSString *)theBucketName
                  planUUID:(NSString *)thePlanUUID 
        encryptionPassword:(NSString *)theEncryptionPassword
  targetConnectionDelegate:(id <TargetConnectionDelegate>)theTCD 
                     error:(NSError * __autoreleasing *)error {
    if (self = [super init]) {
        _planUUID = thePlanUUID;
        _s3 = theS3;
        _bucketName = theBucketName;
        _tcd = theTCD;

        NSString *encryptedKeySetPath = [NSString stringWithFormat:@"/%@/encrypted_master_keys.dat", theBucketName];
        NSData *encryptedKeySet = [_s3 contentsOfFileAtPath:encryptedKeySetPath dataTransferDelegate:nil targetConnectionDelegate:_tcd error:error];
        if (encryptedKeySet == nil) {
            return nil;
        }

        KeySet *keySet = [[KeySet alloc] initWithEncryptedRepresentation:encryptedKeySet encryptionPassword:theEncryptionPassword error:error];
        if (keySet == nil) {
            return nil;
        }
        _encryptor = [[Encryptor alloc] initWithKeySet:keySet];
    }
    return self;
}
- (NSString *)errorDomain {
    return @"PlanRepoErrorDomain";
}


- (NSString *)headId:(NSError * __autoreleasing *)error {
    NSData *headIdData = [_s3 contentsOfFileAtPath:[self pathForHeadCommitId] dataTransferDelegate:nil targetConnectionDelegate:_tcd error:error];
    if (headIdData == nil) {
        return nil;
    }
    NSString *headId = [[NSString alloc] initWithData:headIdData encoding:NSUTF8StringEncoding];
    if (headId == nil) {
        SETNSERROR_ARC([self errorDomain], -1, @"unable to read contents of head id %@", [self pathForHeadCommitId]);
        return nil;
    }
    return headId;
}

- (PlanCommit *)planCommitWithId:(NSString *)theId error:(NSError *__autoreleasing *)error {
    uint64_t storedSize = 0;
    return [self planCommitWithId:theId storedSize:&storedSize error:error];
}
- (PlanCommit *)planCommitWithId:(NSString *)theId storedSize:(uint64_t *)outStoredSize error:(NSError * __autoreleasing *)error {
    if (theId == nil) {
        SETNSERROR_ARC([self errorDomain], -1, @"commit id is nil");
        return nil;
    }
    NSData *data = [self readDecryptAndUncompressDataAtPath:[self pathForCommitWithId:theId] storedSize:outStoredSize error:error];
    if (data == nil) {
        return nil;
    }
    return [[PlanCommit alloc] initWithData:data error:error];
}
- (PlanTree *)planTreeWithId:(NSString *)theId error:(NSError * __autoreleasing *)error {
    uint64_t storedSize = 0;
    return [self planTreeWithId:theId storedSize:&storedSize error:error];
}
- (PlanTree *)planTreeWithId:(NSString *)theId storedSize:(uint64_t *)outStoredSize error:(NSError * __autoreleasing *)error {
    if (theId == nil) {
        SETNSERROR_ARC([self errorDomain], -1, @"tree id is nil");
        return nil;
    }
    NSData *data = [self readDecryptAndUncompressDataAtPath:[self pathForTreeWithId:theId] storedSize:outStoredSize error:error];
    if (data == nil) {
        return nil;
    }
    DataInputStream *dis = [[DataInputStream alloc] initWithData:data description:@"tree"];
    BufferedInputStream *bis = [[BufferedInputStream alloc] initWithUnderlyingStream:dis];
    return [[PlanTree alloc] initWithBufferedInputStream:bis error:error];
}
- (NSInteger)readBlobWithId:(NSString *)theId intoBufferSet:(BufferSet *)theBufferSet dataTransferDelegate:(id <DataTransferDelegate>)theDTD error:(NSError * __autoreleasing *)error {
    NSString *path = [self pathForBlobId:theId];
    return [self readDecryptAndUncompressDataAtPath:path intoBufferSet:theBufferSet dataTransferDelegate:theDTD error:error];
}


#pragma mark internal
- (NSData *)readDecryptAndUncompressDataAtPath:(NSString *)thePath storedSize:(uint64_t *)outStoredSize error:(NSError * __autoreleasing *)error {
    NSData *data = [_s3 contentsOfFileAtPath:thePath dataTransferDelegate:nil targetConnectionDelegate:_tcd error:error];
    if (data == nil) {
        return nil;
    }
    *outStoredSize = [data length];
    NSData *decrypted = [_encryptor decrypt:data error:error];
    if (decrypted == nil) {
        return nil;
    }
    NSData *uncompressed = [decrypted lz4Inflate:error];
    if (uncompressed == nil) {
        return nil;
    }
    return uncompressed;
}
- (NSInteger)readDecryptAndUncompressDataAtPath:(NSString *)thePath intoBufferSet:(BufferSet *)theBufferSet dataTransferDelegate:(id <DataTransferDelegate>)theDTD error:(NSError * __autoreleasing *)error {
    NSInteger encryptedLen = [_s3 readContentsOfFileAtPath:thePath intoBuffer:[[theBufferSet encryptedCompressedBuffer] bytes] bufferLength:[[theBufferSet encryptedCompressedBuffer] bufferSize] dataTransferDelegate:theDTD targetConnectionDelegate:_tcd error:error];
    if (_tcd != nil && ![_tcd targetConnectionShouldRetryOnTransientError:error]) {
        return -1;
    }
    if (encryptedLen < 0) {
        return encryptedLen;
    }
    NSInteger decryptedLen = [_encryptor decrypt:[[theBufferSet encryptedCompressedBuffer] bytes] length:encryptedLen intoOutBuffer:[[theBufferSet compressedBuffer] bytes] outBufferLength:[[theBufferSet compressedBuffer] bufferSize] error:error];
    if (decryptedLen < 0) {
        return decryptedLen;
    }
    int inflatedLen = [[LZ4Compressor shared] lz4InflateBytes:[[theBufferSet compressedBuffer] bytes] length:decryptedLen intoBuffer:[[theBufferSet plaintextBuffer] bytes] length:[[theBufferSet plaintextBuffer] bufferSize] error:error];
    return inflatedLen;
}

- (NSString *)pathForHeadCommitId {
    return [NSString stringWithFormat:@"/%@/plans/%@/head_commit_id", _bucketName, _planUUID];
}
- (NSString *)pathForCommitWithId:(NSString *)theId {
    return [NSString stringWithFormat:@"/%@/plans/%@/commits/%@/%@", _bucketName, _planUUID, [theId substringToIndex:2], [theId substringFromIndex:2]];
}
- (NSString *)pathForTreeWithId:(NSString *)theId {
    return [NSString stringWithFormat:@"/%@/plans/%@/trees/%@/%@", _bucketName, _planUUID, [theId substringToIndex:2], [theId substringFromIndex:2]];
}
- (NSString *)pathForBlobId:(NSString *)theId {
    return [NSString stringWithFormat:@"/%@/plans/%@/blobs/%@/%@", _bucketName, _planUUID, [theId substringToIndex:2], [theId substringFromIndex:2]];
}
@end
