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

#import "PlanNode.h"
#import "BooleanIO.h"
#import "StringIO.h"
#import "IntegerIO.h"
#import "NSObject_extra.h"
#import "BlobDescriptor.h"


@interface PlanNode() {    
    BOOL _isTree;
    ComputerOSType _computerOSType;
    NSArray *_blobDescriptors;
    BlobDescriptor *_aclBlobDescriptor;
    BlobDescriptor *_xattrsBlobDescriptor;
    uint64_t _itemSize;
    uint64_t _containedFiles;
    int64_t _modificationTime_sec;
    int64_t _modificationTime_nsec;
    int64_t _changeTime_sec;
    int64_t _changeTime_nsec;
    int64_t _creationTime_sec;
    int64_t _creationTime_nsec;
    NSString *_userName;
    NSString *_groupName;
    int32_t _mac_st_dev;
    uint64_t _mac_st_ino;
    uint16_t _mac_st_mode;
    uint16_t _mac_st_nlink;
    uint16_t _mac_st_uid;
    uint16_t _mac_st_gid;
    int32_t _mac_st_rdev;
    uint32_t _mac_st_flags;
    uint32_t _winAttrs;
}
@end


@implementation PlanNode
- (instancetype)initWithIsTree:(BOOL)theIsTree
                computerOSType:(ComputerOSType)theComputerOSType
               blobDescriptors:(NSArray *)theBlobDescriptors
             aclBlobDescriptor:(BlobDescriptor *)theAclBlobDescriptor
          xattrsBlobDescriptor:(BlobDescriptor *)theXattrsBlobDescriptor
                      itemSize:(uint64_t)theItemSize
                containedFiles:(uint64_t)theContainedFiles
          modificationTime_sec:(int64_t)theModificationTime_sec
         modificationTime_nsec:(int64_t)theModificationTime_nsec
                changeTime_sec:(int64_t)theChangeTime_sec
               changeTime_nsec:(int64_t)theChangeTime_nsec
              creationTime_sec:(int64_t)theCreationTime_sec
             creationTime_nsec:(int64_t)theCreationTime_nsec
                      userName:(NSString *)theUserName
                     groupName:(NSString *)theGroupName
                    mac_st_dev:(int32_t)theMac_st_dev
                    mac_st_ino:(uint64_t)theMac_st_ino
                   mac_st_mode:(uint16_t)theMac_st_mode
                  mac_st_nlink:(uint16_t)theMac_st_nlink
                    mac_st_uid:(uint16_t)theMac_st_uid
                    mac_st_gid:(uint16_t)theMac_st_gid
                   mac_st_rdev:(uint16_t)theMac_st_rdev
                  mac_st_flags:(uint32_t)theMac_st_flags
                      winAttrs:(uint32_t)theWinAttrs {
    if (self = [super init]) {
        _isTree = theIsTree;
        _computerOSType = theComputerOSType;
        
        NSAssert(theBlobDescriptors != nil, @"missing blob descriptors");
        _blobDescriptors = theBlobDescriptors;

        _aclBlobDescriptor = theAclBlobDescriptor;
        _xattrsBlobDescriptor = theXattrsBlobDescriptor;
        _itemSize = theItemSize;
        _containedFiles = theContainedFiles;
        _modificationTime_sec = theModificationTime_sec;
        _modificationTime_nsec = theModificationTime_nsec;
        _changeTime_sec = theChangeTime_sec;
        _changeTime_nsec = theChangeTime_nsec;
        _creationTime_sec = theCreationTime_sec;
        _creationTime_nsec = theCreationTime_nsec;
        _userName = theUserName;
        _groupName = theGroupName;
        _mac_st_dev = theMac_st_dev;
        _mac_st_ino = theMac_st_ino;
        _mac_st_mode = theMac_st_mode;
        _mac_st_nlink = theMac_st_nlink;
        _mac_st_uid = theMac_st_uid;
        _mac_st_gid = theMac_st_gid;
        _mac_st_rdev = theMac_st_rdev;
        _mac_st_flags = theMac_st_flags;
        _winAttrs = theWinAttrs;
    }
    return self;
}
- (instancetype)initWithJSON:(NSDictionary *)theJSON {
    if (self = [super init]) {
        _isTree = [[theJSON objectForKey:@"isTree"] boolValue];
        _computerOSType = [[theJSON objectForKey:@"computerOSType"] unsignedIntValue];
        
        NSArray *blobDescriptorsJSON = [theJSON objectForKey:@"blobDescriptors"];
        NSMutableArray *blobDescriptors = [NSMutableArray array];
        for (NSDictionary *blobDescriptorJSON in blobDescriptorsJSON) {
            BlobDescriptor *desc = [[BlobDescriptor alloc] initWithJSON:blobDescriptorJSON];
            [blobDescriptors addObject:desc];
        }
        _blobDescriptors = blobDescriptors;
        
        NSDictionary *aclBlobDescriptorJSON = [theJSON objectForKey:@"aclBlobDescriptor"];
        if (aclBlobDescriptorJSON != nil) {
            _aclBlobDescriptor = [[BlobDescriptor alloc] initWithJSON:aclBlobDescriptorJSON];
        }
        NSDictionary *xattrsBlobDescriptorJSON = [theJSON objectForKey:@"xattrsBlobDescriptor"];
        if (xattrsBlobDescriptorJSON != nil) {
            _xattrsBlobDescriptor = [[BlobDescriptor alloc] initWithJSON:xattrsBlobDescriptorJSON];
        }
        _blobDescriptors = blobDescriptors;
        _itemSize = [[theJSON objectForKey:@"itemSize"] unsignedLongLongValue];
        _containedFiles = [[theJSON objectForKey:@"containedFiles"] unsignedLongLongValue];
        _modificationTime_sec = [[theJSON objectForKey:@"modificationTime_sec"] longLongValue];
        _modificationTime_nsec = [[theJSON objectForKey:@"modificationTime_nsec"] longLongValue];
        _changeTime_sec = [[theJSON objectForKey:@"changeTime_sec"] longLongValue];
        _changeTime_nsec = [[theJSON objectForKey:@"changeTime_nsec"] longLongValue];
        _creationTime_sec = [[theJSON objectForKey:@"creationTime_sec"] longLongValue];
        _creationTime_nsec = [[theJSON objectForKey:@"creationTime_nsec"] longLongValue];
        _userName = [theJSON objectForKey:@"userName"];
        _groupName = [theJSON objectForKey:@"groupName"];
        _mac_st_dev = [[theJSON objectForKey:@"mac_st_dev"] intValue];
        _mac_st_ino = [[theJSON objectForKey:@"mac_st_ino"] unsignedLongLongValue];
        _mac_st_mode = (uint16_t)[[theJSON objectForKey:@"mac_st_mode"] unsignedIntValue];
        _mac_st_nlink = (uint16_t)[[theJSON objectForKey:@"mac_st_nlink"] unsignedIntValue];
        _mac_st_uid = (uint16_t)[[theJSON objectForKey:@"mac_st_uid"] unsignedIntValue];
        _mac_st_gid = (uint16_t)[[theJSON objectForKey:@"mac_st_gid"] unsignedIntValue];
        _mac_st_rdev = [[theJSON objectForKey:@"mac_st_rdev"] intValue];
        _mac_st_flags = [[theJSON objectForKey:@"mac_st_flags"] unsignedIntValue];
        _winAttrs = [[theJSON objectForKey:@"winAttrs"] unsignedIntValue];
    }
    return self;
}

