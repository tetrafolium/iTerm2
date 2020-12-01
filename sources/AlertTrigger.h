//
//  AlertTrigger.h
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "Trigger.h"
#import <Cocoa/Cocoa.h>

@interface AlertTrigger : Trigger

+ (NSString *)title;
- (BOOL)takesParameter;

@end
