//
//  CommandHistoryPopup.h
//  iTerm
//
//  Created by George Nachman on 1/14/14.
//
//

#import "PopupEntry.h"
#import "iTermPopupWindowController.h"
#import <Foundation/Foundation.h>

@class VT100RemoteHost;

@interface CommandHistoryPopupEntry : PopupEntry
@property(nonatomic, copy) NSString *command;
@property(nonatomic, retain) NSDate *date;
@end

@interface CommandHistoryPopupWindowController : iTermPopupWindowController

- (instancetype)initForAutoComplete:(BOOL)autocomplete;
- (instancetype)init NS_UNAVAILABLE;

// Returns uses if expand is NO or entries if it is YES.
- (NSArray *)commandsForHost:(VT100RemoteHost *)host
              partialCommand:(NSString *)partialCommand
                      expand:(BOOL)expand;

- (void)loadCommands:(NSArray *)commands
      partialCommand:(NSString *)partialCommand;

@end
