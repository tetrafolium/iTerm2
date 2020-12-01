//
//  VT100SixelParser.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/11/19.
//

#import "VT100DCSParser.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VT100SixelParser : NSObject <VT100DCSParserHook>
- (instancetype)initWithParameters:(NSArray *)parameters;
@end

NS_ASSUME_NONNULL_END
