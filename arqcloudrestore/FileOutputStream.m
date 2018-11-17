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

#include <sys/stat.h>
#import "FileOutputStream.h"


@interface FileOutputStream() {
    NSNumber *_targetUID;
    NSNumber *_targetGID;
    BOOL _append;
    int _fd;
    NSString *_path;
    unsigned long long _bytesWritten;
}
@end

@implementation FileOutputStream
- (id)initWithPath:(NSString *)thePath targetUID:(uid_t)theTargetUID targetGID:(gid_t)theTargetGID append:(BOOL)isAppend {
    if (self = [super init]) {
        _path = thePath;
        _targetUID = [[NSNumber alloc] initWithUnsignedInt:theTargetUID];
        _targetGID = [[NSNumber alloc] initWithUnsignedInt:theTargetGID];
        _append = isAppend;
        _fd = -1;
    }
    return self;
}
- (instancetype)initWithPath:(NSString *)thePath append:(BOOL)isAppend {
    if (self = [super init]) {
        _path = thePath;
        _append = isAppend;
        _fd = -1;
    }
    return self;
}
- (void)dealloc {
    if (_fd != -1) {
        close(_fd);
    }
}
- (void)close {
    if (_fd != -1) {
        close(_fd);
        _fd = -1;
    }
}
- (BOOL)seekTo:(unsigned long long)offset error:(NSError * __autoreleasing *)error {
    if (_fd == -1 && ![self open:error]) {
        return NO;
    }
    if (lseek(_fd, (off_t)offset, SEEK_SET) == -1) {
        int errnum = errno;
        HSLogError(@"lseek(%@, %qu) error %d: %s", _path, offset, errnum, strerror(errnum));
        SETNSERROR_ARC(NSPOSIXErrorDomain, errnum, @"failed to seek to %qu in %@: %s", offset, _path, strerror(errnum));
        return NO;
    }
    return YES;
}
- (NSString *)path {
    return _path;
}
- (NSInteger)write:(const unsigned char *)buf length:(NSUInteger)len error:(NSError * __autoreleasing *)error {
    if (_fd == -1 && ![self open:error]) {
        return -1;
    }
    NSInteger ret = 0;
write_again:
    ret = write(_fd, buf, len);
    if ((ret < 0) && (errno == EINTR)) {
        goto write_again;
    }
    if (ret < 0) {
        int errnum = errno;
        HSLogError(@"write(%@) error %d: %s", _path, errnum, strerror(errnum));
        SETNSERROR_ARC(NSPOSIXErrorDomain, errnum, @"error writing to %@: %s", _path, strerror(errnum));
        return ret;
    }
    _bytesWritten += (NSUInteger)ret;
    return ret;
}
- (unsigned long long)bytesWritten {
    return _bytesWritten;
}

#pragma mark NSObject
- (NSString *)description {
    return [NSString stringWithFormat:@"<FileOutputStream: path=%@>", _path];
}


#pragma mark internal
- (BOOL)open:(NSError * __autoreleasing *)error {
    int oflag = O_WRONLY|O_CREAT;
    if (_append) {
        oflag |= O_APPEND;
    } else {
        oflag |= O_TRUNC;
    }
    mode_t mode = S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH;
    _fd = open([_path fileSystemRepresentation], oflag, mode);
    if (_fd == -1) {
        int errnum = errno;
        HSLogError(@"open(%@) error %d: %s", _path, errnum, strerror(errnum));
        SETNSERROR_ARC(NSPOSIXErrorDomain, errnum, @"failed to open %@: %s", _path, strerror(errnum));
        return NO;
    }
    if (_targetUID != nil && _targetGID != nil) {
        if (fchown(_fd, [_targetUID unsignedIntValue], [_targetGID unsignedIntValue]) == -1) {
            int errnum = errno;
            HSLogError(@"fchown(%@) error %d: %s", _path, errnum, strerror(errnum));
        }
    }
    return YES;
}
@end

