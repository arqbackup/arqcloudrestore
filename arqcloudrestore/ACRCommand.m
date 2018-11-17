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

#include <sys/types.h>
#include <pwd.h>
#include <grp.h>
#include <uuid/uuid.h>
#include <termios.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <sys/attr.h>
#include <sys/xattr.h>
#include <unistd.h>
#import "ACRCommand.h"
#import "S3Service.h"
#import "S3SignatureV4AuthorizationProvider.h"
#import "ACRConfig.h"
#import "WasabiRegion.h"
#import "PlanRepo.h"
#import "PlanCommit.h"
#import "PlanCommitVolume.h"
#import "PlanTree.h"
#import "PlanNode.h"
#import "BlobDescriptor.h"
#import "BufferSet.h"
#import "Buffer.h"
#import "XattrSet.h"
#import "BufferedOutputStream.h"
#import "FileACL.h"


#define BUFSIZE (65536)

// 40 MB:
#define BLOCK_SIZE (40000000)


@interface ACRCommand() {
    ACRConfig *_config;
    NSMutableArray *_args;
    BufferSet *_bufferSet;
    NSMutableDictionary *_uidsByUserName;
    NSMutableDictionary *_gidsByGroupName;
}
@end


@implementation ACRCommand
- (instancetype)initWithArgc:(int)theArgc argv:(const char **)theArgv {
    if (self = [super init]) {
        _args = [[NSMutableArray alloc] init];
        for (int i = 0; i < theArgc; i++) {
            [_args addObject:[NSString stringWithUTF8String:theArgv[i]]];
        }
        
        _bufferSet = [[BufferSet alloc] initWithPlaintextBufferSize:BLOCK_SIZE];
        _uidsByUserName = [[NSMutableDictionary alloc] init];
        _gidsByGroupName = [[NSMutableDictionary alloc] init];
    }
    return self;
}
- (NSString *)errorDomain {
    return @"ACRCommandErrorDomain";
}

- (BOOL)execute:(NSError * __autoreleasing *)error {
    if ([_args count] < 2) {
        [self printUsage];
        return YES;
    }
    if ([_args count] == 2 && [[_args lastObject] isEqualToString:@"-h"]) {
        [self printUsage];
        return YES;
    }
    
    _config = [[ACRConfig alloc] init:error];
    if (_config == nil) {
        return NO;
    }
    NSString *cmd = [_args objectAtIndex:1];
    if ([cmd isEqualToString:@"listplans"]) {
        return [self listPlans:error];
    }
    if ([cmd isEqualToString:@"printplan"]) {
        return [self printPlan:error];
    }
    if ([cmd isEqualToString:@"printcommits"]) {
        return [self printCommits:error];
    }
    if ([cmd isEqualToString:@"listfiles"]) {
        return [self listFiles:error];
    }
    if ([cmd isEqualToString:@"restore"]) {
        return [self restore:error];
    }
    [self printUsage];
    return YES;
}

