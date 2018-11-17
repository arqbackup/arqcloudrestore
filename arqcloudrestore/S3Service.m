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

#import "S3Lister.h"
#import "S3AuthorizationProvider.h"
#import "S3Service.h"
#import "PathReceiver.h"
#import "DataInputStream.h"
#import "HTTP.h"
#import "S3ObjectReceiver.h"
#import "S3Request.h"
#import "NSError_extra.h"
#import "HTTPTransactionImpl.h"
#import "HTTPTransaction.h"
#import "MD5Hash.h"
#import "S3ErrorResult.h"
#import "SHA256Hash.h"
#import "NSString_extra.h"
#import "ISO8601Date.h"
#import "Item.h"
#import "WriteBuffer.h"
#import "S3ServiceConstants.h"


#define DATE_FORMAT (@"^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})\\.(\\d+)Z$")


@interface S3Service() {
    id <S3AuthorizationProvider> _sap;
    NSString *_host;
    NSNumber *_port;
}
@end


@implementation S3Service
+ (NSString *)errorDomain {
    return [S3ServiceConstants errorDomain];
}


- (id)initWithS3AuthorizationProvider:(id <S3AuthorizationProvider>)theSAP host:(NSString *)theHost port:(NSNumber *)thePort {
    if (self = [super init]) {
        _sap = theSAP;
        _host = theHost;
        _port = thePort;
    }
    return self;
}
- (NSArray *)s3BucketNamesWithTargetConnectionDelegate:(id<TargetConnectionDelegate>)theDelegate error:(NSError * __autoreleasing *)error {
    NSXMLDocument *doc = [self listBucketsWithTargetConnectionDelegate:theDelegate error:error];
    if (!doc) {
        return nil;
    }
    NSXMLElement *rootElem = [doc rootElement];
    NSArray *nameNodes = [rootElem nodesForXPath:@"//ListAllMyBucketsResult/Buckets/Bucket/Name" error:error];
    if (!nameNodes) {
        return nil;
    }
    NSMutableArray *bucketNames = [[NSMutableArray alloc] init];
    for (NSXMLNode *nameNode in nameNodes) {
        [bucketNames addObject:[nameNode stringValue]];
    }
    return bucketNames;
}

