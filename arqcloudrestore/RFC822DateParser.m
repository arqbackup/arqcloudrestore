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

#import "RFC822DateParser.h"


@interface RFC822DateParser() {
    NSLock *_lock;
    NSDateFormatter *_formatter;
}
@end


@implementation RFC822DateParser
+ (RFC822DateParser *)shared {
    static id sharedObject = nil;
    static dispatch_once_t sharedObjectOnce = 0;
    dispatch_once(&sharedObjectOnce, ^{
        sharedObject = [[self alloc] init];
    });
    return sharedObject;
}

- (id)init {
    if (self = [super init]) {
        _lock = [[NSLock alloc] init];
        NSLocale *en_US_POSIX = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        _formatter = [[NSDateFormatter alloc] init];
        [_formatter setLocale:en_US_POSIX];
        [_formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    }
    return self;
}
- (NSString *)errorDomain {
    return @"RFC822DateParserErrorDomain";
}

- (NSDate *)parseDateString:(NSString *)str error:(NSError * __autoreleasing *)error {
    // Use a lock because NSDateFormatter isn't reentrant.
    [_lock lock];
    NSDate *ret = [self lockedParseDateString:str error:error];
    [_lock unlock];
    return ret;
}
- (NSDate *)lockedParseDateString:(NSString *)str error:(NSError * __autoreleasing *)error {
    NSDate *date = nil;
    NSString *RFC822String = [[NSString stringWithString:str] uppercaseString];
    if ([RFC822String rangeOfString:@","].location != NSNotFound) {
        if (!date) { // Sun, 19 May 2002 15:21:36 GMT
            [_formatter setDateFormat:@"EEE, d MMM yyyy HH:mm:ss zzz"];
            date = [_formatter dateFromString:RFC822String];
        }
        if (!date) { // Sun, 19 May 2002 15:21 GMT
            [_formatter setDateFormat:@"EEE, d MMM yyyy HH:mm zzz"];
            date = [_formatter dateFromString:RFC822String];
        }
        if (!date) { // Sun, 19 May 2002 15:21:36
            [_formatter setDateFormat:@"EEE, d MMM yyyy HH:mm:ss"];
            date = [_formatter dateFromString:RFC822String];
        }
        if (!date) { // Sun, 19 May 2002 15:21
            [_formatter setDateFormat:@"EEE, d MMM yyyy HH:mm"];
            date = [_formatter dateFromString:RFC822String];
        }
    } else {
        if (!date) { // 19 May 2002 15:21:36 GMT
            [_formatter setDateFormat:@"d MMM yyyy HH:mm:ss zzz"];
            date = [_formatter dateFromString:RFC822String];
        }
        if (!date) { // 19 May 2002 15:21 GMT
            [_formatter setDateFormat:@"d MMM yyyy HH:mm zzz"];
            date = [_formatter dateFromString:RFC822String];
        }
        if (!date) { // 19 May 2002 15:21:36
            [_formatter setDateFormat:@"d MMM yyyy HH:mm:ss"];
            date = [_formatter dateFromString:RFC822String];
        }
        if (!date) { // 19 May 2002 15:21
            [_formatter setDateFormat:@"d MMM yyyy HH:mm"];
            date = [_formatter dateFromString:RFC822String];
        }
    }
    if (!date) {
        SETNSERROR_ARC([self errorDomain], -1, @"failed to parse RFC822 date %@", str);
    }
    return date;
}
@end