- (instancetype)initWithBufferedInputStream:(BufferedInputStream *)bis error:(NSError * __autoreleasing *)error {
    if (self = [super init]) {
        if (![BooleanIO read:&_isTree from:bis error:error]) {
            return nil;
        }
        if (![IntegerIO readUInt32:&_computerOSType from:bis error:error]) {
            return nil;
        }
        uint64_t count = 0;
        if (![IntegerIO readUInt64:&count from:bis error:error]) {
            return nil;
        }
        NSMutableArray *blobDescriptors = [NSMutableArray array];
        for (uint64_t i = 0; i < count; i++) {
            BlobDescriptor *desc = [[BlobDescriptor alloc] initWithBufferedInputStream:bis error:error];
            if (desc == nil) {
                return nil;
            }
            [blobDescriptors addObject:desc];
        }
        _blobDescriptors = blobDescriptors;
        
        BOOL aclBlobDescriptorNotNil = NO;
        if (![BooleanIO read:&aclBlobDescriptorNotNil from:bis error:error]) {
            return nil;
        }
        if (aclBlobDescriptorNotNil) {
            _aclBlobDescriptor = [[BlobDescriptor alloc] initWithBufferedInputStream:bis error:error];
            if (_aclBlobDescriptor == nil) {
                return nil;
            }
        }
        BOOL xattrsBlobDescriptorNotNil = NO;
        if (![BooleanIO read:&xattrsBlobDescriptorNotNil from:bis error:error]) {
            return nil;
        }
        if (xattrsBlobDescriptorNotNil) {
            _xattrsBlobDescriptor = [[BlobDescriptor alloc] initWithBufferedInputStream:bis error:error];
            if (_xattrsBlobDescriptor == nil) {
                return nil;
            }
        }
        
        NSString *userName = nil;
        NSString *groupName = nil;
        uint32_t st_mode = 0;
        uint32_t st_nlink = 0;
        uint32_t uid = 0;
        uint32_t gid = 0;
        if (![IntegerIO readUInt64:&_itemSize from:bis error:error]
            || ![IntegerIO readUInt64:&_containedFiles from:bis error:error]
            || ![IntegerIO readInt64:&_modificationTime_sec from:bis error:error]
            || ![IntegerIO readInt64:&_modificationTime_nsec from:bis error:error]
            || ![IntegerIO readInt64:&_changeTime_sec from:bis error:error]
            || ![IntegerIO readInt64:&_changeTime_nsec from:bis error:error]
            || ![IntegerIO readInt64:&_creationTime_sec from:bis error:error]
            || ![IntegerIO readInt64:&_creationTime_nsec from:bis error:error]
            || ![StringIO read:&userName from:bis error:error]
            || ![StringIO read:&groupName from:bis error:error]
            || ![IntegerIO readInt32:&_mac_st_dev from:bis error:error]
            || ![IntegerIO readUInt64:&_mac_st_ino from:bis error:error]
            || ![IntegerIO readUInt32:&st_mode from:bis error:error]
            || ![IntegerIO readUInt32:&st_nlink from:bis error:error]
            || ![IntegerIO readUInt32:&uid from:bis error:error]
            || ![IntegerIO readUInt32:&gid from:bis error:error]
            || ![IntegerIO readInt32:&_mac_st_rdev from:bis error:error]
            || ![IntegerIO readUInt32:&_mac_st_flags from:bis error:error]
            || ![IntegerIO readUInt32:&_winAttrs from:bis error:error]) {
            return nil;
        }
        _userName = userName;
        _groupName = groupName;
        _mac_st_mode = (uint16_t)st_mode;
        _mac_st_nlink = (uint16_t)st_nlink;
        _mac_st_uid = (uint16_t)uid;
        _mac_st_gid = (uint16_t)gid;
    }
    return self;
}

