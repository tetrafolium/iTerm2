//
//  AdvancedWorkingDirectoryWindowController.h
//  iTerm
//
//  Created by George Nachman on 4/14/14.
//
//

#import "ProfileModel.h"
#import <Cocoa/Cocoa.h>

@interface AdvancedWorkingDirectoryWindowController
    : NSWindowController <NSWindowDelegate>

@property(nonatomic, copy) Profile *profile;

// An array of keys that may be changed in self.profile. All take string values.
@property(nonatomic, readonly) NSArray<NSString *> *allKeys;

@end
