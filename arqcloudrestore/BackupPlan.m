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

#import "BackupPlan.h"
#import "NSString_extra.h"
#import "NetworkShare.h"
#import "Exclusion.h"
#import "BackupPlanVolume.h"
#import "NetworkInterface.h"


#define DEFAULT_RETENTION_MONTHS (60)
#define DEFAULT_PARALLELISM (3)
#define USER_APP_SUPPORT_SUBDIR @"/Library/Application Support/ArqCloudBackup"


@interface BackupPlan() {
    NSMutableDictionary *_backupPlanVolumesByDiskIdentifier;
    NSMutableDictionary *_networkSharesByDiskIdentifier;
    NSMutableDictionary *_slashedIgnoredRelativePathSetsByDiskIdentifier;
    NSArray *_exclusions;
}
@end

@implementation BackupPlan
- (instancetype)initWithUUID:(NSString *)theUUID name:(NSString *)theName {
    if (self = [super init]) {
        _uuid = theUUID;
        _name = theName;

        _retentionMonths = DEFAULT_RETENTION_MONTHS;
        _thinCommits = YES;

        _excludedNetworkInterfacesByBSDName = [[NSDictionary alloc] init];
        _excludedWiFiNetworkNames = [[NSSet alloc] init];

        _backupPlanVolumesByDiskIdentifier = [[NSMutableDictionary alloc] init];
        _networkSharesByDiskIdentifier = [[NSMutableDictionary alloc] init];
        _slashedIgnoredRelativePathSetsByDiskIdentifier = [[NSMutableDictionary alloc] init];
        _exclusions = [[NSMutableArray alloc] init];
        self.exclusionsAreDefaults = NO;

        _parallelism = DEFAULT_PARALLELISM;
    }
    return self;
}
- (instancetype)initWithJSON:(NSDictionary *)theJSON {
    if (self = [self initWithUUID:[theJSON objectForKey:@"uuid"] name:[theJSON objectForKey:@"name"]]) {
        
        self.pauseOnBattery = [[theJSON objectForKey:@"pauseOnBattery"] boolValue];
        self.preventSleep = [[theJSON objectForKey:@"preventSleep"] boolValue];
        
        self.retentionMonths = [[theJSON objectForKey:@"retentionMonths"] unsignedIntegerValue];
        self.thinCommits = [[theJSON objectForKey:@"thinCommits"] boolValue];

        NSMutableDictionary *excludedNetworkInterfacesByBSDName = [NSMutableDictionary dictionary];
        for (NSDictionary *excludedNetworkInterfaceJSON in [theJSON objectForKey:@"excludedNetworkInterfaces"]) {
            NetworkInterface *intf = [[NetworkInterface alloc] initWithJSON:excludedNetworkInterfaceJSON];
            [excludedNetworkInterfacesByBSDName setObject:intf forKey:[intf bsdName]];
        }
        _excludedNetworkInterfacesByBSDName = excludedNetworkInterfacesByBSDName;
        
        _excludedWiFiNetworkNames = [NSSet setWithArray:[theJSON objectForKey:@"excludedWiFiNetworkNames"]];
        
        _throttleEnabled = [[theJSON objectForKey:@"throttleEnabled"] boolValue];
        _throttleKBPS = [[theJSON objectForKey:@"throttleKBPS"] unsignedIntegerValue];
        
        NSDictionary *backupPlanVolumesByDiskIdentifierJSON = [theJSON objectForKey:@"backupPlanVolumesByDiskIdentifier"];
        for (NSString *diskId in [backupPlanVolumesByDiskIdentifierJSON allKeys]) {
            BackupPlanVolume *bpv = [[BackupPlanVolume alloc] initWithJSON:[backupPlanVolumesByDiskIdentifierJSON objectForKey:diskId]];
            [_backupPlanVolumesByDiskIdentifier setObject:bpv forKey:diskId];
        }
        
        self.includeNewVolumes = [[theJSON objectForKey:@"includeNewVolumes"] boolValue];
        
        NSDictionary *networkSharesByDiskIdentifierJSON = [theJSON objectForKey:@"networkSharesByDiskIdentifier"];
        for (NSString *diskId in [networkSharesByDiskIdentifierJSON allKeys]) {
            NetworkShare *share = [[NetworkShare alloc] initWithJSON:[networkSharesByDiskIdentifierJSON objectForKey:diskId]];
            [_networkSharesByDiskIdentifier setObject:share forKey:diskId];
        }
        
        NSDictionary *slashedIgnoredRelativePathArraysByDiskIdentifier = [theJSON objectForKey:@"slashedIgnoredRelativePathArraysByDiskIdentifier"];
        for (NSString *diskId in [slashedIgnoredRelativePathArraysByDiskIdentifier allKeys]) {
            NSArray *paths = [slashedIgnoredRelativePathArraysByDiskIdentifier objectForKey:diskId];
            [_slashedIgnoredRelativePathSetsByDiskIdentifier setObject:[NSSet setWithArray:paths] forKey:diskId];
        }
        
        NSMutableArray *theExclusions = [NSMutableArray array];
        for (NSDictionary *exclusionJSON in [theJSON objectForKey:@"exclusions"]) {
            [theExclusions addObject:[[Exclusion alloc] initWithJSON:exclusionJSON]];
        }
        _exclusions = theExclusions;
        self.exclusionsAreDefaults = [[theJSON objectForKey:@"exclusionsAreDefaults"] boolValue];

        self.parallelism = [[theJSON objectForKey:@"parallelism"] unsignedIntegerValue];
    }
    return self;
}
- (NSString *)errorDomain {
    return @"BackupPlanErrorDomain";
}
- (NSArray *)exclusions {
    return _exclusions;
}
- (NSUInteger)threadCount {
    NSUInteger ret = 1;
    if (self.parallelism == 2) {
        ret = 2;
    } else if (self.parallelism == 3) {
        ret = 4;
    } else if (self.parallelism == 4) {
        ret = 7;
    } else if (self.parallelism == 5) {
        ret = 15;
    }
    if (self.throttleEnabled) {
        NSUInteger maxThreadCount = self.throttleKBPS / 100; // Minimum 100 KBPS per thread.
        if (ret > maxThreadCount) {
            ret = maxThreadCount;
        }
    }
    if (ret == 0) {
        ret = 1;
    }
    return ret;
}
- (NSArray *)sortedBackupPlanVolumeDiskIdentifiers {
    NSMutableArray *sortedBPVs = [NSMutableArray arrayWithArray:[_backupPlanVolumesByDiskIdentifier allValues]];
    [sortedBPVs sortUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        BackupPlanVolume *bpv1 = (BackupPlanVolume *)obj1;
        BackupPlanVolume *bpv2 = (BackupPlanVolume *)obj2;
        return [bpv1.mountPoint compare:bpv2.mountPoint];
    }];
    NSMutableArray *ret = [[NSMutableArray alloc] init];
    for (BackupPlanVolume *bpv in sortedBPVs) {
        [ret addObject:bpv.diskIdentifier];
    }
    return ret;
}
- (BackupPlanVolume *)backupPlanVolumeForDiskIdentifier:(NSString *)theDiskIdentifier {
    return [_backupPlanVolumesByDiskIdentifier objectForKey:theDiskIdentifier];
}
- (NSArray *)sortedNetworkShareDiskIdentifiers {
    return [[_networkSharesByDiskIdentifier allKeys] sortedArrayUsingSelector:@selector(compare:)];
}
- (NetworkShare *)networkShareForDiskIdentifier:(NSString *)theDiskIdentifier {
    return [_networkSharesByDiskIdentifier objectForKey:theDiskIdentifier];
}

