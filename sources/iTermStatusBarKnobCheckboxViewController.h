//
//  iTermStatusBarKnobCheckboxViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import "iTermStatusBarComponentKnob.h"
#import <Cocoa/Cocoa.h>

@interface iTermStatusBarKnobCheckboxViewController
    : NSViewController <iTermStatusBarKnobViewController>

@property(nonatomic, strong) IBOutlet NSButton *checkbox;
@property(nonatomic) NSNumber *value;

@end
