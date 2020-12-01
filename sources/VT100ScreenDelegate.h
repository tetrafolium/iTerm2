#import <Cocoa/Cocoa.h>
#import "PTYTextViewDataSource.h"
#import "VT100TerminalDelegate.h"
#import "VT100Token.h"

@class VT100RemoteHost;
@class VT100Screen;
@class iTermColorMap;
@class iTermSelection;

@protocol VT100ScreenDelegate <NSObject>

// Returns the session's unique ID.
- (NSString *)screenSessionGuid;

// Screen contents have become dirty and should be redrawn right away.
- (void)screenNeedsRedraw;

// Schedule a refresh soon but not immediately.
- (void)screenScheduleRedrawSoon;

// Update window title, tab colors, and redraw view.
- (void)screenUpdateDisplay:(BOOL)redraw;

// Redraw the find on page view because search results may have been lost.
- (void)screenRefreshFindOnPageView;

// Called when the screen's size changes.
- (void)screenSizeDidChangeWithNewTopLineAt:(int)newTop;

// A change was made to the screen's contents which could cause a trigger to fire.
- (void)screenTriggerableChangeDidOccur;

// Called when the screen and terminal's attributes are reset
- (void)screenDidReset;

// Terminal can change title
- (BOOL)screenAllowTitleSetting;

// Called after text was added to the current line. Can be used to check triggers.
- (void)screenDidAppendStringToCurrentLine:(NSString *)string
    isPlainText:(BOOL)plainText;
- (void)screenDidAppendAsciiDataToCurrentLine:(AsciiData *)asciiData;

// Change the cursor's appearance.
- (void)screenSetCursorBlinking:(BOOL)blink;
- (void)screenSetCursorType:(ITermCursorType)type;

- (void)screenGetCursorType:(ITermCursorType *)cursorTypeOut
    blinking:(BOOL *)blinking;

- (void)screenResetCursorTypeAndBlink;


// Returns if the screen is permitted to resize the window.
- (BOOL)screenShouldInitiateWindowResize;

// The delegate should resize the screen to the given size.
- (void)screenResizeToPixelWidth:(int)width height:(int)height;
- (void)screenResizeToWidth:(int)width height:(int)height;

// Returns if terminal-initiated printing is permitted.
- (BOOL)screenShouldBeginPrinting;

// Sets the window title.
- (void)screenSetWindowTitle:(NSString *)title;

// Returns the current window title.
- (NSString *)screenWindowTitle;

// Returns the session's "icon title", which is just its name.
- (NSString *)screenIconTitle;

// Sets the session's name.
- (void)screenSetIconName:(NSString *)name;

// Returns the session's current name
- (NSString *)screenName;

// Returns if the window is full-screen.
- (BOOL)screenWindowIsFullscreen;

// Returns the top left pixel coordinate of the window.
- (NSPoint)screenWindowTopLeftPixelCoordinate;

// Delegate should move the window's top left point to the given screen coordinate.
- (void)screenMoveWindowTopLeftPointTo:(NSPoint)point;

// If flag is set, the window should be miniaturized; otherwise, deminiaturize.
- (void)screenMiniaturizeWindow:(BOOL)flag;

// If flag is set, bring the window to front; if not, move to back.
- (void)screenRaise:(BOOL)flag;

// Set the proxy icon of current session window.
- (void)screenSetPreferredProxyIcon:(NSString *)value;

// Returns if the window is miniaturized.
- (BOOL)screenWindowIsMiniaturized;

// Send input to the task.
- (void)screenWriteDataToTask:(NSData *)data;

// Returns the visible frame of the display the screen's window is in.
- (NSRect)screenWindowScreenFrame;

// Returns the frame of the window this screen is.
- (NSRect)screenWindowFrame;

// Returns the rect in the view that is currently visible.
- (NSSize)screenSize;

// If the flag is set, push the current window title onto a stack; otherwise push the icon title.
- (void)screenPushCurrentTitleForWindow:(BOOL)flag;

// If the flag is set, pop the current window title from the stack; otherwise pop the icon title.
- (void)screenPopCurrentTitleForWindow:(BOOL)flag;

// Returns the screen's number (in practice, this is the tab's number that cmd-N switches to).
- (int)screenNumber;

// Returns the window's index.
- (int)screenWindowIndex;

// Returns the tab's index.
- (int)screenTabIndex;

// Returns the pane's index.
- (int)screenViewIndex;

// Requests that tmux integration mode begin.
- (void)screenStartTmuxModeWithDCSIdentifier:(NSString *)dcsID;

// Handle a line of input in tmux mode in the token's string.
- (void)screenHandleTmuxInput:(VT100Token *)token;

// Returns if ambiguous characters are treated as fullwidth.
- (BOOL)screenShouldTreatAmbiguousCharsAsDoubleWidth;

// Number of scrollback lines changed.
- (void)screenDidChangeNumberOfScrollbackLines;

// Requests that the bell indicator be shown, notification be posted, etc.
- (void)screenShowBellIndicator;

// Request that a string be sent for printing.
- (void)screenPrintString:(NSString *)string;

// Request that the currently visible area of the screen be sent for printing.
- (void)screenPrintVisibleArea;

// Returns if iTermTabContentsChanged notifications should be published when the view is updated.
- (BOOL)screenShouldSendContentsChangedNotification;

// Returns whether terminal-generated notifications are allowed.
- (BOOL)screenShouldPostTerminalGeneratedAlert;

// Should this bell be ignored?
- (BOOL)screenShouldIgnoreBellWhichIsAudible:(BOOL)audible visible:(BOOL)visible;

// PTYTextView deselect
- (void)screenRemoveSelection;

