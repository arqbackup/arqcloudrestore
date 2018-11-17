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

#import "S3AuthorizationProvider.h"
#import "S3Lister.h"
#import "HTTP.h"
#import "S3Service.h"
#import "S3Request.h"
#import "Item.h"
#import "TargetConnectionDelegate.h"


#define DATE_FORMAT (@"^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})\\.(\\d+)Z$")


@interface S3Lister() {
    id <S3AuthorizationProvider> _sap;
    NSString *_host;
    NSNumber *_port;
    BOOL _useSSL;
    NSString *_path;
    NSString *_delimiter;
    
    NSNumberFormatter *_numberFormatter;
    NSString *_s3BucketName;
    NSString *_s3Path;
    NSString *_escapedS3ObjectPathPrefix;
    BOOL _isTruncated;
    NSString *_marker;
}
@property (weak) id <TargetConnectionDelegate> targetConnectionDelegate;
@end


@implementation S3Lister
- (id)initWithS3AuthorizationProvider:(id <S3AuthorizationProvider>)theSAP
                                 host:(NSString *)theHost
                                 port:(NSNumber *)thePort
                               useSSL:(BOOL)theUseSSL
                                 path:(NSString *)thePath
                            delimiter:(NSString *)theDelimiter
             targetConnectionDelegate:(id <TargetConnectionDelegate>)theTCD {
    if (self = [super init]) {
        _sap = theSAP;
        _host = theHost;
        _port = thePort;
        _useSSL = theUseSSL;
        _path = thePath;
        _delimiter = theDelimiter;
        self.targetConnectionDelegate = theTCD;

        _numberFormatter = [[NSNumberFormatter alloc] init];
        
		_isTruncated = YES;
    }
    return self;
}

- (NSDictionary *)itemsByName:(NSError * __autoreleasing *)error {
    if (![_path hasPrefix:@"/"]) {
        SETNSERROR_ARC([S3Service errorDomain], -1, @"path must start with '/'");
        return nil;
    }
    NSString *strippedPrefix = [_path substringFromIndex:1];
    NSRange range = [strippedPrefix rangeOfString:@"/"];
    if (range.location == NSNotFound) {
        SETNSERROR_ARC([S3Service errorDomain], -1, @"path must contain S3 bucket name plus object path");
        return nil;
    }
    _s3BucketName = [strippedPrefix substringToIndex:range.location];
    _s3Path = [[NSString alloc] initWithFormat:@"/%@/", _s3BucketName];
    _escapedS3ObjectPathPrefix = [[strippedPrefix substringFromIndex:(range.location + 1)] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];    
    
    NSMutableDictionary *ret = [NSMutableDictionary dictionary];
    
    while (_isTruncated) {
        NSArray *items = [self nextPage:error];
        if (items == nil) {
            ret = nil;
            break;
        }
        for (Item *item in items) {
            [ret setObject:item forKey:item.name];
        }
    }
    return ret;
}


