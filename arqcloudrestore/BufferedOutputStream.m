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

#import "BufferedOutputStream.h"
#import "DataOutputStream.h"
#import "FileOutputStream.h"

#define MY_BUF_SIZE (4096)


@interface BufferedOutputStream() {
    id <OutputStream> _os;
    unsigned char *_buf;
    NSUInteger _pos;
    NSUInteger _buflen;
    uint64_t _totalBytesWritten;
    BOOL _errorOccurred;
}
@end


@implementation BufferedOutputStream
+ (NSString *)errorDomain {
    return @"BufferedOutputStreamErrorDomain";
}
- (id)initWithMutableData:(NSMutableData *)theMutableData {
    DataOutputStream *dos = [[DataOutputStream alloc] initWithMutableData:theMutableData];
    return [self initWithUnderlyingOutputStream:dos];
}
- (id)initWithPath:(NSString *)thePath append:(BOOL)isAppend {
    FileOutputStream *fos = [[FileOutputStream alloc] initWithPath:thePath append:isAppend];
    return [self initWithUnderlyingOutputStream:fos];
}
- (id)initWithUnderlyingOutputStream:(id <OutputStream>)theOS {
    if (self = [super init]) {
        _os = theOS;
        _buflen = MY_BUF_SIZE;
        _buf = (unsigned char *)malloc(_buflen);
    }
    return self;
}
- (void)dealloc {
    if (_pos > 0 && !_errorOccurred) {
        HSLogWarn(@"BufferedOutputStream pos > 0 -- flush wasn't called?!");
    }
    free(_buf);
}
- (BOOL)setBufferSize:(NSUInteger)size error:(NSError * __autoreleasing *)error {
    if (![self flush:error]) {
        return NO;
    }
    _buf = realloc(_buf, size);
    _buflen = size;
    return YES;
}
- (BOOL)flush:(NSError * __autoreleasing *)error {
    NSAssert(_os != nil, @"write: os can't be nil");
    NSUInteger index = 0;
    while (index < _pos) {
        NSInteger written = [_os write:&_buf[index] length:(_pos - index) error:error];
        if (written < 0) {
            _errorOccurred = YES;
            return NO;
        }
        if (written == 0) {
            SETNSERROR_ARC([BufferedOutputStream errorDomain], ERROR_EOF, @"0 bytes written to underlying stream %@", [_os description]);
            _errorOccurred = YES;
            return NO;
        }
        index += written;
    }
    _pos = 0;
    return YES;
}
- (BOOL)writeFully:(const unsigned char *)theBuf length:(NSUInteger)len error:(NSError * __autoreleasing *)error {
    NSUInteger totalWritten = 0;
    while (totalWritten < len) {
        NSInteger writtenThisTime = [self write:&theBuf[totalWritten] length:(len - totalWritten) error:error];
        if (writtenThisTime < 0) {
            return NO;
        }
        totalWritten += (NSUInteger)writtenThisTime;
    }
    NSAssert(totalWritten == len, @"writeFully must return as all bytes written");
    return YES;
}

#pragma mark OutputStream
- (NSInteger)write:(const unsigned char *)theBuf length:(NSUInteger)theLen error:(NSError * __autoreleasing *)error {
    NSAssert(_os != nil, @"write: os can't be nil");
    if ((_pos + theLen) > _buflen) {
        if (![self flush:error]) {
            _errorOccurred = YES;
            return -1;
        }
    }
    if (theLen > _buflen) {
        NSUInteger written = 0;
        // Loop to write theBuf directly to the underlying stream, since it won't fit in our buffer.
        while (written < theLen) {
            NSInteger writtenThisTime = [_os write:&theBuf[written] length:(theLen - written) error:error];
            if (writtenThisTime < 0) {
                _errorOccurred = YES;
                return -1;
            }
            if (writtenThisTime == 0) {
                SETNSERROR_ARC([BufferedOutputStream errorDomain], ERROR_EOF, @"0 bytes written to underlying stream");
                _errorOccurred = YES;
                return -1;
            }
            written += writtenThisTime;
        }
    } else {
        memcpy(_buf + _pos, theBuf, theLen);
        _pos += theLen;
    }
    _totalBytesWritten += theLen;
    return theLen;
}
- (unsigned long long)bytesWritten {
    return _totalBytesWritten;
}

#pragma mark NSObject
- (NSString *)description {
    return [NSString stringWithFormat:@"<BufferedOutputStream underlying=%@>", _os];
}
@end
