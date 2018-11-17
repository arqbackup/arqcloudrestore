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

#import "S3SignatureV4AuthorizationProvider.h"
#import "HMACSHA256.h"
#import "ISO8601Date.h"
#import "SHA256Hash.h"
#import "NSString_extra.h"
#import "HTTPTransaction.h"

static NSDateFormatter *g_dateFormatter;
static NSString *S3_ALLOWED_VALUE_CHARACTERS = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
static NSString *S3_ALLOWED_KEY_CHARACTERS = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/";


@interface S3SignatureV4AuthorizationProvider() {
    NSString *_accessKey;
    NSString *_secretKey;
    NSString *_regionName;
    NSMutableDictionary *_signingKeysByDateString;
    NSLock *_signingKeysLock;
}
@end

@implementation S3SignatureV4AuthorizationProvider
- (id)initWithAccessKey:(NSString *)access secretKey:(NSString *)secret regionName:(NSString *)theRegionName {
    if (self = [super init]) {
        _accessKey = access;
        _secretKey = secret;
        _regionName = theRegionName;
        _signingKeysByDateString = [[NSMutableDictionary alloc] init];
        if (g_dateFormatter == nil) {
            g_dateFormatter = [[NSDateFormatter alloc] init];
            [g_dateFormatter setDateFormat:@"yyyyMMdd"];
        }
        _signingKeysLock = [[NSLock alloc] init];
    }
    return self;
}


