//
//  iTermNotificationCenter.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/1/19.
//

#import "iTermNotificationCenter.h"
#import "iTermNotificationCenter+Protected.h"

#import "DebugLogging.h"
#import "NSNull+iTerm.h"
#import "NSObject+iTerm.h"

static NSString *const iTermInternalNotification = @"iTermInternalNotification";
static const char iTermNotificationTokenAssociatedObject;

@interface iTermNotificationCenterObserverUnregisterer : NSObject
- (instancetype)initWithToken:(id)token NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

// This may outlive the object it is associated with, but that's ok because the block verifies the
// owner still exists before calling its block.
@implementation iTermNotificationCenterObserverUnregisterer {
    id _token;
}

- (instancetype)initWithToken:(id)token {
    self = [super init];
    if (self) {
        _token = token;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:_token];
}

@end

@implementation iTermBaseNotification

- (instancetype)initPrivate {
    return [super init];
}

+ (void)subscribe:(NSObject *)owner selector:(SEL)selector {
    __weak NSObject *weakOwner = owner;
    [self internalSubscribe:owner withBlock:^(id notification) {
             [weakOwner it_performNonObjectReturningSelector:selector withObject:notification];
         }];
}

+ (void)internalSubscribe:(NSObject *)owner withBlock:(void (^)(id notification))block {
    __weak NSObject *weakOwner = owner;
    // This prevents infinite recursion if you cause the notification to be sent while handling it.
    __block BOOL handling = NO;
    id token = [[NSNotificationCenter defaultCenter] addObserverForName:iTermInternalNotification
                                                     object:[self class]
                                                     queue:nil
                                         usingBlock:^(NSNotification * _Nonnull notification) {
                                             id strongOwner = weakOwner;
                                             if (strongOwner) {
            if (handling) {
                return;
            }
            id object = notification.userInfo[@"object"];
            assert(object);

            handling = YES;
            block(object);
            handling = NO;
        }
    }];
    [owner it_setAssociatedObject:[[iTermNotificationCenterObserverUnregisterer alloc] initWithToken:token]
           forKey:(void *)&iTermNotificationTokenAssociatedObject];
}

- (void)post {
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermInternalNotification
                                          object:[self class]
                                          userInfo:@ { @"object": self }];
}

@end
