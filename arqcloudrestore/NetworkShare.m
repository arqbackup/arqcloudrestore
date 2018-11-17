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

#import "NetworkShare.h"
#import "NSObject_extra.h"


@implementation NetworkShare

- (id)initWithJSON:(NSDictionary *)theJSON {
    if (self = [super init]) {
        self.path = [theJSON objectForKey:@"path"];
        self.username = [theJSON objectForKey:@"username"];
        self.password = [theJSON objectForKey:@"password"];
    }
    return self;
}
+ (NSString *)errorDomain {
    return @"NetworkShareErrorDomain";
}


#pragma mark NSCopying
- (id)copyWithZone:(nullable NSZone *)zone {
    NetworkShare *ret = [[NetworkShare alloc] init];
    ret.path = self.path;
    ret.username = self.username;
    ret.password = self.password;
    return ret;
}


#pragma mark NSObject
- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[NetworkShare class]]) {
        return NO;
    }
    NetworkShare *other = (NetworkShare *)object;
    if (![NSObject equalObjects:self.path and:other.path]) {
        return NO;
    }
    if (![NSObject equalObjects:self.username and:other.username]) {
        return NO;
    }
    if (![NSObject equalObjects:self.password and:other.password]) {
        return NO;
    }
    return YES;
}
- (NSUInteger)hash {
    return [self.path hash];
}
@end
