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

#import "PlanCommitError.h"
#import "NSError_extra.h"
#import "DataIO.h"


@interface PlanCommitError() {
}
@end


@implementation PlanCommitError
- (instancetype)initWithError:(NSError *)theError path:(NSString *)thePath pathIsDirectory:(BOOL)thePathIsDirectory {
    if (self = [super init]) {
        _error = theError;
        _path = thePath;
        _pathIsDirectory = thePathIsDirectory;
    }
    return self;
}
- (instancetype)initWithBufferedInputStream:(BufferedInputStream *)theBIS error:(NSError * __autoreleasing *)error {
    NSData *jsonData = nil;
    if (![DataIO read:&jsonData from:theBIS error:error]) {
        return nil;
    }
    if (jsonData == nil) {
        SETNSERROR_ARC([self errorDomain], -1, @"nil data object");
        return nil;
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:error];
    if (json == nil) {
        return nil;
    }
    return [self initWithJSON:json];
}
- (instancetype)initWithJSON:(NSDictionary *)theJSON {
    if (self = [super init]) {
        _error = [[NSError alloc] initWithJSON:[theJSON objectForKey:@"error"]];
        _path = [theJSON objectForKey:@"path"];
        _pathIsDirectory = [[theJSON objectForKey:@"pathIsDirectory"] boolValue];
    }
    return self;
}
- (NSString *)errorDomain {
    return @"PlanCommitErrorDomain";
}
@end
