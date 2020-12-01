#import "VT100State.h"
#import <Foundation/Foundation.h>

@interface VT100StateTransition : NSObject

@property(nonatomic, retain) VT100State *toState;
@property(nonatomic, copy) VT100StateAction action;

+ (instancetype)transitionToState:(VT100State *)toState
                       withAction:(VT100StateAction)action;

@end
