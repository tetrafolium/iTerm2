// Implements the Autocomplete UI. It grabs the word behind the cursor and opens
// a popup window with likely suffixes. Selecting one appends it, and you can
// search the list Quicksilver-style.

#import "LineBuffer.h"
#import "PTYSession.h"
#import "iTermPopupWindowController.h"
#import <Cocoa/Cocoa.h>

@class iTermCommandHistoryEntryMO;

@interface AutocompleteView : iTermPopupWindowController

- (void)onOpen;
- (void)refresh;
- (void)onClose;
- (void)rowSelected:(id)sender;
- (void)more;
- (void)less;

// Add a bunch of iTermCommandHistoryEntryMO*s. 'context' gives the prefix that
// generated the entries.
- (void)addCommandEntries:(NSArray<iTermCommandHistoryEntryMO *> *)entries
                  context:(NSString *)context;

@end
