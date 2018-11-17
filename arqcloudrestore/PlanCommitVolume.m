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

#import "PlanCommitVolume.h"
#import "PlanNode.h"
#import "StringIO.h"


@implementation PlanCommitVolume
- (instancetype)initWithDiskIdentifier:(NSString *)theDiskIdentifier name:(NSString *)theName mountPoint:(NSString *)theMountPoint planNode:(PlanNode *)thePlanNode {
    if (self = [super init]) {
        _diskIdentifier = theDiskIdentifier;
        _name = theName;
        _mountPoint = theMountPoint;
        NSAssert(thePlanNode != nil, @"thePlanNode may not be nil");
        NSAssert([thePlanNode isTree], @"thePlanNode must be a tree");
        _planNode = thePlanNode;
    }
    return self;
}
- (instancetype)initWithBufferedInputStream:(BufferedInputStream *)theBIS error:(NSError * __autoreleasing *)error {
    if (self = [super init]) {
        NSString *diskIdentifier = nil;
        NSString *name = nil;
        NSString *mountPoint = nil;
        if (![StringIO read:&diskIdentifier from:theBIS error:error]
            || ![StringIO read:&name from:theBIS error:error]
            || ![StringIO read:&mountPoint from:theBIS error:error]) {
            return nil;
        }
        _diskIdentifier = diskIdentifier;
        _name = name;
        _mountPoint = mountPoint;
        
        PlanNode *planNode = [[PlanNode alloc] initWithBufferedInputStream:theBIS error:error];
        if (planNode == nil) {
            return nil;
        }
        _planNode = planNode;
    }
    return self;
}
- (instancetype)initWithJSON:(NSDictionary *)theJSON {
    if (self = [super init]) {
        _diskIdentifier = [theJSON objectForKey:@"diskIdentifier"];
        _name = [theJSON objectForKey:@"name"];
        _mountPoint = [theJSON objectForKey:@"mountPoint"];
        _planNode = [[PlanNode alloc] initWithJSON:[theJSON objectForKey:@"planNode"]];
    }
    return self;
}


#pragma mark NSObject
- (NSString *)description {
    return [NSString stringWithFormat:@"PlanCommitVolume(%@, %@)", _diskIdentifier, _name];
}
- (BOOL)isEqual:(id)other {
    if (other == self) {
        return YES;
    }
    if (other == nil || ![other isKindOfClass:[self class]]) {
        return NO;
    }
    PlanCommitVolume *o = (PlanCommitVolume *)other;
    return [o.name isEqual:self.name] && [o.diskIdentifier isEqual:self.diskIdentifier] && [o.mountPoint isEqual:self.mountPoint] && [o.planNode isEqual:self.planNode];
}
- (NSUInteger)hash {
    return [self.diskIdentifier hash];
}
@end