- (NSString *)errorDomain {
    return @"PlanNodeErrorDomain";
}

- (BOOL)isTree {
    return _isTree;
}
- (ComputerOSType)computerOSType {
    return _computerOSType;
}
- (NSArray *)blobDescriptors {
    return _blobDescriptors;
}
- (BlobDescriptor *)aclBlobDescriptor {
    return _aclBlobDescriptor;
}
- (BlobDescriptor *)xattrsBlobDescriptor {
    return _xattrsBlobDescriptor;
}
- (uint64_t)itemSize {
    return _itemSize;
}
- (uint64_t)containedFiles {
    return _containedFiles;
}
- (int64_t)modificationTime_sec {
    return _modificationTime_sec;
}
- (int64_t)modificationTime_nsec {
    return _modificationTime_nsec;
}
- (int64_t)changeTime_sec {
    return _changeTime_sec;
}
- (int64_t)changeTime_nsec {
    return _changeTime_nsec;
}
- (int64_t)creationTime_sec {
    return _creationTime_sec;
}
- (int64_t)creationTime_nsec {
    return _creationTime_nsec;
}
- (NSString *)userName {
    return _userName;
}
- (NSString *)groupName {
    return _groupName;
}

- (int32_t)mac_st_dev {
    return _mac_st_dev;
}
- (uint64_t)mac_st_ino {
    return _mac_st_ino;
}
- (uint16_t)mac_st_mode {
    return _mac_st_mode;
}
- (uint16_t)mac_st_nlink {
    return _mac_st_nlink;
}
- (uint16_t)mac_st_uid {
    return _mac_st_uid;
}
- (uint16_t)mac_st_gid {
    return _mac_st_gid;
}
- (int32_t)mac_st_rdev {
    return _mac_st_rdev;
}
- (uint32_t)mac_st_flags {
    return _mac_st_flags;
}

