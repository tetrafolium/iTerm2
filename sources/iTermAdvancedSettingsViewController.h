//
//  iTermAdvancedSettingsController.h
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import "iTermSearchableViewController.h"
#import <Cocoa/Cocoa.h>

extern BOOL gIntrospecting;

@interface iTermAdvancedSettingsViewController
    : NSViewController <iTermSearchableViewController, NSTableViewDataSource,
                        NSTableViewDelegate>

@end
