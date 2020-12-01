//
//  iTermSlowOperationGateway.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// This runs potentially very slow operations outside the process. If they hang
// forever it's cool, we'll just kill the process and start it over.
// Consequently, these operations are not 100% reliable.
@interface iTermSlowOperationGateway : NSObject

// If this is true then it's much more likely to succeed, but no guarantees as
// this thing has inherent race conditiosn.
@property(nonatomic, readonly) BOOL ready;

// Monotonic source of request IDs.
@property(nonatomic, readonly) int nextReqid;

+ (instancetype)sharedInstance;

- (instancetype)init NS_UNAVAILABLE;

// NOTE: the completion block won't be called if it times out.
- (void)checkIfDirectoryExists:(NSString *)directory
                    completion:(void (^)(BOOL))completion;

- (void)asyncGetInfoForProcess:(int)pid
                        flavor:(int)flavor
                           arg:(uint64_t)arg
                    buffersize:(int)buffersize
                         reqid:(int)reqid
                    completion:(void (^)(int rc, NSData *buffer))completion;

// Get the value of an environment variable from the user's shell.
- (void)exfiltrateEnvironmentVariableNamed:(NSString *)name
                                     shell:(NSString *)shell
                                completion:
                                    (void (^)(NSString *value))completion;

- (void)runCommandInUserShell:(NSString *)command
                   completion:(void (^)(NSString *_Nullable value))completion;

@end

NS_ASSUME_NONNULL_END
