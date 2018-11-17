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

#import "BlobDescriptor.h"
#import "StringIO.h"
#import "IntegerIO.h"


@interface BlobDescriptor() {
    NSString *_blobId;
    uint64_t _storedSize;
}
@end


@implementation BlobDescriptor
- (instancetype)initWithBlobId:(NSString *)theBlobId storedSize:(uint64_t)theStoredSize {
    if (self = [super init]) {
        _blobId = theBlobId;
        _storedSize = theStoredSize;
    }
    return self;
}
- (instancetype)initWithJSON:(NSDictionary *)theJSON {
    if (self = [super init]) {
        _blobId = [theJSON objectForKey:@"blobId"];
        _storedSize = [[theJSON objectForKey:@"storedSize"] unsignedLongLongValue];
    }
    return self;
}
- (instancetype)initWithBufferedInputStream:(BufferedInputStream *)theBIS error:(NSError * __autoreleasing *)error {
    if (self = [super init]) {
        NSString *blobId = nil;
        if (![StringIO read:&blobId from:theBIS error:error]) {
            return nil;
        }
        _blobId = blobId;
        if (![IntegerIO readUInt64:&_storedSize from:theBIS error:error]) {
            return nil;
        }
    }
    return self;
}
- (NSString *)blobId {
    return _blobId;
}
- (uint64_t)storedSize {
    return _storedSize;
}


#pragma mark NSObject
- (BOOL)isEqual:(id)other {
    if (other == self) {
        return YES;
    }
    if (other == nil || ![other isKindOfClass:[self class]]) {
        return NO;
    }
    BlobDescriptor *o = (BlobDescriptor *)other;
    if (![[o blobId] isEqual:[self blobId]]) {
        return NO;
    }
    if ([o storedSize] != [self storedSize]) {
        return NO;
    }
    return YES;
}
- (NSUInteger)hash {
    return [_blobId hash];
}

@end
