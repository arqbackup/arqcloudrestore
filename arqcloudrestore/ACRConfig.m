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

#import "ACRConfig.h"

static NSString *CONFIG_FILE = @"arqcloudrestore.config";


@implementation ACRConfig
- (instancetype)init:(NSError * __autoreleasing *)error {
    if (self = [super init]) {
        NSData *data = [NSData dataWithContentsOfFile:CONFIG_FILE options:0 error:error];
        if (data == nil) {
            return nil;
        }
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
        if (dict == nil) {
            return nil;
        }
        self.accessKeyId = [dict objectForKey:@"access_key_id"];
        self.secretAccessKey = [dict objectForKey:@"secret_access_key"];
        self.regionName = [dict objectForKey:@"region_name"];
        self.bucketName = [dict objectForKey:@"bucket_name"];
        
        if (self.accessKeyId == nil) {
            SETNSERROR_ARC([self errorDomain], -1, @"missing access_key_id in %@", CONFIG_FILE);
            return nil;
        }
        if (self.secretAccessKey == nil) {
            SETNSERROR_ARC([self errorDomain], -1, @"missing secret_access_key in %@", CONFIG_FILE);
            return nil;
        }
        if (self.regionName == nil) {
            SETNSERROR_ARC([self errorDomain], -1, @"missing region_name in %@", CONFIG_FILE);
            return nil;
        }
        if (self.bucketName == nil) {
            SETNSERROR_ARC([self errorDomain], -1, @"missing bucket_name in %@", CONFIG_FILE);
            return nil;
        }
    }
    return self;
}

- (NSString *)errorDomain {
    return @"ACRConfigErrorDomain";
}
@end
