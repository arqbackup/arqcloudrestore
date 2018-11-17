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

#import "Exclusion.h"


@implementation Exclusion
- (instancetype)initWithType:(ExclusionType)theType text:(NSString *)theText {
    if (self = [super init]) {
        self.type = theType;
        self.text = theText;
    }
    return self;
}
- (instancetype)initWithJSON:(NSDictionary *)theJSON {
    return [self initWithType:[[theJSON objectForKey:@"type"] unsignedIntValue] text:[theJSON objectForKey:@"text"]];
}

- (NSString *)displayDescription {
    NSString *ret = @"Unknown";
    switch(self.type) {
        case kExclusionTypeFileNameIs:
            ret = [@"File/folder name is " stringByAppendingString:self.text];
            break;
        case kExclusionTypeFileNameContains:
            ret = [@"File/folder name contains " stringByAppendingString:self.text];
            break;
        case kExclusionTypeFileNameStartsWith:
            ret = [@"File/folder name starts with " stringByAppendingString:self.text];
            break;
        case kExclusionTypeFileNameEndsWith:
            ret = [@"File/folder name ends with " stringByAppendingString:self.text];
            break;
        case kExclusionTypePathEndsWith:
            ret = [@"File/folder path ends with " stringByAppendingString:self.text];
            break;
    }
    return ret;
}
- (NSDictionary *)toJSON {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithUnsignedInt:self.type], @"type",
            self.text, @"text",
            nil];
}
- (BOOL)matchesFilename:(NSString *)theFilename path:(NSString *)thePath {
    BOOL ret = NO;
    switch(self.type) {
        case kExclusionTypeFileNameIs:
            ret = [theFilename isEqualToString:self.text];
            break;
        case kExclusionTypeFileNameContains:
            ret = [theFilename containsString:self.text]; // Only available on 10.10 or later.
            break;
        case kExclusionTypeFileNameStartsWith:
            ret = [theFilename hasPrefix:self.text];
            break;
        case kExclusionTypeFileNameEndsWith:
            ret = [theFilename hasSuffix:self.text];
            break;
        case kExclusionTypePathEndsWith:
            ret = [thePath hasSuffix:self.text];
            break;
    }
    return ret;
}


#pragma mark NSObject
- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[Exclusion class]]) {
        return NO;
    }
    Exclusion *other = (Exclusion *)object;
    return self.type == other.type && [self.text isEqualToString:other.text];
}
- (NSUInteger)hash {
    return [self.text hash];
}
@end
