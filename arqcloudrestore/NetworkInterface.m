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

#import <SystemConfiguration/SystemConfiguration.h>
#import "NetworkInterface.h"
#import "NSObject_extra.h"


@implementation NetworkInterface
- (instancetype)initWithBSDName:(NSString *)theBSDName displayName:(NSString *)theDisplayName interfaceType:(NSString *)theInterfaceType {
    if (self = [super init]) {
        _bsdName = theBSDName;
        _displayName = theDisplayName;
        _interfaceType = theInterfaceType;
    }
    return self;
}
- (instancetype)initWithJSON:(NSDictionary *)theJSON {
    if (self = [super init]) {
        _bsdName = [theJSON objectForKey:@"bsdName"];
        _displayName = [theJSON objectForKey:@"displayName"];
        _interfaceType = [theJSON objectForKey:@"interfaceType"];
    }
    return self;
}

- (BOOL)isWiFi {
    return [_interfaceType isEqualToString:(NSString *)kSCNetworkInterfaceTypeIEEE80211];
}
- (NSDictionary *)toJSON {
    NSMutableDictionary *ret = [NSMutableDictionary dictionary];
    [ret setObject:_bsdName forKey:@"bsdName"];
    [ret setObject:_displayName forKey:@"displayName"];
    [ret setObject:_interfaceType forKey:@"interfaceType"];
    return ret;
}

#pragma mark NSCopying
- (id)copyWithZone:(NSZone *)zone {
    return [[NetworkInterface alloc] initWithBSDName:_bsdName displayName:_displayName interfaceType:_interfaceType];
}


#pragma mark NSObject
- (NSString *)description {
    return [NSString stringWithFormat:@"<NetworkInterface: %@, %@, %@>", _bsdName, _displayName, _interfaceType];
}
- (BOOL)isEqual:(id)object {
    if (object == self) {
        return YES;
    }
    if (object == nil || ![object isKindOfClass:[self class]]) {
        return NO;
    }
    NetworkInterface *intf = (NetworkInterface *)object;
    return [NSObject equalObjects:[intf bsdName] and:_bsdName] && [NSObject equalObjects:[intf displayName] and:_displayName] && [NSObject equalObjects:[intf interfaceType] and:_interfaceType];
}
- (NSUInteger)hash {
    return [_bsdName hash];
}
@end