- (NSDictionary *)itemsByNameInDirectory:(NSString *)theDirectoryPath targetConnectionDelegate:(id <TargetConnectionDelegate>)theTCD error:(NSError * __autoreleasing *)error {
    if ([theDirectoryPath isEqualToString:@"/"]) {
        NSArray *bucketNames = [self s3BucketNamesWithTargetConnectionDelegate:theTCD error:error];
        if (bucketNames == nil) {
            return nil;
        }
        NSMutableDictionary *ret = [NSMutableDictionary dictionary];
        for (NSString *name in bucketNames) {
            Item *item = [[Item alloc] init];
            item.name = name;
            item.isDirectory = YES;
            [ret setObject:item forKey:name];
        }
        return ret;
    }
    if (![theDirectoryPath hasSuffix:@"/"]) {
        theDirectoryPath = [theDirectoryPath stringByAppendingString:@"/"];
    }
    
    S3Lister *lister = [[S3Lister alloc] initWithS3AuthorizationProvider:_sap
                                                                    host:_host
                                                                    port:_port
                                                                  useSSL:YES
                                                                    path:theDirectoryPath
                                                               delimiter:@"/"
                                                targetConnectionDelegate:theTCD];
    NSDictionary *ret = [lister itemsByName:error];
    return ret;
}
- (Item *)itemAtPath:(NSString *)thePath targetConnectionDelegate:(id <TargetConnectionDelegate>)theTCD error:(NSError * __autoreleasing *)error {
    S3Request *s3r = [[S3Request alloc] initWithMethod:@"HEAD" host:_host port:_port useSSL:YES path:thePath queryString:nil authorizationProvider:_sap dataTransferDelegate:nil error:error];
    if (s3r == nil) {
        return nil;
    }
    WriteBuffer *buffer = [[WriteBuffer alloc] init];
    if (![s3r executeWithResponseBuffer:buffer targetConnectionDelegate:theTCD error:error]) {
        return nil;
    }
    Item *ret = [[Item alloc] init];
    ret.name = [thePath lastPathComponent];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"EEE, d MMM yyyy HH:mm:ss ZZZ"];
    [dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    NSString *lastModifiedString = [s3r responseHeaderForKey:@"Last-Modified"];
    NSDate *lastModified = [dateFormatter dateFromString:lastModifiedString];
    if (lastModified == nil) {
        SETNSERROR_ARC([S3Service errorDomain], -1, @"failed to parse date header %@", lastModifiedString);
        return nil;
    }
    ret.fileLastModified = lastModified;
    
    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    unsigned long long size = [[numberFormatter numberFromString:[s3r responseHeaderForKey:@"Content-Length"]] unsignedLongLongValue];
    ret.fileSize = size;
    
    ret.storageClass = @"STANDARD";
    
    NSString *etag = [s3r responseHeaderForKey:@"ETag"];
    if (etag != nil) {
        if ([etag hasPrefix:@"\""] && [etag hasSuffix:@"\""]) {
            etag = [etag substringWithRange:NSMakeRange(1, [etag length] - 2)];
        }
        ret.checksum = [@"md5:" stringByAppendingString:etag];
    }

    return ret;
}
- (NSInteger)readContentsOfFileAtPath:(NSString *)theFullPath intoBuffer:(unsigned char *)theBuffer bufferLength:(NSUInteger)theBufferLength dataTransferDelegate:(id <DataTransferDelegate>)theDTD targetConnectionDelegate:(id <TargetConnectionDelegate>)theTCD error:(NSError * __autoreleasing *)error {
    S3Request *s3r = [[S3Request alloc] initWithMethod:@"GET" host:_host port:_port useSSL:YES path:theFullPath queryString:nil authorizationProvider:_sap dataTransferDelegate:theDTD error:error];
    if (s3r == nil) {
        return -1;
    }
    WriteBuffer *buffer = [[WriteBuffer alloc] initWithInternalBuffer:theBuffer length:theBufferLength];
    if (![s3r executeWithResponseBuffer:buffer targetConnectionDelegate:theTCD error:error]) {
        return -1;
    }
    return [buffer length];
}
- (NSData *)contentsOfFileAtPath:(NSString *)theFullPath dataTransferDelegate:(id <DataTransferDelegate>)theDTD targetConnectionDelegate:(id <TargetConnectionDelegate>)theTCD error:(NSError * __autoreleasing *)error {
    return [self contentsOfRange:NSMakeRange(NSNotFound, 0) ofFileAtPath:theFullPath dataTransferDelegate:theDTD targetConnectionDelegate:theTCD error:error];
}
- (NSData *)contentsOfRange:(NSRange)theRange ofFileAtPath:(NSString *)theFullPath dataTransferDelegate:(id <DataTransferDelegate>)theDTD targetConnectionDelegate:(id <TargetConnectionDelegate>)theTCD error:(NSError * __autoreleasing *)error {
    S3Request *s3r = [[S3Request alloc] initWithMethod:@"GET" host:_host port:_port useSSL:YES path:theFullPath queryString:nil authorizationProvider:_sap dataTransferDelegate:theDTD error:error];
    if (s3r == nil) {
        return nil;
    }
    if (theRange.location != NSNotFound) {
        [s3r setRequestHeader:[NSString stringWithFormat:@"bytes=%ld-%ld", theRange.location, (theRange.location + theRange.length - 1)] forKey:@"Range"];
    }
    WriteBuffer *buffer = [[WriteBuffer alloc] init];
    if (![s3r executeWithResponseBuffer:buffer targetConnectionDelegate:theTCD error:error]) {
        return nil;
    }
    
    if (theRange.location != NSNotFound && [buffer length] != theRange.length) {
        SETNSERROR_ARC([S3Service errorDomain], -1, @"requested bytes at %ld length %ld but got %ld bytes", theRange.location, theRange.length, [buffer length]);
        return nil;
    }
    return [buffer toData];
}


#pragma mark NSCopying
- (id)copyWithZone:(NSZone *)zone {
    return [[S3Service alloc] initWithS3AuthorizationProvider:_sap host:_host port:_port];
}


#pragma mark internal
- (NSXMLDocument *)listBucketsWithTargetConnectionDelegate:(id <TargetConnectionDelegate>)theDelegate error:(NSError * __autoreleasing *)error {
    S3Request *s3r = [[S3Request alloc] initWithMethod:@"GET" host:_host port:_port useSSL:YES path:@"/" queryString:nil authorizationProvider:_sap error:error];
    if (s3r == nil) {
        return nil;
    }
    NSError *myError = nil;
    NSData *response = [s3r executeWithTargetConnectionDelegate:theDelegate error:&myError];
    if (response == nil) {
        SETERRORFROMMYERROR;
        if ([myError isErrorWithDomain:[S3Service errorDomain] code:S3SERVICE_ERROR_AMAZON_ERROR]) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:[myError userInfo]];
            [userInfo setObject:[myError localizedDescription] forKey:NSLocalizedDescriptionKey];
            NSError *rewritten = [NSError errorWithDomain:[S3Service errorDomain] code:[[[myError userInfo] objectForKey:@"HTTPStatusCode"] intValue] userInfo:userInfo];
            if (error != NULL) {
                *error = rewritten;
            }
        }
        return nil;
    }
    NSXMLDocument *ret = [[NSXMLDocument alloc] initWithData:response options:0 error:&myError];
    if (ret == nil) {
        HSLogDebug(@"error parsing List Buckets result XML %@", [[NSString alloc] initWithBytes:[response bytes] length:[response length] encoding:NSUTF8StringEncoding]);
        SETNSERROR_ARC([S3Service errorDomain], [myError code], @"error parsing S3 List Buckets result XML: %@", [myError description]);
    }
    return ret;
}
@end