- (uint32_t)winAttrs {
    return _winAttrs;
}

#pragma mark NSObject
- (BOOL)isEqual:(id)other {
    if (other == self) {
        return YES;
    }
    if (other == nil || ![other isKindOfClass:[self class]]) {
        return NO;
    }
    PlanNode *o = (PlanNode *)other;
    if (o->_isTree != _isTree) {
        return NO;
    }
    if (o->_computerOSType != _computerOSType) {
        return NO;
    }
    if (![o->_blobDescriptors isEqual:_blobDescriptors]) {
        return NO;
    }
    if (o->_itemSize != _itemSize) {
        return NO;
    }
    if (o->_containedFiles != _containedFiles) {
        return NO;
    }
    if (o->_modificationTime_sec != _modificationTime_sec) {
        return NO;
    }
    if (o->_modificationTime_nsec != _modificationTime_nsec) {
        return NO;
    }
    if (o->_changeTime_sec != _changeTime_sec) {
        return NO;
    }
    if (o->_changeTime_nsec != _changeTime_nsec) {
        return NO;
    }
    if (o->_creationTime_sec != _creationTime_sec) {
        return NO;
    }
    if (o->_creationTime_nsec != _creationTime_nsec) {
        return NO;
    }
    if (![NSObject equalObjects:o->_aclBlobDescriptor and:_aclBlobDescriptor]) {
        return NO;
    }
    if (![NSObject equalObjects:o->_userName and:_userName]) {
        return NO;
    }
    if (![NSObject equalObjects:o->_groupName and:_groupName]) {
        return NO;
    }
    if (![NSObject equalObjects:o->_xattrsBlobDescriptor and:_xattrsBlobDescriptor]) {
        return NO;
    }
    if (o->_mac_st_dev != _mac_st_dev) {
        return NO;
    }
    if (o->_mac_st_ino != _mac_st_ino) {
        return NO;
    }
    if (o->_mac_st_mode != _mac_st_mode) {
        return NO;
    }
    if (o->_mac_st_nlink != _mac_st_nlink) {
        return NO;
    }
    if (o->_mac_st_uid != _mac_st_uid) {
        return NO;
    }
    if (o->_mac_st_gid != _mac_st_gid) {
        return NO;
    }
    if (o->_mac_st_rdev != _mac_st_rdev) {
        return NO;
    }
    if (o->_mac_st_flags != _mac_st_flags) {
        return NO;
    }
    if (o->_winAttrs != _winAttrs) {
        return NO;
    }
    return YES;
}
- (NSUInteger)hash {
    return [_blobDescriptors hash];
}
@end