#pragma mark internal
- (NSArray *)nextPage:(NSError * __autoreleasing *)error {
    if (self.targetConnectionDelegate != nil && ![self.targetConnectionDelegate targetConnectionShouldRetryOnTransientError:error]) {
        return nil;
    }
    
    NSMutableString *queryString = [NSMutableString stringWithFormat:@"prefix=%@", _escapedS3ObjectPathPrefix];
    if (_delimiter != nil) {
        [queryString appendFormat:@"&delimiter=%@", [_delimiter stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    }
    if (_marker != nil) {
        NSAssert([_marker hasPrefix:_s3BucketName], @"marker must start with S3 bucket name");
        NSString *suffix = [_marker substringFromIndex:([_s3BucketName length] + 1)];
        [queryString appendFormat:@"&marker=%@", [suffix stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    }
    [queryString appendString:@"&max-keys=500"];
    S3Request *s3r = [[S3Request alloc] initWithMethod:@"GET" host:_host port:_port useSSL:_useSSL path:[NSString stringWithFormat:@"/%@/", _s3BucketName] queryString:queryString authorizationProvider:_sap error:error];
    if (s3r == nil) {
        return nil;
    }
    NSError *myError = nil;
    NSData *response = [s3r executeWithTargetConnectionDelegate:self.targetConnectionDelegate error:&myError];
    if (response == nil) {
        if ([myError isErrorWithDomain:[S3Service errorDomain] code:ERROR_NOT_FOUND]) {
            // minio (S3-compatible server) returns not found instead of an empty result set.
            _isTruncated = NO;
            return [NSArray array];
        }
        SETERRORFROMMYERROR;
        return nil;
    }
    NSArray *foundPrefixes = nil;
    NSArray *listBucketResultContents = [self parseXMLResponse:response foundPrefixes:&foundPrefixes error:&myError];
    if (listBucketResultContents == nil && myError == nil) {
        [NSThread sleepForTimeInterval:0.2];
        listBucketResultContents = [self parseXMLResponse:response foundPrefixes:&foundPrefixes error:&myError];
    }
    if (listBucketResultContents == nil) {
        if (myError == nil) {
            myError = [[NSError alloc] initWithDomain:[S3Service errorDomain] code:-1 description:@"Failed to parse ListBucketResult XML response"];
        }
        HSLogDebug(@"response was %@", [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding]);
        HSLogError(@"error getting //ListBucketResult/Contents nodes: %@", myError);
        SETERRORFROMMYERROR;
        return nil;
    }
    
    NSString *lastObjectPath = nil;
    NSMutableArray *ret = [NSMutableArray array];
    
    for (NSString *foundPrefix in foundPrefixes) {
        Item *item = [[Item alloc] init];
        item.isDirectory = YES;
        item.name = [foundPrefix lastPathComponent];
        [ret addObject:item];
    }
    
    for (NSXMLNode *objectNode in listBucketResultContents) {
        Item *item = [[Item alloc] init];
        item.isDirectory = NO;
        
        NSXMLNode *keyNode = nil;
        NSXMLNode *lastModifiedNode = nil;
        NSXMLNode *sizeNode = nil;
        NSXMLNode *storageClassNode = nil;
        NSXMLNode *etagNode = nil;
        NSArray *children = [objectNode children];
        for (NSXMLNode *child in children) {
            NSString *name = [child name];
            if ([name isEqualToString:@"Key"]) {
                keyNode = child;
            } else if ([name isEqualToString:@"LastModified"]) {
                lastModifiedNode = child;
            } else if ([name isEqualToString:@"Size"]) {
                sizeNode = child;
            } else if ([name isEqualToString:@"StorageClass"]) {
                storageClassNode = child;
            } else if ([name isEqualToString:@"ETag"]) {
                etagNode = child;
            }
        }
        
        if (keyNode == nil) {
            SETNSERROR_ARC([S3Service errorDomain], -1, @"missing 'Key' child node in list bucket result node %@", objectNode);
            return nil;
        }
        if (lastModifiedNode == nil) {
            SETNSERROR_ARC([S3Service errorDomain], -1, @"missing 'LastModified' child node in list bucket result node %@", objectNode);
            return nil;
        }
        if (sizeNode == nil) {
            SETNSERROR_ARC([S3Service errorDomain], -1, @"missing 'Size' child node in list bucket result node %@", objectNode);
            return nil;
        }
        if (storageClassNode == nil) {
            SETNSERROR_ARC([S3Service errorDomain], -1, @"missing 'StorageClass' child node in list bucket result node %@", objectNode);
            return nil;
        }

        NSString *objectPath = [NSString stringWithFormat:@"/%@/%@", _s3BucketName, [keyNode stringValue]];
        item.name = [objectPath lastPathComponent];
        lastObjectPath = objectPath;
        NSDate *lastModified = [self dateFromString:[lastModifiedNode stringValue] error:error];
        if (lastModified == nil) {
            return nil;
        }
        item.fileLastModified = lastModified;
        
        unsigned long long size = [[_numberFormatter numberFromString:[sizeNode stringValue]] unsignedLongLongValue];
        item.fileSize = size;

        NSString *storageClass = [storageClassNode stringValue];
        if (storageClass == nil) {
            storageClass = @"STANDARD";
        }
        item.storageClass = storageClass;
        
        if (etagNode != nil) {
            NSString *etag = [etagNode stringValue];
            if ([etag hasPrefix:@"\""] && [etag hasSuffix:@"\""]) {
                etag = [etag substringWithRange:NSMakeRange(1, [etag length] - 2)];
            }
            item.checksum = [@"md5:" stringByAppendingString:etag];
        }
        
        [ret addObject:item];
        
    }
    if (lastObjectPath != nil) {
        _marker = [lastObjectPath substringFromIndex:1];
    }
    return ret;
}

- (NSArray *)parseXMLResponse:(NSData *)response foundPrefixes:(NSArray **)foundPrefixes error:(NSError * __autoreleasing *)error {
    NSError *myError = nil;
    NSXMLDocument *xmlDoc = [[NSXMLDocument alloc] initWithData:response options:0 error:&myError];
    if (!xmlDoc) {
        HSLogDebug(@"list Objects XML data: %@", [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding]);
        SETNSERROR_ARC([S3Service errorDomain], [myError code], @"error parsing List Objects XML response: %@", myError);
        return nil;
    }
    NSXMLElement *rootElement = [xmlDoc rootElement];
    NSArray *isTruncatedNodes = [rootElement nodesForXPath:@"//ListBucketResult/IsTruncated" error:&myError];
    if (isTruncatedNodes == nil) {
        HSLogError(@"nodesForXPath: %@", myError);
        SETERRORFROMMYERROR;
        return nil;
    }
    if ([isTruncatedNodes count] == 0) {
        _isTruncated = NO;
    } else {
        _isTruncated = [[[isTruncatedNodes objectAtIndex:0] stringValue] isEqualToString:@"true"];
    }
    NSArray *prefixNodes = [rootElement nodesForXPath:@"//ListBucketResult/CommonPrefixes/Prefix" error:error];
    if (prefixNodes == nil) {
        if (error != NULL) {
            HSLogError(@"error getting //ListBucketResult/CommonPrefixes/Prefix nodes: %@", *error);
        }
        return nil;
    }
    NSMutableArray *theFoundPrefixes = [NSMutableArray array];
    for (NSXMLNode *prefixNode in prefixNodes) {
        NSString *thePrefix = [prefixNode stringValue];
        thePrefix = [thePrefix substringToIndex:([thePrefix length] - 1)];
        [theFoundPrefixes addObject:[NSString stringWithFormat:@"/%@/%@", _s3BucketName, thePrefix]];
    }
    if (foundPrefixes != NULL) {
        *foundPrefixes = theFoundPrefixes;
    }
    return [rootElement nodesForXPath:@"//ListBucketResult/Contents" error:error];
}

- (NSDate *)dateFromString:(NSString *)dateString error:(NSError * __autoreleasing *)error {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:DATE_FORMAT options:0 error:error];
    if (regex == nil) {
        return nil;
    }
    if ([regex numberOfMatchesInString:dateString options:0 range:NSMakeRange(0, [dateString length])] == 0) {
        SETNSERROR_ARC([S3Service errorDomain], S3SERVICE_INVALID_PARAMETERS, @"invalid date '%@'", dateString);
        return nil;
    }
    NSTextCheckingResult *result = [regex firstMatchInString:dateString options:0 range:NSMakeRange(0, [dateString length])];
    NSString *year = [dateString substringWithRange:[result rangeAtIndex:1]];
    NSString *month = [dateString substringWithRange:[result rangeAtIndex:2]];
    NSString *day = [dateString substringWithRange:[result rangeAtIndex:3]];
    NSString *hour = [dateString substringWithRange:[result rangeAtIndex:4]];
    NSString *minute = [dateString substringWithRange:[result rangeAtIndex:5]];
    NSString *second = [dateString substringWithRange:[result rangeAtIndex:6]];

    NSDateComponents *components = [[NSDateComponents alloc] init];
    [components setYear:[year integerValue]];
    [components setMonth:[month integerValue]];
    [components setDay:[day integerValue]];
    [components setHour:[hour integerValue]];
    [components setMinute:[minute integerValue]];
    [components setSecond:[second integerValue]];
    [components setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

    NSCalendar *calendar = [NSCalendar currentCalendar];
    return [calendar dateFromComponents:components];
}
@end
