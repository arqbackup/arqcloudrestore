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

#define CURRENT_PLANCOMMIT_VERSION (100)

@class PlanCommitError;
@class PlanCommitVolume;


@interface PlanCommit : NSObject

- (instancetype)initWithPlanCommitVolumesByDiskIdentifier:(NSDictionary *)thePCVsByDiskIdentifier
                                                 parentId:(NSString *)theParentId
                                             creationDate:(NSDate *)theCreationDate
                                               isComplete:(BOOL)theIsComplete
                                                 planJSON:(NSDictionary *)thePlanJSON
                                         planCommitErrors:(NSArray *)thePlanCommitErrors
                                               arqVersion:(NSString *)theArqVersion;
- (instancetype)initWithPlanCommit:(PlanCommit *)thePlanCommit parentId:(NSString *)theParentId;
- (instancetype)initWithData:(NSData *)theData error:(NSError * __autoreleasing *)error;
- (instancetype)initWithJSON:(NSDictionary *)theJSON;

@property (readonly, strong) NSDictionary *planCommitVolumesByDiskIdentifier;
@property (readonly, strong) NSString *parentId;
@property (readonly, strong) NSDate *creationDate;
@property (readonly) BOOL isComplete;
@property (readonly, strong) NSDictionary *planJSON;
@property (readonly, strong) NSArray *planCommitErrors;
@property (readonly, strong) NSString *arqVersion;
@property (readonly) uint32_t commitVersion;

- (uint64_t)totalBytes;
- (uint64_t)totalFiles;
@end
