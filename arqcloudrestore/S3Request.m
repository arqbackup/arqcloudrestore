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

#import "S3Request.h"
#import "HTTP.h"
#import "S3Service.h"
#import "NSError_extra.h"
#import "S3AuthorizationProvider.h"
#import "S3ErrorResult.h"
#import "TargetConnectionDelegate.h"
#import "ISO8601Date.h"
#import "SHA256Hash.h"
#import "NSString_extra.h"
#import "HTTPTransactionImpl.h"
#import "WriteBuffer.h"


#define INITIAL_RETRY_SLEEP (0.5)
#define RETRY_SLEEP_GROWTH_FACTOR (1.5)
#define MAX_RETRY_SLEEP (5.0)


@interface S3Request() {
    NSString *_method;
    NSString *_host;
    NSNumber *_port;
    BOOL _useSSL;
    NSString *_pathWithQuery;
    id <S3AuthorizationProvider> _sap;
    NSData *_requestBody;
    NSMutableDictionary *_extraRequestHeaders;
    unsigned long long _bytesUploaded;
    int _httpResponseCode;
    NSMutableDictionary *_responseHeaders;
}
@property (weak) id <DataTransferDelegate> dataTransferDelegate;
@end


@implementation S3Request
- (id)initWithMethod:(NSString *)theMethod host:(NSString *)theHost port:(NSNumber *)thePort useSSL:(BOOL)theUseSSL path:(NSString *)thePath queryString:(NSString *)theQueryString authorizationProvider:(id <S3AuthorizationProvider>)theSAP error:(NSError * __autoreleasing *)error {
    return [self initWithMethod:theMethod host:theHost port:thePort useSSL:theUseSSL path:thePath queryString:theQueryString authorizationProvider:theSAP dataTransferDelegate:nil error:error];
}
- (id)initWithMethod:(NSString *)theMethod host:(NSString *)theHost port:(NSNumber *)thePort useSSL:(BOOL)theUseSSL path:(NSString *)thePath queryString:(NSString *)theQueryString authorizationProvider:(id <S3AuthorizationProvider>)theSAP dataTransferDelegate:(id<DataTransferDelegate>)theDelegate error:(NSError * __autoreleasing *)error {
    if (self = [super init]) {
        _method = theMethod;
        _host = theHost;
        _port = thePort;
        _useSSL = theUseSSL;
        _sap = theSAP;
        self.dataTransferDelegate = theDelegate;
        _extraRequestHeaders = [[NSMutableDictionary alloc] init];
        _responseHeaders = [[NSMutableDictionary alloc] init];
        
        if (theQueryString != nil) {
            if ([theQueryString hasPrefix:@"?"]) {
                SETNSERROR_ARC([S3Service errorDomain], -1, @"query string may not begin with a ?");
                return nil;
            }
            _pathWithQuery = [[thePath stringByAppendingString:@"?"] stringByAppendingString:theQueryString];
        } else {
            _pathWithQuery = thePath;
        }
    }
    return self;
}

