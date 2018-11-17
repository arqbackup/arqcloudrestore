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

#import "WasabiRegion.h"
#import "NSObject_extra.h"


@interface WasabiRegion() {
    NSString *_regionName;
    NSString *_s3LocationConstraint;
    NSString *_s3Hostname;
    NSString *_displayName;
}
@end


@implementation WasabiRegion
+ (NSArray *)allRegions {
    return [NSArray arrayWithObjects:[WasabiRegion usEast1], [WasabiRegion usWest1], nil];
}
+ (WasabiRegion *)regionWithS3Endpoint:(NSURL *)theEndpoint {
    for (WasabiRegion *region in [WasabiRegion allRegions]) {
        if ([[[region s3Endpoint] host] isEqualToString:[theEndpoint host]]) {
            return region;
        }
    }
    return nil;
}
+ (WasabiRegion *)regionWithName:(NSString *)theName {
    if (theName == nil) {
        return nil;
    }
    for (WasabiRegion *region in [WasabiRegion allRegions]) {
        if ([[region regionName] isEqualToString:theName]) {
            return region;
        }
    }
    return nil;
}
+ (WasabiRegion *)regionWithLocation:(NSString *)theLocation {
    if ([theLocation length] == 0) {
        return [WasabiRegion usEast1];
    }
    
    for (WasabiRegion *region in [WasabiRegion allRegions]) {
        if ([NSObject equalObjects:[[region s3LocationConstraint] lowercaseString] and:[theLocation lowercaseString]]) {
            return region;
        }
    }
    return nil;
}
+ (WasabiRegion *)usEast1 {
    return [[WasabiRegion alloc] initWithRegionName:@"us-east-1"
                               s3LocationConstraint:nil
                                         s3Hostname:@"s3.wasabisys.com"
                                        displayName:@"US East Coast (Virginia)"];
}
+ (WasabiRegion *)usWest1 {
    return [[WasabiRegion alloc] initWithRegionName:@"us-west-1"
                               s3LocationConstraint:@"us-west-1"
                                         s3Hostname:@"s3.us-west-1.wasabisys.com"
                                        displayName:@"US West Coast (Oregon)"];
}

- (WasabiRegion *)initWithRegionName:(NSString *)theRegionName
                s3LocationConstraint:(NSString *)theS3LocationConstraint
                          s3Hostname:(NSString *)theS3Hostname
                         displayName:(NSString *)theDisplayName {
    if (self = [super init]) {
        _regionName = theRegionName;
        _s3LocationConstraint = theS3LocationConstraint;
        _s3Hostname = theS3Hostname;
        _displayName = theDisplayName;
    }
    return self;
}
- (NSURL *)s3Endpoint {
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://%@", _s3Hostname]];
}
- (NSString *)regionName {
    return _regionName;
}
- (NSString *)s3LocationConstraint {
    return _s3LocationConstraint;
}
- (NSString *)s3Hostname {
    return _s3Hostname;
}
- (NSString *)displayName {
    return _displayName;
}

// This is used in the start-trial 'options' dialog:
- (NSString *)description {
    return _displayName;
}



#pragma mark NSCopying
- (instancetype)copyWithZone:(NSZone *)zone {
    return [[WasabiRegion alloc] initWithRegionName:_regionName
                               s3LocationConstraint:_s3LocationConstraint
                                         s3Hostname:_s3Hostname
                                        displayName:_displayName];
}
@end
