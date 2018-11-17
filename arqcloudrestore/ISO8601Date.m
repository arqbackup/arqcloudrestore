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

#import "ISO8601Date.h"


@interface ISO8601Date() {
    NSDateFormatter *_outputFormatter;
    NSLock *_lock;
}
@end


@implementation ISO8601Date
+ (ISO8601Date *)shared {
    static id sharedObject = nil;
    static dispatch_once_t sharedObjectOnce = 0;
    dispatch_once(&sharedObjectOnce, ^{
        sharedObject = [[self alloc] init];
    });
    return sharedObject;
}

- (id)init {
    if (self = [super init]) {
        _outputFormatter = [self newDateFormatterWithFormat:@"yyyyMMdd'T'HHmmss'Z'"];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (NSString *)errorDomain {
    return @"ISO8601DateErrorDomain";
}
- (NSString *)basicDateTimeStringFromDate:(NSDate *)theDate {
    [_lock lock];
    NSString *ret = [self lockedBasicDateTimeStringFromDate:theDate];
    [_lock unlock];
    return ret;
}
- (NSString *)lockedBasicDateTimeStringFromDate:(NSDate *)theDate {
    return [_outputFormatter stringFromDate:theDate];
}


#pragma mark internal
- (NSDateFormatter *)newDateFormatterWithFormat:(NSString *)theFormat {
    NSDateFormatter *ret = [[NSDateFormatter alloc] init];
    [ret setDateFormat:theFormat];
    
    NSLocale *usLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    if (usLocale != nil) {
        [ret setLocale:usLocale];
    } else {
        HSLogWarn(@"no en_US locale installed");
    }
    [ret setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    NSCalendar *gregorianCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    [ret setCalendar:gregorianCalendar];
    return ret;
}
@end
