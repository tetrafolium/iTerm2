#import <Cocoa/Cocoa.h>

#import "ITAddressBookMgr.h"
#import "NSDictionary+iTerm.h"
#import "iTermHotkeyPreferencesModel.h"
#import "iTermShortcut.h"

@interface iTermHotkeyPreferencesWindowController : NSWindowController

// Assign to this before using it. UI will be updated on assignment. Model will
// be updated when the user interacts with the UI.
@property(nonatomic, retain) iTermHotkeyPreferencesModel *model;
@property(nonatomic, copy)
    NSArray<iTermHotKeyDescriptor *> *descriptorsInUseByOtherProfiles;

- (void)setExplanation:(NSString *)explanation;

@end
