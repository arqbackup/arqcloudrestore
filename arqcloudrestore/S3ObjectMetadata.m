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

#import "S3ObjectMetadata.h"
#import "RFC822DateParser.h"


@interface S3ObjectMetadata() {
    NSString *_path;
    NSDate *_lastModified;
    long _size;
    NSString *_storageClass;
    NSString *_itemId;
}
@end


@implementation S3ObjectMetadata
- (id)initWithS3BucketName:(NSString *)s3BucketName node:(NSXMLNode *)node error:(NSError * __autoreleasing *)error {
    if (error != NULL) {
        *error = nil;
    }
    if (self = [super init]) {
        NSArray *nodes = [node nodesForXPath:@"Key" error:error];
        if (!nodes) {
            return nil;
        }
        NSXMLNode *keyNode = [nodes objectAtIndex:0];
        _path = [[NSString alloc] initWithFormat:@"/%@/%@", s3BucketName, [keyNode stringValue]];
        nodes = [node nodesForXPath:@"LastModified" error:error];
        if (!nodes) {
            return nil;
        }
        NSXMLNode *lastModifiedNode = [nodes objectAtIndex:0];
        _lastModified = [[RFC822DateParser shared] parseDateString:[lastModifiedNode stringValue] error:error];
        if (_lastModified == nil) {
            return nil;
        }
        nodes = [node nodesForXPath:@"Size" error:error];
        if (!nodes) {
            return nil;
        }
        NSXMLNode *sizeNode = [nodes objectAtIndex:0];
        NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
        _size = [[numberFormatter numberFromString:[sizeNode stringValue]] longValue];
        nodes = [node nodesForXPath:@"StorageClass" error:error];
        if (!nodes) {
            return nil;
        }
        if ([nodes count] == 0) {
            _storageClass = @"STANDARD";
        } else {
            NSXMLNode *storageClassNode = [nodes objectAtIndex:0];
            _storageClass = [storageClassNode stringValue];
        }
    }
    return self;
}
- (id)initWithPath:(NSString *)thePath lastModified:(NSDate *)theLastModified size:(long)theSize storageClass:(NSString *)theStorageClass {
    return [self initWithPath:thePath lastModified:theLastModified size:theSize storageClass:theStorageClass itemId:nil];
}
- (id)initWithPath:(NSString *)thePath lastModified:(NSDate *)theLastModified size:(long)theSize storageClass:(NSString *)theStorageClass itemId:(NSString  *)theItemId {
    if (self = [super init]) {
        _path = thePath;
        _lastModified = theLastModified;
        _size = theSize;
        _storageClass = theStorageClass;
        _itemId = theItemId;
    }
    return self;
}
- (NSString *)path {
    return _path;
}
- (NSDate *)lastModified {
    return _lastModified;
}
- (long)size {
    return _size;
}
- (NSString *)storageClass {
    return _storageClass;
}
- (NSString *)itemId {
    return _itemId;
}

#pragma mark NSObject
- (NSString *)description {
    return [NSString stringWithFormat:@"<S3ObjectMetadata: %18s; %12ld bytes; %@", 
            [_storageClass UTF8String], 
            _size, 
            _path];
}
@end
