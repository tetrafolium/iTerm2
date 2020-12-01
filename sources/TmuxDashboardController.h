//
//  TmuxDashboardController.h
//  iTerm
//
//  Created by George Nachman on 12/23/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import "TmuxSessionsTable.h"
#import "TmuxWindowsTable.h"
#import <Cocoa/Cocoa.h>

@class TmuxController;

@interface TmuxDashboardController
    : NSWindowController <TmuxSessionsTableProtocol, TmuxWindowsTableProtocol>

+ (instancetype)sharedInstance;
- (void)didAttachWithHiddenWindows:(BOOL)anyHidden tooManyWindows:(BOOL)tooMany;

@end
