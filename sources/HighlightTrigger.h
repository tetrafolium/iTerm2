//
//  HighlightTrigger.h
//  iTerm2
//
//  Created by George Nachman on 9/23/11.
//

#import "Trigger.h"
#import <Cocoa/Cocoa.h>

@interface HighlightTrigger : Trigger

+ (NSString *)title;
- (void)setTextColor:(NSColor *)textColor;
- (void)setBackgroundColor:(NSColor *)backgroundColor;

@end
