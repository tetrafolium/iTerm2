//
//  iTermGitPollWorker.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import "iTermGitState.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermGitPollWorker : NSObject
+ (instancetype)instanceForPath:(NSString *)path;
- (void)requestPath:(NSString *)path
         completion:(void (^)(iTermGitState *_Nullable))completion;
- (void)invalidateCacheForPath:(NSString *)path;
@end

NS_ASSUME_NONNULL_END