- (NSArray *)slashedIgnoredRelativePathDiskIdentifiers {
    return [_slashedIgnoredRelativePathSetsByDiskIdentifier allKeys];
}
- (NSSet *)slashedIgnoredRelativePathSetForDiskIdentifier:(NSString *)theDiskIdentifier {
    return [[_slashedIgnoredRelativePathSetsByDiskIdentifier objectForKey:theDiskIdentifier] copy];
}
- (BackupPlanPathState)stateForRelativePath:(NSString *)theRelativePath diskIdentifier:(NSString *)theDiskIdentifier {
    if ([theRelativePath isEqualToString:USER_APP_SUPPORT_SUBDIR]) {
        BackupPlanVolume *bpv = [_backupPlanVolumesByDiskIdentifier objectForKey:theDiskIdentifier];
        if ([bpv.mountPoint isEqualToString:@"/"]) {
            return BackupPlanPathOff;
        }
    }
    
    BackupPlanPathState ret = BackupPlanPathOn;
    NSSet *slashedIgnoredRelativePaths = [_slashedIgnoredRelativePathSetsByDiskIdentifier objectForKey:theDiskIdentifier];
    if (slashedIgnoredRelativePaths != nil) {
        if ([slashedIgnoredRelativePaths containsObject:@"/"]) {
            // Everything was excluded.
            return BackupPlanPathOff;
        }
        if ([theRelativePath isEqualToString:@"/"]) {
            if ([slashedIgnoredRelativePaths count] > 0) {
                return BackupPlanPathMixed;
            } else {
                return BackupPlanPathOn;
            }
        }
        
        NSString *slashedRelativePath = [theRelativePath slashed];
        if ([slashedIgnoredRelativePaths containsObject:slashedRelativePath]) {
            return BackupPlanPathOff;
        }
        
        BackupPlanPathState ret = BackupPlanPathOn;
        for (NSString *slashedIgnoredRelativePath in slashedIgnoredRelativePaths) {
            if ([slashedRelativePath hasPrefix:slashedIgnoredRelativePath] && [slashedRelativePath length] > [slashedIgnoredRelativePath length]) {
                return BackupPlanPathOff;
            }
            if ([slashedIgnoredRelativePath hasPrefix:slashedRelativePath] && [slashedIgnoredRelativePath length] > [slashedRelativePath length]) {
                ret = BackupPlanPathMixed;
            }
        }
    }
    
    if (ret != BackupPlanPathOff) {
        NSString *filename = [theRelativePath lastPathComponent];
        for (Exclusion *exclusion in _exclusions) {
            if ([exclusion matchesFilename:filename path:theRelativePath]) {
                return BackupPlanPathOff;
            }
        }
    }
    
    return ret;
}


