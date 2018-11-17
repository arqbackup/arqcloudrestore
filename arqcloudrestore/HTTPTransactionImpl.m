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

#import "HTTPTransactionImpl.h"
#import "RFC2616DateFormatter.h"
#import "URLSession.h"


@interface HTTPTransactionImpl() {
    NSURL *_url;
    NSString *_method;
    WriteBuffer *_responseBuffer;
    NSMutableDictionary *_requestHeaders;
    NSHTTPURLResponse *_httpURLResponse;
    
}
@end


@implementation HTTPTransactionImpl
- (instancetype)initWithURL:(NSURL *)theURL method:(NSString *)theMethod responseBuffer:(WriteBuffer *)theResponseBuffer {
    if (self = [super init]) {
        _url = theURL;
        _method = theMethod;
        _responseBuffer = theResponseBuffer;
        _requestHeaders = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark HTTPTransaction
- (NSString *)errorDomain {
    return @"HTTPTransactionErrorDomain";
}

- (NSURL *)URL {
    return _url;
}
- (void)setRequestHeader:(NSString *)value forKey:(NSString *)key {
    [_requestHeaders setObject:value forKey:key];
}
- (void)setRequestHostHeader {
    [self setRequestHeader:[_url host] forKey:@"Host"];
}
- (void)setRFC2616DateRequestHeader:(NSDate *)theDate {
    [self setRequestHeader:[[RFC2616DateFormatter shared] rfc2616StringFromDate:theDate] forKey:@"Date"];
}
- (NSString *)requestMethod {
    return _method;
}
- (NSString *)requestPathInfo {
    NSString *urlDescription = [_url description];
    NSRange rangeBeforeQueryString = [urlDescription rangeOfString:@"^([^?]+)" options:NSRegularExpressionSearch];
    NSString *stringBeforeQueryString = [urlDescription substringWithRange:rangeBeforeQueryString];
    NSString *path = [_url path];
    if ([stringBeforeQueryString hasSuffix:@"/"] && ![path hasSuffix:@"/"]) {
        // NSURL's path method strips trailing slashes. Add it back in.
        path = [path stringByAppendingString:@"/"];
    }
    return [path stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
}
- (NSString *)requestQueryString {
    return [_url query];
}
- (NSArray *)requestHeaderKeys {
    return [_requestHeaders allKeys];
}
- (NSString *)requestHeaderForKey:(NSString *)theKey {
    return [_requestHeaders objectForKey:theKey];
}
- (BOOL)executeTransactionWithDataTransferDelegate:(id <DataTransferDelegate>)theDTD error:(NSError * __autoreleasing *)error {
    return [self executeTransactionWithBody:nil dataTransferDelegate:theDTD error:error];
}
- (BOOL)executeTransactionWithBody:(NSData *)theBody dataTransferDelegate:(id <DataTransferDelegate>)theDTD error:(NSError * __autoreleasing *)error {
    _httpURLResponse = [[URLSession shared] executeTransactionWithURL:_url method:_method requestHeaders:_requestHeaders requestBody:theBody responseBuffer:_responseBuffer dataTransferDelegate:theDTD error:error];
    if (_httpURLResponse == nil) {
        return NO;
    }
    return YES;
}
- (NSInteger)responseCode {
    return [_httpURLResponse statusCode];
}
- (NSDictionary *)responseHeaders {
    return [_httpURLResponse allHeaderFields];
}
- (NSString *)responseHeaderForKey:(NSString *)key {
    return [[_httpURLResponse allHeaderFields] objectForKey:key];
}
- (NSString *)responseContentType {
    return [self responseHeaderForKey:@"Content-Type"];
}
@end
