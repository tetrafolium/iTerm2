//
//  GeneralPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "iTermPreferencesBaseViewController.h"
#import <Cocoa/Cocoa.h>

@interface GeneralPreferencesViewController : iTermPreferencesBaseViewController

// Custom folder stuff
- (IBAction)browseCustomFolder:(id)sender;
- (IBAction)pushToCustomFolder:(id)sender;

@end
