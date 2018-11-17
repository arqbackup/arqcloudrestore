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

#import <Security/Security.h>
#import <Security/SecCertificate.h>
#import "NSError_extra.h"
#import "S3ServiceConstants.h"


enum {
    kUserInfoValueTypeString = 1,
    kUserInfoValueTypeNumber = 2,
    kUserInfoValueTypeNSURL = 3,
    kUserInfoValueTypeNSError = 4,
    kUserInfoValueTypeUnknown = 5
};


@implementation NSError (extra)
- (instancetype)initWithJSON:(NSDictionary *)theJSON {
    NSString *domain = [theJSON objectForKey:@"domain"];
    NSInteger code = [[theJSON objectForKey:@"code"] integerValue];
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    NSDictionary *userInfoJSON = [theJSON objectForKey:@"userInfo"];
    for (NSString *key in [userInfoJSON allKeys]) {
        NSDictionary *valueDict = [userInfoJSON objectForKey:key];
        int jsonValueType = [[valueDict objectForKey:@"type"] intValue];
        id jsonValue = [valueDict objectForKey:@"value"];
        id value = jsonValue;
        if (jsonValueType == kUserInfoValueTypeNSURL) {
            value = [NSURL URLWithString:value];
        } else if (jsonValueType == kUserInfoValueTypeNSError) {
            value = [[NSError alloc] initWithJSON:jsonValue];
        }
        [userInfo setObject:value forKey:key];
    }
    
    return [self initWithDomain:domain code:code userInfo:userInfo];
}
- (id)initWithDomain:(NSString *)domain code:(NSInteger)code description:(NSString *)theDescription {
    if (theDescription == nil) {
        theDescription = @"(missing description)";
    }
    return [self initWithDomain:domain code:code userInfo:[NSDictionary dictionaryWithObject:theDescription forKey:NSLocalizedDescriptionKey]];
}
- (BOOL)isErrorWithDomain:(NSString *)theDomain code:(int)theCode {
    return [self code] == theCode && [[self domain] isEqualToString:theDomain];
}
- (NSDictionary *)toJSON {
    NSMutableDictionary *ret = [NSMutableDictionary dictionary];
    [ret setObject:[self domain] forKey:@"domain"];
    [ret setObject:[NSNumber numberWithInteger:[self code]] forKey:@"code"];
    NSDictionary *theUserInfo = [self userInfo];

    NSMutableDictionary *userInfoDict = [NSMutableDictionary dictionary];
    for (NSString *key in [theUserInfo allKeys]) {
        id value = [theUserInfo objectForKey:key];
        int jsonValueType = kUserInfoValueTypeUnknown;
        id jsonValue = value;
        if ([value isKindOfClass:[NSString class]]) {
            jsonValueType = kUserInfoValueTypeString;
        } else if ([value isKindOfClass:[NSURL class]]) {
            jsonValueType = kUserInfoValueTypeNSURL;
            jsonValue = [value description];
        } else if ([value isKindOfClass:[NSError class]]) {
            NSError *underlyingError = (NSError *)value;
            jsonValueType = kUserInfoValueTypeNSError;
            jsonValue = [underlyingError toJSON];
        } else if ([value isKindOfClass:[NSNumber class]]) {
            jsonValueType = kUserInfoValueTypeNumber;
        } else {
            HSLogWarn(@"converting NSError UserInfo value into string: key=%@ valueclass=%@ value=%@", key, [value class], value);
            jsonValue = [value description];
        }
        [userInfoDict setObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:jsonValueType], @"type", jsonValue, @"value", nil] forKey:key];
    }
    [ret setObject:userInfoDict forKey:@"userInfo"];
    
    return ret;
}
- (BOOL)isConnectionResetError {
    if ([[self domain] isEqualToString:NSPOSIXErrorDomain] || [[self domain] isEqualToString:@"NSPOSIXErrorDomain"]) {
        if ([self code] == ENETRESET
            || [self code] == ECONNRESET) {
            return YES;
        }
    }
    return NO;
}
- (BOOL)isTransientError {
    if ([[self domain] isEqualToString:NSPOSIXErrorDomain] || [[self domain] isEqualToString:@"NSPOSIXErrorDomain"]) {
        if ([self code] == ENETDOWN
            || [self code] == EADDRNOTAVAIL
            || [self code] == ENETUNREACH
            || [self code] == ENETRESET
            || [self code] == ECONNABORTED
            || [self code] == ECONNRESET
            || [self code] == EISCONN
            || [self code] == ENOTCONN
            || [self code] == ETIMEDOUT
            || [self code] == ECONNREFUSED
            || [self code] == EHOSTDOWN
            || [self code] == EHOSTUNREACH
            || [self code] == EPIPE) {
            return YES;
        }
    }
    if ([[self domain] isEqualToString:(NSString *)kCFErrorDomainCFNetwork]) {
        return YES;
    }
    if ([[self domain] isEqualToString:NSURLErrorDomain]) {
        if ([self code] == NSURLErrorTimedOut
            || [self code] == NSURLErrorCannotFindHost
            || [self code] == NSURLErrorCannotConnectToHost
            || [self code] == NSURLErrorNetworkConnectionLost
            || [self code] == NSURLErrorDNSLookupFailed
            || [self code] == NSURLErrorResourceUnavailable
            || [self code] == NSURLErrorNotConnectedToInternet) {
            return YES;
        }
    }
    if ([[self domain] isEqualToString:[S3ServiceConstants errorDomain]] && [self code] == S3SERVICE_ERROR_AMAZON_ERROR) {
        if ([[[self userInfo] objectForKey:@"AmazonCode"] isEqualToString:@"PoorAccountStanding"]) {
            // Wasabi returns this AmazonCode if the account doesn't have valid billing info and/or the trial has expired.
            HSLogDebug(@"Wasabi account probably has invalid billing info");
        } else {
            return YES;
        }
    }
    
    if ([[self domain] isEqualToString:@"NSOSStatusErrorDomain"] && [self code] <= errSSLProtocol && [self code] >= errSSLLast) {
        return YES;
    }
    if ([self isSSLError]) {
        return YES;
    }
    if ([self code] == ERROR_TIMEOUT) {
        return YES;
    }
    
    HSLogDebug(@"%@ not a transient error", self);
    return NO;
}
- (BOOL)isSSLError {
    return [[self domain] isEqualToString:NSURLErrorDomain]
    && [self code] <= NSURLErrorSecureConnectionFailed
    && [self code] >= NSURLErrorClientCertificateRejected;
}
@end
