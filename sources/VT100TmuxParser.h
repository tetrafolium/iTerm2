//
//  VT100TmuxParser.h
//  iTerm
//
//  Created by George Nachman on 3/10/14.
//
//

#import "VT100DCSParser.h"
#import "VT100Token.h"
#import "iTermParser.h"
#import <Foundation/Foundation.h>

@interface VT100TmuxParser : NSObject <VT100DCSParserHook>
- (instancetype)initInRecoveryMode;
@end
