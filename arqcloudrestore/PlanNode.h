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

#import "ComputerOSType.h"
@class BufferedInputStream;
@class BlobDescriptor;


@interface PlanNode : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithIsTree:(BOOL)theIsTree
                computerOSType:(ComputerOSType)theComputerOSType
               blobDescriptors:(NSArray *)theBlobDescriptors
             aclBlobDescriptor:(BlobDescriptor *)theAclBlobDescriptor
          xattrsBlobDescriptor:(BlobDescriptor *)theXattrsBlobDescriptor
                      itemSize:(uint64_t)theItemSize
                containedFiles:(uint64_t)theContainedFiles
          modificationTime_sec:(int64_t)theModificationTime_sec
         modificationTime_nsec:(int64_t)theModificationTime_nsec
                changeTime_sec:(int64_t)theChangeTime_nsec
               changeTime_nsec:(int64_t)theChangeTime_sec
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
                      winAttrs:(uint32_t)theWinAttrs;

- (instancetype)initWithJSON:(NSDictionary *)theJSON;
- (instancetype)initWithBufferedInputStream:(BufferedInputStream *)bis error:(NSError * __autoreleasing *)error;

// Common:
- (BOOL)isTree;
- (ComputerOSType)computerOSType;
- (NSArray *)blobDescriptors;
- (BlobDescriptor *)aclBlobDescriptor;

// Mac-specific:
- (BlobDescriptor *)xattrsBlobDescriptor;

// Common:
- (uint64_t)itemSize;
- (uint64_t)containedFiles;
- (int64_t)modificationTime_sec; // seconds since epoch
- (int64_t)modificationTime_nsec;
- (int64_t)changeTime_sec; // seconds since epoch
- (int64_t)changeTime_nsec;
- (int64_t)creationTime_sec; // seconds since epoch
- (int64_t)creationTime_nsec;
- (NSString *)userName;
- (NSString *)groupName;


// Mac-specific, from stat():
- (int32_t)mac_st_dev;
- (uint64_t)mac_st_ino;
- (uint16_t)mac_st_mode;
- (uint16_t)mac_st_nlink;
- (uint16_t)mac_st_uid;
- (uint16_t)mac_st_gid;
- (int32_t)mac_st_rdev;
- (uint32_t)mac_st_flags;

// Windows-specific:
- (uint32_t)winAttrs;

@end
