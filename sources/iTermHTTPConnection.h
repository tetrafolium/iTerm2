//
//  iTermHTTPConnection.h
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import <Foundation/Foundation.h>

@class iTermSocketAddress;

@interface iTermHTTPConnection : NSObject

@property (nonatomic, readonly) dispatch_queue_t queue;
@property (nonatomic, readonly) iTermSocketAddress *clientAddress;
@property (nonatomic, readonly) NSNumber *euid;

- (instancetype)initWithFileDescriptor:(int)fd
    clientAddress:(iTermSocketAddress *)address
    euid:(NSNumber *)euid;

// All methods methods should only be called on self.queue:
- (NSURLRequest *)readRequest;
- (BOOL)sendResponseWithCode:(int)code reason:(NSString *)reason headers:(NSDictionary *)headers;
- (void)threadSafeClose;
- (dispatch_io_t)newChannelOnQueue:(dispatch_queue_t)queue;
- (void)badRequest;
- (void)unauthorized;
- (void)unacceptable;  // library version too old

// read a chunk of bytes. blocks.
- (NSMutableData *)readSynchronously;

// For testing
- (NSData *)nextByte;

@end