- (void)setRequestBody:(NSData *)theRequestBody {
    _requestBody = theRequestBody;
}
- (void)setRequestHeader:(NSString *)value forKey:(NSString *)key {
    [_extraRequestHeaders setObject:value forKey:key];
}
- (int)httpResponseCode {
    return _httpResponseCode;
}
- (NSArray *)responseHeaderKeys {
    return [_responseHeaders allKeys];
}
- (NSString *)responseHeaderForKey:(NSString *)theKey {
    return [_responseHeaders objectForKey:theKey];
}
- (NSData *)executeWithTargetConnectionDelegate:(id <TargetConnectionDelegate>)theDelegate error:(NSError * __autoreleasing *)error {
    WriteBuffer *writeBuffer = [[WriteBuffer alloc] init];
    if (![self executeWithResponseBuffer:writeBuffer targetConnectionDelegate:theDelegate error:error]) {
        return nil;
    }
    return [writeBuffer toData];
}
- (BOOL)executeWithResponseBuffer:(WriteBuffer *)theWriteBuffer targetConnectionDelegate:(id <TargetConnectionDelegate>)theDelegate error:(NSError * __autoreleasing *)error {
    NSTimeInterval sleepTime = INITIAL_RETRY_SLEEP;
    NSError *myError = nil;
    BOOL ret = NO;
    for (;;) {
        @autoreleasepool {
            BOOL needRetry = NO;
            BOOL needSleep = NO;
            myError = nil;
            if ([self dataOnceWithResponseBuffer:theWriteBuffer error:&myError]) {
                ret = YES;
                break;
            }
            
            if ([myError isErrorWithDomain:[S3Service errorDomain] code:ERROR_NOT_FOUND]) {
                break;
            }

            HSLogDebug(@"S3Request dataOnce failed; %@", myError);
            
            BOOL is500Error = NO;
            if ([myError isErrorWithDomain:[S3Service errorDomain] code:ERROR_TEMPORARY_REDIRECT]) {
                NSString *location = [[myError userInfo] objectForKey:@"location"];
                HSLogDebug(@"redirecting to %@", location);
                NSURL *url = [NSURL URLWithString:location];
                if (url == nil) {
                    HSLogError(@"invalid redirect URL %@", location);
                    myError = [[NSError alloc] initWithDomain:[S3Service errorDomain] code:-1 description:[NSString stringWithFormat:@"invalid redirect URL %@", location]];
                    break;
                }
                _host = [url host];
                _port = [url port];
                needRetry = YES;
            } else if ([myError isErrorWithDomain:[S3Service errorDomain] code:S3SERVICE_ERROR_AMAZON_ERROR]) {
                int httpStatusCode = [[[myError userInfo] objectForKey:@"HTTPStatusCode"] intValue];
                NSString *amazonCode = [[myError userInfo] objectForKey:@"AmazonCode"];
                
                if ([amazonCode isEqualToString:@"RequestTimeout"] || [amazonCode isEqualToString:@"RequestTimeoutException"]) {
                    needRetry = YES;
                } else if (httpStatusCode == HTTP_INTERNAL_SERVER_ERROR) {
                    needRetry = YES;
                    needSleep = YES;
                    is500Error = YES;
                } else if (httpStatusCode == HTTP_SERVICE_NOT_AVAILABLE) {
                    needRetry = YES;
                    needSleep = YES;
                } else if (httpStatusCode == HTTP_CONFLICT && [amazonCode isEqualToString:@"OperationAborted"]) {
                    // "A conflicting conditional operation is currently in progress against this resource. Please try again."
                    // Happens sometimes when putting bucket lifecycle policy.
                    needRetry = YES;
                    needSleep = YES;
                }
            } else if ([myError isConnectionResetError]) {
                needRetry = YES;
            } else if ([myError isTransientError]) {
                needRetry = YES;
                needSleep = YES;
            }
            
//            if (!is500Error && (!needRetry || ![theDelegate targetConnectionShouldRetryOnTransientError:&myError])) {
            // Always call the delegate because the user may have requested a stop.
            if (!needRetry || (theDelegate != nil && ![theDelegate targetConnectionShouldRetryOnTransientError:&myError])) {
                HSLogDebug(@"request failed and no retry requested: %@ %@: %@", _method, _pathWithQuery, myError);
                break;
            }
            
            if (needSleep) {
                [NSThread sleepForTimeInterval:sleepTime];
                sleepTime *= RETRY_SLEEP_GROWTH_FACTOR;
                if (sleepTime > MAX_RETRY_SLEEP) {
                    sleepTime = MAX_RETRY_SLEEP;
                }
            }

            HSLogInfo(@"retrying %@ %@: %@", _method, _pathWithQuery, [myError localizedDescription]);
        }
    }
    if (!ret) {
        SETERRORFROMMYERROR;
    }
    return ret;
}


