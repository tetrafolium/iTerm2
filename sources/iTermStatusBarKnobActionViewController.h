//
//  iTermStatusBarKnobActionViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/19.
//

#import "iTermStatusBarComponentKnob.h"
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermStatusBarKnobActionViewController
    : NSViewController <iTermStatusBarKnobViewController>

@property(nonatomic) NSDictionary *value;

@end

NS_ASSUME_NONNULL_END
