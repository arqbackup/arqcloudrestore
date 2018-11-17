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

@class PlanCommit;
@class PlanTree;
@class Store;
@protocol TargetConnectionDelegate;
@class BufferSet;
@protocol DataTransferDelegate;
@class S3Service;
@class BlobDescriptor;


@interface PlanRepo : NSObject

- (instancetype)initWithS3:(S3Service *)theS3
                bucketName:(NSString *)theBucketName
                  planUUID:(NSString *)thePlanUUID 
        encryptionPassword:(NSString *)theEncryptionPassword
  targetConnectionDelegate:(id <TargetConnectionDelegate>)theTCD 
                     error:(NSError * __autoreleasing *)error;

- (NSString *)headId:(NSError * __autoreleasing *)error;

- (PlanCommit *)planCommitWithId:(NSString *)theId error:(NSError * __autoreleasing *)error;
- (PlanCommit *)planCommitWithId:(NSString *)theId storedSize:(uint64_t *)outStoredSize error:(NSError * __autoreleasing *)error;

- (PlanTree *)planTreeWithId:(NSString *)theId error:(NSError * __autoreleasing *)error;
- (PlanTree *)planTreeWithId:(NSString *)theId storedSize:(uint64_t *)outStoredSize error:(NSError * __autoreleasing *)error;

- (NSInteger)readBlobWithId:(NSString *)theId intoBufferSet:(BufferSet *)theBufferSet dataTransferDelegate:(id <DataTransferDelegate>)theDTD error:(NSError * __autoreleasing *)error;

@end
