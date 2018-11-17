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

#import "URLSession.h"
#import "URLTask.h"


#define DEFAULT_TIMEOUT_SECONDS (90)


@interface URLSession() {
    NSURLSession *_session;
    NSMutableDictionary *_urlTasksByURLSessionTaskIdentifier;
    NSOperationQueue *_opQueue;
    dispatch_queue_t _urlTasksByURLSessionTaskIdentifierQueue;
}
@end


@implementation URLSession
+ (URLSession *)shared {
    static id sharedObject = nil;
    static dispatch_once_t sharedObjectOnce = 0;
    dispatch_once(&sharedObjectOnce, ^{
        sharedObject = [[self alloc] initInternal];
    });
    return sharedObject;
}

- (instancetype)initInternal {
    if (self = [super init]) {
        _opQueue = [[NSOperationQueue alloc] init];
        _opQueue.maxConcurrentOperationCount = 1;
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:_opQueue];
        _urlTasksByURLSessionTaskIdentifier = [NSMutableDictionary dictionary];
        _urlTasksByURLSessionTaskIdentifierQueue = dispatch_queue_create("URLSession urlTasks", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSHTTPURLResponse *)executeTransactionWithURL:(NSURL *)theURL method:(NSString *)theMethod requestHeaders:(NSDictionary *)theRequestHeaders requestBody:(NSData *)theRequestBody responseBuffer:(WriteBuffer *)theResponseBuffer dataTransferDelegate:(id <DataTransferDelegate>)theDTD error:(NSError * __autoreleasing *)error {
    
    URLTask *urlTask = [[URLTask alloc] initWithRequestBody:theRequestBody responseBuffer:theResponseBuffer dataTransferDelegate:theDTD];
    NSMutableURLRequest *mutableURLRequest = [[NSMutableURLRequest alloc] initWithURL:theURL];
    [mutableURLRequest setHTTPMethod:theMethod];
    [mutableURLRequest setCachePolicy:NSURLRequestReloadIgnoringCacheData];
    [mutableURLRequest setTimeoutInterval:DEFAULT_TIMEOUT_SECONDS];
    [mutableURLRequest setAllHTTPHeaderFields:theRequestHeaders];
    
    if ([theRequestBody length] > 0) {
        [mutableURLRequest setHTTPBodyStream:[urlTask httpInputStream]];
        [mutableURLRequest setValue:[NSString stringWithFormat:@"%ld", [theRequestBody length]] forHTTPHeaderField:@"Content-Length"];
    } else if (theRequestBody != nil) {
        // For 0-byte body, HTTPInputStream seems to hang, so just give it an empty NSData:
        [mutableURLRequest setHTTPBody:theRequestBody];
    }

    NSURLSessionDataTask *dataTask = [_session dataTaskWithRequest:mutableURLRequest];
    NSNumber *key = [NSNumber numberWithUnsignedInteger:dataTask.taskIdentifier];
    dispatch_sync(_urlTasksByURLSessionTaskIdentifierQueue, ^{
        [self->_urlTasksByURLSessionTaskIdentifier setObject:urlTask forKey:key];
    });
    
    [dataTask resume];
    
    [urlTask waitForCompletion];
    dispatch_sync(_urlTasksByURLSessionTaskIdentifierQueue, ^{
        [self->_urlTasksByURLSessionTaskIdentifier removeObjectForKey:key];
    });
    if ([urlTask errorOccurred]) {
        if ([urlTask.error code] == NSURLErrorCancelled) {
            HSLogDebug(@"URLSession canceled");
        } else if ([urlTask.error code] == NSURLErrorTimedOut) {
            HSLogDebug(@"URLSession timed out");
        } else {
            HSLogDebug(@"URLSession error: %@", [urlTask.error localizedDescription]);
        }
        if (error != NULL) {
            *error = [urlTask error];
        }
        return nil;
    }
    return [urlTask httpURLResponse];
}


#pragma mark NSURLSessionDelegate and subprotocols
/* The last message a session receives.  A session will only become
 * invalid because of a systemic error or when it has been
 * explicitly invalidated, in which case the error parameter will be nil.
 */
- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(nullable NSError *)error {
    HSLogError(@"unexpected: NSURLSession didBecomeInvalidWithError: %@", error);
}

/* If implemented, when a connection level authentication challenge
 * has occurred, this delegate will be given the opportunity to
 * provide authentication credentials to the underlying
 * connection. Some types of authentication will apply to more than
 * one request on a given connection to a server (SSL Server Trust
 * challenges).  If this delegate message is not implemented, the
 * behavior will be to use the default handling, which may involve user
 * interaction.
 */
//- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
// completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler;


/* Sent if a task requires a new, unopened body stream.  This may be
 * necessary when authentication has failed for any request that
 * involves a body stream.
 */
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task needNewBodyStream:(void (^)(NSInputStream * _Nullable bodyStream))completionHandler {
    __block URLTask *urlTask = nil;
    dispatch_sync(_urlTasksByURLSessionTaskIdentifierQueue, ^{
        urlTask = [self->_urlTasksByURLSessionTaskIdentifier objectForKey:[NSNumber numberWithUnsignedInteger:task.taskIdentifier]];
    });
    [urlTask resetInputStream];
    completionHandler([urlTask httpInputStream]);
}

/* Sent periodically to notify the delegate of upload progress.  This
 * information is also available as properties of the task.
 */
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend {
    __block URLTask *urlTask = nil;
    dispatch_sync(_urlTasksByURLSessionTaskIdentifierQueue, ^{
        urlTask = [self->_urlTasksByURLSessionTaskIdentifier objectForKey:[NSNumber numberWithUnsignedInteger:task.taskIdentifier]];
    });
    [urlTask didSendBodyData:bytesSent totalBytesSent:totalBytesSent totalBytesExpectedToSend:totalBytesExpectedToSend task:task];
}

/* Sent as the last message related to a specific task.  Error may be
 * nil, which implies that no error occurred and this task is complete.
 */
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error {
    __block URLTask *urlTask = nil;
    dispatch_sync(_urlTasksByURLSessionTaskIdentifierQueue, ^{
        urlTask = [self->_urlTasksByURLSessionTaskIdentifier objectForKey:[NSNumber numberWithUnsignedInteger:task.taskIdentifier]];
    });
    [urlTask didCompleteWithError:error];
}

/* The task has received a response and no further messages will be
 * received until the completion block is called. The disposition
 * allows you to cancel a request or to turn a data task into a
 * download task. This delegate message is optional - if you do not
 * implement it, you can get the response as a property of the task.
 *
 * This method will not be called for background upload tasks (which cannot be converted to download tasks).
 */
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    __block URLTask *urlTask = nil;
    dispatch_sync(_urlTasksByURLSessionTaskIdentifierQueue, ^{
        urlTask = [self->_urlTasksByURLSessionTaskIdentifier objectForKey:[NSNumber numberWithUnsignedInteger:dataTask.taskIdentifier]];
    });
    [urlTask didReceiveResponse:response];
    completionHandler(NSURLSessionResponseAllow);
}

