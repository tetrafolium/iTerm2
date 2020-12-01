//
//  InteractiveScriptTrigger.h
//  iTerm
//
//  Created by George Nachman on 9/24/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ScriptTrigger.h"
#import <Cocoa/Cocoa.h>

@interface CoprocessTrigger : Trigger

+ (NSString *)title;

@end

@interface MuteCoprocessTrigger : CoprocessTrigger

+ (NSString *)title;

@end
