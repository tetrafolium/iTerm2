//
//  BellTrigger.h
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "Trigger.h"
#import <Cocoa/Cocoa.h>

@interface BellTrigger : Trigger {
}

+ (NSString *)title;
- (BOOL)takesParameter;

@end