// Selection range
- (iTermSelection *)screenSelection;

// Returns the size in pixels of a single cell.
- (NSSize)screenCellSize;

// Remove highlights of search results.
- (void)screenClearHighlights;

// Scrollback buffer deleted
- (void)screenDidClearScrollbackBuffer:(VT100Screen *)screen;

// Called when the mouse reporting mode changes.
- (void)screenMouseModeDidChange;

// An image should be flashed over the view.
- (void)screenFlashImage:(NSString *)identifier;

- (void)screenIncrementBadge;

// Bounce the dock. Set request to false to cancel.
- (void)screenRequestAttention:(VT100AttentionRequestType)request;
- (void)screenDidTryToUseDECRQCRA;

- (void)screenDisinterSession;

- (void)screenGetWorkingDirectoryWithCompletion:(void (^)(NSString *workingDirectory))completion;

// Show/hide the cursor.
- (void)screenSetCursorVisible:(BOOL)visible;

- (void)screenSetHighlightCursorLine:(BOOL)highlight;
- (void)screenClearCapturedOutput;

// Only called if the trackCursorLineMovement property is set.
- (void)screenCursorDidMoveToLine:(int)line;

// Returns if there is a view.
- (BOOL)screenHasView;

// Save the current scroll position
- (void)screenSaveScrollPosition;
- (VT100ScreenMark *)screenAddMarkOnLine:(int)line;
- (void)screenPromptDidStartAtLine:(int)line;
- (void)screenPromptDidEndAtLine:(int)line;

- (void)screenStealFocus;

- (void)screenSetProfileToProfileNamed:(NSString *)value;
- (void)screenSetPasteboard:(NSString *)value;
- (void)screenDidAddNote:(PTYNoteViewController *)note;
- (void)screenDidEndEditingNote;
- (void)screenCopyBufferToPasteboard;
- (BOOL)screenIsAppendingToPasteboard;
- (void)screenAppendDataToPasteboard:(NSData *)data;

- (void)screenWillReceiveFileNamed:(NSString *)name ofSize:(NSInteger)size preconfirmed:(BOOL)preconfirmed;
- (void)screenDidFinishReceivingFile;
- (void)screenDidFinishReceivingInlineFile;
- (void)screenDidReceiveBase64FileData:(NSString *)data;
- (void)screenFileReceiptEndedUnexpectedly;

- (void)screenRequestUpload:(NSString *)args;

- (iTermColorMap *)screenColorMap;
- (void)screenSetCurrentTabColor:(NSColor *)color;
- (void)screenSetTabColorRedComponentTo:(CGFloat)color;
- (void)screenSetTabColorGreenComponentTo:(CGFloat)color;
- (void)screenSetTabColorBlueComponentTo:(CGFloat)color;
- (void)screenSetColor:(NSColor *)color forKey:(int)key;
- (void)screenSelectColorPresetNamed:(NSString *)name;

- (void)screenCurrentHostDidChange:(VT100RemoteHost *)host;
- (void)screenCurrentDirectoryDidChangeTo:(NSString *)newPath;
- (void)screenDidReceiveCustomEscapeSequenceWithParameters:(NSDictionary<NSString *, NSString *> *)parameters
    payload:(NSString *)payload;
- (CGFloat)screenBackingScaleFactor;

// Ok to write to shell?
- (BOOL)screenShouldSendReport;
- (BOOL)screenShouldSendReportForVariable:(NSString *)name;

// FinalTerm stuff
- (void)screenCommandDidChangeWithRange:(VT100GridCoordRange)range;
- (void)screenCommandDidEndWithRange:(VT100GridCoordRange)range;
- (void)screenCommandDidExitWithCode:(int)code mark:(VT100ScreenMark *)maybeMark;
- (BOOL)screenShouldPlacePromptAtFirstColumn;

- (NSString *)screenProfileName;

- (void)screenLogWorkingDirectoryAtLine:(int)line
    withDirectory:(NSString *)directory
    pushed:(BOOL)pushed
    timely:(BOOL)timely;

- (void)screenSuggestShellIntegrationUpgrade;
- (void)screenDidDetectShell:(NSString *)shell;

- (void)screenSetBackgroundImageFile:(NSString *)filename;
- (void)screenSetBadgeFormat:(NSString *)theFormat;
- (void)screenSetUserVar:(NSString *)kvp;

- (BOOL)screenShouldReduceFlicker;
- (NSInteger)screenUnicodeVersion;
- (void)screenSetUnicodeVersion:(NSInteger)unicodeVersion;
- (void)screenSetLabel:(NSString *)label forKey:(NSString *)keyName;
- (void)screenPushKeyLabels:(NSString *)value;
- (void)screenPopKeyLabels:(NSString *)value;
- (void)screenSendModifiersDidChange;

- (void)screenTerminalAttemptedPasteboardAccess;
- (NSString *)screenValueOfVariableNamed:(NSString *)name;
- (void)screenReportFocusWillChangeTo:(BOOL)reportFocus;
- (void)screenReportPasteBracketingWillChangeTo:(BOOL)bracket;
- (void)screenDidReceiveLineFeed;
- (void)screenSoftAlternateScreenModeDidChange;
- (void)screenReportKeyUpDidChange:(BOOL)reportKeyUp;
- (BOOL)screenConfirmDownloadNamed:(NSString *)name canExceedSize:(NSInteger)limit;
- (BOOL)screenConfirmDownloadAllowed:(NSString *)name
    size:(NSInteger)size
    displayInline:(BOOL)displayInline
    promptIfBig:(BOOL *)promptIfBig;
- (BOOL)screenShouldClearScrollbackBuffer;
- (VT100GridRange)screenRangeOfVisibleLines;

@end