#pragma mark internal
- (BOOL)dataOnceWithResponseBuffer:(WriteBuffer *)theResponseBuffer error:(NSError * __autoreleasing *)error {
    NSString *urlString = [NSString stringWithFormat:@"http%@://%@%@%@", (_useSSL ? @"s" : @""), _host, (_port != nil ? [NSString stringWithFormat:@":%d", [_port intValue]] : @""), _pathWithQuery];
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        SETNSERROR_ARC([S3Service errorDomain], -2, @"invalid URL: %@", urlString);
        return NO;
    }
    [theResponseBuffer reset];
    id <HTTPTransaction> conn = [[HTTPTransactionImpl alloc] initWithURL:url method:_method responseBuffer:theResponseBuffer];
    if (conn == nil) {
        return NO;
    }
    [conn setRequestHostHeader];
    
    NSDate *now = [NSDate date];
    
    NSString *contentSHA256 = nil;
    if (_requestBody != nil) {
        [conn setRequestHeader:[NSString stringWithFormat:@"%lu", (unsigned long)[_requestBody length]] forKey:@"Content-Length"];
        contentSHA256 = [NSString hexStringWithData:[SHA256Hash hashData:_requestBody]];
    } else {
        contentSHA256 = [NSString hexStringWithData:[SHA256Hash hashData:[@"" dataUsingEncoding:NSUTF8StringEncoding]]];
    }
    
    if ([_sap signatureVersion] == 4) {
        [conn setRequestHeader:[[ISO8601Date shared] basicDateTimeStringFromDate:now] forKey:@"x-amz-date"];
        [conn setRequestHeader:contentSHA256 forKey:@"x-amz-content-sha256"];
    } else {
        [conn setRFC2616DateRequestHeader:now];
    }
    
    for (NSString *headerKey in [_extraRequestHeaders allKeys]) {
        [conn setRequestHeader:[_extraRequestHeaders objectForKey:headerKey] forKey:headerKey];
    }
    
    NSString *stringToSign = nil;
    NSString *canonicalRequest = nil;
    if (![_sap setAuthorizationOnHTTPTransaction:conn contentSHA256:contentSHA256 now:now stringToSign:&stringToSign canonicalRequest:&canonicalRequest error:error]) {
        return NO;
    }
    
    _bytesUploaded = 0;
    
    HSLogDebug(@"%@ %@", _method, urlString);
    
    if (![conn executeTransactionWithBody:_requestBody dataTransferDelegate:_dataTransferDelegate error:error]) {
        return NO;
    }
    
    [_responseHeaders setDictionary:[conn responseHeaders]];
    
    _httpResponseCode = (int)[conn responseCode];
    if (_httpResponseCode >= 200 && _httpResponseCode <= 299) {
        HSLogDebug(@"HTTP %d; %ld-byte response", _httpResponseCode, [theResponseBuffer length]);
        return YES;
    }
    //    HSLogDebug(@"HTTP %d; response length=%ld", _httpResponseCode, (long)[response length]);
    
    if (_httpResponseCode == HTTP_NOT_FOUND) {
        HSLogDebug(@"HTTP %d", _httpResponseCode);
        S3ErrorResult *errorResult = [[S3ErrorResult alloc] initWithAction:[NSString stringWithFormat:@"%@ %@", _method, [url description]]
                                                                      data:[theResponseBuffer toData]
                                                             httpErrorCode:_httpResponseCode
                                                              stringToSign:stringToSign
                                                          canonicalRequest:canonicalRequest];
        NSError *myError = [errorResult error];
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:[myError userInfo]];
        [userInfo setObject:[NSString stringWithFormat:@"%@ not found", url] forKey:NSLocalizedDescriptionKey];
        myError = [NSError errorWithDomain:[S3Service errorDomain] code:ERROR_NOT_FOUND userInfo:userInfo];
        SETERRORFROMMYERROR;
        return NO;
    }
    if (_httpResponseCode == HTTP_METHOD_NOT_ALLOWED) {
        HSLogError(@"%@ 405 error", url);
        SETNSERROR_ARC([S3Service errorDomain], ERROR_RRS_NOT_FOUND, @"%@ 405 error", url);
    }
    if (_httpResponseCode == HTTP_MOVED_TEMPORARILY) {
        NSString *location = [conn responseHeaderForKey:@"Location"];
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:location forKey:@"location"];
        NSError *myError = [NSError errorWithDomain:[S3Service errorDomain] code:ERROR_TEMPORARY_REDIRECT userInfo:userInfo];
        if (error != NULL) {
            *error = myError;
        }
        HSLogDebug(@"returning moved-temporarily error");
        return NO;
    }
    S3ErrorResult *errorResult = [[S3ErrorResult alloc] initWithAction:[NSString stringWithFormat:@"%@ %@", _method, [url description]]
                                                                  data:[theResponseBuffer toData]
                                                         httpErrorCode:_httpResponseCode
                                                          stringToSign:stringToSign
                                                      canonicalRequest:canonicalRequest];
    NSError *myError = [errorResult error];
    HSLogDebug(@"%@ error: %@", conn, myError);
    SETERRORFROMMYERROR;
    
    return NO;
}
@end
