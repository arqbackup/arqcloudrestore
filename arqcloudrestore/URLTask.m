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

#import "URLTask.h"
#import "WriteBuffer.h"
#import "DataTransferDelegate.h"


@interface URLTask() {
    NSData *_requestBody;
    NSInputStream *_inputStream;
    WriteBuffer *_responseBuffer;
    id <DataTransferDelegate> _dtd;
    BOOL _errorOccurred;
    NSError *_error;
    NSUInteger _totalBytesSent;
    NSHTTPURLResponse *_httpURLResponse;
    dispatch_semaphore_t _semaphore;
}
@end


@implementation URLTask
- (instancetype)initWithRequestBody:(NSData *)theRequestBody responseBuffer:(WriteBuffer *)theResponseBuffer dataTransferDelegate:(id <DataTransferDelegate>)theDTD {
    if (self = [super init]) {
        if (theRequestBody != nil) {
            _requestBody = theRequestBody;
            _inputStream = [[NSInputStream alloc] initWithData:theRequestBody];
        }
        _responseBuffer = theResponseBuffer;
        _dtd = theDTD;
        _semaphore = dispatch_semaphore_create(0);
    }
    return self;
}

- (void)waitForCompletion {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
}
- (BOOL)errorOccurred {
    return _errorOccurred;
}
- (NSError *)error {
    return _error;
}
- (NSHTTPURLResponse *)httpURLResponse {
    return _httpURLResponse;
}

- (void)resetInputStream {
    _inputStream = [[NSInputStream alloc] initWithData:_requestBody];
}
- (NSInputStream *)httpInputStream {
    return _inputStream;
}

- (void)didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend task:(NSURLSessionTask *)theTask {
    if ([_dtd respondsToSelector:@selector(dataTransferDidUploadBytes:error:)]) {
        int64_t bytesSentThisTime = bytesSent;
        NSError *myError = nil;
        if (![_dtd dataTransferDidUploadBytes:bytesSentThisTime error:&myError]) {
            _error = myError;
            _errorOccurred = YES;
            HSLogDebug(@"canceling HTTP task %@", self);
            [theTask cancel];
        }
    }
    _totalBytesSent = totalBytesSent;
}
- (void)didCompleteWithError:(NSError *)theError {
    if (theError != nil) {
        _errorOccurred = YES;
        _error = theError;
    }
    dispatch_semaphore_signal(_semaphore);
}
- (void)didReceiveResponse:(NSURLResponse *)response {
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        _httpURLResponse = (NSHTTPURLResponse *)response;
        [_responseBuffer reset];
    } else {
        HSLogError(@"unexpected NSURLResponse (not an NSHTTPURLResponse)");
    }
}
- (void)didReceiveData:(NSData *)theData {
    [_responseBuffer appendData:theData];
}
@end
