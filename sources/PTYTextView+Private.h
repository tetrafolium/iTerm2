//
//  PTYTextView+Private.h
//  iTerm2
//
//  Created by George Nachman on 4/15/19.
//

#import "PTYTextView.h"

#import "iTermBadgeLabel.h"
#import "iTermFindCursorView.h"
#import "iTermFindOnPageHelper.h"
#import "iTermKeyboardHandler.h"
#import "iTermQuickLookController.h"
#import "iTermSelection.h"
#import "iTermSelectionScrollHelper.h"
#import "iTermSemanticHistoryController.h"
#import "iTermTextViewAccessibilityHelper.h"
#import "iTermTextViewContextMenuHelper.h"

@class iTermShellIntegrationWindowController;
@class iTermURLActionHelper;
@class PTYMouseHandler;

@interface PTYTextView () <
    iTermBadgeLabelDelegate, iTermTextViewAccessibilityHelperDelegate,
    iTermFindCursorViewDelegate, iTermFindOnPageHelperDelegate,
    iTermKeyboardHandlerDelegate, iTermSelectionDelegate,
    iTermSelectionScrollHelperDelegate, NSDraggingSource, NSPopoverDelegate> {
  NSCursor *cursor_;
  PTYMouseHandler *_mouseHandler;
  iTermURLActionHelper *_urlActionHelper;
  iTermShellIntegrationWindowController *_shellIntegrationInstallerWindow;
  iTermTextViewContextMenuHelper *_contextMenuHelper;
}

@property(nonatomic, strong) iTermSelection *selection;
@property(nonatomic, strong)
    iTermSemanticHistoryController *semanticHistoryController;
@property(nonatomic, strong) iTermFindCursorView *findCursorView;
@property(nonatomic, strong)
    NSWindow *findCursorWindow; // For find-cursor animation
@property(nonatomic, strong) iTermQuickLookController *quickLookController;
@property(strong, readwrite) NSTouchBar *touchBar NS_AVAILABLE_MAC(10_12_2);

- (void)addNote;
- (NSString *)selectedTextCappedAtSize:(int)maxBytes;
- (BOOL)_haveShortSelection;
- (BOOL)withRelativeCoord:(VT100GridAbsCoord)coord
                    block:(void (^NS_NOESCAPE)(VT100GridCoord coord))block;
- (BOOL)withRelativeCoordRange:(VT100GridAbsCoordRange)range
                         block:(void (^NS_NOESCAPE)(VT100GridCoordRange))block;

@end
