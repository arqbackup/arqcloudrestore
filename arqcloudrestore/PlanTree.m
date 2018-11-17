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

#import "PlanTree.h"
#import "PlanNode.h"
#import "IntegerIO.h"
#import "StringIO.h"


@interface PlanTree() {
    uint32_t _version;
    NSDictionary *_childNodesByName;
}
@end


@implementation PlanTree
- (instancetype)initWithJSON:(NSDictionary *)theJSON {
    if (self = [super init]) {
        _version = [[theJSON objectForKey:@"version"] unsignedIntValue];

        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        NSDictionary *childNodesJSON = [theJSON objectForKey:@"childNodesByName"];
        for (NSString *nodeName in [childNodesJSON allKeys]) {
            PlanNode *planNode = [[PlanNode alloc] initWithJSON:[childNodesJSON objectForKey:nodeName]];
            [dict setObject:planNode forKey:nodeName];
        }
        _childNodesByName = dict;
    }
    return self;
}

- (instancetype)initWithBufferedInputStream:(BufferedInputStream *)bis error:(NSError * __autoreleasing *)error {
    if (self = [super init]) {
        if (![IntegerIO readUInt32:&_version from:bis error:error]) {
            return nil;
        }
        uint64_t count = 0;
        if (![IntegerIO readUInt64:&count from:bis error:error]) {
            return nil;
        }
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        for (uint64_t i = 0; i < count; i++) {
            NSString *name = nil;
            if (![StringIO read:&name from:bis error:error]) {
                return nil;
            }
            PlanNode *planNode = [[PlanNode alloc] initWithBufferedInputStream:bis error:error];
            if (planNode == nil) {
                return nil;
            }
            [dict setObject:planNode forKey:name];
        }
        _childNodesByName = [NSDictionary dictionaryWithDictionary:dict];
    }
    return self;
}

- (NSArray *)childNodeNames {
    return [_childNodesByName allKeys];
}
- (PlanNode *)childNodeWithName:(NSString *)theName {
    return [_childNodesByName objectForKey:theName];
}
- (uint32_t)version {
    return _version;
}
- (uint64_t)itemSize {
    uint64_t ret = 0;
    for (PlanNode *node in [_childNodesByName allValues]) {
        ret += [node itemSize];
    }
    return ret;
}
- (uint64_t)containedFiles {
    uint64_t ret = 0;
    for (PlanNode *node in [_childNodesByName allValues]) {
        ret += [node containedFiles];
    }
    return ret;
}
@end