#pragma mark S3AuthorizationProvider
- (int)signatureVersion {
    return 4;
}
- (BOOL)setAuthorizationOnHTTPTransaction:(id<HTTPTransaction>)conn contentSHA256:(NSString *)theContentSHA256 now:(NSDate *)now stringToSign:(NSString **)outStringToSign canonicalRequest:(NSString **)outCanonicalRequest error:(NSError * __autoreleasing *)error {
    NSString *signedHeaders = nil;
    NSString *canonicalRequest = [self canonicalRequestForTransaction:conn contentSHA256:theContentSHA256 signedHeaders:&signedHeaders];
    if (outCanonicalRequest != NULL) {
        *outCanonicalRequest = canonicalRequest;
    }
    NSString *theString = [self stringToSignForTransaction:conn canonicalRequest:canonicalRequest contentSHA256:theContentSHA256 now:now];
    if (outStringToSign != NULL) {
        *outStringToSign = theString;
    }
    
    [_signingKeysLock lock];
    // Lock before using g_dateFormatter because it's not thread-safe!
    NSString *dateString = [g_dateFormatter stringFromDate:now];
    
    NSData *signingKey = [_signingKeysByDateString objectForKey:dateString];
    if (signingKey == nil) {
        signingKey = [self makeSigningKeyForDateString:dateString];
        [_signingKeysByDateString setObject:signingKey forKey:dateString];
    }
    [_signingKeysLock unlock];
    
    NSData *signatureData = [HMACSHA256 digestForKey:signingKey data:[theString dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *signature = [NSString hexStringWithData:signatureData];
    
    NSString *authorization = [NSString stringWithFormat:@"AWS4-HMAC-SHA256 Credential=%@/%@/%@/s3/aws4_request,SignedHeaders=%@,Signature=%@",
                               _accessKey, dateString, _regionName, signedHeaders, signature];
    [conn setRequestHeader:authorization forKey:@"Authorization"];
    
    return YES;
}


#pragma mark internal
- (NSData *)makeSigningKeyForDateString:(NSString *)theDateString {
    NSString *secret = [@"AWS4" stringByAppendingString:_secretKey];
    
    NSData *dateKey = [HMACSHA256 digestForKey:[secret dataUsingEncoding:NSUTF8StringEncoding] data:[theDateString dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSData *dateRegionKey = [HMACSHA256 digestForKey:dateKey data:[_regionName dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSData *dateRegionServiceKey = [HMACSHA256 digestForKey:dateRegionKey data:[@"s3" dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSData *signingKey = [HMACSHA256 digestForKey:dateRegionServiceKey data:[@"aws4_request" dataUsingEncoding:NSUTF8StringEncoding]];
    
    return signingKey;
}
- (NSString *)stringToSignForTransaction:(id<HTTPTransaction>)theTransaction canonicalRequest:(NSString *)canonicalRequest contentSHA256:(NSString *)theContentSHA256 now:(NSDate *)now {
    
    // Scope
    NSMutableString *scope = [[NSMutableString alloc] init];
    [_signingKeysLock lock];
    // Lock before using g_dateFormatter because it's not thread-safe!
    [scope appendString:[g_dateFormatter stringFromDate:now]];
    [_signingKeysLock unlock];
    
    [scope appendString:@"/"];
    [scope appendString:_regionName];
    [scope appendString:@"/s3/aws4_request"];
    
    // String to sign
    NSMutableString *ret = [[NSMutableString alloc] init];
    [ret appendString:@"AWS4-HMAC-SHA256\n"];
    [ret appendString:[[ISO8601Date shared] basicDateTimeStringFromDate:now]];
    [ret appendString:@"\n"];
    [ret appendString:scope];
    [ret appendString:@"\n"];
    [ret appendString:[NSString hexStringWithData:[SHA256Hash hashData:[canonicalRequest dataUsingEncoding:NSUTF8StringEncoding]]]];
    
#if 0
    HSLogDebug(@"v4 stringtosign: %@", ret);
    NSData *stringToSignData = [ret dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char *bytes = (unsigned char *)[stringToSignData bytes];
    NSMutableString *debugBuf = [NSMutableString string];
    for (NSUInteger i = 0; i < [stringToSignData length]; i++) {
        [debugBuf appendFormat:@"%02x ", bytes[i]];
    }
    HSLogDebug(@"string-to-sign bytes: %@", debugBuf);
#endif
    
    return ret;
}
- (NSString *)canonicalRequestForTransaction:(id <HTTPTransaction>)theTransaction contentSHA256:(NSString *)theContentSHA256 signedHeaders:(NSString **)theSignedHeaders {
    /*
     <HTTPMethod>\n
     <CanonicalURI>\n
     <CanonicalQueryString>\n
     <CanonicalHeaders>\n
     <SignedHeaders>\n
     <HashedPayload>
     */
    
    NSMutableString *buf = [[NSMutableString alloc] init];
    
    // HTTPMethod
    [buf appendString:[theTransaction requestMethod]];
    [buf appendString:@"\n"];
    
    // CanonicalURI
    [buf appendString:[theTransaction requestPathInfo]];
    [buf appendString:@"\n"];
    
    // CanonicalQueryString
    NSArray *queryStringComponents = [[theTransaction requestQueryString] componentsSeparatedByString:@"&"];
    NSMutableDictionary *encodedComponents = [NSMutableDictionary dictionary];
    for (NSString *component in queryStringComponents) {
        if ([component rangeOfString:@"="].location != NSNotFound) {
            NSArray *pairComponents = [component componentsSeparatedByString:@"="];
            NSString *key = [pairComponents objectAtIndex:0];
            NSString *value = [pairComponents objectAtIndex:1];
            key = [key stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:S3_ALLOWED_KEY_CHARACTERS]];
            // Decode any percent-encoded stuff in the value first.
            NSString *decodedValue = [value stringByRemovingPercentEncoding];
            // Then encode everything in the value, including / characters.
            value = [decodedValue stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:S3_ALLOWED_VALUE_CHARACTERS]];
            [encodedComponents setObject:value forKey:key];
        } else {
            NSString *key = [component stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:S3_ALLOWED_KEY_CHARACTERS]];
            [encodedComponents setObject:@"" forKey:key];
        }
    }
    NSArray *sortedEncodedKeys = [[encodedComponents allKeys] sortedArrayUsingSelector:@selector(compare:)];
    BOOL addAmpersand = NO;
    for (NSString *key in sortedEncodedKeys) {
        if (!addAmpersand) {
            addAmpersand = YES;
        } else {
            [buf appendString:@"&"];
        }
        [buf appendString:key];
        [buf appendString:@"="];
        [buf appendString:[encodedComponents objectForKey:key]];
    }
    [buf appendString:@"\n"];
    
    NSMutableDictionary *lcHeaders = [NSMutableDictionary dictionary];
    for (NSString *headerName in [theTransaction requestHeaderKeys]) {
        [lcHeaders setObject:[theTransaction requestHeaderForKey:headerName] forKey:[headerName lowercaseString]];
    }
    NSArray *sortedLCHeaderNames = [[lcHeaders allKeys] sortedArrayUsingSelector:@selector(compare:)];
    
    // CanonicalHeaders
    for (NSString *headerName in sortedLCHeaderNames) {
        [buf appendString:[headerName lowercaseString]];
        [buf appendString:@":"];
        [buf appendString:[[lcHeaders objectForKey:headerName] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
        [buf appendString:@"\n"];
    }
    [buf appendString:@"\n"];
    
    // SignedHeaders
    NSMutableString *headerNameString = [[NSMutableString alloc] init];
    BOOL needSemicolon = NO;
    for (NSString *lcHeaderName in sortedLCHeaderNames) {
        if (!needSemicolon) {
            needSemicolon = YES;
        } else {
            [headerNameString appendString:@";"];
        }
        [headerNameString appendString:lcHeaderName];
    }
    *theSignedHeaders = headerNameString;
    [buf appendString:headerNameString];
    [buf appendString:@"\n"];
    
    // HashedPayload
    [buf appendString:theContentSHA256];
    
#if 0
    HSLogDebug(@"v4 canonical request: %@", buf);
    NSData *canonicalRequestData = [buf dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char *bytes = (unsigned char *)[canonicalRequestData bytes];
    NSMutableString *debugBuf = [NSMutableString string];
    for (NSUInteger i = 0; i < [canonicalRequestData length]; i++) {
        [debugBuf appendFormat:@"%02x ", bytes[i]];
    }
    HSLogDebug(@"canonical request bytes: %@", debugBuf);
#endif
    return buf;
}

@end