- (BOOL)listPlans:(NSError * __autoreleasing *)error {
    if ([_args count] != 2) {
        [self printUsage];
        return YES;
    }
    S3Service *s3 = [self s3:error];
    if (s3 == nil) {
        return NO;
    }
    NSString *plansDir = [NSString stringWithFormat:@"/%@/plans", _config.bucketName];
    NSDictionary *itemsByName = [s3 itemsByNameInDirectory:plansDir targetConnectionDelegate:nil error:error];
    if (itemsByName == nil) {
        return NO;
    }
    for (NSString *planUUID in [itemsByName allKeys]) {
        printf("%s\n", [planUUID UTF8String]);
    }
    return YES;
}
- (BOOL)printPlan:(NSError * __autoreleasing *)error {
    if ([_args count] != 3) {
        [self printUsage];
        return YES;
    }
    
    NSString *encryptionPassword = [self readPasswordWithPrompt:@"Enter encryption password" error:error];
    if (encryptionPassword == nil) {
        return NO;
    }
    S3Service *s3 = [self s3:error];
    if (s3 == nil) {
        return NO;
    }    
    PlanRepo *repo = [[PlanRepo alloc] initWithS3:s3 bucketName:_config.bucketName planUUID:[_args objectAtIndex:2] encryptionPassword:encryptionPassword targetConnectionDelegate:nil error:error];
    if (repo == nil) {
        return NO;
    }
    NSString *commitId = [repo headId:error];
    if (commitId == nil) {
        return NO;
    }
    PlanCommit *commit = [repo planCommitWithId:commitId error:error];
    if (commit == nil) {
        return NO;
    }
    
    NSOutputStream *stream = [NSOutputStream outputStreamToFileAtPath: @"/dev/tty" append: NO];
    [stream open];
    if (![NSJSONSerialization writeJSONObject:commit.planJSON toStream:stream options:NSJSONWritingPrettyPrinted error:error]) {
        return NO;
    }
    [stream close];
    return YES;
}
- (BOOL)printCommits:(NSError * __autoreleasing *)error {
    if ([_args count] != 3) {
        [self printUsage];
        return YES;
    }
    
    NSString *encryptionPassword = [self readPasswordWithPrompt:@"Enter encryption password" error:error];
    if (encryptionPassword == nil) {
        return NO;
    }
    S3Service *s3 = [self s3:error];
    if (s3 == nil) {
        return NO;
    }    
    PlanRepo *repo = [[PlanRepo alloc] initWithS3:s3 bucketName:_config.bucketName planUUID:[_args objectAtIndex:2] encryptionPassword:encryptionPassword targetConnectionDelegate:nil error:error];
    if (repo == nil) {
        return NO;
    }
    NSString *commitId = [repo headId:error];
    if (commitId == nil) {
        return NO;
    }
    while (commitId != nil) {
        PlanCommit *commit = [repo planCommitWithId:commitId error:error];
        if (commit == nil) {
            return NO;
        }
        printf("Backup Record %s %s\n", [commitId UTF8String], [[[commit creationDate] description] UTF8String]);
        for (NSString *diskIdentifier in [commit.planCommitVolumesByDiskIdentifier allKeys]) {
            printf("\tDisk Identifier: %s\n", [diskIdentifier UTF8String]);
            PlanCommitVolume *pcv = [commit.planCommitVolumesByDiskIdentifier objectForKey:diskIdentifier];
            printf("\t\tMount Point: %s\n", [pcv.mountPoint UTF8String]);
            printf("\t\tBytes: %qu\n", [pcv planNode].itemSize);
        }
        commitId = [commit parentId];
    }
    return YES;
}
- (BOOL)listFiles:(NSError * __autoreleasing *)error {
    if ([_args count] != 5) {
        [self printUsage];
        return YES;
    }
    NSString *planUUID = [_args objectAtIndex:2];
    NSString *commitId = [_args objectAtIndex:3];
    NSString *diskIdentifier = [_args objectAtIndex:4];
    
    NSString *encryptionPassword = [self readPasswordWithPrompt:@"Enter encryption password" error:error];
    if (encryptionPassword == nil) {
        return NO;
    }
    
    S3Service *s3 = [self s3:error];
    if (s3 == nil) {
        return NO;
    }    
    PlanRepo *repo = [[PlanRepo alloc] initWithS3:s3 bucketName:_config.bucketName planUUID:planUUID encryptionPassword:encryptionPassword targetConnectionDelegate:nil error:error];
    if (repo == nil) {
        return NO;
    }
    PlanCommit *commit = [repo planCommitWithId:commitId error:error];
    if (commit == nil) {
        return NO;
    }
    PlanCommitVolume *pcv = [[commit planCommitVolumesByDiskIdentifier] objectForKey:diskIdentifier];
    if (pcv == nil) {
        SETNSERROR_ARC([self errorDomain], ERROR_NOT_FOUND, @"disk identifier %@ not found in backup record %@", diskIdentifier, commitId);
        return NO;
    }
    return [self printNode:pcv.planNode withName:@"" prefix:@"/" repo:repo error:error];
}
- (BOOL)printNode:(PlanNode *)theNode withName:(NSString *)theName prefix:(NSString *)thePrefix repo:(PlanRepo *)theRepo error:(NSError * __autoreleasing *)error {
    NSString *path = [thePrefix stringByAppendingPathComponent:theName];
    printf("\t%s\n", [path UTF8String]);        
    if ([theNode isTree]) {
        NSString *treeId = [[theNode.blobDescriptors firstObject] blobId];
        PlanTree *tree = [theRepo planTreeWithId:treeId error:error];
        if (tree == nil) {
            return NO;
        }
        for (NSString *childNodeName in [tree childNodeNames]) {
            PlanNode *childNode = [tree childNodeWithName:childNodeName];
            if (![self printNode:childNode withName:childNodeName prefix:path repo:theRepo error:error]) {
                return NO;
            }
        }
    }
    return YES;
}
- (BOOL)restore:(NSError * __autoreleasing *)error {
    if ([_args count] != 6) {
        [self printUsage];
        return YES;
    }
    NSString *planUUID = [_args objectAtIndex:2];
    NSString *commitId = [_args objectAtIndex:3];
    NSString *diskIdentifier = [_args objectAtIndex:4];
    NSString *path = [_args objectAtIndex:5];
    
    NSString *encryptionPassword = [self readPasswordWithPrompt:@"Enter encryption password" error:error];
    if (encryptionPassword == nil) {
        return NO;
    }
    
    S3Service *s3 = [self s3:error];
    if (s3 == nil) {
        return NO;
    }    
    PlanRepo *repo = [[PlanRepo alloc] initWithS3:s3 bucketName:_config.bucketName planUUID:planUUID encryptionPassword:encryptionPassword targetConnectionDelegate:nil error:error];
    if (repo == nil) {
        return NO;
    }
    PlanCommit *commit = [repo planCommitWithId:commitId error:error];
    if (commit == nil) {
        return NO;
    }
    PlanCommitVolume *pcv = [[commit planCommitVolumesByDiskIdentifier] objectForKey:diskIdentifier];
    if (pcv == nil) {
        SETNSERROR_ARC([self errorDomain], ERROR_NOT_FOUND, @"disk identifier %@ not found in backup record %@", diskIdentifier, commitId);
        return NO;
    }
    
    PlanNode *node = pcv.planNode;
    
    if ([path hasSuffix:@"/"]) {
        path = [path substringToIndex:([path length] - 1)];
    }
    NSArray *pathComponents = [path pathComponents];
    for (NSUInteger i = 1; i < [pathComponents count]; i++) {
        NSString *pathComponent = [pathComponents objectAtIndex:i];
        if (![node isTree]) {
            SETNSERROR_ARC([self errorDomain], -1, @"path component '%@' is not a directory", pathComponent);
            return NO;
        }
        NSString *treeId = [[[node blobDescriptors] firstObject] blobId];
        PlanTree *tree = [repo planTreeWithId:treeId error:error];
        if (tree == nil) {
            return NO;
        }
        node = [tree childNodeWithName:pathComponent];
        if (node == nil) {
            SETNSERROR_ARC([self errorDomain], -1, @"path component '%@' not found", pathComponent);
            return NO;
        }
    }
    
    NSString *restorePath = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:[pathComponents lastObject]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:restorePath]) {
        SETNSERROR_ARC([self errorDomain], -1, @"%@ already exists; not overwriting", restorePath);
        return NO;
    }
    
    return [self restore:node to:restorePath repo:repo error:error];
}
- (BOOL)restore:(PlanNode *)theNode to:(NSString *)theRestorePath repo:(PlanRepo *)theRepo error:(NSError * __autoreleasing *)error {
    if ([theNode isTree]) {
        // Create the directory.
        if (![[NSFileManager defaultManager] createDirectoryAtPath:theRestorePath withIntermediateDirectories:NO attributes:nil error:error]) {
            return NO;
        }
        
        // Restore the contents.
        NSString *treeId = [[[theNode blobDescriptors] firstObject] blobId];
        PlanTree *tree = [theRepo planTreeWithId:treeId error:error];
        if (tree == nil) {
            return NO;
        }        
        for (NSString *childName in [tree childNodeNames]) {
            PlanNode *childNode = [tree childNodeWithName:childName];
            NSString *childPath = [theRestorePath stringByAppendingPathComponent:childName];
            if (![self restore:childNode to:childPath repo:theRepo error:error]) {
                return NO;
            }
        }
    } else {
        // Restore the file.
        if (![self restoreFileNode:theNode to:theRestorePath repo:theRepo error:error]) {
            return NO;
        }
    }
    
    NSError *myError = nil;
    
    if (theNode.computerOSType == kComputerOSTypeMac) {
        struct stat st;
        if (lstat([theRestorePath fileSystemRepresentation], &st) < 0) {
            int errnum = errno;
            HSLogError(@"lstat(%@) error %d: %s", theRestorePath, errnum, strerror(errnum));
        } else {
            // Set ownership.
            uid_t uid = theNode.mac_st_uid;
            gid_t gid = theNode.mac_st_gid;
            NSNumber *translatedUID = [self uidForUserName:theNode.userName];
            NSNumber *translatedGID = [self gidForGroupName:theNode.groupName];
            if (translatedUID != nil && translatedGID != nil) {
                uid = [translatedUID unsignedIntValue];
                gid = [translatedGID unsignedIntValue];
            }
            HSLogDebug(@"setting ownership of %@ to %d:%d", theRestorePath, uid, gid);
            if (lchown([theRestorePath fileSystemRepresentation], [translatedUID unsignedIntValue], [translatedGID unsignedIntValue]) == -1) {
                int errnum = errno;
                HSLogError(@"lchown(%@) error %d: %s", theRestorePath, errnum, strerror(errnum));
            }
            
            if (theNode.xattrsBlobDescriptor != nil) {
                // Apply xattrs.
                XattrSet *currentXattrs = [[XattrSet alloc] initWithPath:theRestorePath error:&myError];
                if (currentXattrs == nil) {
                    myError = [[NSError alloc] initWithDomain:[self errorDomain] code:-1 description:[NSString stringWithFormat:@"Failed to read current extended attributes of %@: %@", theRestorePath, [myError localizedDescription]]];
                } else {
                    // Remove existing xattrs.
                    for (NSString *name in [currentXattrs names]) {
                        HSLogDebug(@"removing existing xattr %@ from %@", name, theRestorePath);
                        if (removexattr([theRestorePath fileSystemRepresentation], [name UTF8String], XATTR_NOFOLLOW) == -1) {
                            int errnum = errno;
                            HSLogError(@"removexattr(%@) error %d: %s", theRestorePath, errnum, strerror(errnum));
                        }
                    }
                    
                    // Add xattrs from backup record.
                    NSInteger len = [theRepo readBlobWithId:[theNode.xattrsBlobDescriptor blobId] intoBufferSet:_bufferSet dataTransferDelegate:nil error:&myError];
                    if (len < 0) {
                        HSLogError(@"failed to read xattrs blob for %@: %@", theRestorePath, [myError localizedDescription]);
                    } else {
                        NSData *xattrsData = [NSData dataWithBytes:[[_bufferSet plaintextBuffer] bytes] length:len];
                        XattrSet *xattrsToApply = [[XattrSet alloc] initWithData:xattrsData error:&myError];
                        if (xattrsToApply == nil) {
                            HSLogError(@"failed to parse xattrs blob for %@: %@", theRestorePath, [myError localizedDescription]);
                        } else {
                            for (NSString *key in [xattrsToApply names]) {
                                HSLogDebug(@"writing xattr %@ to %@", key, theRestorePath);
                                NSData *value = [xattrsToApply valueForName:key];
                                if (setxattr([theRestorePath fileSystemRepresentation],
                                             [key UTF8String],
                                             [value bytes],
                                             [value length],
                                             0,
                                             XATTR_NOFOLLOW) == -1) {
                                    int errnum = errno;
                                    HSLogError(@"setxattr(%@, %@) error %d: %s", theRestorePath, key, errnum, strerror(errnum));
                                }
                            }
                        }
                    }
                }
            }
            
            if (theNode.aclBlobDescriptor != nil) {
                // Apply ACL.
                NSInteger len = [theRepo readBlobWithId:[theNode.aclBlobDescriptor blobId] intoBufferSet:_bufferSet dataTransferDelegate:nil error:&myError];
                if (len < 0) {
                    HSLogError(@"failed to read acl blob for %@: %@", theRestorePath, [myError localizedDescription]);
                } else {
                    NSString *aclString = [[NSString alloc] initWithBytes:[[_bufferSet plaintextBuffer] bytes] length:len encoding:NSUTF8StringEncoding];
                    HSLogDebug(@"applying acl '%@' to %@", aclString, theRestorePath);
                    if (![FileACL writeACLText:aclString toFile:theRestorePath error:&myError]) {
                        HSLogError(@"failed to write acl to %@: %@", theRestorePath, [myError localizedDescription]);
                    }
                }
            }
            
            // Apply create time.
            struct attrlist attributes;
            attributes.bitmapcount = ATTR_BIT_MAP_COUNT;
            attributes.reserved = 0;
            attributes.commonattr = ATTR_CMN_CRTIME;
            attributes.dirattr = 0;
            attributes.fileattr = 0;
            attributes.forkattr = 0;
            attributes.volattr = 0;
            struct timespec creationTimeSpec = { (__darwin_time_t)theNode.creationTime_sec, (__darwin_time_t)theNode.creationTime_nsec };
            HSLogDebug(@"applying create time to %@", theRestorePath);
            if (setattrlist([theRestorePath fileSystemRepresentation], &attributes, &creationTimeSpec, sizeof(struct timespec), FSOPT_NOFOLLOW) == -1) {
                int errnum = errno;
                HSLogError(@"fsetattrlist(%@) error %d: %s", theRestorePath, errnum, strerror(errnum));
            }            
            
            // Apply mode.
            if (st.st_mode != theNode.mac_st_mode) {
                HSLogDebug(@"applying mode %o to %@", theNode.mac_st_mode, theRestorePath);
                if (lchmod([theRestorePath fileSystemRepresentation], theNode.mac_st_mode) == -1) {
                    int errnum = errno;
                    HSLogError(@"lchmod(%@) error %d: %s", theRestorePath, errnum, strerror(errnum));
                }
            }
            
            // Apply mtime.
            struct timespec mtimeSpec = { (__darwin_time_t)theNode.modificationTime_sec, (__darwin_time_t)theNode.modificationTime_nsec };
            struct timeval atimeVal;
            struct timeval mtimeVal;
            TIMESPEC_TO_TIMEVAL(&atimeVal, &mtimeSpec); // Just use mtime because we don't have atime, nor do we care about atime.
            TIMESPEC_TO_TIMEVAL(&mtimeVal, &mtimeSpec);
            struct timeval timevals[2];
            timevals[0] = atimeVal;
            timevals[1] = mtimeVal;
            HSLogDebug(@"applying mtime to %@", theRestorePath);
            if (lutimes([theRestorePath fileSystemRepresentation], timevals) == -1) {
                int errnum = errno;
                HSLogError(@"lutimes(%@) error %d: %s", theRestorePath, errnum, strerror(errnum));
            }
            
            if (!S_ISFIFO(theNode.mac_st_mode)) {
                // Apply flags.
                if (st.st_flags != theNode.mac_st_flags) {
                    HSLogDebug(@"applying flags to %@", theRestorePath);
                    if (lchflags([theRestorePath fileSystemRepresentation], theNode.mac_st_flags) == -1) {
                        int errnum = errno;
                        HSLogError(@"lchflags(%@) error %d: %s", theRestorePath, errnum, strerror(errnum));
                    }
                }
            }
        }
    }
    return YES;
}
- (BOOL)restoreFileNode:(PlanNode *)theNode to:(NSString *)theRestorePath repo:(PlanRepo *)theRepo error:(NSError * __autoreleasing *)error {
    if (S_ISLNK(theNode.mac_st_mode)) {
        NSInteger len = [theRepo readBlobWithId:[[[theNode blobDescriptors] firstObject] blobId] intoBufferSet:_bufferSet dataTransferDelegate:nil error:error];
        if (len < 0) {
            return NO;
        }
        [[_bufferSet plaintextBuffer] bytes][len] = '\0';
        if (symlink((const char *)[[_bufferSet plaintextBuffer] bytes], [theRestorePath UTF8String]) == -1) {
            int errnum = errno;
            SETNSERROR_ARC(NSPOSIXErrorDomain, errnum, @"failed to create symlink %@: %s", theRestorePath, strerror(errnum));
            return NO;
        }
    } else {
        if ([theNode itemSize] == 0) {
            // It's a zero-byte file.
            int fd = open([theRestorePath fileSystemRepresentation], O_CREAT|O_EXCL, S_IRWXU);
            if (fd == -1) {
                int errnum = errno;
                SETNSERROR_ARC(NSPOSIXErrorDomain, errnum, @"failed to open %@: %s", theRestorePath, strerror(errnum));
                return NO;
            }
            close(fd);                
        } else {
            BufferedOutputStream *bos = [[BufferedOutputStream alloc] initWithPath:theRestorePath append:NO];
            for (BlobDescriptor *blobDescriptor in [theNode blobDescriptors]) {
                NSInteger len = [theRepo readBlobWithId:[blobDescriptor blobId] intoBufferSet:_bufferSet dataTransferDelegate:nil error:error];
                if (len < 0) {
                    return NO;
                }
                if (![bos writeFully:[[_bufferSet plaintextBuffer] bytes] length:len error:error]) {
                    return NO;
                }
            }
            if (![bos flush:error]) {
                return NO;
            }
        }
    }

    return YES;
}
- (void)printUsage {
    printf("usage:\n");
    printf("\t%s listplans\n", [[_args firstObject] UTF8String]);
    printf("\t%s printplan plan_uuid\n", [[_args firstObject] UTF8String]);
    printf("\t%s printcommits plan_uuid\n", [[_args firstObject] UTF8String]);
    printf("\t%s listfiles plan_uuid backup_record_identifier disk_identifier\n", [[_args firstObject] UTF8String]);
    printf("\t%s restore plan_uuid backup_record_identifier disk_identifier path\n", [[_args firstObject] UTF8String]);
}
- (S3Service *)s3:(NSError * __autoreleasing *)error {
    S3SignatureV4AuthorizationProvider *sap = [[S3SignatureV4AuthorizationProvider alloc] initWithAccessKey:_config.accessKeyId secretKey:_config.secretAccessKey regionName:_config.regionName];
    
    WasabiRegion *region = [WasabiRegion regionWithName:_config.regionName];
    if (region == nil) {
        SETNSERROR_ARC([self errorDomain], -1, @"unknown region %@", _config.regionName);
        return nil;
    }
    S3Service *s3 = [[S3Service alloc] initWithS3AuthorizationProvider:sap host:region.s3Hostname port:nil];
    return s3;
}
- (NSString *)readPasswordWithPrompt:(NSString *)thePrompt error:(NSError **)error {
    if (getenv("ACR_ENCRYPTION_PASSWORD")) {
        return [NSString stringWithUTF8String:getenv("ACR_ENCRYPTION_PASSWORD")];
    }
    
    fprintf(stderr, "%s ", [thePrompt UTF8String]);
    fflush(stderr);
    
    struct termios oldTermios;
    struct termios newTermios;
    
    if (tcgetattr(STDIN_FILENO, &oldTermios) != 0) {
        int errnum = errno;
        HSLogError(@"tcgetattr error %d: %s", errnum, strerror(errnum));
        SETNSERROR_ARC(@"UnixErrorDomain", errnum, @"%s", strerror(errnum));
        return nil;
    }
    newTermios = oldTermios;
    newTermios.c_lflag &= ~(ICANON | ECHO);
    tcsetattr(STDIN_FILENO, TCSANOW, &newTermios);
    size_t bufsize = BUFSIZE;
    char *buf = malloc(bufsize);
    ssize_t len = getline(&buf, &bufsize, stdin);
    free(buf);
    tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios);
    
    if (len > 0 && buf[len - 1] == '\n') {
        --len;
    }
    printf("\n");
    return [[NSString alloc] initWithBytes:buf length:len encoding:NSUTF8StringEncoding];
}
- (NSNumber *)uidForUserName:(NSString *)theUserName {
    NSNumber *ret = nil;
    if (theUserName != nil) {
        id uid = [_uidsByUserName objectForKey:theUserName];
        if (uid == nil) {
            struct passwd *pw = getpwnam([theUserName UTF8String]);
            if (pw == NULL) {
                int errnum = errno;
                HSLogWarn(@"failed to get uid for username %@: %s", theUserName, strerror(errnum));
                // Store NSNull in dictionary so we don't keep looking it up.
                uid = [NSNull null];
                ret = nil;
            } else {
                uid = [NSNumber numberWithUnsignedInt:pw->pw_uid];
                ret = uid;
            }
            [_uidsByUserName setObject:uid forKey:theUserName];
        } else {
            if (![uid isEqual:[NSNull null]]) {
                ret = uid;
            }
        }
    }
    return ret;
}
- (NSNumber *)gidForGroupName:(NSString *)theGroupName {
    NSNumber *ret = nil;
    if (theGroupName != nil) {
        id gid = [_gidsByGroupName objectForKey:theGroupName];
        if (gid == nil) {
            struct group *gr = getgrnam([theGroupName UTF8String]);
            if (gr == NULL) {
                int errnum = errno;
                HSLogWarn(@"failed to get gid for group name %@: %s", theGroupName, strerror(errnum));
                // Store NSNull in dictionary so we don't keep looking it up.
                gid = [NSNull null];
                ret = nil;
            } else {
                gid = [NSNumber numberWithUnsignedInt:gr->gr_gid];
                ret = gid;
            }
            [_gidsByGroupName setObject:gid forKey:theGroupName];
        } else {
            if (![gid isEqual:[NSNull null]]) {
                ret = gid;
            }
        }
    }
    return ret;
}
@end
