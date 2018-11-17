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

#include "lz4.h"
#import "LZ4Compressor.h"


@interface LZ4Compressor() {
    dispatch_queue_t _serialQueue;
}
@end


@implementation LZ4Compressor
+ (LZ4Compressor *)shared {
    static id sharedObject = nil;
    static dispatch_once_t sharedObjectOnce = 0;
    dispatch_once(&sharedObjectOnce, ^{
        sharedObject = [[self alloc] init];
    });
    return sharedObject;
}

- (id)init {
    if (self = [super init]) {
        _serialQueue = dispatch_queue_create("LZ4Compressor", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSString *)errorDomain {
    return @"LZ4ErrorDomain";
}
- (NSData *)lz4Deflate:(NSData *)data error:(NSError * __autoreleasing *)error {
    return [self lz4DeflateBytes:(unsigned char *)[data bytes] length:[data length] error:error];
}
- (NSData *)lz4DeflateBytes:(unsigned char *)bytes length:(NSUInteger)length error:(NSError * __autoreleasing *)error {
    if (length == 0) {
        return [NSData data];
    }
    
    int outbuflen = LZ4_compressBound((int)length) + 4;
    NSMutableData *ret = [[NSMutableData alloc] initWithLength:outbuflen];
    unsigned char *outbuf = (unsigned char *)[ret mutableBytes];
    
    __block int deflatedlen = -1;
    dispatch_sync(_serialQueue, ^{
        deflatedlen = [self lockedLZ4DeflateBytes:bytes length:length intoBuffer:outbuf length:outbuflen error:error];        
    });
    if (deflatedlen < 0) {
        return nil;
    }
    [ret setLength:deflatedlen];
    return ret;
}
- (int)lz4DeflateBytes:(unsigned char *)bytes length:(NSUInteger)length intoBuffer:(unsigned char *)outbuf length:(NSUInteger)outbuflen error:(NSError * __autoreleasing *)error {
    __block int ret = -1;
    dispatch_sync(_serialQueue, ^{
        ret = [self lockedLZ4DeflateBytes:bytes length:length intoBuffer:outbuf length:outbuflen error:error];        
    });
    return ret;    
}
- (NSData *)lz4Inflate:(NSData *)data error:(NSError * __autoreleasing *)error {
    return [self lz4InflateBytes:(unsigned char *)[data bytes] length:[data length] error:error];
}
- (NSData *)lz4InflateBytes:(unsigned char *)bytes length:(NSUInteger)length error:(NSError * __autoreleasing *)error {
    if (length < 5) {
        SETNSERROR_ARC([self errorDomain], -1, @"not enough bytes for an lz4-compressed buffer");
        return nil;
    }
    uint32_t nboSize = 0;
    memcpy(&nboSize, bytes, 4);
    int originalSize = OSSwapBigToHostInt32(nboSize);
    if (originalSize < 0) {
        SETNSERROR_ARC([self errorDomain], -1, @"invalid size for LZ4-compressed %ld-byte data chunk: %d", length, originalSize);
        return nil;
    }

    NSMutableData *ret = [NSMutableData dataWithLength:originalSize];
    __block int inflated = 0;
    dispatch_sync(_serialQueue, ^{
        inflated = [self lockedLZ4InflateBytes:bytes length:length originalSize:originalSize intoBuffer:(unsigned char *)[ret mutableBytes] length:[ret length] error:error];
    });
    if (inflated < 0) {
        return nil;
    }
    return ret;
}
- (int)lz4InflateBytes:(unsigned char *)bytes length:(NSUInteger)length intoBuffer:(unsigned char *)outbuf length:(NSUInteger)outbuflen error:(NSError * __autoreleasing *)error {
    if (length < 5) {
        SETNSERROR_ARC([self errorDomain], -1, @"not enough bytes for an lz4-compressed buffer");
        return -1;
    }
    uint32_t nboSize = 0;
    memcpy(&nboSize, bytes, 4);
    int originalSize = OSSwapBigToHostInt32(nboSize);
    if (originalSize < 0) {
        SETNSERROR_ARC([self errorDomain], -1, @"invalid size for LZ4-compressed %ld-byte data chunk: %d", length, originalSize);
        return -1;
    }
    if (outbuflen < originalSize) {
        SETNSERROR_ARC([self errorDomain], -1, @"lz4 inflate: output buffer length %ld is too small (must be at least %d)", outbuflen, originalSize);
        return -1;
    }    
    
    __block int inflated = 0;
    dispatch_sync(_serialQueue, ^{
        inflated = [self lockedLZ4InflateBytes:bytes length:length originalSize:originalSize intoBuffer:outbuf length:outbuflen error:error];
    });
    return inflated;
}


- (int)lockedLZ4DeflateBytes:(unsigned char *)bytes length:(NSUInteger)length intoBuffer:(unsigned char *)outbuf length:(NSUInteger)outbuflen error:(NSError * __autoreleasing *)error {
    if (length > (NSUInteger)INT_MAX) {
        SETNSERROR_ARC([self errorDomain], -1, @"length larger than INT_MAX");
        return -1;
    }
    
    int originalSize = (int)length;
    if (originalSize == 0) {
        return 0;
    }
    
    int destSize = LZ4_compressBound((int)length);
    if (outbuflen < (destSize + 4)) {
        SETNSERROR_ARC([self errorDomain], -1, @"lz4 deflate: output buffer length %ld is too small (must be at least %d)", outbuflen, (destSize + 4));
        return -1;
    }
    
    int compressed = LZ4_compress_default((const char *)bytes, (char *)(outbuf + 4), (int)length, (int)outbuflen);
    if (compressed == 0) {
        SETNSERROR_ARC([self errorDomain], -1, @"LZ4_compress_default failed");
        return -1;
    }
    uint32_t nboSize = OSSwapHostToBigInt32(originalSize);
    memcpy(outbuf, &nboSize, 4);
    return compressed + 4;
}

- (int)lockedLZ4InflateBytes:(unsigned char *)bytes length:(NSUInteger)length originalSize:(int)theOriginalSize intoBuffer:(unsigned char *)outbuf length:(NSUInteger)outbuflen error:(NSError * __autoreleasing *)error {
    NSAssert(length <= INT_MAX, @"compressed size may not be larger than INT_MAX");
    
    int compressedSize = (int)length - 4;
    int inflatedLen = LZ4_decompress_safe((const char *)(bytes + 4), (char *)outbuf, compressedSize, (int)outbuflen);
    if (inflatedLen != theOriginalSize) {
        HSLogDebug(@"LZ4_decompress error: returned %d (expected %d)", inflatedLen, theOriginalSize);
        SETNSERROR_ARC([self errorDomain], -1, @"LZ4_decompress failed");
        return -1;
    }
    return inflatedLen;
}
@end
