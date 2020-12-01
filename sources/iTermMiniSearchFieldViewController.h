//
//  iTermMiniSearchFieldViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/7/18.
//

#import "iTermFindViewController.h"
#import <Cocoa/Cocoa.h>

@interface iTermMiniSearchFieldViewController
    : NSViewController <iTermFindViewController>
@property(nonatomic) BOOL canClose;

- (void)sizeToFitSize:(NSSize)size;

@end