#pragma mark NSCopying
- (id)copyWithZone:(nullable NSZone *)zone {
    BackupPlan *ret = [[BackupPlan alloc] initWithUUID:self.uuid name:self.name];

    ret.pauseOnBattery = self.pauseOnBattery;
    ret.preventSleep = self.preventSleep;

    ret->_excludedNetworkInterfacesByBSDName = [_excludedNetworkInterfacesByBSDName copyWithZone:zone];
    ret->_excludedWiFiNetworkNames = [_excludedWiFiNetworkNames copyWithZone:zone];
    ret->_throttleEnabled = _throttleEnabled;
    ret->_throttleKBPS = _throttleKBPS;

    ret->_backupPlanVolumesByDiskIdentifier = [[NSMutableDictionary alloc] initWithDictionary:_backupPlanVolumesByDiskIdentifier copyItems:YES];
    ret.includeNewVolumes = self.includeNewVolumes;
    ret->_networkSharesByDiskIdentifier = [[NSMutableDictionary alloc] initWithDictionary:_networkSharesByDiskIdentifier copyItems:YES];
    ret->_slashedIgnoredRelativePathSetsByDiskIdentifier = [[NSMutableDictionary alloc] initWithDictionary:_slashedIgnoredRelativePathSetsByDiskIdentifier copyItems:YES];
    ret->_exclusions = [_exclusions mutableCopyWithZone:zone];

    ret.parallelism = self.parallelism;
    
    return ret;
}


#pragma mark NSObject
- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[BackupPlan class]]) {
        return NO;
    }
    BackupPlan *other = (BackupPlan *)object;
    if (![other.uuid isEqual:self.uuid]) {
        return NO;
    }
    if (![other.name isEqual:self.name]) {
        return NO;
    }

    if (other.pauseOnBattery != self.pauseOnBattery) {
        return NO;
    }
    if (other.preventSleep != self.preventSleep) {
        return NO;
    }
    
    if (![other->_excludedNetworkInterfacesByBSDName isEqual:_excludedNetworkInterfacesByBSDName]) {
        return NO;
    }
    if (![other->_excludedWiFiNetworkNames isEqual:_excludedWiFiNetworkNames]) {
        return NO;
    }
    if (other.throttleEnabled != _throttleEnabled) {
        return NO;
    }
    if (other.throttleKBPS != _throttleKBPS) {
        return NO;
    }

    if (![other->_backupPlanVolumesByDiskIdentifier isEqual:_backupPlanVolumesByDiskIdentifier]) {
        return NO;
    }
    if (other.includeNewVolumes != self.includeNewVolumes) {
        return NO;
    }
    if (![other->_networkSharesByDiskIdentifier isEqual:_networkSharesByDiskIdentifier]) {
        return NO;
    }  
    if (![other->_slashedIgnoredRelativePathSetsByDiskIdentifier isEqual:_slashedIgnoredRelativePathSetsByDiskIdentifier]) {
        return NO;
    }
    if (![[other exclusions] isEqualToArray:_exclusions]) {
        return NO;
    }

    if (other.parallelism != self.parallelism) {
        return NO;
    }
    return YES;
}
- (NSUInteger)hash {
    return [self.uuid hash];
}
@end
