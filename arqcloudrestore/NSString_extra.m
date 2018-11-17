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

#import "NSString_extra.h"


static NSString *PATH_PATTERN = @"^(.+)(\\.\\w+)$";


@implementation NSString (extra)
+ (NSString *)hexStringWithData:(NSData *)data {
    return [NSString hexStringWithBytes:[data bytes] length:(unsigned int)[data length]];
}
+ (NSString *)hexStringWithBytes:(const unsigned char *)bytes length:(unsigned int)length {
    if (length == 0) {
        return [NSString string];
    }

    char *buf = (char *)malloc(length * 2 + 1);
    for (unsigned int i = 0; i < length; i++) {
        unsigned char c = bytes[i];
        
        unsigned char c1 = (c >> 4) & 0x0f;
        if (c1 > 9) {
            c1 = 'a' + c1 - 10;
        } else {
            c1 = '0' + c1;
        }

        unsigned char c2 = (c & 0xf);
        if (c2 > 9) {
            c2 = 'a' + c2 - 10;
        } else {
            c2 = '0' + c2;
        }
        
        buf[i*2] = c1;
        buf[i*2+1] = c2;
    }
    NSString *ret = [[NSString alloc] initWithBytes:buf length:length*2 encoding:NSUTF8StringEncoding];
    free(buf);
    return ret;
}
- (NSString *)slashed {
    if ([self hasSuffix:@"/"]) {
        return self;
    }
    return [self stringByAppendingString:@"/"];
}

@end
