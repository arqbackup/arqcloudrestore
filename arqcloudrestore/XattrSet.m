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

#include <sys/xattr.h>
#import "XattrSet.h"
#import "IntegerIO.h"
#import "StringIO.h"
#import "DataIO.h"
#import "DataInputStream.h"
#import "BufferedInputStream.h"


#define HEADER "XATTRSET"
#define HEADER_LENGTH (8)


@interface XattrSet() {
    NSMutableDictionary *_xattrs;
}
@end


@implementation XattrSet
- (instancetype)initWithPath:(NSString *)thePath error:(NSError * __autoreleasing *)error {
    if (self  = [super init]) {
        _xattrs = [[NSMutableDictionary alloc] init];
        if (![self loadFromPath:thePath error:error]) {
            return nil;
        }
    }
    return self;
}
- (instancetype)initWithData:(NSData *)theData error:(NSError * __autoreleasing *)error {
    if (self = [super init]) {
        _xattrs = [[NSMutableDictionary alloc] init];
        DataInputStream *dis = [[DataInputStream alloc] initWithData:theData description:@"xattrs"];
        BufferedInputStream *bis = [[BufferedInputStream alloc] initWithUnderlyingStream:dis];
        
        unsigned char *buf = (unsigned char *)malloc(HEADER_LENGTH);
        if (![bis readExactly:HEADER_LENGTH into:buf error:error]) {
            free(buf);
            return nil;
        }
        if (strncmp((const char *)buf, HEADER, HEADER_LENGTH)) {
            free(buf);
            SETNSERROR_ARC([self errorDomain], -1, @"invalid XattrSet header");
            return nil;
        }
        free(buf);
        
        uint64_t count = 0;
        if (![IntegerIO readUInt64:&count from:bis error:error]) {
            return nil;
        }
        for (uint64_t i = 0; i < count; i++) {
            NSString *name = nil;
            NSData *data = nil;
            if (![StringIO read:&name from:bis error:error]) {
                return nil;
            }
            if (![DataIO read:&data from:bis error:error]) {
                return nil;
            }
            [_xattrs setObject:data forKey:name];
        }
    }
    return self;
}
- (NSString *)errorDomain {
    return @"XattrSetErrorDomain";
}
- (NSUInteger)count {
    return [_xattrs count];
}
- (NSArray *)names {
    return [_xattrs allKeys];
}
- (NSData *)valueForName:(NSString *)theName {
    return [_xattrs objectForKey:theName];
}


#pragma mark internal
- (BOOL)loadFromPath:(NSString *)thePath error:(NSError * __autoreleasing *)error {
    const char *cpath = [thePath fileSystemRepresentation];
    ssize_t xattrsize = listxattr(cpath, NULL, 0, XATTR_NOFOLLOW);
    if (xattrsize == -1) {
        int errnum = errno;
        HSLogError(@"listxattr(%@) error %d: %s", thePath, errnum, strerror(errnum));
        SETNSERROR_ARC(NSPOSIXErrorDomain, errnum, @"failed to get size of extended attributes of %@: %s", thePath, strerror(errnum));
        
        // One customer with an encfs volume gets not-found errors on symlinks on that volume, even though the lstat succeeds!? So this could happen:
        if (errnum == ENOENT) {
            SETNSERROR_ARC([self errorDomain], ERROR_NOT_FOUND, @"%@ not found", thePath);
        }
        
        return NO;
    }
    
    if (xattrsize > 0) {
        char *xattrbuf = (char *)malloc(xattrsize);
        xattrsize = listxattr(cpath, xattrbuf, xattrsize, XATTR_NOFOLLOW);
        if (xattrsize == -1) {
            int errnum = errno;
            HSLogError(@"listxattr(%@) error %d: %s", thePath, errnum, strerror(errnum));
            SETNSERROR_ARC(NSPOSIXErrorDomain, errnum, @"failed to list extended attributes of %@ (%ld bytes): %s", thePath, xattrsize, strerror(errnum));
            free(xattrbuf);
            return NO;
        }
        for (char *name = xattrbuf; name < (xattrbuf + xattrsize); name += strlen(name) + 1) {
            NSString *theName = [NSString stringWithUTF8String:name];
            ssize_t valuesize = getxattr(cpath, name, NULL, 0, 0, XATTR_NOFOLLOW);
            if (valuesize == -1) {
                int errnum = errno;
                HSLogError(@"skipping xattrs %s of %s: error %d: %s", name, cpath, errnum, strerror(errnum));
            } else if (valuesize > 0) {
                void *value = malloc(valuesize);
                if (getxattr(cpath, name, value, valuesize, 0, XATTR_NOFOLLOW) == -1) {
                    int errnum = errno;
                    HSLogError(@"skipping xattrs %s of %s: error %d: %s", name, cpath, errnum, strerror(errnum));
                } else {
                    [_xattrs setObject:[NSData dataWithBytes:value length:valuesize] forKey:theName];
                }
                free(value);
            } else {
                [_xattrs setObject:[NSData data] forKey:theName];
            }
        }
        free(xattrbuf);
    }
    return YES;
}
@end