/* Notification that a data task has become a download task.  No
 * future messages will be sent to the data task.
 */
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didBecomeDownloadTask:(NSURLSessionDownloadTask *)downloadTask {
    NSAssert(1==0, @"should never happen");
}

/* Sent when data is available for the delegate to consume.  It is
 * assumed that the delegate will retain and not copy the data.  As
 * the data may be discontiguous, you should use
 * [NSData enumerateByteRangesUsingBlock:] to access it.
 */
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    __block URLTask *urlTask = nil;
    dispatch_sync(_urlTasksByURLSessionTaskIdentifierQueue, ^{
        urlTask = [self->_urlTasksByURLSessionTaskIdentifier objectForKey:[NSNumber numberWithUnsignedInteger:dataTask.taskIdentifier]];
    });
    [urlTask didReceiveData:data];
}

/* Invoke the completion routine with a valid NSCachedURLResponse to
 * allow the resulting data to be cached, or pass nil to prevent
 * caching. Note that there is no guarantee that caching will be
 * attempted for a given resource, and you should not rely on this
 * message to receive the resource data.
 */
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask willCacheResponse:(NSCachedURLResponse *)proposedResponse completionHandler:(void (^)(NSCachedURLResponse * _Nullable cachedResponse))completionHandler {
    completionHandler(nil);
}
@end
