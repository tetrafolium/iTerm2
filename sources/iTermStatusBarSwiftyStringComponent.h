//
//  iTermStatusBarSwiftyStringComponent.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import "iTermStatusBarTextComponent.h"
#import "iTermSwiftyString.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermStatusBarSwiftyStringComponentExpressionKey;

// A status bar component showing a swifty string.
@interface iTermStatusBarSwiftyStringComponent : iTermStatusBarTextComponent
@property(nonatomic, readonly) NSString *value;
@end

NS_ASSUME_NONNULL_END
