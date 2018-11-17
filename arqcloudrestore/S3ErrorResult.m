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

#import "S3ErrorResult.h"
#import "S3Service.h"


@interface S3ErrorResult() {
    NSMutableDictionary *_values;
    NSMutableString *_currentStringBuffer;
    BOOL _errorOccurred;
    NSError *_amazonError;
}
@end


@implementation S3ErrorResult
- (id)initWithAction:(NSString *)theAction data:(NSData *)theData httpErrorCode:(int)theHTTPStatusCode stringToSign:(NSString *)theStringToSign canonicalRequest:(NSString *)theCanonicalRequest {
    if (self = [super init]) {
        _values = [[NSMutableDictionary alloc] init];
        NSXMLParser *parser = [[NSXMLParser alloc] initWithData:theData];
        [parser setDelegate:self];
        [parser parse];
        if (_errorOccurred) {
            HSLogDebug(@"error parsing amazon result %@", [[NSString alloc] initWithData:theData encoding:NSUTF8StringEncoding]);
            if (theHTTPStatusCode == 500) {
                // DreamObjects can return a 500 with an HTML response body, so we fake it as an Amazon XML error response so that S3Request retries the request:
                NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:500], @"HTTPStatusCode", @"InternalError", @"AmazonCode", nil];
                _amazonError = [[NSError alloc] initWithDomain:[S3Service errorDomain] code:S3SERVICE_ERROR_AMAZON_ERROR userInfo:userInfo];
            } else {
                _amazonError = [[NSError alloc] initWithDomain:[S3Service errorDomain] code:S3SERVICE_ERROR_AMAZON_ERROR description:[NSString stringWithFormat:@"%@: error (missing or unreadable error details)", theAction]];
            }
        } else {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            // Typically we have 'Code', 'Message', and 'Resource' keys in userInfo.
            // We create an error with 'AmazonCode', 'AmazonMessage', 'AmazonResource' and NSLocalizedDescriptionKey.
            [userInfo setObject:[NSNumber numberWithInt:theHTTPStatusCode] forKey:@"HTTPStatusCode"];
            for (NSString *key in [_values allKeys]) {
                [userInfo setObject:[_values objectForKey:key] forKey:[@"Amazon" stringByAppendingString:key]];
            }
            NSString *msg = nil;
            if ([_values objectForKey:@"Message"] == nil) {
                msg = [NSString stringWithFormat:@"S3 error %ld: %@", (unsigned long)theHTTPStatusCode, [userInfo objectForKey:@"AmazonCode"]];
            } else {
                msg = [NSString stringWithFormat:@"%@: %@", theAction, [_values objectForKey:@"Message"]];
            }
            [userInfo setObject:msg forKey:NSLocalizedDescriptionKey];
            if ([[userInfo objectForKey:@"AmazonCode"] isEqualToString:@"SignatureDoesNotMatch"]) {
                if (theStringToSign != nil) {
                    [userInfo setObject:theStringToSign forKey:@"ArqStringToSign"];
                }
                if (theCanonicalRequest != nil) {
                    [userInfo setObject:theCanonicalRequest forKey:@"ArqCanonicalRequest"];
                }
            }
            
            _amazonError = [[NSError alloc] initWithDomain:[S3Service errorDomain] code:S3SERVICE_ERROR_AMAZON_ERROR userInfo:userInfo];
        }
    }
    return self;
}

- (NSError *)error {
    return _amazonError;
}


#pragma mark - NSXMLParserDelegate
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName 
  namespaceURI:(NSString *)namespaceURI 
 qualifiedName:(NSString *)qualifiedName 
    attributes:(NSDictionary *)attributeDict {
    _currentStringBuffer = nil;
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (_currentStringBuffer == nil) {
        _currentStringBuffer = [[NSMutableString alloc] init];
    }
    [_currentStringBuffer appendString:string];
}
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if (_currentStringBuffer != nil) {
        [_values setObject:[NSString stringWithString:_currentStringBuffer] forKey:elementName];
    }
}
- (void)parser:(NSXMLParser *)theParser parseErrorOccurred:(NSError *)parseError {
    _errorOccurred = YES;
    HSLogError(@"error parsing amazon error response: %@", parseError);
}
- (void)parserDidEndDocument:(NSXMLParser *)parser {
}

@end
