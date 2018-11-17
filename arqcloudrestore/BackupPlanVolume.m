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

#import "BackupPlanVolume.h"


@implementation BackupPlanVolume
- (instancetype)initWithDiskIdentifier:(NSString *)theDiskIdentifier name:(NSString *)theName mountPoint:(NSString *)theMountPoint included:(BOOL)theIncluded {
    if (self = [super init]) {
        _diskIdentifier = theDiskIdentifier;
        _name = theName;
        _mountPoint = theMountPoint;
        _included = theIncluded;
    }
    return self;
}
- (instancetype)initWithJSON:(NSDictionary *)theJSON {
    if (self = [super init]) {
        _diskIdentifier = [theJSON objectForKey:@"diskIdentifier"];
        _name = [theJSON objectForKey:@"name"];
        _mountPoint = [theJSON objectForKey:@"mountPoint"];
        _included = [[theJSON objectForKey:@"included"] boolValue];
    }
    return self;
}

- (NSDictionary *)toJSON {
    NSMutableDictionary *ret = [NSMutableDictionary dictionary];
    [ret setObject:self.diskIdentifier forKey:@"diskIdentifier"];
    [ret setObject:self.name forKey:@"name"];
    [ret setObject:self.mountPoint forKey:@"mountPoint"];
    [ret setObject:[NSNumber numberWithBool:self.included] forKey:@"included"];
    return ret;
}


#pragma mark NSCopying
- (id)copyWithZone:(NSZone *)zone {
    BackupPlanVolume *ret = [[BackupPlanVolume alloc] initWithDiskIdentifier:_diskIdentifier name:_name mountPoint:_mountPoint included:_included];
    return ret;
}


#pragma mark NSObject
- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[BackupPlanVolume class]]) {
        return NO;
    }
    BackupPlanVolume *other = (BackupPlanVolume *)object;
    if (![other.diskIdentifier isEqual:_diskIdentifier]) {
        return NO;
    }
    if (![other.name isEqual:_name]) {
        return NO;
    }
    if (![other.mountPoint isEqual:_mountPoint]) {
        return NO;
    }
    if (other.included != _included) {
        return NO;
    }
    return YES;
}
- (NSUInteger)hash {
    return [_diskIdentifier hash];
}
@end
