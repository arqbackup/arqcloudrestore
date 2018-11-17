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

#import "PlanCommit.h"
#import "StringIO.h"
#import "DateIO.h"
#import "IntegerIO.h"
#import "BooleanIO.h"
#import "DataInputStream.h"
#import "BufferedInputStream.h"
#import "DataIO.h"
#import "PlanCommitError.h"
#import "PlanCommitVolume.h"
#import "NSDictionary_JSON.h"
#import "PlanNode.h"


#define PLANCOMMIT_HEADER "PLANCOMMIT"


@implementation PlanCommit
- (instancetype)initWithPlanCommitVolumesByDiskIdentifier:(NSDictionary *)thePCVsByDiskIdentifier
                                                 parentId:(NSString *)theParentId
                                             creationDate:(NSDate *)theCreationDate
                                               isComplete:(BOOL)theIsComplete
                                                 planJSON:(NSDictionary *)thePlanJSON
                                         planCommitErrors:(NSArray *)thePlanCommitErrors
                                               arqVersion:(NSString *)theArqVersion {
    if (self = [super init]) {
        _planCommitVolumesByDiskIdentifier = thePCVsByDiskIdentifier;
        _parentId = theParentId;
        _creationDate = theCreationDate;
        _isComplete = theIsComplete;
        _planJSON = thePlanJSON;
        _planCommitErrors = thePlanCommitErrors;
        _arqVersion = theArqVersion;
        _commitVersion = CURRENT_PLANCOMMIT_VERSION;
    }
    return self;
}
- (instancetype)initWithPlanCommit:(PlanCommit *)thePlanCommit parentId:(NSString *)theParentId {
    return [self initWithPlanCommitVolumesByDiskIdentifier:thePlanCommit.planCommitVolumesByDiskIdentifier
                                                  parentId:theParentId
                                              creationDate:thePlanCommit.creationDate
                                                isComplete:thePlanCommit.isComplete
                                                  planJSON:thePlanCommit.planJSON
                                          planCommitErrors:thePlanCommit.planCommitErrors
                                                arqVersion:thePlanCommit.arqVersion];
}
- (instancetype)initWithData:(NSData *)theData error:(NSError * __autoreleasing *)error {
    if (self = [super init]) {
        DataInputStream *dis = [[DataInputStream alloc] initWithData:theData description:@"commit"];
        BufferedInputStream *bis = [[BufferedInputStream alloc] initWithUnderlyingStream:dis];
        NSData *header = [bis readExactly:strlen(PLANCOMMIT_HEADER) error:error];
        if (header == nil) {
            return nil;
        }
        if (strncmp([header bytes], PLANCOMMIT_HEADER, strlen(PLANCOMMIT_HEADER))) {
            SETNSERROR_ARC([self errorDomain], -1, @"invalid PlanCommit header");
            return nil;
        }
        uint64_t pcvCount = 0;
        if (![IntegerIO readUInt64:&pcvCount from:bis error:error]) {
            return nil;
        }
        NSMutableDictionary *pcvsByDiskIdentifier = [NSMutableDictionary dictionary];
        for (uint64_t i = 0; i < pcvCount; i++) {
            PlanCommitVolume *pcv = [[PlanCommitVolume alloc] initWithBufferedInputStream:bis error:error];
            if (pcv == nil) {
                return nil;
            }
            [pcvsByDiskIdentifier setObject:pcv forKey:pcv.diskIdentifier];
        }
        _planCommitVolumesByDiskIdentifier = pcvsByDiskIdentifier;
        
        NSString *parentId = nil;
        NSDate *creationDate = nil;
        NSData *planJSONData = nil;
        NSString *arqVersion = nil;
        uint64_t planCommitErrorCount = 0;
        if (![StringIO read:&parentId from:bis error:error]
            || ![DateIO read:&creationDate from:bis error:error]
            || ![BooleanIO read:&_isComplete from:bis error:error]
            || ![DataIO read:&planJSONData from:bis error:error]
            || ![StringIO read:&arqVersion from:bis error:error]
            || ![IntegerIO readUInt32:&_commitVersion from:bis error:error]
            || ![IntegerIO readUInt64:&planCommitErrorCount from:bis error:error]) {
            return nil;
        }
        _parentId = parentId;
        _creationDate = creationDate;
        _planJSON = [NSJSONSerialization JSONObjectWithData:planJSONData options:0 error:error];
        if (_planJSON == nil) {
            return nil;
        }
        _arqVersion = arqVersion;

        NSMutableArray *planCommitErrors = [NSMutableArray array];
        for (uint64_t i = 0; i < planCommitErrorCount; i++) {
            PlanCommitError *pce = [[PlanCommitError alloc] initWithBufferedInputStream:bis error:error];
            if (pce == nil) {
                return nil;
            }
            [planCommitErrors addObject:pce];
        }
        _planCommitErrors = planCommitErrors;
    }
    return self;
}

- (instancetype)initWithJSON:(NSDictionary *)theJSON {
    if (self = [super init]) {
        NSMutableDictionary *pcvsByDiskIdentifier = [NSMutableDictionary dictionary];
        for (NSDictionary *pcvJSON in [[theJSON objectForKey:@"planCommitVolumesByDiskIdentifier"] allValues]) {
            PlanCommitVolume *pcv = [[PlanCommitVolume alloc] initWithJSON:pcvJSON];
            [pcvsByDiskIdentifier setObject:pcv forKey:pcv.diskIdentifier];
        }
        _planCommitVolumesByDiskIdentifier = pcvsByDiskIdentifier;
        
        _parentId = [theJSON objectForKey:@"parentId"];
        _creationDate = [theJSON dateForKey:@"creationDate"];
        _isComplete = [[theJSON objectForKey:@"isComplete"] boolValue];
        _planJSON = [theJSON objectForKey:@"planJSON"];
        _arqVersion = [theJSON objectForKey:@"arqVersion"];
        _commitVersion = [[theJSON objectForKey:@"commitVersion"] intValue];
        
        NSMutableArray *planCommitErrors = [NSMutableArray array];
        for (NSDictionary *planCommitJSON in [theJSON objectForKey:@"planCommitErrors"]) {
            PlanCommitError *pce = [[PlanCommitError alloc] initWithJSON:planCommitJSON];
            [planCommitErrors addObject:pce];
        }
        _planCommitErrors = planCommitErrors;
    }
    return self;
}

- (NSString *)errorDomain {
    return @"PlanCommitErrorDomain";
}

- (uint64_t)totalBytes {
    uint64_t ret = 0;
    for (PlanCommitVolume *pcv in [_planCommitVolumesByDiskIdentifier allValues]) {
        ret += [pcv.planNode itemSize];
    }
    return ret;
}
- (uint64_t)totalFiles {
    uint64_t ret = 0;
    for (PlanCommitVolume *pcv in [_planCommitVolumesByDiskIdentifier allValues]) {
        ret += [pcv.planNode containedFiles];
    }
    return ret;
}
@end
