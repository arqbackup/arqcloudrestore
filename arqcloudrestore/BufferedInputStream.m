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

#import "BufferedInputStream.h"
#import "InputStream.h"
#import "InputStreams.h"

#define MY_BUF_SIZE (4096)


@interface BufferedInputStream() {
    id <InputStream> _underlyingStream;
    unsigned char *_buf;
    NSUInteger _pos;
    NSUInteger _len;
    uint64_t _totalBytesReceived;
}
@end


@implementation BufferedInputStream
+ (NSString *)errorDomain {
    return @"BufferedInputStreamErrorDomain";
}
- (id)initWithUnderlyingStream:(id <InputStream>)theUnderlyingStream {
    if (self = [super init]) {
        _underlyingStream = theUnderlyingStream;
        _buf = (unsigned char *)malloc(MY_BUF_SIZE);
        _pos = 0;
        _len = 0;
    }
    return self;
}
- (void)dealloc {
    free(_buf);
}
- (int)readByte:(NSError * __autoreleasing *)error {
    if ((_len - _pos) == 0) {
        NSInteger myRet = [_underlyingStream read:_buf bufferLength:MY_BUF_SIZE error:error];
        if (myRet < 0) {
            return -1;
        }
        _pos = 0;
        _len = myRet;
    }
    if ((_len - _pos) == 0) {
        SETNSERROR_ARC([BufferedInputStream errorDomain], ERROR_EOF, @"%@ EOF", self);
        return -1;
    }
    int ret = _buf[_pos++];
    _totalBytesReceived++;
    return ret;
}
- (NSData *)readExactly:(NSUInteger)exactLength error:(NSError * __autoreleasing *)error {
    NSMutableData *data = [NSMutableData data];
    if (![self readExactly:exactLength intoBuffer:data error:error]) {
        return nil;
    }
    return data;
}
- (BOOL)readExactly:(NSUInteger)exactLength intoBuffer:(NSMutableData *)theOutBuffer error:(NSError * __autoreleasing *)error {
    [theOutBuffer setLength:exactLength];
    unsigned char *dataBuf = [theOutBuffer mutableBytes];
    if (![self readExactly:exactLength into:dataBuf error:error]) {
        return NO;
    }
    return YES;
}
- (BOOL)readExactly:(NSUInteger)exactLength into:(unsigned char *)outBuf error:(NSError * __autoreleasing *)error {
    if (exactLength > 2147483648) {
        NSString *err = [NSString stringWithFormat:@"absurd length %lu requested", (unsigned long)exactLength];
        SETNSERROR_ARC(@"InputStreamErrorDomain", -1, @"%@", err);
        return NO;
    }
    NSUInteger received = 0;
    while (received < exactLength) {
        NSInteger ret = [self read:(outBuf + received) bufferLength:(exactLength - received) error:error];
        if (ret == -1) {
            return NO;
        }
        if (ret == 0) {
            SETNSERROR_ARC([BufferedInputStream errorDomain], ERROR_EOF, @"%@ EOF after %lu of %lu bytes received", self, (unsigned long)received, (unsigned long)exactLength);
            return NO;
        }
        received += ret;
    }
    return YES;
}
- (NSString *)readLineWithCRLFWithMaxLength:(NSUInteger)maxLength error:(NSError * __autoreleasing *)error {
    unsigned char *lineBuf = (unsigned char *)malloc(maxLength);
    NSUInteger received = 0;
    for (;;) {
        if (received > maxLength) {
            SETNSERROR_ARC(@"InputStreamErrorDomain", -1, @"exceeded maxLength %lu before finding CRLF", (unsigned long)maxLength);
            free(lineBuf);
            return nil;
        }
        if (![self readExactly:1 into:(lineBuf + received) error:error]) {
            free(lineBuf);
            return nil;
        }
        received++;
        if (received >= 2 && lineBuf[received - 1] == '\n' && lineBuf[received - 2] == '\r') {
            break;
        }
    }
    NSString *ret = [[NSString alloc] initWithBytes:lineBuf length:received encoding:NSUTF8StringEncoding];
    free(lineBuf);
    return ret;
}
- (NSString *)readLine:(NSError * __autoreleasing *)error {
    NSMutableData *data = [NSMutableData data];
    unsigned char charBuf[1];
    NSUInteger received = 0;
    for (;;) {
        if (![self readExactly:1 into:charBuf error:error]) {
            return nil;
        }
        if (*charBuf == '\n') {
            break;
        }
        [data appendBytes:charBuf length:1];
        received++;
    }
    NSString *ret = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return ret;
}
- (uint64_t)bytesReceived {
    return _totalBytesReceived;
}


#pragma mark InputStream
- (NSInteger)read:(unsigned char *)outBuf bufferLength:(NSUInteger)outBufLen error:(NSError * __autoreleasing *)error {
    NSInteger ret = 0;
    NSUInteger remaining = _len - _pos;
    if (remaining > 0) {
        // Return bytes from my buf:
        ret = remaining > outBufLen ? outBufLen : remaining;
        memcpy(outBuf, _buf + _pos, ret);
        _pos += ret;
    } else if (outBufLen > MY_BUF_SIZE) {
        // Read direct into outBuf:
        ret = [_underlyingStream read:outBuf bufferLength:outBufLen error:error];
    } else {
        // Read into my buf and return only what's asked for.
        NSInteger myRet = [_underlyingStream read:_buf bufferLength:MY_BUF_SIZE error:error];
        if (myRet < 0) {
            return myRet;
        }
        _pos = 0;
        _len = myRet;
        if (_len > 0) {
            ret = _len > outBufLen ? outBufLen : _len;
            memcpy(outBuf, _buf, ret);
            _pos += ret;
       } else {
           ret = 0;
       }
    }
    if (ret > 0) {
        _totalBytesReceived += ret;
    }
    return ret;
}
- (NSData *)slurp:(NSError * __autoreleasing *)error {
    return [InputStreams slurp:self error:error];
}
- (BOOL)slurpIntoBuffer:(NSMutableData *)theBuffer error:(NSError * __autoreleasing *)error {
    return [InputStreams slurp:self intoBuffer:theBuffer error:error];
}


#pragma mark NSObject
- (NSString *)description {
    return [NSString stringWithFormat:@"<BufferedInputStream %@>", _underlyingStream];
}
@end
