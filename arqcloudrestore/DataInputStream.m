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

#import "DataInputStream.h"
#import "InputStreams.h"


@interface DataInputStream() {
    NSData *_data;
    NSString *_description;
    NSUInteger _pos;
}
@end

@implementation DataInputStream
- (id)initWithData:(NSData *)theData description:(NSString *)theDescription {
    if (self = [super init]) {
        _data = theData;
        _description = theDescription;
    }
    return self;
}
- (id)initWithData:(NSData *)theData description:(NSString *)theDescription offset:(unsigned long long)theOffset length:(unsigned long long)theLength {
    if (self = [super init]) {
        _data = [theData subdataWithRange:NSMakeRange((NSUInteger)theOffset, (NSUInteger)theLength)];
        _description = theDescription;
    }
    return self;
}


#pragma mark InputStream protocol
- (NSInteger)read:(unsigned char *)buf bufferLength:(NSUInteger)bufferLength error:(NSError * __autoreleasing *)error {
    NSInteger ret = 0;
    NSInteger remaining = [_data length] - _pos;
    if (remaining > 0) {
        ret = remaining > bufferLength ? bufferLength : remaining;
        unsigned char *bytes = (unsigned char *)[_data bytes];
        memcpy(buf, bytes + _pos, ret);
        _pos += ret;
    }
    return ret;
}
- (NSData *)slurp:(NSError * __autoreleasing *)error {
    NSData *ret = nil;
    if (_pos == 0) {
        ret = _data;
    } else if (_pos >= [_data length]) {
        ret = [NSData data];
    } else {
        ret = [_data subdataWithRange:NSMakeRange(_pos, [_data length] - _pos)];
        _pos = [_data length];
    }
    return ret;
}
- (BOOL)slurpIntoBuffer:(NSMutableData *)theBuffer error:(NSError * __autoreleasing *)error {
    return [InputStreams slurp:self intoBuffer:theBuffer error:error];
}


#pragma mark NSObject
- (NSString *)description {
    return [NSString stringWithFormat:@"<DataInputStream: %ld bytes: %@>", (unsigned long)[_data length], _description];
}
@end
