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

#import "WriteBuffer.h"


@interface WriteBuffer() {
    unsigned char *_buffer;
    NSUInteger _bufferLength;
    NSMutableData *_data;
    NSUInteger _pos;
}
@end


@implementation WriteBuffer

- (instancetype)init {
    if (self = [super init]) {
        _data = [[NSMutableData alloc] init];
    }
    return self;
}
- (instancetype)initWithInternalBuffer:(unsigned char *)theBuffer length:(NSUInteger)theLength {
    if (self = [super init]) {
        _buffer = theBuffer;
        _bufferLength = theLength;
        _pos = 0;
    }
    return self;
}
- (void)reset {
    [_data setLength:0];
    _pos = 0;
}
- (void)appendData:(NSData *)theData {
    if (_data == nil) {
        [theData enumerateByteRangesUsingBlock:^(const void * _Nonnull bytes, NSRange byteRange, BOOL * _Nonnull stop) {
            NSUInteger offset = self->_pos + byteRange.location;
            NSAssert((offset + byteRange.length) <= self->_bufferLength, @"goes beyond buffer!");
            memcpy(self->_buffer + offset, bytes, byteRange.length);
        }];
        _pos += [theData length];
    } else {
        [_data appendData:theData];
    }
}
- (void)appendBytes:(unsigned char *)bytes length:(NSUInteger)theLength {
    if (_data == nil) {
        NSAssert((_pos + theLength) <= _bufferLength, @"goes beyond buffer!");
        memcpy(_buffer + _pos, bytes, theLength);
        _pos += theLength;
    } else {
        [_data appendBytes:bytes length:theLength];
    }
}
- (unsigned char *)bytes {
    if (_data == nil) {
        return _buffer;
    }
    return (unsigned char *)[_data bytes];
}
- (NSUInteger)length {
    if (_data == nil) {
        return _pos;
    }
    return [_data length];
}
- (NSData *)toData {
    if (_data == nil) {
        return [NSData dataWithBytes:_buffer length:_pos];
    }
    return _data;
}
@end
