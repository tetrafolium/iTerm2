#import "PTYTextView.h"

#import "charmaps.h"
#import "FileTransferManager.h"
#import "FontSizeEstimator.h"
#import "FutureMethods.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "iTerm.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermBadgeLabel.h"
#import "iTermColorMap.h"
#import "iTermController.h"
#import "iTermCPS.h"
#import "iTermFindCursorView.h"
#import "iTermFindOnPageHelper.h"
#import "iTermFindPasteboard.h"
#import "iTermImageInfo.h"
#import "iTermKeyboardHandler.h"
#import "iTermLaunchServices.h"
#import "iTermMetalClipView.h"
#import "iTermMouseCursor.h"
#import "iTermPreferences.h"
#import "iTermPrintAccessoryViewController.h"
#import "iTermQuickLookController.h"
#import "iTermRateLimitedUpdate.h"
#import "iTermScrollAccumulator.h"
#import "iTermSecureKeyboardEntryController.h"
#import "iTermSelection.h"
#import "iTermSelectionScrollHelper.h"
#import "iTermSetFindStringNotification.h"
#import "iTermShellHistoryController.h"
#import "iTermTextDrawingHelper.h"
#import "iTermTextExtractor.h"
#import "iTermTextViewAccessibilityHelper.h"
#import "iTermURLActionHelper.h"
#import "iTermURLStore.h"
#import "iTermWebViewWrapperViewController.h"
#import "iTermWarning.h"
#import "MovePaneController.h"
#import "MovingAverage.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSCharacterSet+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSEvent+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSPasteboard+iTerm.h"
#import "NSSavePanel+iTerm.h"
#import "NSResponder+iTerm.h"
#import "NSSavePanel+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+iTerm.h"
#import "NSWindow+PSM.h"
#import "PasteboardHistory.h"
#import "PointerController.h"
#import "PointerPrefsController.h"
#import "PreferencePanel.h"
#import "PTYMouseHandler.h"
#import "PTYNoteView.h"
#import "PTYNoteViewController.h"
#import "PTYScrollView.h"
#import "PTYTab.h"
#import "PTYTask.h"
#import "PTYTextView+ARC.h"
#import "PTYTextView+Private.h"
#import "PTYWindow.h"
#import "RegexKitLite.h"
#import "SCPPath.h"
#import "SearchResult.h"
#import "SmartMatch.h"
#import "SmartSelectionController.h"
#import "SolidColorView.h"
#import "ThreeFingerTapGestureRecognizer.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenMark.h"
#import "WindowControllerInterface.h"

#import <CoreServices/CoreServices.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <sys/time.h>

#import <WebKit/WebKit.h>

@implementation iTermHighlightedRow

- (instancetype)initWithAbsoluteLineNumber:(long long)row success:(BOOL)success {
    self = [super init];
    if (self) {
        _absoluteLineNumber = row;
        _creationDate = [NSDate timeIntervalSinceReferenceDate];
        _success = success;
    }
    return self;
}

@end

@interface PTYTextView(MouseHandler)<iTermSecureInputRequesting, PTYMouseHandlerDelegate>
@end

@implementation PTYTextView {
    // -refresh does not want to be reentrant.
    BOOL _inRefresh;

    // geometry
    double _lineHeight;
    double _charWidth;

    // NSTextInputClient support

    NSDictionary *_markedTextAttributes;

    // blinking cursor
    NSTimeInterval _timeOfLastBlink;

    // Helps with "selection scroll"
    iTermSelectionScrollHelper *_selectionScrollHelper;

    // Helps drawing text and background.
    iTermTextDrawingHelper *_drawingHelper;

    // Last position that accessibility was read up to.
    int _lastAccessibilityCursorX;
    int _lastAccessibiltyAbsoluteCursorY;

    // Detects three finger taps (as opposed to clicks).
    ThreeFingerTapGestureRecognizer *threeFingerTapGestureRecognizer_;

    // Position of cursor last time we looked. Since the cursor might move around a lot between
    // calls to -updateDirtyRects without making any changes, we only redraw the old and new cursor
    // positions.
    VT100GridAbsCoord _previousCursorCoord;

    iTermSelection *_oldSelection;

    // Size of the documentVisibleRect when the badge was set.
    NSSize _badgeDocumentVisibleRectSize;

    // Show a background indicator when in broadcast input mode
    BOOL _showStripesWhenBroadcastingInput;

    iTermTextViewAccessibilityHelper *_accessibilityHelper;
    iTermBadgeLabel *_badgeLabel;

    NSPoint _mouseLocationToRefuseFirstResponderAt;

    NSMutableArray<iTermHighlightedRow *> *_highlightedRows;

    // Used to report scroll wheel mouse events.
    iTermScrollAccumulator *_scrollAccumulator;

    iTermRateLimitedUpdate *_shadowRateLimit;
}


- (instancetype)initWithFrame:(NSRect)frameRect {
    // Must call initWithFrame:colorMap:.
    assert(false);
}

// This is an attempt to fix performance problems that appeared in macOS 10.14
// (rdar://45295749, also mentioned in PTYScrollView.m).
//
// It seems that some combination of implementing drawRect:, not having a
// layer, having a frame larger than the clip view, and maybe some other stuff
// I can't figure out causes terrible performance problems.
//
// For a while I worked around this by dismembering the scroll view. The scroll
// view itself would be hidden, while its scrollers were reparented and allowed
// to remain visible. This worked around it, but I'm sure it caused crashes and
// weird behavior. It may have been responsible for issue 8405.
//
// After flailing around for a while, I discovered that giving the view a layer
// and hiding it while using Metal seems to fix the problem (at least on my iMac).
//
// My fear is that giving it a layer will break random things because that is a
// proud tradition of layers on macOS. Time will tell if that is true.
//
// The test for whether performance is "good" or "bad" is to use the default
// app settings and make a maximized window on a 2014 iMac. Run tests/spam.cc.
// You should get just about 60 fps if it's fast, and 30-45 if it's slow.
+ (BOOL)useLayerForBetterPerformance {
    if (@available(macOS 10.14, *)) {
        return ![iTermAdvancedSettingsModel dismemberScrollView];
    }
    return NO;
}

+ (NSSize)charSizeForFont:(NSFont *)aFont
    horizontalSpacing:(CGFloat)hspace
    verticalSpacing:(CGFloat)vspace {
    FontSizeEstimator* fse = [FontSizeEstimator fontSizeEstimatorForFont:aFont];
    NSSize size = [fse size];
    size.width = ceil(size.width);
    size.height = ceil(size.height + [aFont leading]);
    size.width = ceil(size.width * hspace);
    size.height = ceil(size.height * vspace);
    return size;
}

- (instancetype)initWithFrame:(NSRect)aRect colorMap:(iTermColorMap *)colorMap {
    self = [super initWithFrame:aRect];
    if (self) {
        [self resetMouseLocationToRefuseFirstResponderAt];
        _drawingHelper = [[iTermTextDrawingHelper alloc] init];
        if ([iTermAdvancedSettingsModel showTimestampsByDefault]) {
            _drawingHelper.showTimestamps = YES;
        }
        _drawingHelper.delegate = self;

        _colorMap = [colorMap retain];
        _colorMap.delegate = self;

        _drawingHelper.colorMap = colorMap;

        [self updateMarkedTextAttributes];
        _drawingHelper.cursorVisible = YES;
        _selection = [[iTermSelection alloc] init];
        _selection.delegate = self;
        _oldSelection = [_selection copy];
        _drawingHelper.underlinedRange =
            VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0);
        _timeOfLastBlink = [NSDate timeIntervalSinceReferenceDate];

        // Register for drag and drop.
        [self registerForDraggedTypes: @[
             NSPasteboardTypeFileURL,
             NSPasteboardTypeString ]];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(useBackgroundIndicatorChanged:)
                                              name:kUseBackgroundPatternIndicatorChangedNotification
                                              object:nil];
        [self useBackgroundIndicatorChanged:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(_settingsChanged:)
                                              name:kRefreshTerminalNotification
                                              object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applicationDidResignActive:)
                                              name:NSApplicationDidResignActiveNotification
                                              object:nil];

        _semanticHistoryController = [[iTermSemanticHistoryController alloc] init];
        _semanticHistoryController.delegate = self;

        _urlActionHelper = [[iTermURLActionHelper alloc] initWithSemanticHistoryController:_semanticHistoryController];
        _urlActionHelper.delegate = self;
        _contextMenuHelper = [[iTermTextViewContextMenuHelper alloc] initWithURLActionHelper:_urlActionHelper];
        _urlActionHelper.smartSelectionActionTarget = _contextMenuHelper;

        _primaryFont = [[PTYFontInfo alloc] init];
        _secondaryFont = [[PTYFontInfo alloc] init];

        DLog(@"Begin tracking touches in view %@", self);
        self.allowedTouchTypes = NSTouchTypeMaskIndirect;
        [self setWantsRestingTouches:YES];
        threeFingerTapGestureRecognizer_ =
            [[ThreeFingerTapGestureRecognizer alloc] initWithTarget:self
                                                     selector:@selector(threeFingerTap:)];

        [self viewDidChangeBackingProperties];
        _indicatorsHelper = [[iTermIndicatorsHelper alloc] init];
        _indicatorsHelper.delegate = self;

        _selectionScrollHelper = [[iTermSelectionScrollHelper alloc] init];
        _selectionScrollHelper.delegate = self;

        _findOnPageHelper = [[iTermFindOnPageHelper alloc] init];
        _findOnPageHelper.delegate = self;

        _accessibilityHelper = [[iTermTextViewAccessibilityHelper alloc] init];
        _accessibilityHelper.delegate = self;

        _badgeLabel = [[iTermBadgeLabel alloc] init];
        _badgeLabel.delegate = self;

        [self refuseFirstResponderAtCurrentMouseLocation];

        _scrollAccumulator = [[iTermScrollAccumulator alloc] init];
        _keyboardHandler = [[iTermKeyboardHandler alloc] init];
        _keyboardHandler.delegate = self;

        _mouseHandler =
            [[PTYMouseHandler alloc] initWithSelectionScrollHelper:_selectionScrollHelper
                                     threeFingerTapGestureRecognizer:threeFingerTapGestureRecognizer_
                                     pointerControllerDelegate:self
                                     mouseReportingFrustrationDetectorDelegate:self];
        _mouseHandler.mouseDelegate = self;

        [self initARC];
    }
    return self;
}

- (void)dealloc {
    [_mouseHandler release];
    [_selection release];
    [_oldSelection release];
    [_smartSelectionRules release];

    [self removeAllTrackingAreas];
    if ([self isFindingCursor]) {
        [self.findCursorWindow close];
    }
    [_findCursorWindow release];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _colorMap.delegate = nil;
    [_colorMap release];

    [_primaryFont release];
    [_secondaryFont release];

    [_markedTextAttributes release];

    [_semanticHistoryController release];

    [cursor_ release];
    [threeFingerTapGestureRecognizer_ disconnectTarget];
    [threeFingerTapGestureRecognizer_ release];

    _indicatorsHelper.delegate = nil;
    [_indicatorsHelper release];
    _selectionScrollHelper.delegate = nil;
    [_selectionScrollHelper release];
    _findOnPageHelper.delegate = nil;
    [_findOnPageHelper release];
    [_drawingHook release];
    _drawingHelper.delegate = nil;
    [_drawingHelper release];
    [_accessibilityHelper release];
    [_badgeLabel release];
    [_quickLookController close];
    [_quickLookController release];
    [_contextMenuHelper release];
    [_highlightedRows release];
    [_scrollAccumulator release];
    [_shadowRateLimit release];
    _keyboardHandler.delegate = nil;
    [_keyboardHandler release];
    _urlActionHelper.delegate = nil;
    [_urlActionHelper release];

    [super dealloc];
}

#pragma mark - NSObject

- (NSString *)description {
    return [NSString stringWithFormat:@"<PTYTextView: %p frame=%@ visibleRect=%@ dataSource=%@ delegate=%@ window=%@>",
                     self,
                     [NSValue valueWithRect:self.frame],
                     [NSValue valueWithRect:[self visibleRect]],
                     _dataSource,
                     _delegate,
                     self.window];
}

- (void)changeFont:(id)fontManager {
    if ([[[PreferencePanel sharedInstance] windowIfLoaded] isVisible]) {
        [[PreferencePanel sharedInstance] changeFont:fontManager];
    } else if ([[[PreferencePanel sessionsInstance] windowIfLoaded] isVisible]) {
        [[PreferencePanel sessionsInstance] changeFont:fontManager];
    }
}

#pragma mark - NSResponder

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if ([item action] == @selector(paste:)) {
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];
        // Check if there is a string type on the pasteboard
        if ([pboard stringForType:NSPasteboardTypeString] != nil) {
            return YES;
        }
        return [[[NSPasteboard generalPasteboard] pasteboardItems] anyWithBlock:^BOOL(NSPasteboardItem *item) {
                                              return [item stringForType:(NSString *)kUTTypeUTF8PlainText] != nil;
                                          }];
    }

    if ([item action] == @selector(pasteOptions:)) {
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];
        return [[pboard pasteboardItems] count] > 0;
    }

    if ([item action ] == @selector(cut:)) {
        // Never allow cut.
        return NO;
    }
    if ([item action] == @selector(showHideNotes:)) {
        item.state = [self anyAnnotationsAreVisible] ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if ([item action] == @selector(toggleShowTimestamps:)) {
        item.state = _drawingHelper.showTimestamps ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }

    if ([item action]==@selector(saveDocumentAs:)) {
        return [self isAnyCharSelected];
    } else if ([item action] == @selector(selectAll:) ||
               [item action]==@selector(installShellIntegration:) ||
               ([item action] == @selector(print:) && [item tag] != 1)) {
        // We always validate the above commands
        return YES;
    }
    if ([item action]==@selector(copy:) ||
            [item action]==@selector(copyWithStyles:) ||
            [item action]==@selector(copyWithControlSequences:) ||
            [item action]==@selector(performFindPanelAction:) ||
            ([item action]==@selector(print:) && [item tag] == 1)) { // print selection
        // These commands are allowed only if there is a selection.
        return [_selection hasSelection];
    } else if ([item action]==@selector(pasteSelection:)) {
        return [[iTermController sharedInstance] lastSelection] != nil;
    } else if ([item action]==@selector(selectOutputOfLastCommand:)) {
        return [_delegate textViewCanSelectOutputOfLastCommand];
    } else if ([item action]==@selector(selectCurrentCommand:)) {
        return [_delegate textViewCanSelectCurrentCommand];
    }
    if ([item action] == @selector(pasteBase64Encoded:)) {
        return [[NSPasteboard generalPasteboard] dataForFirstFile] != nil;
    }
    if (item.action == @selector(bury:)) {
        return YES;
    }
    if (item.action == @selector(terminalStateToggleAlternateScreen:) ||
            item.action == @selector(terminalStateToggleFocusReporting:) ||
            item.action == @selector(terminalStateToggleMouseReporting:) ||
            item.action == @selector(terminalStateTogglePasteBracketing:) ||
            item.action == @selector(terminalStateToggleApplicationCursor:) ||
            item.action == @selector(terminalStateToggleApplicationKeypad:) ||
            item.action == @selector(terminalToggleKeyboardMode:)) {
        item.state = [self.delegate textViewTerminalStateForMenuItem:item] ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (item.action == @selector(terminalStateReset:)) {
        return YES;
    }

    SEL theSel = [item action];
    if ([NSStringFromSelector(theSel) hasPrefix:@"contextMenuAction"]) {
        return YES;
    }
    return [self arcValidateMenuItem:item];
}

- (BOOL)resignFirstResponder {
    DLog(@"resign first responder: reset numTouches to 0");
    _mouseHandler.numTouches = 0;
    if (!self.it_shouldIgnoreFirstResponderChanges) {
        [_mouseHandler didResignFirstResponder];
        [self removeUnderline];
        [self placeFindCursorOnAutoHide];
        [_delegate textViewDidResignFirstResponder];
        DLog(@"resignFirstResponder %@", self);
        DLog(@"%@", [NSThread callStackSymbols]);
    } else {
        DLog(@"%@ ignoring first responder changes in resignFirstResponder", self);
    }
    dispatch_async(dispatch_get_main_queue(), ^ {
        [[iTermSecureKeyboardEntryController sharedInstance] update];
    });
    return YES;
}

- (BOOL)becomeFirstResponder {
    if (!self.it_shouldIgnoreFirstResponderChanges) {
        [_mouseHandler didBecomeFirstResponder];
        [_delegate textViewDidBecomeFirstResponder];
        DLog(@"becomeFirstResponder %@", self);
        DLog(@"%@", [NSThread callStackSymbols]);
    } else {
        DLog(@"%@ ignoring first responder changes in becomeFirstResponder", self);
    }
    [[iTermSecureKeyboardEntryController sharedInstance] update];
    return YES;
}

- (void)scrollLineUp:(id)sender {
    [self scrollBy:-[self.enclosingScrollView verticalLineScroll]];
}

- (void)scrollLineDown:(id)sender {
    [self scrollBy:[self.enclosingScrollView verticalLineScroll]];
}

- (void)scrollPageUp:(id)sender {
    [self scrollBy:-self.pageScrollHeight];
}

- (void)scrollPageDown:(id)sender {
    [self scrollBy:self.pageScrollHeight];
}

- (void)scrollHome {
    NSRect scrollRect;

    scrollRect = [self visibleRect];
    scrollRect.origin.y = 0;
    [self scrollRectToVisible:scrollRect];
}

- (void)scrollEnd {
    if ([_dataSource numberOfLines] <= 0) {
        return;
    }
    NSRect lastLine = [self visibleRect];
    lastLine.origin.y = (([_dataSource numberOfLines] - 1) * _lineHeight +
                         [self excess] +
                         _drawingHelper.numberOfIMELines * _lineHeight);
    lastLine.size.height = _lineHeight;
    if (!NSContainsRect(self.visibleRect, lastLine)) {
        [self scrollRectToVisible:lastLine];
    }
}

- (void)flagsChanged:(NSEvent *)theEvent {
    [self updateUnderlinedURLs:theEvent];
    NSString *string = [_keyboardHandler.keyMapper keyMapperStringForPreCocoaEvent:theEvent];
    if (string) {
        [_delegate insertText:string];
    }
    [super flagsChanged:theEvent];
}

#pragma mark - NSResponder Keyboard Input and Helpers

// Control-pgup and control-pgdown are handled at this level by NSWindow if no
// view handles it. It's necessary to setUserScroll in the PTYScroller, or else
// it scrolls back to the bottom right away. This code handles those two
// keypresses and scrolls correctly.
// Addendum: control page up/down seem to be supported because I did not understand
// macOS very well back in issue 1112. I guess I won't break it.
- (BOOL)performKeyEquivalent:(NSEvent *)theEvent {
    if (self.window.firstResponder != self) {
        return [super performKeyEquivalent:theEvent];
    }
    NSString* unmodkeystr = [theEvent charactersIgnoringModifiers];
    if ([unmodkeystr length] == 0) {
        return [super performKeyEquivalent:theEvent];
    }
    unichar unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;

    if ([_keyboardHandler performKeyEquivalent:theEvent inputContext:self.inputContext]) {
        return YES;
    }

    NSUInteger modifiers = [theEvent it_modifierFlags];
    if ((modifiers & NSEventModifierFlagControl) &&
            (modifiers & NSEventModifierFlagFunction)) {
        switch (unmodunicode) {
        case NSPageUpFunctionKey:
            [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];
            [self scrollPageUp:self];
            return YES;

        case NSPageDownFunctionKey:
            [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];
            [self scrollPageDown:self];
            return YES;

        default:
            break;
        }
    }
    return [super performKeyEquivalent:theEvent];
}

- (void)keyDown:(NSEvent *)event {
    [_mouseHandler keyDown:event];
    [_keyboardHandler keyDown:event inputContext:self.inputContext];
}

- (void)keyUp:(NSEvent *)event {
    [self.delegate keyUp:event];
    [super keyUp:event];
}

- (BOOL)keyIsARepeat {
    return _keyboardHandler.keyIsARepeat;
}

// Compute the length, in _charWidth cells, of the input method text.
- (int)inputMethodEditorLength {
    if (![self hasMarkedText]) {
        return 0;
    }
    NSString* str = [_drawingHelper.markedText string];

    const int maxLen = [str length] * kMaxParts;
    screen_char_t buf[maxLen];
    screen_char_t fg, bg;
    memset(&bg, 0, sizeof(bg));
    memset(&fg, 0, sizeof(fg));
    int len;
    StringToScreenChars(str,
                        buf,
                        fg,
                        bg,
                        &len,
                        [_delegate textViewAmbiguousWidthCharsAreDoubleWidth],
                        NULL,
                        NULL,
                        [_delegate textViewUnicodeNormalizationForm],
                        [_delegate textViewUnicodeVersion]);

    // Count how many additional cells are needed due to double-width chars
    // that span line breaks being wrapped to the next line.
    int x = [_dataSource cursorX] - 1;  // cursorX is 1-based
    int width = [_dataSource width];
    if (width == 0 && len > 0) {
        // Width should only be zero in weirdo edge cases, but the modulo below caused crashes.
        return len;
    }
    int extra = 0;
    int curX = x;
    for (int i = 0; i < len; ++i) {
        if (curX == 0 && buf[i].code == DWC_RIGHT) {
            ++extra;
            ++curX;
        }
        ++curX;
        curX %= width;
    }
    return len + extra;
}

#pragma mark - Scrolling Helpers

- (void)scrollBy:(CGFloat)deltaY {
    NSScrollView *scrollView = self.enclosingScrollView;
    NSRect rect = scrollView.documentVisibleRect;
    NSPoint point;
    point = rect.origin;
    point.y += deltaY;
    [scrollView.documentView scrollPoint:point];
}

- (CGFloat)pageScrollHeight {
    NSRect scrollRect = [self visibleRect];
    return scrollRect.size.height - [[self enclosingScrollView] verticalPageScroll];
}

- (long long)absoluteScrollPosition {
    NSRect visibleRect = [self visibleRect];
    long long localOffset = (visibleRect.origin.y + [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins]) / [self lineHeight];
    return localOffset + [_dataSource totalScrollbackOverflow];
}

- (void)scrollToAbsoluteOffset:(long long)absOff height:(int)height
{
    NSRect aFrame;
    aFrame.origin.x = 0;
    aFrame.origin.y = (absOff - [_dataSource totalScrollbackOverflow]) * _lineHeight - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    aFrame.size.width = [self frame].size.width;
    aFrame.size.height = _lineHeight * height;
    [self scrollRectToVisible: aFrame];
    [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];
}

- (BOOL)withRelativeCoord:(VT100GridAbsCoord)coord
    block:(void (^ NS_NOESCAPE)(VT100GridCoord coord))block {
    const long long overflow = _dataSource.totalScrollbackOverflow;
    if (coord.y < overflow) {
        return NO;
    }
    if (coord.y - overflow > INT_MAX) {
        return NO;
    }
    VT100GridCoord relative = VT100GridCoordMake(coord.x, coord.y - overflow);
    block(relative);
    return YES;
}

- (BOOL)withRelativeCoordRange:(VT100GridAbsCoordRange)range
    block:(void (^ NS_NOESCAPE)(VT100GridCoordRange))block {
    const long long overflow = _dataSource.totalScrollbackOverflow;
    VT100GridCoordRange relative = VT100GridCoordRangeFromAbsCoordRange(range, overflow);
    if (relative.start.x < 0) {
        return NO;
    }
    block(relative);
    return YES;
}

- (BOOL)withRelativeWindowedRange:(VT100GridAbsWindowedRange)range
    block:(void (^ NS_NOESCAPE)(VT100GridWindowedRange))block {
    const long long overflow = _dataSource.totalScrollbackOverflow;
    if (range.coordRange.start.y < overflow || range.coordRange.start.y - overflow > INT_MAX) {
        return NO;
    }
    if (range.coordRange.end.y < overflow || range.coordRange.end.y - overflow > INT_MAX) {
        return NO;
    }
    VT100GridWindowedRange relative = VT100GridWindowedRangeFromAbsWindowedRange(range, overflow);
    block(relative);
    return YES;
}

- (void)scrollToSelection {
    if (![_selection hasSelection]) {
        return;
    }
    [self withRelativeCoordRange:[_selection spanningAbsRange] block:^(VT100GridCoordRange range) {
             NSRect aFrame;
             aFrame.origin.x = 0;
        aFrame.origin.y = range.start.y * _lineHeight - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];  // allow for top margin
        aFrame.size.width = [self frame].size.width;
        aFrame.size.height = (range.end.y - range.start.y + 1) * _lineHeight;
        [self scrollRectToVisible: aFrame];
        [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];
    }];
}

- (void)_scrollToLine:(int)line {
    NSRect aFrame;
    aFrame.origin.x = 0;
    aFrame.origin.y = line * _lineHeight;
    aFrame.size.width = [self frame].size.width;
    aFrame.size.height = _lineHeight;
    [self scrollRectToVisible:aFrame];
}

- (void)_scrollToCenterLine:(int)line {
    NSRect visible = [self visibleRect];
    int visibleLines = (visible.size.height - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2) / _lineHeight;
    int lineMargin = (visibleLines - 1) / 2;
    double margin = lineMargin * _lineHeight;

    NSRect aFrame;
    aFrame.origin.x = 0;
    aFrame.origin.y = MAX(0, line * _lineHeight - margin);
    aFrame.size.width = [self frame].size.width;
    aFrame.size.height = margin * 2 + _lineHeight;
    double end = aFrame.origin.y + aFrame.size.height;
    NSRect total = [self frame];
    if (end > total.size.height) {
        double err = end - total.size.height;
        aFrame.size.height -= err;
    }
    [self scrollRectToVisible:aFrame];
}

- (void)scrollLineNumberRangeIntoView:(VT100GridRange)range {
    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    int firstVisibleLine = visibleRect.origin.y / _lineHeight;
    int lastVisibleLine = firstVisibleLine + [_dataSource height] - 1;
    if (range.location >= firstVisibleLine && range.location + range.length <= lastVisibleLine) {
        // Already visible
        return;
    }
    if (range.length < [_dataSource height]) {
        [self _scrollToCenterLine:range.location + range.length / 2];
    } else {
        const VT100GridRange rangeOfVisibleLines = [self rangeOfVisibleLines];
        const int currentBottomLine = rangeOfVisibleLines.location + rangeOfVisibleLines.length;
        const int desiredBottomLine = range.length + range.location;
        const int dy = desiredBottomLine - currentBottomLine;
        [self scrollBy:[self.enclosingScrollView verticalLineScroll] * dy];
    }
    [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];
}

#pragma mark - NSView

- (void)setAlphaValue:(CGFloat)alphaValue {
    DLog(@"Set textview alpha to %@", @(alphaValue));
    [super setAlphaValue:alphaValue];
}

// Overrides an NSView method.
- (NSRect)adjustScroll:(NSRect)proposedVisibleRect {
    proposedVisibleRect.origin.y = (int)(proposedVisibleRect.origin.y / _lineHeight + 0.5) * _lineHeight;
    return proposedVisibleRect;
}

// For Metal
- (void)setNeedsDisplay:(BOOL)needsDisplay {
    [super setNeedsDisplay:needsDisplay];
    if (needsDisplay) {
        [_delegate textViewNeedsDisplayInRect:self.bounds];
    }
}

// For Metal
- (void)setNeedsDisplayInRect:(NSRect)invalidRect {
    [super setNeedsDisplayInRect:invalidRect];
    [_delegate textViewNeedsDisplayInRect:invalidRect];
}

- (void)removeAllTrackingAreas {
    while (self.trackingAreas.count) {
        [self removeTrackingArea:self.trackingAreas[0]];
    }
}

- (void)viewDidChangeBackingProperties {
    CGFloat scale = [[[self window] screen] backingScaleFactor];
    BOOL isRetina = scale > 1;
    _drawingHelper.antiAliasedShift = isRetina ? 0.5 : 0;
    _drawingHelper.isRetina = isRetina;
}

- (void)viewWillMoveToWindow:(NSWindow *)win {
    if (!win && [self window]) {
        [self removeAllTrackingAreas];
    }
    [super viewWillMoveToWindow:win];
}

// TODO: Not sure if this is used.
- (BOOL)shouldDrawInsertionPoint {
    return NO;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return YES;
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self recomputeBadgeLabel];
}

#pragma mark Set Needs Display Helpers

- (void)setNeedsDisplayOnLine:(int)line {
    [self setNeedsDisplayOnLine:line inRange:VT100GridRangeMake(0, _dataSource.width)];
}

- (void)setNeedsDisplayOnLine:(int)y inRange:(VT100GridRange)range {
    NSRect dirtyRect;
    const BOOL allowPartialLineRedraw = [iTermAdvancedSettingsModel preferSpeedToFullLigatureSupport];
    const int x = allowPartialLineRedraw ? range.location : 0;
    const int maxX = range.location + range.length;

    dirtyRect.origin.x = [iTermPreferences intForKey:kPreferenceKeySideMargins] + x * _charWidth;
    dirtyRect.origin.y = y * _lineHeight;
    dirtyRect.size.width = allowPartialLineRedraw ? (maxX - x) * _charWidth : _dataSource.width;
    dirtyRect.size.height = _lineHeight;

    if (_drawingHelper.showTimestamps) {
        dirtyRect.size.width = self.visibleRect.size.width - dirtyRect.origin.x;
    }

    // Expand the rect in case we're drawing a changed cell with an oversize glyph.
    dirtyRect = [self rectWithHalo:dirtyRect];

    DLog(@"Line %d is dirty in range [%d, %d), set rect %@ dirty",
         y, x, maxX, [NSValue valueWithRect:dirtyRect]);
    [self setNeedsDisplayInRect:dirtyRect];
}

- (void)invalidateInputMethodEditorRect {
    if ([_dataSource width] == 0) {
        return;
    }
    int imeLines = ([_dataSource cursorX] - 1 + [self inputMethodEditorLength] + 1) / [_dataSource width] + 1;

    NSRect imeRect = NSMakeRect([iTermPreferences intForKey:kPreferenceKeySideMargins],
                                ([_dataSource cursorY] - 1 + [_dataSource numberOfLines] - [_dataSource height]) * _lineHeight,
                                [_dataSource width] * _charWidth,
                                imeLines * _lineHeight);
    imeRect = [self rectWithHalo:imeRect];
    [self setNeedsDisplayInRect:imeRect];
}

- (void)viewDidMoveToWindow {
    DLog(@"View %@ did move to window %@\n%@", self, self.window, [NSThread callStackSymbols]);
    // If you change tabs while dragging you never get a mouseUp. Issue 8350.
    [_selection endLiveSelection];
    if (self.window == nil) {
        [_shellIntegrationInstallerWindow close];
        _shellIntegrationInstallerWindow = nil;
    }
    [super viewDidMoveToWindow];
}

#pragma mark - NSView Mouse-Related Overrides

- (BOOL)wantsScrollEventsForSwipeTrackingOnAxis:(NSEventGestureAxis)axis {
    if (@available(macOS 10.14, *)) {
        return (axis == NSEventGestureAxisHorizontal) ? YES : NO;
    } else {
        return [super wantsScrollEventsForSwipeTrackingOnAxis:axis];
    }
}

- (void)scrollWheel:(NSEvent *)event {
    DLog(@"scrollWheel:%@", event);
    const NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    if ([_mouseHandler scrollWheel:event pointInView:point]) {
        [super scrollWheel:event];
    }
}

- (void)mouseDown:(NSEvent *)event {
    [_mouseHandler mouseDown:event superCaller:^ { [super mouseDown:event]; }];
}

- (BOOL)mouseDownImpl:(NSEvent *)event {
    return [_mouseHandler mouseDownImpl:event];
}

- (void)mouseUp:(NSEvent *)event {
    [_mouseHandler mouseUp:event];
}

- (void)mouseMoved:(NSEvent *)event {
    [self resetMouseLocationToRefuseFirstResponderAt];
    [self updateUnderlinedURLs:event];
    [_mouseHandler mouseMoved:event];
}

- (void)mouseDragged:(NSEvent *)event {
    [_mouseHandler mouseDragged:event];
}

- (void)rightMouseDown:(NSEvent *)event {
    [_mouseHandler rightMouseDown:event
                   superCaller:^ { [super rightMouseDown:event]; }];
}

- (void)rightMouseUp:(NSEvent *)event {
    [_mouseHandler rightMouseUp:event superCaller:^ { [super rightMouseUp:event]; }];
}

- (void)rightMouseDragged:(NSEvent *)event {
    [_mouseHandler rightMouseDragged:event
                   superCaller:^ { [super rightMouseDragged:event]; }];
}

- (void)otherMouseDown:(NSEvent *)event {
    [_mouseHandler otherMouseDown:event];
}

- (void)otherMouseUp:(NSEvent *)event {
    [_mouseHandler otherMouseUp:event
                   superCaller:^ { [super otherMouseUp:event]; }];
}

- (void)otherMouseDragged:(NSEvent *)event {
    [_mouseHandler otherMouseDragged:event
                   superCaller:^ { [super otherMouseDragged:event]; }];
}

- (void)touchesBeganWithEvent:(NSEvent *)ev {
    _mouseHandler.numTouches = [[ev touchesMatchingPhase:NSTouchPhaseBegan | NSTouchPhaseStationary
                                 inView:self] count];
    DLog(@"%@ Begin touch. numTouches_ -> %d", self, _mouseHandler.numTouches);
    [threeFingerTapGestureRecognizer_ touchesBeganWithEvent:ev];
}

- (void)touchesEndedWithEvent:(NSEvent *)ev {
    _mouseHandler.numTouches = [[ev touchesMatchingPhase:NSTouchPhaseStationary
                                 inView:self] count];
    DLog(@"%@ End touch. numTouches_ -> %d", self, _mouseHandler.numTouches);
    [threeFingerTapGestureRecognizer_ touchesEndedWithEvent:ev];
}

- (void)touchesMovedWithEvent:(NSEvent *)event {
    DLog(@"%@ Move touch.", self);
    [threeFingerTapGestureRecognizer_ touchesMovedWithEvent:event];
}
- (void)touchesCancelledWithEvent:(NSEvent *)event {
    _mouseHandler.numTouches = 0;
    DLog(@"%@ Cancel touch. numTouches_ -> %d", self, _mouseHandler.numTouches);
    [threeFingerTapGestureRecognizer_ touchesCancelledWithEvent:event];
}

- (void)swipeWithEvent:(NSEvent *)event {
    [_mouseHandler swipeWithEvent:event];
}

- (void)pressureChangeWithEvent:(NSEvent *)event {
    [_mouseHandler pressureChangeWithEvent:event];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent {
    return [_mouseHandler acceptsFirstMouse:theEvent];
}

- (void)mouseExited:(NSEvent *)event {
    DLog(@"Mouse exited %@", self);
    if (_keyFocusStolenCount) {
        DLog(@"Releasing key focus %d times", (int)_keyFocusStolenCount);
        for (int i = 0; i < _keyFocusStolenCount; i++) {
            [self releaseKeyFocus];
        }
        [[iTermSecureKeyboardEntryController sharedInstance] didReleaseFocus];
        _keyFocusStolenCount = 0;
        [self setNeedsDisplay:YES];
    }
    if ([NSApp isActive]) {
        [self resetMouseLocationToRefuseFirstResponderAt];
    } else {
        DLog(@"Ignore mouse exited because app is not active");
    }
    [self updateUnderlinedURLs:event];
    [_delegate textViewShowHoverURL:nil];
}

- (void)mouseEntered:(NSEvent *)event {
    DLog(@"Mouse entered %@", self);
    if ([iTermAdvancedSettingsModel stealKeyFocus] &&
            [iTermPreferences boolForKey:kPreferenceKeyFocusFollowsMouse]) {
        DLog(@"Trying to steal key focus");
        if ([self stealKeyFocus]) {
            if (_keyFocusStolenCount == 0) {
                [[self window] makeFirstResponder:self];
                [[iTermSecureKeyboardEntryController sharedInstance] didStealFocus];
            }
            ++_keyFocusStolenCount;
            [self setNeedsDisplay:YES];
        }
    }
    [self updateUnderlinedURLs:event];
    if ([iTermPreferences boolForKey:kPreferenceKeyFocusFollowsMouse] &&
            [[self window] alphaValue] > 0 &&
            ![NSApp modalWindow]) {
        // Some windows automatically close when they lose key status and are
        // incompatible with FFM. Check if the key window or its controller implements
        // disableFocusFollowsMouse and if it returns YES do nothing.
        id obj = nil;
        if ([[NSApp keyWindow] respondsToSelector:@selector(disableFocusFollowsMouse)]) {
            obj = [NSApp keyWindow];
        } else if ([[[NSApp keyWindow] windowController] respondsToSelector:@selector(disableFocusFollowsMouse)]) {
            obj = [[NSApp keyWindow] windowController];
        }
        if (!NSEqualPoints(_mouseLocationToRefuseFirstResponderAt, [NSEvent mouseLocation])) {
            DLog(@"%p Mouse location is %@, refusal point is %@", self, NSStringFromPoint([NSEvent mouseLocation]), NSStringFromPoint(_mouseLocationToRefuseFirstResponderAt));
            if ([iTermAdvancedSettingsModel stealKeyFocus]) {
                if (![obj disableFocusFollowsMouse]) {
                    [[self window] makeKeyWindow];
                }
            } else {
                if ([NSApp isActive] && ![obj disableFocusFollowsMouse]) {
                    [[self window] makeKeyWindow];
                }
            }
            if ([self isInKeyWindow]) {
                [_delegate textViewDidBecomeFirstResponder];
            }
        } else {
            DLog(@"%p Refusing first responder on enter", self);
        }
    }
}

#pragma mark - NSView Mouse Helpers

- (void)sendFakeThreeFingerClickDown:(BOOL)isDown basedOnEvent:(NSEvent *)event {
    NSEvent *fakeEvent = isDown ? [event mouseDownEventFromGesture] : [event mouseUpEventFromGesture];

    [_mouseHandler performBlockWithThreeTouches:^ {
                      if (isDown) {
                          DLog(@"Emulate three finger click down");
            [self mouseDown:fakeEvent];
            DLog(@"Returned from mouseDown");
        } else {
            DLog(@"Emulate three finger click up");
            [self mouseUp:fakeEvent];
            DLog(@"Returned from mouseDown");
        }
    }];
}

- (void)threeFingerTap:(NSEvent *)ev {
    if (![_mouseHandler threeFingerTap:ev]) {
        [self sendFakeThreeFingerClickDown:YES basedOnEvent:ev];
        [self sendFakeThreeFingerClickDown:NO basedOnEvent:ev];
    }
}

- (BOOL)it_wantsScrollWheelMomentumEvents {
    return [_mouseHandler wantsScrollWheelMomentumEvents];
}

- (void)it_scrollWheelMomentum:(NSEvent *)event {
    DLog(@"Scroll wheel momentum event!");
    [self scrollWheel:event];
}

#pragma mark - NSView Drawing

- (void)drawRect:(NSRect)rect {
    if (![_delegate textViewShouldDrawRect]) {
        // Metal code path in use
        [super drawRect:rect];
        if (![iTermAdvancedSettingsModel disableWindowShadowWhenTransparencyOnMojave]) {
            [self maybeInvalidateWindowShadow];
        }
        return;
    }
    if (_dataSource.width <= 0) {
        ITCriticalError(_dataSource.width < 0, @"Negative datasource width of %@", @(_dataSource.width));
        return;
    }
    DLog(@"drawing document visible rect %@", NSStringFromRect(self.enclosingScrollView.documentVisibleRect));

    const NSRect *rectArray;
    NSInteger rectCount;
    [self getRectsBeingDrawn:&rectArray count:&rectCount];

    [self performBlockWithFlickerFixerGrid:^ {
             // Initialize drawing helper
             [self drawingHelper];

             if (_drawingHook) {
            // This is used by tests to customize the draw helper.
            _drawingHook(_drawingHelper);
        }

        [_drawingHelper drawTextViewContentInRect:rect rectsPtr:rectArray rectCount:rectCount];

        [_indicatorsHelper drawInFrame:_drawingHelper.indicatorFrame];
        [_drawingHelper drawTimestamps];

        // Not sure why this is needed, but for some reason this view draws over its subviews.
        for (NSView *subview in [self subviews]) {
            [subview setNeedsDisplay:YES];
        }

        if (_drawingHelper.blinkingFound && _blinkAllowed) {
            // The user might have used the scroll wheel to cause blinking text to become
            // visible. Make sure the timer is running if anything onscreen is
            // blinking.
            [self.delegate textViewWillNeedUpdateForBlink];
        }
    }];
    [self maybeInvalidateWindowShadow];
}

- (void)performBlockWithFlickerFixerGrid:(void (NS_NOESCAPE ^)(void))block {
    PTYTextViewSynchronousUpdateState *originalState = nil;
    PTYTextViewSynchronousUpdateState *savedState = [_dataSource setUseSavedGridIfAvailable:YES];
    if (savedState) {
        originalState = [[[PTYTextViewSynchronousUpdateState alloc] init] autorelease];
        originalState.colorMap = _colorMap;
        originalState.cursorVisible = _drawingHelper.cursorVisible;

        _drawingHelper.cursorVisible = savedState.cursorVisible;
        _drawingHelper.colorMap = savedState.colorMap;
        _colorMap = savedState.colorMap;
    }

    block();

    [_dataSource setUseSavedGridIfAvailable:NO];
    if (originalState) {
        _drawingHelper.colorMap = originalState.colorMap;
        _colorMap = originalState.colorMap;
        _drawingHelper.cursorVisible = originalState.cursorVisible;
    }
}

- (void)setSuppressDrawing:(BOOL)suppressDrawing {
    if (suppressDrawing == _suppressDrawing) {
        return;
    }
    _suppressDrawing = suppressDrawing;
    if (PTYTextView.useLayerForBetterPerformance) {
        if (@available(macOS 10.15, *)) {} {
            // Using a layer in a view inside a scrollview is a disaster, per macOS
            // tradition (insane drawing artifacts, especially when scrolling). But
            // not using a layer makes it godawful slow (see note about
            // rdar://45295749). So use a layer when the view is hidden, and
            // remove it when visible.
            if (suppressDrawing) {
                self.layer = [[[CALayer alloc] init] autorelease];
            } else {
                self.layer = nil;
            }
        }
        // This is necessary to avoid drawing artifacts when Metal is enabled.
        self.alphaValue = suppressDrawing ? 0 : 1;
    }
    PTYScrollView *scrollView = (PTYScrollView *)self.enclosingScrollView;
    [scrollView.verticalScroller setNeedsDisplay:YES];
}

- (iTermTextDrawingHelper *)drawingHelper {
    _drawingHelper.showStripes = (_showStripesWhenBroadcastingInput &&
                                  [_delegate textViewSessionIsBroadcastingInput]);
    _drawingHelper.cursorBlinking = [self isCursorBlinking];
    _drawingHelper.excess = [self excess];
    _drawingHelper.selection = _selection;
    _drawingHelper.ambiguousIsDoubleWidth = [_delegate textViewAmbiguousWidthCharsAreDoubleWidth];
    _drawingHelper.normalization = [_delegate textViewUnicodeNormalizationForm];
    _drawingHelper.hasBackgroundImage = [_delegate textViewHasBackgroundImage];
    _drawingHelper.cursorGuideColor = [_delegate textViewCursorGuideColor];
    _drawingHelper.gridSize = VT100GridSizeMake(_dataSource.width, _dataSource.height);
    _drawingHelper.numberOfLines = _dataSource.numberOfLines;
    _drawingHelper.cursorCoord = VT100GridCoordMake(_dataSource.cursorX - 1,
                                 _dataSource.cursorY - 1);
    _drawingHelper.totalScrollbackOverflow = [_dataSource totalScrollbackOverflow];
    _drawingHelper.numberOfScrollbackLines = [_dataSource numberOfScrollbackLines];
    _drawingHelper.reverseVideo = [[_dataSource terminal] reverseVideo];
    _drawingHelper.textViewIsActiveSession = [self.delegate textViewIsActiveSession];
    _drawingHelper.isInKeyWindow = [self isInKeyWindow];
    // Draw the cursor filled in when we're inactive if there's a popup open or key focus was stolen.
    _drawingHelper.shouldDrawFilledInCursor = ([self.delegate textViewShouldDrawFilledInCursor] || _keyFocusStolenCount);
    _drawingHelper.isFrontTextView = (self == [[iTermController sharedInstance] frontTextView]);
    _drawingHelper.transparencyAlpha = [self transparencyAlpha];
    _drawingHelper.now = [NSDate timeIntervalSinceReferenceDate];
    _drawingHelper.drawMarkIndicators = [_delegate textViewShouldShowMarkIndicators];
    _drawingHelper.thinStrokes = _thinStrokes;
    _drawingHelper.showSearchingCursor = _showSearchingCursor;
    _drawingHelper.baselineOffset = [self minimumBaselineOffset];
    _drawingHelper.underlineOffset = [self minimumUnderlineOffset];
    _drawingHelper.boldAllowed = _useBoldFont;
    _drawingHelper.unicodeVersion = [_delegate textViewUnicodeVersion];
    _drawingHelper.asciiLigatures = _primaryFont.hasDefaultLigatures || _asciiLigatures;
    _drawingHelper.nonAsciiLigatures = _secondaryFont.hasDefaultLigatures || _nonAsciiLigatures;
    _drawingHelper.copyMode = _delegate.textViewCopyMode;
    _drawingHelper.copyModeSelecting = _delegate.textViewCopyModeSelecting;
    _drawingHelper.copyModeCursorCoord = _delegate.textViewCopyModeCursorCoord;
    _drawingHelper.passwordInput = ([self isInKeyWindow] &&
                                    [_delegate textViewIsActiveSession] &&
                                    _delegate.textViewPasswordInput);
    _drawingHelper.useNativePowerlineGlyphs = self.useNativePowerlineGlyphs;
    _drawingHelper.badgeTopMargin = [_delegate textViewBadgeTopMargin];
    _drawingHelper.badgeRightMargin = [_delegate textViewBadgeRightMargin];
    _drawingHelper.forceAntialiasingOnRetina = [iTermAdvancedSettingsModel forceAntialiasingOnRetina];
    _drawingHelper.blend = MIN(MAX(0.05, [_delegate textViewBlend]), 1);

    CGFloat rightMargin = 0;
    if (_drawingHelper.showTimestamps) {
        [_drawingHelper createTimestampDrawingHelper];
        rightMargin = _drawingHelper.timestampDrawHelper.maximumWidth + 8;
    }
    _drawingHelper.indicatorFrame = [self configureIndicatorsHelperWithRightMargin:rightMargin];

    return _drawingHelper;
}

- (NSColor *)defaultBackgroundColor {
    CGFloat alpha = [self useTransparency] ? 1 - _transparency : 1;
    return [[_colorMap processedBackgroundColorForBackgroundColor:[_colorMap colorForKey:kColorMapBackground]] colorWithAlphaComponent:alpha];
}

- (NSColor *)defaultTextColor {
    return [_colorMap processedTextColorForTextColor:[_colorMap colorForKey:kColorMapForeground]
                      overBackgroundColor:[self defaultBackgroundColor]
                      disableMinimumContrast:NO];
}

- (void)updateMarkedTextAttributes {
    // During initialization, this may be called before the non-ascii font is set so we use a system
    // font as a placeholder.
    NSDictionary *theAttributes =
        @ { NSBackgroundColorAttributeName:
            [self defaultBackgroundColor] ?: [NSColor blackColor],
            NSForegroundColorAttributeName: [self defaultTextColor] ?: [NSColor whiteColor],
            NSFontAttributeName: self.nonAsciiFont ?: [NSFont systemFontOfSize:12],
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle | NSUnderlineByWord)
          };

    [self setMarkedTextAttributes:theAttributes];
}

- (void)updateScrollerForBackgroundColor {
    PTYScroller *scroller = [_delegate textViewVerticalScroller];
    NSColor *backgroundColor = [_colorMap colorForKey:kColorMapBackground];
    const BOOL isDark = [backgroundColor isDark];

    if (isDark) {
        // Dark background, any theme, any OS version
        scroller.knobStyle = NSScrollerKnobStyleLight;
    } else if (@available(macOS 10.14, *)) {
        if (self.effectiveAppearance.it_isDark) {
            // Light background, dark theme — issue 8322
            scroller.knobStyle = NSScrollerKnobStyleDark;
        } else {
            // Light background, light theme
            scroller.knobStyle = NSScrollerKnobStyleDefault;
        }
    } else {
        // Pre-10.4, light background
        scroller.knobStyle = NSScrollerKnobStyleDefault;
    }

    // The knob style is used only for overlay scrollers. In the minimal theme, the window decorations'
    // colors are based on the terminal background color. That means the appearance must be changed to get
    // legacy scrollbars to change color.
    if (@available(macOS 10.14, *)) {
        if ([self.delegate textViewTerminalBackgroundColorDeterminesWindowDecorationColor]) {
            scroller.appearance = isDark ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] : [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        } else {
            scroller.appearance = nil;
        }
    }
}

// Number of extra lines below the last line of text that are always the background color.
// This is 2 except for just after the frame has changed and things are resizing.
- (double)excess {
    NSRect visible = [self scrollViewContentSize];
    visible.size.height -= [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2;  // Height without top and bottom margins.
    int rows = visible.size.height / _lineHeight;
    double usablePixels = rows * _lineHeight;
    return MAX(visible.size.height - usablePixels + [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins], [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins]);  // Never have less than VMARGIN excess, but it can be more (if another tab has a bigger font)
}

- (void)maybeInvalidateWindowShadow {
    if (@available(macOS 10.16, *)) {
        return;
    }
    if (@available(macOS 10.14, *)) {
        const double invalidateFPS = [iTermAdvancedSettingsModel invalidateShadowTimesPerSecond];
        if (invalidateFPS > 0) {
            if (self.transparencyAlpha < 1) {
                if ([self.window conformsToProtocol:@protocol(PTYWindow)]) {
                    if (_shadowRateLimit == nil) {
                        _shadowRateLimit = [[iTermRateLimitedUpdate alloc] init];
                        _shadowRateLimit.minimumInterval = 1.0 / invalidateFPS;
                    }
                    id<PTYWindow> ptyWindow = (id<PTYWindow>)self.window;
                    [_shadowRateLimit performRateLimitedBlock:^ {
                                         [ptyWindow it_setNeedsInvalidateShadow];
                                     }];
                }
            }
        }
    }
}

- (BOOL)getAndResetDrawingAnimatedImageFlag {
    BOOL result = _drawingHelper.animated;
    _drawingHelper.animated = NO;
    return result;
}

- (BOOL)hasUnderline {
    return _drawingHelper.underlinedRange.coordRange.start.x >= 0;
}

// Reset underlined chars indicating cmd-clickable url.
- (BOOL)removeUnderline {
    if (![self hasUnderline]) {
        return NO;
    }
    _drawingHelper.underlinedRange =
        VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0);
    [self setNeedsDisplay:YES];  // It would be better to just display the underlined/formerly underlined area.
    return YES;
}

#pragma mark - Indicators

- (NSRect)configureIndicatorsHelperWithRightMargin:(CGFloat)rightMargin {
    [_indicatorsHelper setIndicator:kiTermIndicatorMaximized
                       visible:[_delegate textViewIsMaximized]];
    [_indicatorsHelper setIndicator:kItermIndicatorBroadcastInput
                       visible:[_delegate textViewSessionIsBroadcastingInput]];
    [_indicatorsHelper setIndicator:kiTermIndicatorCoprocess
                       visible:[_delegate textViewHasCoprocess]];
    [_indicatorsHelper setIndicator:kiTermIndicatorAlert
                       visible:[_delegate alertOnNextMark]];
    [_indicatorsHelper setIndicator:kiTermIndicatorAllOutputSuppressed
                       visible:[_delegate textViewSuppressingAllOutput]];
    [_indicatorsHelper setIndicator:kiTermIndicatorZoomedIn
                       visible:[_delegate textViewIsZoomedIn]];
    [_indicatorsHelper setIndicator:kiTermIndicatorCopyMode
                       visible:[_delegate textViewCopyMode]];
    NSRect rect = self.visibleRect;
    rect.size.width -= rightMargin;
    return rect;
}

- (void)useBackgroundIndicatorChanged:(NSNotification *)notification {
    _showStripesWhenBroadcastingInput = [iTermApplication.sharedApplication delegate].useBackgroundPatternIndicator;
    [self setNeedsDisplay:YES];
}


#pragma mark - First Responder

- (void)refuseFirstResponderAtCurrentMouseLocation {
    DLog(@"set refuse location");
    _mouseLocationToRefuseFirstResponderAt = [NSEvent mouseLocation];
}

- (void)resetMouseLocationToRefuseFirstResponderAt {
    DLog(@"reset refuse location from\n%@", [NSThread callStackSymbols]);
    _mouseLocationToRefuseFirstResponderAt = NSMakePoint(DBL_MAX, DBL_MAX);
}

#pragma mark - Geometry

- (NSRect)scrollViewContentSize {
    NSRect r = NSMakeRect(0, 0, 0, 0);
    r.size = [[self enclosingScrollView] contentSize];
    return r;
}

- (CGFloat)desiredHeight {
    // Force the height to always be correct
    return ([_dataSource numberOfLines] * _lineHeight +
            [self excess] +
            _drawingHelper.numberOfIMELines * _lineHeight);
}

- (NSPoint)locationInTextViewFromEvent:(NSEvent *)event {
    NSPoint locationInWindow = [event locationInWindow];
    NSPoint locationInTextView = [self convertPoint:locationInWindow fromView:nil];
    locationInTextView.x = ceil(locationInTextView.x);
    locationInTextView.y = ceil(locationInTextView.y);
    // Clamp the y position to be within the view. Sometimes we get events we probably shouldn't.
    locationInTextView.y = MIN(self.frame.size.height - 1,
                               MAX(0, locationInTextView.y));
    return locationInTextView;
}

- (BOOL)coordinateIsInMutableArea:(VT100GridCoord)coord {
    return coord.y >= self.dataSource.numberOfScrollbackLines;
}

- (NSRect)visibleContentRect {
    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    visibleRect.size.height -= [self excess];
    visibleRect.size.height -= [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    return visibleRect;
}

- (VT100GridRange)rangeOfVisibleLines {
    NSRect visibleRect = [self visibleContentRect];
    int start = [self coordForPoint:visibleRect.origin allowRightMarginOverflow:NO].y;
    int end = [self coordForPoint:NSMakePoint(0, NSMaxY(visibleRect) - 1) allowRightMarginOverflow:NO].y;
    return VT100GridRangeMake(start, MAX(0, end - start + 1));
}

- (long long)firstVisibleAbsoluteLineNumber {
    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    long long firstVisibleLine = visibleRect.origin.y / _lineHeight;
    return firstVisibleLine + _dataSource.totalScrollbackOverflow;
}

- (NSRect)gridRect {
    NSRect visibleRect = [self visibleRect];
    int lineStart = [_dataSource numberOfLines] - [_dataSource height];
    int lineEnd = [_dataSource numberOfLines];
    return NSMakeRect(visibleRect.origin.x,
                      lineStart * _lineHeight,
                      visibleRect.origin.x + visibleRect.size.width,
                      (lineEnd - lineStart + 1) * _lineHeight);
}

- (NSRect)rectWithHalo:(NSRect)rect {
    const int kHaloWidth = 4;
    rect.origin.x = rect.origin.x - _charWidth * kHaloWidth;
    rect.origin.y -= _lineHeight;
    rect.size.width = self.frame.size.width + _charWidth * 2 * kHaloWidth;
    rect.size.height += _lineHeight * 2;

    return rect;
}

#pragma mark - Accessors

- (void)setHighlightCursorLine:(BOOL)highlightCursorLine {
    _drawingHelper.highlightCursorLine = highlightCursorLine;
}

- (BOOL)highlightCursorLine {
    return _drawingHelper.highlightCursorLine;
}

- (void)setUseNonAsciiFont:(BOOL)useNonAsciiFont {
    _drawingHelper.useNonAsciiFont = useNonAsciiFont;
    _useNonAsciiFont = useNonAsciiFont;
    [self setNeedsDisplay:YES];
    [self updateMarkedTextAttributes];
}

- (void)setAntiAlias:(BOOL)asciiAntiAlias nonAscii:(BOOL)nonAsciiAntiAlias {
    _drawingHelper.asciiAntiAlias = asciiAntiAlias;
    _drawingHelper.nonAsciiAntiAlias = nonAsciiAntiAlias;
    [self setNeedsDisplay:YES];
}

- (void)setUseBoldFont:(BOOL)boldFlag {
    _useBoldFont = boldFlag;
    [self setNeedsDisplay:YES];
}

- (void)setThinStrokes:(iTermThinStrokesSetting)thinStrokes {
    _thinStrokes = thinStrokes;
    [self setNeedsDisplay:YES];
}

- (void)setAsciiLigatures:(BOOL)asciiLigatures {
    _asciiLigatures = asciiLigatures;
    [self setNeedsDisplay:YES];
}

- (void)setNonAsciiLigatures:(BOOL)nonAsciiLigatures {
    _nonAsciiLigatures = nonAsciiLigatures;
    [self setNeedsDisplay:YES];
}

- (void)setUseItalicFont:(BOOL)italicFlag {
    _useItalicFont = italicFlag;
    [self setNeedsDisplay:YES];
}


- (void)setUseBoldColor:(BOOL)flag brighten:(BOOL)brighten {
    _useCustomBoldColor = flag;
    _brightenBold = brighten;
    _drawingHelper.useCustomBoldColor = flag;
    [self setNeedsDisplay:YES];
}

- (void)setBlinkAllowed:(BOOL)value {
    _drawingHelper.blinkAllowed = value;
    _blinkAllowed = value;
    [self setNeedsDisplay:YES];
}

- (void)setCursorNeedsDisplay {
    [self setNeedsDisplayInRect:[self rectWithHalo:[self cursorFrame]]];
}

- (void)setCursorType:(ITermCursorType)value {
    _drawingHelper.cursorType = value;
    [self markCursorDirty];
}

- (NSDictionary *)markedTextAttributes {
    return _markedTextAttributes;
}

- (void)setMarkedTextAttributes:(NSDictionary *)attr {
    [_markedTextAttributes autorelease];
    _markedTextAttributes = [attr retain];
}

- (NSFont *)font {
    return _primaryFont.font;
}

- (NSFont *)nonAsciiFont {
    return _useNonAsciiFont ? _secondaryFont.font : _primaryFont.font;
}

- (NSFont *)nonAsciiFontEvenIfNotUsed {
    return _secondaryFont.font;
}

- (void)setFont:(NSFont*)aFont
    nonAsciiFont:(NSFont *)nonAsciiFont
    horizontalSpacing:(CGFloat)horizontalSpacing
    verticalSpacing:(CGFloat)verticalSpacing {
    NSSize sz = [PTYTextView charSizeForFont:aFont
                             horizontalSpacing:1.0
                             verticalSpacing:1.0];

    _charWidthWithoutSpacing = sz.width;
    _charHeightWithoutSpacing = sz.height;
    _horizontalSpacing = horizontalSpacing;
    _verticalSpacing = verticalSpacing;
    self.charWidth = ceil(_charWidthWithoutSpacing * horizontalSpacing);
    self.lineHeight = ceil(_charHeightWithoutSpacing * verticalSpacing);

    _primaryFont.font = aFont;
    _primaryFont.boldVersion = [_primaryFont computedBoldVersion];
    _primaryFont.italicVersion = [_primaryFont computedItalicVersion];
    _primaryFont.boldItalicVersion = [_primaryFont computedBoldItalicVersion];

    _secondaryFont.font = nonAsciiFont;
    _secondaryFont.boldVersion = [_secondaryFont computedBoldVersion];
    _secondaryFont.italicVersion = [_secondaryFont computedItalicVersion];
    _secondaryFont.boldItalicVersion = [_secondaryFont computedBoldItalicVersion];

    [self updateMarkedTextAttributes];

    NSScrollView* scrollview = [self enclosingScrollView];
    [scrollview setLineScroll:[self lineHeight]];
    [scrollview setPageScroll:2 * [self lineHeight]];
    [self updateNoteViewFrames];
    [_delegate textViewFontDidChange];

    // Refresh to avoid drawing before and after resize.
    [self refresh];
    [self setNeedsDisplay:YES];
}

- (void)setLineHeight:(double)aLineHeight {
    _lineHeight = ceil(aLineHeight);
    _drawingHelper.cellSize = NSMakeSize(_charWidth, _lineHeight);
    _drawingHelper.cellSizeWithoutSpacing = NSMakeSize(_charWidthWithoutSpacing, _charHeightWithoutSpacing);
}

- (void)setCharWidth:(double)width {
    _charWidth = ceil(width);
    _drawingHelper.cellSize = NSMakeSize(_charWidth, _lineHeight);
    _drawingHelper.cellSizeWithoutSpacing = NSMakeSize(_charWidthWithoutSpacing, _charHeightWithoutSpacing);
}

- (void)toggleShowTimestamps:(id)sender {
    _drawingHelper.showTimestamps = !_drawingHelper.showTimestamps;
    [self setNeedsDisplay:YES];
}

- (BOOL)showTimestamps {
    return _drawingHelper.showTimestamps;
}

- (void)setShowTimestamps:(BOOL)value {
    _drawingHelper.showTimestamps = value;
    [self setNeedsDisplay:YES];
}

- (void)setCursorVisible:(BOOL)cursorVisible {
    [self markCursorDirty];
    _drawingHelper.cursorVisible = cursorVisible;
}

- (BOOL)cursorVisible {
    return _drawingHelper.cursorVisible;
}

- (CGFloat)minimumBaselineOffset {
    return _primaryFont.baselineOffset;
}

- (CGFloat)minimumUnderlineOffset {
    return _primaryFont.underlineOffset;
}

- (void)setTransparency:(double)fVal {
    _transparency = fVal;
    [self setNeedsDisplay:YES];
    [_delegate textViewBackgroundColorDidChange];
}

- (void)setTransparencyAffectsOnlyDefaultBackgroundColor:(BOOL)value {
    _drawingHelper.transparencyAffectsOnlyDefaultBackgroundColor = value;
    [self setNeedsDisplay:YES];
}

- (float)blend {
    return _drawingHelper.blend;
}

- (void)setBlend:(float)fVal {
    _drawingHelper.blend = MIN(MAX(0.05, fVal), 1);
    [self setNeedsDisplay:YES];
}

- (void)setUseSmartCursorColor:(BOOL)value {
    _drawingHelper.useSmartCursorColor = value;
}

- (BOOL)useSmartCursorColor {
    return _drawingHelper.useSmartCursorColor;
}

- (void)setMinimumContrast:(double)value {
    _drawingHelper.minimumContrast = value;
    [_colorMap setMinimumContrast:value];
}

- (BOOL)useTransparency {
    return [_delegate textViewWindowUsesTransparency];
}

- (double)transparencyAlpha {
    return [self useTransparency] ? 1.0 - _transparency : 1.0;
}

#pragma mark - Focus

// This exists to work around an apparent OS bug described in issue 2690. Under some circumstances
// (which I cannot reproduce) the key window will be an NSToolbarFullScreenWindow and the iTermTerminalWindow
// will be one of the main windows. NSToolbarFullScreenWindow doesn't appear to handle keystrokes,
// so they fall through to the main window. We'd like the cursor to blink and have other key-
// window behaviors in this case.
- (BOOL)isInKeyWindow {
    if ([[self window] isKeyWindow]) {
        DLog(@"%@ is key window", self);
        return YES;
    }
    NSWindow *theKeyWindow = [[NSApplication sharedApplication] keyWindow];
    if (!theKeyWindow) {
        DLog(@"There is no key window");
        return NO;
    }
    if (!strcmp("NSToolbarFullScreenWindow", object_getClassName(theKeyWindow))) {
        DLog(@"key window is a NSToolbarFullScreenWindow, using my main window status of %d as key status",
             (int)self.window.isMainWindow);
        return [[self window] isMainWindow];
    }
    return NO;
}

// Uses an undocumented/deprecated API to receive key presses even when inactive.
- (BOOL)stealKeyFocus {
    // Make sure everything needed for focus stealing exists in this version of Mac OS.
    CPSGetCurrentProcessFunction *getCurrentProcess = GetCPSGetCurrentProcessFunction();
    CPSStealKeyFocusFunction *stealKeyFocus = GetCPSStealKeyFocusFunction();
    CPSReleaseKeyFocusFunction *releaseKeyFocus = GetCPSReleaseKeyFocusFunction();

    if (!getCurrentProcess || !stealKeyFocus || !releaseKeyFocus) {
        return NO;
    }

    CPSProcessSerNum psn;
    if (getCurrentProcess(&psn) == noErr) {
        OSErr err = stealKeyFocus(&psn);
        DLog(@"CPSStealKeyFocus returned %d", (int)err);
        // CPSStealKeyFocus appears to succeed even when it returns an error. See issue 4113.
        return YES;
    }

    return NO;
}

// Undoes -stealKeyFocus.
- (void)releaseKeyFocus {
    CPSGetCurrentProcessFunction *getCurrentProcess = GetCPSGetCurrentProcessFunction();
    CPSReleaseKeyFocusFunction *releaseKeyFocus = GetCPSReleaseKeyFocusFunction();

    if (!getCurrentProcess || !releaseKeyFocus) {
        return;
    }

    CPSProcessSerNum psn;
    if (getCurrentProcess(&psn) == noErr) {
        DLog(@"CPSReleaseKeyFocus");
        releaseKeyFocus(&psn);
    }
}

#pragma mark - Blinking

- (BOOL)isCursorBlinking {
    if (_blinkingCursor &&
            [self isInKeyWindow] &&
            [_delegate textViewIsActiveSession]) {
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)_isTextBlinking {
    int width = [_dataSource width];
    int lineStart = ([self visibleRect].origin.y + [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins]) / _lineHeight;  // add VMARGIN because stuff under top margin isn't visible.
    int lineEnd = ceil(([self visibleRect].origin.y + [self visibleRect].size.height - [self excess]) / _lineHeight);
    if (lineStart < 0) {
        lineStart = 0;
    }
    if (lineEnd > [_dataSource numberOfLines]) {
        lineEnd = [_dataSource numberOfLines];
    }
    for (int y = lineStart; y < lineEnd; y++) {
        screen_char_t* theLine = [_dataSource getLineAtIndex:y];
        for (int x = 0; x < width; x++) {
            if (theLine[x].blink) {
                return YES;
            }
        }
    }

    return NO;
}

- (BOOL)_isAnythingBlinking {
    return [self isCursorBlinking] || (_blinkAllowed && [self _isTextBlinking]);
}

#pragma mark - Refresh

// WARNING: Do not call this function directly. Call
// -[refresh] instead, as it ensures scrollback overflow
// is dealt with so that this function can dereference
// [_dataSource dirty] correctly.
- (BOOL)updateDirtyRects:(BOOL *)foundDirtyPtr {
    BOOL anythingIsBlinking = NO;
    BOOL foundDirty = NO;
    assert([_dataSource scrollbackOverflow] == 0);

    // Flip blink bit if enough time has passed. Mark blinking cursor dirty
    // when it blinks.
    BOOL redrawBlink = [self shouldRedrawBlinkingObjects];
    if (redrawBlink) {
        DebugLog(@"Time to redraw blinking objects");
        if (_blinkingCursor && [self isInKeyWindow]) {
            // Blink flag flipped and there is a blinking cursor. Make it redraw.
            [self setCursorNeedsDisplay];
        }
    }
    int WIDTH = [_dataSource width];

    // Any characters that changed selection status since the last update or
    // are blinking should be set dirty.
    anythingIsBlinking = [self _markChangedSelectionAndBlinkDirty:redrawBlink width:WIDTH];

    // Copy selection position to detect change in selected chars next call.
    [_oldSelection release];
    _oldSelection = [_selection copy];

    // Redraw lines with dirty characters
    int lineStart = [_dataSource numberOfLines] - [_dataSource height];
    int lineEnd = [_dataSource numberOfLines];
    // lineStart to lineEnd is the region that is the screen when the scrollbar
    // is at the bottom of the frame.

    [_dataSource setUseSavedGridIfAvailable:YES];
    long long totalScrollbackOverflow = [_dataSource totalScrollbackOverflow];
    int allDirty = [_dataSource isAllDirty] ? 1 : 0;
    [_dataSource resetAllDirty];

    VT100GridCoord cursorPosition = VT100GridCoordMake([_dataSource cursorX] - 1,
                                    [_dataSource cursorY] - 1);
    if (_previousCursorCoord.x != cursorPosition.x ||
            _previousCursorCoord.y - totalScrollbackOverflow != cursorPosition.y) {
        // Mark previous and current cursor position dirty
        DLog(@"Mark previous cursor position %d,%lld dirty",
             _previousCursorCoord.x, _previousCursorCoord.y - totalScrollbackOverflow);
        int maxX = [_dataSource width] - 1;
        if (_drawingHelper.highlightCursorLine) {
            [_dataSource setLineDirtyAtY:_previousCursorCoord.y - totalScrollbackOverflow];
            DLog(@"Mark current cursor line %d dirty", cursorPosition.y);
            [_dataSource setLineDirtyAtY:cursorPosition.y];
        } else {
            [_dataSource setCharDirtyAtCursorX:MIN(maxX, _previousCursorCoord.x)
                         Y:_previousCursorCoord.y - totalScrollbackOverflow];
            DLog(@"Mark current cursor position %d,%lld dirty", _previousCursorCoord.x,
                 _previousCursorCoord.y - totalScrollbackOverflow);
            [_dataSource setCharDirtyAtCursorX:MIN(maxX, cursorPosition.x) Y:cursorPosition.y];
        }
        // Set _previousCursorCoord to new cursor position
        _previousCursorCoord = VT100GridAbsCoordMake(cursorPosition.x,
                               cursorPosition.y + totalScrollbackOverflow);
    }

    // Remove results from dirty lines and mark parts of the view as needing display.
    NSMutableIndexSet *cleanLines = [NSMutableIndexSet indexSet];
    if (allDirty) {
        foundDirty = YES;
        [_findOnPageHelper removeHighlightsInRange:NSMakeRange(lineStart + totalScrollbackOverflow,
                                  lineEnd - lineStart)];
        [self setNeedsDisplayInRect:[self gridRect]];
    } else {
        const BOOL hasScrolled = [self.dataSource textViewGetAndResetHasScrolled];
        for (int y = lineStart; y < lineEnd; y++) {
            VT100GridRange range = [_dataSource dirtyRangeForLine:y - lineStart];
            if (range.length > 0) {
                foundDirty = YES;
                [_findOnPageHelper removeHighlightsInRange:NSMakeRange(y + totalScrollbackOverflow, 1)];
                [_findOnPageHelper removeSearchResultsInRange:NSMakeRange(y + totalScrollbackOverflow, 1)];
                [self setNeedsDisplayOnLine:y inRange:range];
            } else if (!hasScrolled) {
                [cleanLines addIndex:y - lineStart];
            }
        }
    }

    // Always mark the IME as needing to be drawn to keep things simple.
    if ([self hasMarkedText]) {
        [self invalidateInputMethodEditorRect];
    }

    if (foundDirty) {
        // Dump the screen contents
        DLog(@"Found dirty with delegate %@", _delegate);
        DLog(@"\n%@", [_dataSource debugString]);
    } else {
        DLog(@"Nothing dirty found, delegate=%@", _delegate);
    }

    // Unset the dirty bit for all chars.
    DebugLog(@"updateDirtyRects resetDirty");
    [_dataSource resetDirty];

    if (foundDirty) {
        [_dataSource saveToDvr:cleanLines];
        [_delegate textViewInvalidateRestorableState];
        [_delegate textViewDidFindDirtyRects];
    }

    if (foundDirty && [_dataSource shouldSendContentsChangedNotification]) {
        [_delegate textViewPostTabContentsChangedNotification];
    }

    [_dataSource setUseSavedGridIfAvailable:NO];

    // If you're viewing the scrollback area and it contains an animated gif it will need
    // to be redrawn periodically. The set of animated lines is added to while drawing and then
    // reset here.
    // TODO: Limit this to the columns that need to be redrawn.
    NSIndexSet *animatedLines = [_dataSource animatedLines];
    [animatedLines enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
                      [self setNeedsDisplayOnLine:idx];
                  }];
    [_dataSource resetAnimatedLines];

    if (foundDirtyPtr) {
        *foundDirtyPtr = foundDirty;
    }
    return _blinkAllowed && anythingIsBlinking;
}

- (void)handleScrollbackOverflow:(int)scrollbackOverflow userScroll:(BOOL)userScroll {
    // Keep correct selection highlighted
    [_selection scrollbackOverflowDidChange];
    [_oldSelection scrollbackOverflowDidChange];

    // Keep the user's current scroll position.
    NSScrollView *scrollView = [self enclosingScrollView];
    BOOL canSkipRedraw = NO;
    if (userScroll) {
        NSRect scrollRect = [self visibleRect];
        double amount = [scrollView verticalLineScroll] * scrollbackOverflow;
        scrollRect.origin.y -= amount;
        if (scrollRect.origin.y < 0) {
            scrollRect.origin.y = 0;
        } else {
            // No need to redraw the whole screen because nothing is
            // changing because of the scroll.
            canSkipRedraw = YES;
        }
        [self scrollRectToVisible:scrollRect];
    }

    // NOTE: I used to use scrollRect:by: here, and it is faster, but it is
    // absolutely a lost cause as far as correctness goes. When drawRect
    // gets called it needs to take that scrolling (which would happen
    // immediately when scrollRect:by: gets called) into account. Good luck
    // getting that right. I don't *think* it's a meaningful performance issue.
    // Because of a bug, we were always drawing the whole screen anyway. And if
    // the screen has scrolled by less than its height, input is coming in
    // slowly anyway.
    if (!canSkipRedraw) {
        [self setNeedsDisplay:YES];
    }

    // Move subviews up
    [self updateNoteViewFrames];

    // Update find on page
    [_findOnPageHelper overflowAdjustmentDidChange];

    NSAccessibilityPostNotification(self, NSAccessibilityRowCountChangedNotification);
}

// Update accessibility, to be called periodically.
- (void)refreshAccessibility {
    NSAccessibilityPostNotification(self, NSAccessibilityValueChangedNotification);
    long long absCursorY = ([_dataSource cursorY] + [_dataSource numberOfLines] +
                            [_dataSource totalScrollbackOverflow] - [_dataSource height]);
    if ([_dataSource cursorX] != _lastAccessibilityCursorX ||
            absCursorY != _lastAccessibiltyAbsoluteCursorY) {
        NSAccessibilityPostNotification(self, NSAccessibilitySelectedTextChangedNotification);
        NSAccessibilityPostNotification(self, NSAccessibilitySelectedRowsChangedNotification);
        NSAccessibilityPostNotification(self, NSAccessibilitySelectedColumnsChangedNotification);
        _lastAccessibilityCursorX = [_dataSource cursorX];
        _lastAccessibiltyAbsoluteCursorY = absCursorY;
        if (UAZoomEnabled()) {
            CGRect selectionRect = NSRectToCGRect(
                                       [self.window convertRectToScreen:[self convertRect:[self cursorFrame] toView:nil]]);
            selectionRect = [self accessibilityConvertScreenRect:selectionRect];
            UAZoomChangeFocus(&selectionRect, &selectionRect, kUAZoomFocusTypeInsertionPoint);
        }
    }
}

// This is called periodically. It updates the frame size, scrolls if needed, ensures selections
// and subviews are positioned correctly in case things scrolled
//
// Returns YES if blinking text or cursor was found.
- (BOOL)refresh {
    DLog(@"PTYTextView refresh called with delegate %@", _delegate);
    if (_dataSource == nil || _inRefresh) {
        return YES;
    }

    // Get the number of lines that have disappeared if scrollback buffer is full.
    const int scrollbackOverflow = [_dataSource scrollbackOverflow];
    [_dataSource resetScrollbackOverflow];
    const BOOL frameDidChange = [_delegate textViewResizeFrameIfNeeded];
    // Perform adjustments if lines were lost from the head of the buffer.
    BOOL userScroll = [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) userScroll];
    if (scrollbackOverflow > 0) {
        // -selectionDidChange might get called here, which calls -refresh.
        // Keeping this function safely reentrant is just too difficult.
        _inRefresh = YES;
        [self handleScrollbackOverflow:scrollbackOverflow userScroll:userScroll];
        _inRefresh = NO;
    }

    // Scroll to the bottom if needed.
    if (!userScroll) {
        iTermMetalClipView *clipView = [iTermMetalClipView castFrom:self.enclosingScrollView.contentView];
        [clipView performBlockWithoutShowingOverlayScrollers:^ {
                     [self scrollEnd];
                 }];
    }

    if ([[self subviews] count]) {
        // TODO: Why update notes not in this textview?
        [[NSNotificationCenter defaultCenter] postNotificationName:PTYNoteViewControllerShouldUpdatePosition
                                              object:nil];
        // Not sure why this is needed, but for some reason this view draws over its subviews.
        for (NSView *subview in [self subviews]) {
            [subview setNeedsDisplay:YES];
        }
    }

    [_delegate textViewDidRefresh];

    // See if any characters are dirty and mark them as needing to be redrawn.
    // Return if anything was found to be blinking.
    BOOL foundDirty = NO;
    const BOOL foundBlink = [self updateDirtyRects:&foundDirty] || [self isCursorBlinking];

    // Update accessibility.
    if (foundDirty) {
        [self refreshAccessibility];
    }
    if (scrollbackOverflow > 0 || frameDidChange) {
        // Need to redraw locations of search results.
        [self.delegate textViewFindOnPageLocationsDidChange];
    }

    return foundBlink;
}

- (void)markCursorDirty {
    int currentCursorX = [_dataSource cursorX] - 1;
    int currentCursorY = [_dataSource cursorY] - 1;
    DLog(@"Mark cursor position %d, %d dirty.", currentCursorX, currentCursorY);
    [_dataSource setCharDirtyAtCursorX:currentCursorX Y:currentCursorY];
}

- (BOOL)shouldRedrawBlinkingObjects {
    // Time to redraw blinking text or cursor?
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    double timeDelta = now - _timeOfLastBlink;
    if (timeDelta >= [iTermAdvancedSettingsModel timeBetweenBlinks]) {
        _drawingHelper.blinkingItemsVisible = !_drawingHelper.blinkingItemsVisible;
        _timeOfLastBlink = now;
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)_markChangedSelectionAndBlinkDirty:(BOOL)redrawBlink width:(int)width
{
    BOOL anyBlinkers = NO;
    // Visible chars that have changed selection status are dirty
    // Also mark blinking text as dirty if needed
    int lineStart = ([self visibleRect].origin.y + [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins]) / _lineHeight;  // add VMARGIN because stuff under top margin isn't visible.
    int lineEnd = ceil(([self visibleRect].origin.y + [self visibleRect].size.height - [self excess]) / _lineHeight);
    if (lineStart < 0) {
        lineStart = 0;
    }
    if (lineEnd > [_dataSource numberOfLines]) {
        lineEnd = [_dataSource numberOfLines];
    }
    NSArray<ScreenCharArray *> *lines = nil;
    if (_blinkAllowed) {
        lines = [_dataSource linesInRange:NSMakeRange(lineStart, lineEnd - lineStart)];
    }
    const NSInteger numLines = lines.count;
    DLog(@"Visible lines are [%d,%d)", lineStart, lineEnd);
    for (int y = lineStart, i = 0; y < lineEnd; y++, i++) {
        if (_blinkAllowed && i < numLines) {
            // First, mark blinking chars as dirty.
            screen_char_t *theLine = lines[i].line;
            for (int x = 0; x < lines[i].length; x++) {
                const BOOL charBlinks = theLine[x].blink;
                anyBlinkers |= charBlinks;
                const BOOL blinked = redrawBlink && charBlinks;
                if (blinked) {
                    NSRect dirtyRect = [self visibleRect];
                    dirtyRect.origin.y = y * _lineHeight;
                    dirtyRect.size.height = _lineHeight;
                    if (gDebugLogging) {
                        DLog(@"Found blinking char on line %d", y);
                    }
                    const NSRect rect = [self rectWithHalo:dirtyRect];
                    DLog(@"Redraw rect for line y=%d i=%d blink: %@", y, i, NSStringFromRect(rect));
                    [self setNeedsDisplayInRect:rect];
                    break;
                }
            }
        }

        // Now mark chars whose selection status has changed as needing display.
        const long long overflow = _dataSource.totalScrollbackOverflow;
        NSIndexSet *areSelected = [_selection selectedIndexesOnAbsoluteLine:y + overflow];
        NSIndexSet *wereSelected = [_oldSelection selectedIndexesOnAbsoluteLine:y + overflow];
        if (![areSelected isEqualToIndexSet:wereSelected]) {
            // Just redraw the whole line for simplicity.
            NSRect dirtyRect = [self visibleRect];
            dirtyRect.origin.y = y * _lineHeight;
            dirtyRect.size.height = _lineHeight;
            if (gDebugLogging) {
                DLog(@"found selection change on line %d", y);
            }
            [self setNeedsDisplayInRect:[self rectWithHalo:dirtyRect]];
        }
    }
    return anyBlinkers;
}

#pragma mark - Selection

- (SmartMatch *)smartSelectAtX:(int)x
    y:(int)y
    to:(VT100GridWindowedRange *)range
    ignoringNewlines:(BOOL)ignoringNewlines
    actionRequired:(BOOL)actionRequired
    respectDividers:(BOOL)respectDividers {
    VT100GridAbsWindowedRange absRange;
    const long long overflow = _dataSource.totalScrollbackOverflow;
    SmartMatch *match = [_urlActionHelper smartSelectAtAbsoluteCoord:VT100GridAbsCoordMake(x, y + overflow)
                                          to:&absRange
                                          ignoringNewlines:ignoringNewlines
                                          actionRequired:actionRequired
                                          respectDividers:respectDividers];
    if (range) {
        *range = VT100GridWindowedRangeFromAbsWindowedRange(absRange, overflow);
    }
    return match;
}

- (VT100GridCoordRange)rangeByTrimmingNullsFromRange:(VT100GridCoordRange)range
    trimSpaces:(BOOL)trimSpaces {
    VT100GridCoordRange result = range;
    int width = [_dataSource width];
    int lineY = result.start.y;
    screen_char_t *line = [_dataSource getLineAtIndex:lineY];
    while (!VT100GridCoordEquals(result.start, range.end)) {
        if (lineY != result.start.y) {
            lineY = result.start.y;
            line = [_dataSource getLineAtIndex:lineY];
        }
        unichar code = line[result.start.x].code;
        BOOL trim = ((code == 0) ||
                     (trimSpaces && (code == ' ' || code == '\t' || code == TAB_FILLER)));
        if (trim) {
            result.start.x++;
            if (result.start.x == width) {
                result.start.x = 0;
                result.start.y++;
            }
        } else {
            break;
        }
    }

    while (!VT100GridCoordEquals(result.end, result.start)) {
        // x,y is the predecessor of result.end and is the cell to test.
        int x = result.end.x - 1;
        int y = result.end.y;
        if (x < 0) {
            x = width - 1;
            y = result.end.y - 1;
        }
        if (lineY != y) {
            lineY = y;
            line = [_dataSource getLineAtIndex:y];
        }
        unichar code = line[x].code;
        BOOL trim = ((code == 0) ||
                     (trimSpaces && (code == ' ' || code == '\t' || code == TAB_FILLER)));
        if (trim) {
            result.end = VT100GridCoordMake(x, y);
        } else {
            break;
        }
    }

    return result;
}

- (IBAction)selectAll:(id)sender {
    // Set the selection region to the whole text.
    const long long overflow = _dataSource.totalScrollbackOverflow;
    [_selection beginSelectionAtAbsCoord:VT100GridAbsCoordMake(0, overflow)
                mode:kiTermSelectionModeCharacter
                resume:NO
                append:NO];
    [_selection moveSelectionEndpointTo:VT100GridAbsCoordMake([_dataSource width],
                       overflow + [_dataSource numberOfLines] - 1)];
    [_selection endLiveSelection];
    if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
        [self copySelectionAccordingToUserPreferences];
    }
}

- (IBAction)selectCurrentCommand:(id)sender {
    DLog(@"selectCurrentCommand");
    [self selectRange:[_delegate textViewRangeOfCurrentCommand]];
}

- (IBAction)selectOutputOfLastCommand:(id)sender {
    DLog(@"selectOutputOfLastCommand:");
    [self selectRange:[_delegate textViewRangeOfLastCommandOutput]];
}

- (void)selectRange:(VT100GridAbsCoordRange)range {
    DLog(@"The range is %@", VT100GridAbsCoordRangeDescription(range));

    if (range.start.x < 0) {
        DLog(@"Aborting");
        return;
    }

    DLog(@"Total scrollback overflow is %lld", [_dataSource totalScrollbackOverflow]);

    [_selection beginSelectionAtAbsCoord:range.start
                mode:kiTermSelectionModeCharacter
                resume:NO
                append:NO];
    [_selection moveSelectionEndpointTo:range.end];
    [_selection endLiveSelection];
    DLog(@"Done selecting output of last command.");

    if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
        [self copySelectionAccordingToUserPreferences];
    }
}

- (void)deselect {
    [_selection endLiveSelection];
    [_selection clearSelection];
}

- (NSString *)selectedText {
    if (_contextMenuHelper.savedSelectedText) {
        DLog(@"Returning saved selected text");
        return _contextMenuHelper.savedSelectedText;
    }
    return [self selectedTextCappedAtSize:0];
}

- (NSString *)selectedTextCappedAtSize:(int)maxBytes {
    return [self selectedTextWithStyle:iTermCopyTextStylePlainText cappedAtSize:maxBytes minimumLineNumber:0];
}

// Does not include selected text on lines before |minimumLineNumber|.
// Returns an NSAttributedString* if style is iTermCopyTextStyleAttributed, or an NSString* if not.
- (id)selectedTextWithStyle:(iTermCopyTextStyle)style
    cappedAtSize:(int)maxBytes
    minimumLineNumber:(int)minimumLineNumber {
    if (![_selection hasSelection]) {
        DLog(@"startx < 0 so there is no selected text");
        return nil;
    }
    BOOL copyLastNewline = [iTermPreferences boolForKey:kPreferenceKeyCopyLastNewline];
    BOOL trimWhitespace = [iTermAdvancedSettingsModel trimWhitespaceOnCopy];
    id theSelectedText;
    NSAttributedStringKey sgrAttribute = @"iTermSGR";
    NSDictionary *(^attributeProvider)(screen_char_t);
    switch (style) {
    case iTermCopyTextStyleAttributed:
        theSelectedText = [[[NSMutableAttributedString alloc] init] autorelease];
        attributeProvider = ^NSDictionary *(screen_char_t theChar) {
            return [self charAttributes:theChar];
        };
        break;

    case iTermCopyTextStylePlainText:
        theSelectedText = [[[NSMutableString alloc] init] autorelease];
        attributeProvider = nil;
        break;

    case iTermCopyTextStyleWithControlSequences:
        theSelectedText = [[[NSMutableAttributedString alloc] init] autorelease];
        attributeProvider = ^NSDictionary *(screen_char_t theChar) {
            return @ { sgrAttribute: [self.dataSource sgrCodesForChar:theChar] };
        };
        break;
    }

    [_selection enumerateSelectedAbsoluteRanges:^(VT100GridAbsWindowedRange absRange, BOOL *stop, BOOL eol) {
                   [self withRelativeWindowedRange:absRange block:^(VT100GridWindowedRange range) {
                       if (range.coordRange.end.y < minimumLineNumber) {
                           return;
                       } else {
                           range.coordRange.start.y = MAX(range.coordRange.start.y, minimumLineNumber);
            }
            int cap = INT_MAX;
            if (maxBytes > 0) {
                cap = maxBytes - [theSelectedText length];
                if (cap <= 0) {
                    *stop = YES;
                    return;
                }
            }
            iTermTextExtractor *extractor =
                [iTermTextExtractor textExtractorWithDataSource:_dataSource];
            id content = [extractor contentInRange:range
                                    attributeProvider:attributeProvider
                                    nullPolicy:kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal
                                    pad:NO
                                    includeLastNewline:copyLastNewline
                                    trimTrailingWhitespace:trimWhitespace
                                    cappedAtSize:cap
                                    truncateTail:YES
                                    continuationChars:nil
                                    coords:nil];
            if (attributeProvider != nil) {
                [theSelectedText appendAttributedString:content];
            } else {
                [theSelectedText appendString:content];
            }
            NSString *contentString = (attributeProvider != nil) ? [content string] : content;
            if (eol && ![contentString hasSuffix:@"\n"]) {
                if (attributeProvider != nil) {
                    [theSelectedText iterm_appendString:@"\n"];
                } else {
                    [theSelectedText appendString:@"\n"];
                }
            }
        }];
    }];

    if (style == iTermCopyTextStyleWithControlSequences) {
        NSAttributedString *attributedString = theSelectedText;
        NSMutableString *string = [NSMutableString string];
        [attributedString enumerateAttribute:sgrAttribute
                          inRange:NSMakeRange(0, attributedString.length)
                          options:0
                         usingBlock:^(NSSet *_Nullable value, NSRange range, BOOL * _Nonnull stop) {
                             NSString *code = [NSString stringWithFormat:@"%c[%@m", VT100CC_ESC, [value.allObjects componentsJoinedByString:@";"]];
            [string appendString:code];
            [string appendString:[attributedString.string substringWithRange:range]];
        }];
        return string;
    }

    return theSelectedText;
}

- (NSString *)selectedTextCappedAtSize:(int)maxBytes
    minimumLineNumber:(int)minimumLineNumber {
    return [self selectedTextWithStyle:iTermCopyTextStylePlainText
                 cappedAtSize:maxBytes
                 minimumLineNumber:minimumLineNumber];
}

- (NSAttributedString *)selectedAttributedTextWithPad:(BOOL)pad {
    return [self selectedTextWithStyle:iTermCopyTextStyleAttributed cappedAtSize:0 minimumLineNumber:0];
}

- (BOOL)_haveShortSelection {
    int width = [_dataSource width];
    return [_selection hasSelection] && [_selection length] <= width;
}

- (iTermLogicalMovementHelper *)logicalMovementHelperForCursorCoordinate:(VT100GridCoord)relativeCursorCoord {
    const long long overflow = _dataSource.totalScrollbackOverflow;
    VT100GridAbsCoord cursorCoord = VT100GridAbsCoordMake(relativeCursorCoord.x,
                                    relativeCursorCoord.y + overflow);
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    iTermLogicalMovementHelper *helper =
        [[iTermLogicalMovementHelper alloc] initWithTextExtractor:extractor
                                            selection:_selection
                                            cursorCoordinate:cursorCoord
                                            width:[_dataSource width]
                                            numberOfLines:[_dataSource numberOfLines]
                                            totalScrollbackOverflow:overflow];
    helper.delegate = self.dataSource;
    return [helper autorelease];
}

- (void)moveSelectionEndpoint:(PTYTextViewSelectionEndpoint)endpoint
    inDirection:(PTYTextViewSelectionExtensionDirection)direction
    by:(PTYTextViewSelectionExtensionUnit)unit {
    return [self moveSelectionEndpoint:endpoint
                 inDirection:direction
                 by:unit
                 cursorCoord:[self cursorCoord]];
}

- (void)moveSelectionEndpoint:(PTYTextViewSelectionEndpoint)endpoint
    inDirection:(PTYTextViewSelectionExtensionDirection)direction
    by:(PTYTextViewSelectionExtensionUnit)unit
    cursorCoord:(VT100GridCoord)cursorCoord {
    iTermLogicalMovementHelper *helper = [self logicalMovementHelperForCursorCoordinate:cursorCoord];
    VT100GridAbsCoordRange newRange =
        [helper moveSelectionEndpoint:endpoint
                inDirection:direction
                by:unit];

    [self withRelativeCoordRange:newRange block:^(VT100GridCoordRange range) {
             [self scrollLineNumberRangeIntoView:VT100GridRangeMake(range.start.y,
                range.end.y - range.start.y)];
         }];

    // Copy to pasteboard if needed.
    if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
        [self copySelectionAccordingToUserPreferences];
    }
}

// Returns YES if the selection changed.
- (BOOL)moveSelectionEndpointToX:(int)x Y:(int)y locationInTextView:(NSPoint)locationInTextView {
    if (!_selection.live) {
        return NO;
    }

    DLog(@"Move selection endpoint to %d,%d, coord=%@",
         x, y, [NSValue valueWithPoint:locationInTextView]);
    int width = [_dataSource width];
    if (locationInTextView.y == 0) {
        x = y = 0;
    } else if (locationInTextView.x < [iTermPreferences intForKey:kPreferenceKeySideMargins] && _selection.liveRange.coordRange.start.y < y) {
        // complete selection of previous line
        x = width;
        y--;
    }
    if (y >= [_dataSource numberOfLines]) {
        y = [_dataSource numberOfLines] - 1;
    }
    const BOOL hasColumnWindow = (_selection.liveRange.columnWindow.location > 0 ||
                                  _selection.liveRange.columnWindow.length < width);
    if (hasColumnWindow &&
            !VT100GridRangeContains(_selection.liveRange.columnWindow, x)) {
        DLog(@"Mouse has wandered outside columnn window %@", VT100GridRangeDescription(_selection.liveRange.columnWindow));
        [_selection clearColumnWindowForLiveSelection];
    }
    const BOOL result = [_selection moveSelectionEndpointTo:VT100GridAbsCoordMake(x, y + _dataSource.totalScrollbackOverflow)];
    DLog(@"moveSelectionEndpoint. selection=%@", _selection);
    return result;
}

- (BOOL)growSelectionLeft {
    if (![_selection hasSelection]) {
        return NO;
    }

    [self moveSelectionEndpoint:kPTYTextViewSelectionEndpointStart
          inDirection:kPTYTextViewSelectionExtensionDirectionLeft
          by:kPTYTextViewSelectionExtensionUnitWord];

    return YES;
}

- (void)growSelectionRight {
    if (![_selection hasSelection]) {
        return;
    }

    [self moveSelectionEndpoint:kPTYTextViewSelectionEndpointEnd
          inDirection:kPTYTextViewSelectionExtensionDirectionRight
          by:kPTYTextViewSelectionExtensionUnitWord];
}

- (BOOL)isAnyCharSelected {
    return [_selection hasSelection];
}

- (NSString *)getWordForX:(int)x
    y:(int)y
    range:(VT100GridWindowedRange *)rangePtr
    respectDividers:(BOOL)respectDividers {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    VT100GridCoord coord = VT100GridCoordMake(x, y);
    if (respectDividers) {
        [extractor restrictToLogicalWindowIncludingCoord:coord];
    }
    VT100GridWindowedRange range = [extractor rangeForWordAt:coord  maximumLength:kLongMaximumWordLength];
    if (rangePtr) {
        *rangePtr = range;
    }

    return [extractor contentInRange:range
                      attributeProvider:nil
                      nullPolicy:kiTermTextExtractorNullPolicyTreatAsSpace
                      pad:YES
                      includeLastNewline:NO
                      trimTrailingWhitespace:NO
                      cappedAtSize:-1
                      truncateTail:YES
                      continuationChars:nil
                      coords:nil];
}

- (BOOL)liveSelectionRespectsSoftBoundaries {
    if (_selection.haveClearedColumnWindow) {
        return NO;
    }
    return [[iTermController sharedInstance] selectionRespectsSoftBoundaries];
}

#pragma mark - Copy/Paste

- (void)copySelectionAccordingToUserPreferences {
    DLog(@"copySelectionAccordingToUserPreferences");
    if ([iTermAdvancedSettingsModel copyWithStylesByDefault]) {
        [self copyWithStyles:self];
    } else {
        [self copy:self];
    }
}

- (void)copy:(id)sender {
    // TODO: iTermSelection should use absolute coordinates everywhere. Until that is done, we must
    // call refresh here to take care of any scrollback overflow that would cause the selected range
    // to not match reality.
    [self refresh];

    DLog(@"-[PTYTextView copy:] called");
    DLog(@"%@", [NSThread callStackSymbols]);

    NSString *copyString = [self selectedText];

    if ([iTermAdvancedSettingsModel disallowCopyEmptyString] && copyString.length == 0) {
        DLog(@"Disallow copying empty string");
        return;
    }
    DLog(@"Have selected text: “%@”. selection=%@", copyString, _selection);
    if (copyString) {
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];
        [pboard declareTypes:[NSArray arrayWithObject:NSPasteboardTypeString] owner:self];
        [pboard setString:copyString forType:NSPasteboardTypeString];
    }

    [[PasteboardHistory sharedInstance] save:copyString];
}

- (IBAction)copyWithStyles:(id)sender {
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];

    DLog(@"-[PTYTextView copyWithStyles:] called");
    NSAttributedString *copyAttributedString = [self selectedAttributedTextWithPad:NO];
    if ([iTermAdvancedSettingsModel disallowCopyEmptyString] &&
            copyAttributedString.length == 0) {
        DLog(@"Disallow copying empty string");
        return;
    }

    DLog(@"Have selected text of length %d. selection=%@", (int)[copyAttributedString length], _selection);
    NSMutableArray *types = [NSMutableArray array];
    if (copyAttributedString) {
        [types addObject:NSPasteboardTypeRTF];
    }
    [pboard declareTypes:types owner:self];
    if (copyAttributedString) {
        // I used to convert this to RTF data using
        // RTFFromRange:documentAttributes: but images wouldn't paste right.
        [pboard clearContents];
        [pboard writeObjects:@[ copyAttributedString ]];
    }
    // I used to do
    //   [pboard setString:[copyAttributedString string] forType:NSPasteboardTypeString]
    // but this seems to take precedence over the attributed version for
    // pasting sometimes, for example in TextEdit.
    [[PasteboardHistory sharedInstance] save:[copyAttributedString string]];
}

- (IBAction)copyWithControlSequences:(id)sender {
    DLog(@"-[PTYTextView copyWithControlSequences:] called");
    DLog(@"%@", [NSThread callStackSymbols]);

    NSString *copyString = [self selectedTextWithStyle:iTermCopyTextStyleWithControlSequences
                                 cappedAtSize:-1
                                 minimumLineNumber:0];

    if ([iTermAdvancedSettingsModel disallowCopyEmptyString] && copyString.length == 0) {
        DLog(@"Disallow copying empty string");
        return;
    }
    DLog(@"Have selected text: “%@”. selection=%@", copyString, _selection);
    if (copyString) {
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];
        [pboard declareTypes:[NSArray arrayWithObject:NSPasteboardTypeString] owner:self];
        [pboard setString:copyString forType:NSPasteboardTypeString];
    }

    [[PasteboardHistory sharedInstance] save:copyString];
}

- (void)paste:(id)sender {
    DLog(@"Checking if delegate %@ can paste", _delegate);
    if ([_delegate respondsToSelector:@selector(paste:)]) {
        DLog(@"Calling paste on delegate.");
        [_delegate paste:sender];
    }
}

- (void)pasteOptions:(id)sender {
    [_delegate pasteOptions:sender];
}

- (void)pasteSelection:(id)sender {
    [_delegate textViewPasteFromSessionWithMostRecentSelection:[sender tag]];
}

- (IBAction)pasteBase64Encoded:(id)sender {
    NSData *data = [[NSPasteboard generalPasteboard] dataForFirstFile];
    if (data) {
        [_delegate pasteString:[data stringWithBase64EncodingWithLineBreak:@"\r"]];
    }
}

- (BOOL)pasteValuesOnPasteboard:(NSPasteboard *)pasteboard cdToDirectory:(BOOL)cdToDirectory {
    // Paste string or filenames in.
    NSArray *types = [pasteboard types];

    if ([types containsObject:NSPasteboardTypeFileURL]) {
        // Filenames were dragged.
        NSArray *filenames = [pasteboard filenamesOnPasteboardWithShellEscaping:YES];
        if (filenames.count) {
            BOOL pasteNewline = NO;

            NSMutableString *stringToPaste = [NSMutableString string];
            if (cdToDirectory) {
                // cmd-drag: "cd" to dragged directory (well, we assume it's a directory).
                // If multiple files are dragged, balk.
                if (filenames.count > 1) {
                    return NO;
                } else {
                    [stringToPaste appendString:@"cd "];
                    pasteNewline = YES;
                }
            }

            // Paste filenames separated by spaces.
            [stringToPaste appendString:[filenames componentsJoinedByString:@" "]];
            if (pasteNewline) {
                // For cmd-drag, we append a newline.
                [stringToPaste appendString:@"\r"];
            } else if (!cdToDirectory) {
                [stringToPaste appendString:@" "];
            }
            [_delegate pasteString:stringToPaste];

            return YES;
        }
    }

    if ([types containsObject:NSPasteboardTypeString]) {
        NSString *string = [pasteboard stringForType:NSPasteboardTypeString];
        if (string.length) {
            [_delegate pasteString:string];
            return YES;
        }
    }

    return NO;
}

#pragma mark - Content

- (NSAttributedString *)attributedContent {
    return [self contentWithAttributes:YES];
}

- (NSString *)content {
    return [self contentWithAttributes:NO];
}

- (id)contentWithAttributes:(BOOL)attributes {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    VT100GridCoordRange theRange = VT100GridCoordRangeMake(0,
                                   0,
                                   [_dataSource width],
                                   [_dataSource numberOfLines] - 1);
    NSDictionary *(^attributeProvider)(screen_char_t) = nil;
    if (attributes) {
        attributeProvider =^NSDictionary *(screen_char_t theChar) {
            return [self charAttributes:theChar];
        };
    }
    return [extractor contentInRange:VT100GridWindowedRangeMake(theRange, 0, 0)
                      attributeProvider:attributeProvider
                      nullPolicy:kiTermTextExtractorNullPolicyTreatAsSpace
                      pad:NO
                      includeLastNewline:YES
                      trimTrailingWhitespace:NO
                      cappedAtSize:-1
                      truncateTail:YES
                      continuationChars:nil
                      coords:nil];
}

// Save method
- (void)saveDocumentAs:(id)sender {
    // We get our content of the textview or selection, if any
    NSString *aString = [self selectedText];
    if (!aString) {
        aString = [self content];
    }

    NSData *aData = [aString dataUsingEncoding:[_delegate textViewEncoding]
                             allowLossyConversion:YES];

    // initialize a save panel
    NSSavePanel *aSavePanel = [NSSavePanel savePanel];
    [aSavePanel setAccessoryView:nil];

    NSString *path = @"";
    NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                           NSUserDomainMask,
                           YES);
    if ([searchPaths count]) {
        path = [searchPaths objectAtIndex:0];
    }

    NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
    dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"yyyy-MM-dd hh-mm-ss" options:0 locale:nil];
    NSString *formattedDate = [dateFormatter stringFromDate:[NSDate date]];
    // Stupid mac os can't have colons in filenames
    formattedDate = [formattedDate stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    NSString *nowStr = [NSString stringWithFormat:@"Log at %@.txt", formattedDate];

    // Show the save panel. The first time it's done set the path, and from then on the save panel
    // will remember the last path you used.tmp
    [NSSavePanel setDirectoryURL:[NSURL fileURLWithPath:path] onceForID:@"saveDocumentAs:" savePanel:aSavePanel];
    aSavePanel.nameFieldStringValue = nowStr;
    if ([aSavePanel runModal] == NSModalResponseOK) {
        if (![aData writeToFile:aSavePanel.URL.path atomically:YES]) {
            DLog(@"Beep: can't write to %@", aSavePanel.URL);
            NSBeep();
        }
    }
}

#pragma mark - Miscellaneous Actions

- (IBAction)terminalStateToggleAlternateScreen:(id)sender {
    [self contextMenu:_contextMenuHelper toggleTerminalStateForMenuItem:sender];
}
- (IBAction)terminalStateToggleFocusReporting:(id)sender {
    [self contextMenu:_contextMenuHelper toggleTerminalStateForMenuItem:sender];
}
- (IBAction)terminalStateToggleMouseReporting:(id)sender {
    [self contextMenu:_contextMenuHelper toggleTerminalStateForMenuItem:sender];
}
- (IBAction)terminalStateTogglePasteBracketing:(id)sender {
    [self contextMenu:_contextMenuHelper toggleTerminalStateForMenuItem:sender];
}
- (IBAction)terminalStateToggleApplicationCursor:(id)sender {
    [self contextMenu:_contextMenuHelper toggleTerminalStateForMenuItem:sender];
}
- (IBAction)terminalStateToggleApplicationKeypad:(id)sender {
    [self contextMenu:_contextMenuHelper toggleTerminalStateForMenuItem:sender];
}

- (IBAction)terminalToggleKeyboardMode:(id)sender {
    [self contextMenu:_contextMenuHelper toggleTerminalStateForMenuItem:sender];
}

- (IBAction)terminalStateReset:(id)sender {
    [self.delegate textViewResetTerminal];
}

- (void)movePane:(id)sender {
    [_delegate textViewMovePane];
}

- (IBAction)bury:(id)sender {
    [_delegate textViewBurySession];
}

#pragma mark - Marks

- (void)beginFlash:(NSString *)flashIdentifier {
    if ([flashIdentifier isEqualToString:kiTermIndicatorBell] &&
            [iTermAdvancedSettingsModel traditionalVisualBell]) {
        [_indicatorsHelper beginFlashingFullScreen];
    } else {
        [_indicatorsHelper beginFlashingIndicator:flashIdentifier];
    }
}

- (void)highlightMarkOnLine:(int)line hasErrorCode:(BOOL)hasErrorCode {
    CGFloat y = line * _lineHeight;
    NSView *highlightingView = [[[NSView alloc] initWithFrame:NSMakeRect(0, y, self.frame.size.width, _lineHeight)] autorelease];
    [highlightingView setWantsLayer:YES];
    [self addSubview:highlightingView];

    // Set up layer's initial state
    highlightingView.layer.backgroundColor = hasErrorCode ? [[NSColor redColor] CGColor] : [[NSColor blueColor] CGColor];
    highlightingView.layer.opaque = NO;
    highlightingView.layer.opacity = 0.75;

    // Animate it out, removing from superview when complete.
    [CATransaction begin];
    [highlightingView retain];
    [CATransaction setCompletionBlock:^ {
                      [highlightingView removeFromSuperview];
        [highlightingView release];
    }];
    const NSTimeInterval duration = 0.75;

    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    animation.fromValue = (id)@0.75;
    animation.toValue = (id)@0.0;
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.removedOnCompletion = NO;
    animation.fillMode = kCAFillModeForwards;
    [highlightingView.layer addAnimation:animation forKey:@"opacity"];

    [CATransaction commit];

    if (!_highlightedRows) {
        _highlightedRows = [[NSMutableArray alloc] init];
    }

    iTermHighlightedRow *entry = [[iTermHighlightedRow alloc] initWithAbsoluteLineNumber:_dataSource.totalScrollbackOverflow + line
                                                              success:!hasErrorCode];
    [_highlightedRows addObject:entry];
    [_delegate textViewDidHighlightMark];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^ {
        [self removeHighlightedRow:entry];
        [entry release];
    });
}

- (void)removeHighlightedRow:(iTermHighlightedRow *)row {
    [_highlightedRows removeObject:row];
}

#pragma mark - Annotations

- (void)addViewForNote:(PTYNoteViewController *)note {
    // Make sure scrollback overflow is reset.
    [self refresh];
    [note.view removeFromSuperview];
    [self addSubview:note.view];
    [self updateNoteViewFrames];
    [note setNoteHidden:NO];
}

- (void)addNote {
    if (![_selection hasSelection]) {
        return;
    }
    [self withRelativeCoordRange:_selection.lastAbsRange.coordRange block:^(VT100GridCoordRange range) {
             PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
        [_dataSource addNote:note inRange:range];

        // Make sure scrollback overflow is reset.
        [self refresh];
        [note.view removeFromSuperview];
        [self addSubview:note.view];
        [self updateNoteViewFrames];
        [note setNoteHidden:NO];
        [note beginEditing];
    }];
}

- (void)showNotes:(id)sender {
}

- (void)updateNoteViewFrames {
    for (NSView *view in [self subviews]) {
        if ([view isKindOfClass:[PTYNoteView class]]) {
            PTYNoteView *noteView = (PTYNoteView *)view;
            PTYNoteViewController *note =
                (PTYNoteViewController *)noteView.delegate.noteViewController;
            VT100GridCoordRange coordRange = [_dataSource coordRangeOfNote:note];
            if (coordRange.end.y >= 0) {
                [note setAnchor:NSMakePoint(coordRange.end.x * _charWidth + [iTermPreferences intForKey:kPreferenceKeySideMargins],
                                            (1 + coordRange.end.y) * _lineHeight)];
            }
        }
    }
    [_dataSource removeInaccessibleNotes];
}

- (BOOL)anyAnnotationsAreVisible {
    for (NSView *view in [self subviews]) {
        if ([view isKindOfClass:[PTYNoteView class]]) {
            if (!view.hidden) {
                return YES;
            }
        }
    }
    return NO;
}

- (void)showHideNotes:(id)sender {
    [_delegate textViewToggleAnnotations];
}

#pragma mark - Cursor

- (void)updateCursor:(NSEvent *)event {
    [self updateCursor:event action:nil];
}

- (VT100GridCoord)moveCursorHorizontallyTo:(VT100GridCoord)target from:(VT100GridCoord)cursor {
    DLog(@"Moving cursor horizontally from %@ to %@",
         VT100GridCoordDescription(cursor), VT100GridCoordDescription(target));
    VT100Terminal *terminal = [_dataSource terminal];
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    NSComparisonResult initialOrder = VT100GridCoordOrder(cursor, target);
    // Note that we could overshoot the destination because of double-width characters if the target
    // is a DWC_RIGHT.
    while (![extractor coord:cursor isEqualToCoord:target]) {
        switch (initialOrder) {
        case NSOrderedAscending:
            [_delegate writeStringWithLatin1Encoding:[[terminal.output keyArrowRight:0] stringWithEncoding:NSISOLatin1StringEncoding]];
            cursor = [extractor successorOfCoord:cursor];
            break;

        case NSOrderedDescending:
            [_delegate writeStringWithLatin1Encoding:[[terminal.output keyArrowLeft:0] stringWithEncoding:NSISOLatin1StringEncoding]];
            cursor = [extractor predecessorOfCoord:cursor];
            break;

        case NSOrderedSame:
            return cursor;
        }
    }
    DLog(@"Cursor will move to %@", VT100GridCoordDescription(cursor));
    return cursor;
}

- (void)placeCursorOnCurrentLineWithEvent:(NSEvent *)event verticalOk:(BOOL)verticalOk {
    DLog(@"PTYTextView placeCursorOnCurrentLineWithEvent BEGIN %@", event);

    NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:NO];
    VT100GridCoord target = VT100GridCoordMake(clickPoint.x, clickPoint.y);
    VT100Terminal *terminal = [_dataSource terminal];

    VT100GridCoord cursor = VT100GridCoordMake([_dataSource cursorX] - 1,
                            [_dataSource absoluteLineNumberOfCursor] - [_dataSource totalScrollbackOverflow]);
    if (!verticalOk) {
        DLog(@"Vertical movement not allowed");
        [self moveCursorHorizontallyTo:target from:cursor];
        return;
    }

    if (cursor.x > target.x) {
        DLog(@"Move cursor left before any vertical movement");
        // current position is right of target x,
        // so first move to left, and (if necessary)
        // up or down afterwards
        cursor = [self moveCursorHorizontallyTo:VT100GridCoordMake(target.x, cursor.y)
                       from:cursor];
    }

    // Move cursor vertically.
    DLog(@"Move cursor vertically from %@ to y=%d", VT100GridCoordDescription(cursor), target.y);
    while (cursor.y != target.y) {
        if (cursor.y > target.y) {
            [_delegate writeStringWithLatin1Encoding:[[terminal.output keyArrowUp:0] stringWithEncoding:NSISOLatin1StringEncoding]];
            cursor.y--;
        } else {
            [_delegate writeStringWithLatin1Encoding:[[terminal.output keyArrowDown:0] stringWithEncoding:NSISOLatin1StringEncoding]];
            cursor.y++;
        }
    }

    if (cursor.x != target.x) {
        [self moveCursorHorizontallyTo:target from:cursor];
    }

    DLog(@"PTYTextView placeCursorOnCurrentLineWithEvent END");
}

- (VT100GridCoord)cursorCoord {
    return VT100GridCoordMake(_dataSource.cursorX - 1,
                              _dataSource.numberOfScrollbackLines + _dataSource.cursorY - 1);
}

#pragma mark - Badge

- (void)setBadgeLabel:(NSString *)badgeLabel {
    _badgeLabel.stringValue = badgeLabel;
    [self recomputeBadgeLabel];
}

- (void)recomputeBadgeLabel {
    if (!_delegate) {
        return;
    }

    _badgeLabel.fillColor = [_delegate textViewBadgeColor];
    _badgeLabel.backgroundColor = [_colorMap colorForKey:kColorMapBackground];
    _badgeLabel.viewSize = self.enclosingScrollView.documentVisibleRect.size;
    if (_badgeLabel.isDirty) {
        _badgeLabel.dirty = NO;
        _drawingHelper.badgeImage = _badgeLabel.image;
        [self setNeedsDisplay:YES];
    }
}

#pragma mark - Semantic History

- (void)setSemanticHistoryPrefs:(NSDictionary *)prefs {
    self.semanticHistoryController.prefs = prefs;
}

- (void)openSemanticHistoryPath:(NSString *)path
    orRawFilename:(NSString *)rawFileName
    fragment:(NSString *)fragment
    workingDirectory:(NSString *)workingDirectory
    lineNumber:(NSString *)lineNumber
    columnNumber:(NSString *)columnNumber
    prefix:(NSString *)prefix
    suffix:(NSString *)suffix
    completion:(void (^)(BOOL))completion {
    [_urlActionHelper openSemanticHistoryPath:path
                      orRawFilename:rawFileName
                      fragment:fragment
                      workingDirectory:workingDirectory
                      lineNumber:lineNumber
                      columnNumber:columnNumber
                      prefix:prefix
                      suffix:suffix
                      completion:completion];
}

#pragma mark PointerControllerDelegate

- (void)pasteFromClipboardWithEvent:(NSEvent *)event {
    [self paste:nil];
}

- (void)pasteFromSelectionWithEvent:(NSEvent *)event {
    [self pasteSelection:nil];
}

- (void)openTargetWithEvent:(NSEvent *)event {
    [_urlActionHelper openTargetWithEvent:event inBackground:NO];
}

- (void)openTargetInBackgroundWithEvent:(NSEvent *)event {
    [_urlActionHelper openTargetWithEvent:event inBackground:YES];
}

- (void)smartSelectAndMaybeCopyWithEvent:(NSEvent *)event
    ignoringNewlines:(BOOL)ignoringNewlines {
    [_selection endLiveSelection];
    [_urlActionHelper smartSelectAndMaybeCopyWithEvent:event
                      ignoringNewlines:ignoringNewlines];
}

// Called for a right click that isn't control+click (e.g., two fingers on trackpad).
- (void)openContextMenuWithEvent:(NSEvent *)event {
    NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:NO];
    [_contextMenuHelper openContextMenuAt:VT100GridCoordMake(clickPoint.x, clickPoint.y)
                        event:event];
}

- (void)extendSelectionWithEvent:(NSEvent *)event {
    if (![_selection hasSelection]) {
        return;
    }
    NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:YES];
    const long long overflow = _dataSource.totalScrollbackOverflow;
    [_selection beginExtendingSelectionAt:VT100GridAbsCoordMake(clickPoint.x, clickPoint.y + overflow)];
    [_selection endLiveSelection];
    if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
        [self copySelectionAccordingToUserPreferences];
    }
}

- (void)quickLookWithEvent:(NSEvent *)event {
    [self handleQuickLookWithEvent:event];
}

- (void)nextTabWithEvent:(NSEvent *)event {
    [_delegate textViewSelectNextTab];
}

- (void)previousTabWithEvent:(NSEvent *)event {
    [_delegate textViewSelectPreviousTab];
}

- (void)nextWindowWithEvent:(NSEvent *)event {
    [_delegate textViewSelectNextWindow];
}

- (void)previousWindowWithEvent:(NSEvent *)event {
    [_delegate textViewSelectPreviousWindow];
}

- (void)movePaneWithEvent:(NSEvent *)event {
    [self movePane:nil];
}

- (void)sendEscapeSequence:(NSString *)text withEvent:(NSEvent *)event {
    [_delegate sendEscapeSequence:text];
}

- (void)sendHexCode:(NSString *)codes withEvent:(NSEvent *)event {
    [_delegate sendHexCode:codes];
}

- (void)sendText:(NSString *)text withEvent:(NSEvent *)event {
    [_delegate sendText:text];
}

- (void)selectPaneLeftWithEvent:(NSEvent *)event {
    [_delegate selectPaneLeftInCurrentTerminal];
}

- (void)selectPaneRightWithEvent:(NSEvent *)event {
    [_delegate selectPaneRightInCurrentTerminal];
}

- (void)selectPaneAboveWithEvent:(NSEvent *)event {
    [_delegate selectPaneAboveInCurrentTerminal];
}

- (void)selectPaneBelowWithEvent:(NSEvent *)event {
    [_delegate selectPaneBelowInCurrentTerminal];
}

- (void)newWindowWithProfile:(NSString *)guid withEvent:(NSEvent *)event {
    [_delegate textViewCreateWindowWithProfileGuid:guid];
}

- (void)newTabWithProfile:(NSString *)guid withEvent:(NSEvent *)event {
    [_delegate textViewCreateTabWithProfileGuid:guid];
}

- (void)newVerticalSplitWithProfile:(NSString *)guid withEvent:(NSEvent *)event {
    [_delegate textViewSplitVertically:YES withProfileGuid:guid];
}

- (void)newHorizontalSplitWithProfile:(NSString *)guid withEvent:(NSEvent *)event {
    [_delegate textViewSplitVertically:NO withProfileGuid:guid];
}

- (void)selectNextPaneWithEvent:(NSEvent *)event {
    [_delegate textViewSelectNextPane];
}

- (void)selectPreviousPaneWithEvent:(NSEvent *)event {
    [_delegate textViewSelectPreviousPane];
}

- (void)advancedPasteWithConfiguration:(NSString *)configuration
    fromSelection:(BOOL)fromSelection
    withEvent:(NSEvent *)event {
    [self.delegate textViewPasteSpecialWithStringConfiguration:configuration
                   fromSelection:fromSelection];
}

- (NSMenu *)titleBarMenu {
    return [_contextMenuHelper titleBarMenu];
}

#pragma mark - Drag and Drop

//
// Called when our drop area is entered
//
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    // NOTE: draggingUpdated: calls this method because they need the same implementation.
    int numValid = -1;
    if ([NSEvent modifierFlags] & NSEventModifierFlagOption) {  // Option-drag to copy
        _drawingHelper.showDropTargets = YES;
        [self.delegate textViewDidUpdateDropTargetVisibility];
    }
    NSDragOperation operation = [self dragOperationForSender:sender numberOfValidItems:&numValid];
    if (numValid != sender.numberOfValidItemsForDrop) {
        sender.numberOfValidItemsForDrop = numValid;
    }
    [self setNeedsDisplay:YES];
    return operation;
}

- (void)draggingExited:(nullable id <NSDraggingInfo>)sender {
    _drawingHelper.showDropTargets = NO;
    [self.delegate textViewDidUpdateDropTargetVisibility];
    [self setNeedsDisplay:YES];
}

//
// Called when the dragged object is moved within our drop area
//
- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender {
    NSPoint windowDropPoint = [sender draggingLocation];
    NSPoint dropPoint = [self convertPoint:windowDropPoint fromView:nil];
    int dropLine = dropPoint.y / _lineHeight;
    if (dropLine != _drawingHelper.dropLine) {
        _drawingHelper.dropLine = dropLine;
        [self setNeedsDisplay:YES];
    }
    return [self draggingEntered:sender];
}

//
// Called when the dragged item is about to be released in our drop area.
//
- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender {
    BOOL result;

    // Check if parent NSTextView knows how to handle this.
    result = [super prepareForDragOperation: sender];

    // If parent class does not know how to deal with this drag type, check if we do.
    if (result != YES &&
            [self dragOperationForSender:sender] != NSDragOperationNone) {
        result = YES;
    }

    return result;
}

// Returns the drag operation to use. It is determined from the type of thing
// being dragged, the modifiers pressed, and where it's being dropped.
- (NSDragOperation)dragOperationForSender:(id<NSDraggingInfo>)sender
    numberOfValidItems:(int *)numberOfValidItemsPtr {
    NSPasteboard *pb = [sender draggingPasteboard];
    NSArray *types = [pb types];
    NSPoint windowDropPoint = [sender draggingLocation];
    NSPoint dropPoint = [self convertPoint:windowDropPoint fromView:nil];
    int dropLine = dropPoint.y / _lineHeight;
    SCPPath *dropScpPath = [_dataSource scpPathForFile:@"" onLine:dropLine];

    // It's ok to upload if a file is being dragged in and the drop location has a remote host path.
    BOOL uploadOK = ([types containsObject:NSPasteboardTypeFileURL] && dropScpPath);

    // It's ok to paste if the the drag object is either a file or a string.
    BOOL pasteOK = !![[sender draggingPasteboard] availableTypeFromArray:@[ NSPasteboardTypeFileURL, NSPasteboardTypeString ]];

    const BOOL optionPressed = ([NSEvent modifierFlags] & NSEventModifierFlagOption) != 0;
    NSDragOperation sourceMask = [sender draggingSourceOperationMask];
    DLog(@"source mask=%@, optionPressed=%@, pasteOk=%@", @(sourceMask), @(optionPressed), @(pasteOK));
    if (!optionPressed && pasteOK && (sourceMask & (NSDragOperationGeneric | NSDragOperationCopy)) != 0) {
        DLog(@"Allowing a filename drag");
        // No modifier key was pressed and pasting is OK, so select the paste operation.
        NSArray *filenames = [pb filenamesOnPasteboardWithShellEscaping:YES];
        DLog(@"filenames=%@", filenames);
        if (numberOfValidItemsPtr) {
            if (filenames.count) {
                *numberOfValidItemsPtr = filenames.count;
            } else {
                *numberOfValidItemsPtr = 1;
            }
        }
        if (sourceMask & NSDragOperationGeneric) {
            // This is preferred since it doesn't have the green plus indicating a copy
            return NSDragOperationGeneric;
        } else {
            // Even if the source only allows copy, we allow it. See issue 4286.
            // Such sources are silly and we route around the damage.
            return NSDragOperationCopy;
        }
    } else if (optionPressed && uploadOK && (sourceMask & NSDragOperationCopy) != 0) {
        DLog(@"Allowing an upload drag");
        // Either Option was pressed or the sender allows Copy but not Generic,
        // and it's ok to upload, so select the upload operation.
        if (numberOfValidItemsPtr) {
            *numberOfValidItemsPtr = [[pb filenamesOnPasteboardWithShellEscaping:NO] count];
        }
        // You have to press option to get here so Copy is the only possibility.
        return NSDragOperationCopy;
    } else {
        // No luck.
        DLog(@"Not allowing drag");
        return NSDragOperationNone;
    }
}

- (void)_dragImage:(iTermImageInfo *)imageInfo forEvent:(NSEvent *)theEvent
{
    NSImage *icon = [imageInfo imageWithCellSize:NSMakeSize(_charWidth, _lineHeight)];

    NSData *imageData = imageInfo.data;
    if (!imageData || !icon) {
        return;
    }

    // tell our app not switch windows (currently not working)
    [NSApp preventWindowOrdering];

    // drag from center of the image
    NSPoint dragPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];

    VT100GridCoord coord = VT100GridCoordMake((dragPoint.x - [iTermPreferences intForKey:kPreferenceKeySideMargins]) / _charWidth,
                           dragPoint.y / _lineHeight);
    screen_char_t* theLine = [_dataSource getLineAtIndex:coord.y];
    if (theLine &&
            coord.x < [_dataSource width] &&
            theLine[coord.x].image &&
            theLine[coord.x].code == imageInfo.code) {
        // Get the cell you clicked on (small y at top of view)
        VT100GridCoord pos = GetPositionOfImageInChar(theLine[coord.x]);

        // Get the top-left origin of the image in cell coords
        VT100GridCoord imageCellOrigin = VT100GridCoordMake(coord.x - pos.x,
                                         coord.y - pos.y);

        // Compute the pixel coordinate of the image's top left point
        NSPoint imageTopLeftPoint = NSMakePoint(imageCellOrigin.x * _charWidth + [iTermPreferences intForKey:kPreferenceKeySideMargins],
                                                imageCellOrigin.y * _lineHeight);

        // Compute the distance from the click location to the image's origin
        NSPoint offset = NSMakePoint(dragPoint.x - imageTopLeftPoint.x,
                                     dragPoint.y - imageTopLeftPoint.y);

        // Adjust the drag point so the image won't jump as soon as the drag begins.
        dragPoint.x -= offset.x;
        dragPoint.y -= offset.y;
    }

    // start the drag
    NSPasteboardItem *pbItem = [imageInfo pasteboardItem];
    NSDraggingItem *dragItem = [[[NSDraggingItem alloc] initWithPasteboardWriter:pbItem] autorelease];
    [dragItem setDraggingFrame:NSMakeRect(dragPoint.x, dragPoint.y, icon.size.width, icon.size.height)
              contents:icon];
    NSDraggingSession *draggingSession = [self beginDraggingSessionWithItems:@[ dragItem ]
                                               event:theEvent
                                               source:self];

    draggingSession.animatesToStartingPositionsOnCancelOrFail = YES;
    draggingSession.draggingFormation = NSDraggingFormationNone;
}

- (void)_dragText:(NSString *)aString forEvent:(NSEvent *)theEvent {
    NSImage *anImage;
    int length;
    NSString *tmpString;
    NSSize imageSize;
    NSPoint dragPoint;

    length = [aString length];
    if ([aString length] > 15) {
        length = 15;
    }

    imageSize = NSMakeSize(_charWidth * length, _lineHeight);
    anImage = [[[NSImage alloc] initWithSize:imageSize] autorelease];
    [anImage lockFocus];
    if ([aString length] > 15) {
        tmpString = [NSString stringWithFormat:@"%@…",
                              [aString substringWithRange:NSMakeRange(0, 12)]];
    } else {
        tmpString = [aString substringWithRange:NSMakeRange(0, length)];
    }

    [tmpString drawInRect:NSMakeRect(0, 0, _charWidth * length, _lineHeight) withAttributes:nil];
    [anImage unlockFocus];

    // tell our app not switch windows (currently not working)
    [NSApp preventWindowOrdering];

    // drag from center of the image
    dragPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    dragPoint.x -= imageSize.width / 2;

    // start the drag
    NSPasteboardItem *pbItem = [[[NSPasteboardItem alloc] init] autorelease];
    [pbItem setString:aString forType:(NSString *)kUTTypeUTF8PlainText];
    NSDraggingItem *dragItem =
        [[[NSDraggingItem alloc] initWithPasteboardWriter:pbItem] autorelease];
    [dragItem setDraggingFrame:NSMakeRect(dragPoint.x,
                                          dragPoint.y,
                                          anImage.size.width,
                                          anImage.size.height)
              contents:anImage];
    NSDraggingSession *draggingSession = [self beginDraggingSessionWithItems:@[ dragItem ]
                                               event:theEvent
                                               source:self];

    draggingSession.animatesToStartingPositionsOnCancelOrFail = YES;
    draggingSession.draggingFormation = NSDraggingFormationNone;
}

- (NSDragOperation)dragOperationForSender:(id<NSDraggingInfo>)sender {
    return [self dragOperationForSender:sender numberOfValidItems:NULL];
}

#pragma mark NSDraggingSource

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return NSDragOperationEvery;
}

#pragma mark - File Transfer

- (BOOL)confirmUploadOfFiles:(NSArray *)files toPath:(SCPPath *)path {
    NSString *text;
    if (files.count == 0) {
        return NO;
    }
    if (files.count == 1) {
        text = [NSString stringWithFormat:@"Ok to scp\n%@\nto\n%@@%@:%@?",
                         [files componentsJoinedByString:@", "],
                         path.username, path.hostname, path.path];
    } else {
        text = [NSString stringWithFormat:@"Ok to scp the following files:\n%@\n\nto\n%@@%@:%@?",
                         [files componentsJoinedByString:@", "],
                         path.username, path.hostname, path.path];
    }
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = text;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert layout];
    NSInteger button = [alert runModal];
    return (button == NSAlertFirstButtonReturn);
}

- (void)maybeUpload:(NSArray *)tuple {
    NSArray *propertyList = tuple[0];
    SCPPath *dropScpPath = tuple[1];
    DLog(@"Confirm upload to %@", dropScpPath);
    if ([self confirmUploadOfFiles:propertyList toPath:dropScpPath]) {
        DLog(@"initiating upload");
        [self.delegate uploadFiles:propertyList toPath:dropScpPath];
    }
}

- (BOOL)uploadFilenamesOnPasteboard:(NSPasteboard *)pasteboard location:(NSPoint)windowDropPoint {
    // Upload a file.
    NSArray *types = [pasteboard types];
    NSPoint dropPoint = [self convertPoint:windowDropPoint fromView:nil];
    int dropLine = dropPoint.y / _lineHeight;
    SCPPath *dropScpPath = [_dataSource scpPathForFile:@"" onLine:dropLine];
    NSArray *filenames = [pasteboard filenamesOnPasteboardWithShellEscaping:NO];
    if ([types containsObject:NSPasteboardTypeFileURL] && filenames.count && dropScpPath) {
        // This is all so the mouse cursor will change to a plain arrow instead of the
        // drop target cursor.
        if (![[self window] isKindOfClass:[NSPanel class]]) {
            // Can't do this to a floating panel or we switch away from the lion fullscreen app we're over.
            [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        }
        [[self window] makeKeyAndOrderFront:nil];
        [self performSelector:@selector(maybeUpload:)
              withObject:@[ filenames, dropScpPath ]
              afterDelay:0];
        return YES;
    }
    return NO;
}

//
// Called when the dragged item is released in our drop area.
//
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    _drawingHelper.showDropTargets = NO;
    [self.delegate textViewDidUpdateDropTargetVisibility];
    NSPasteboard *draggingPasteboard = [sender draggingPasteboard];
    NSDragOperation dragOperation = [sender draggingSourceOperationMask];
    DLog(@"Perform drag operation");
    if (dragOperation & (NSDragOperationCopy | NSDragOperationGeneric)) {
        DLog(@"Drag operation is acceptable");
        if ([NSEvent modifierFlags] & NSEventModifierFlagOption) {
            DLog(@"Holding option so doing an upload");
            NSPoint windowDropPoint = [sender draggingLocation];
            return [self uploadFilenamesOnPasteboard:draggingPasteboard location:windowDropPoint];
        } else {
            DLog(@"No option so pasting filename");
            return [self pasteValuesOnPasteboard:draggingPasteboard
                         cdToDirectory:(dragOperation == NSDragOperationGeneric)];
        }
    }
    DLog(@"Drag/drop Failing");
    return NO;
}

#pragma mark - Printing

- (void)print:(id)sender {
    NSRect visibleRect;
    int lineOffset, numLines;
    int type = sender ? [sender tag] : 0;
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];

    switch (type) {
    case 0: // visible range
        visibleRect = [[self enclosingScrollView] documentVisibleRect];
        // Starting from which line?
        lineOffset = visibleRect.origin.y / _lineHeight;
        // How many lines do we need to draw?
        numLines = visibleRect.size.height / _lineHeight;
        VT100GridCoordRange coordRange = VT100GridCoordRangeMake(0,
                                         lineOffset,
                                         [_dataSource width],
                                         lineOffset + numLines - 1);
        [self printContent:[extractor contentInRange:VT100GridWindowedRangeMake(coordRange, 0, 0)
             attributeProvider:^NSDictionary *(screen_char_t theChar) {
                 return [self charAttributes:theChar];
             }
             nullPolicy:kiTermTextExtractorNullPolicyTreatAsSpace
             pad:NO
             includeLastNewline:YES
             trimTrailingWhitespace:NO
             cappedAtSize:-1
             truncateTail:YES
             continuationChars:nil
             coords:nil]];
        break;
    case 1: // text selection
        [self printContent:[self selectedAttributedTextWithPad:NO]];
        break;
    case 2: // entire buffer
        [self printContent:[self attributedContent]];
        break;
    }
}

- (void)printContent:(id)content {
    NSPrintInfo *printInfo = [NSPrintInfo sharedPrintInfo];
    [printInfo setHorizontalPagination:NSFitPagination];
    [printInfo setVerticalPagination:NSAutoPagination];
    [printInfo setVerticallyCentered:NO];

    // Create a temporary view with the contents, change to black on white, and
    // print it.
    NSRect frame = [[self enclosingScrollView] documentVisibleRect];
    NSTextView *tempView =
        [[[NSTextView alloc] initWithFrame:frame] autorelease];

    iTermPrintAccessoryViewController *accessory = nil;
    NSAttributedString *attributedString;
    if ([content isKindOfClass:[NSAttributedString class]]) {
        attributedString = content;
        accessory = [[[iTermPrintAccessoryViewController alloc] initWithNibName:@"iTermPrintAccessoryViewController"
                                                                 bundle:[NSBundle bundleForClass:self.class]] autorelease];
        accessory.userDidChangeSetting = ^() {
            NSAttributedString *theAttributedString = nil;
            if (accessory.blackAndWhite) {
                theAttributedString = [attributedString attributedStringByRemovingColor];
            } else {
                theAttributedString = attributedString;
            }
            [[tempView textStorage] setAttributedString:theAttributedString];
        };
    } else {
        NSDictionary *attributes =
            @ { NSBackgroundColorAttributeName:
                [NSColor textBackgroundColor],
                NSForegroundColorAttributeName:
                [NSColor textColor],
                NSFontAttributeName:
                self.font ?: [NSFont userFixedPitchFontOfSize:0]
              };
        attributedString = [[[NSAttributedString alloc] initWithString:content
                                                         attributes:attributes] autorelease];
    }
    [[tempView textStorage] setAttributedString:attributedString];

    // Now print the temporary view.
    NSPrintOperation *operation = [NSPrintOperation printOperationWithView:tempView printInfo:printInfo];
    if (accessory) {
        operation.printPanel.options = (NSPrintPanelShowsCopies |
                                        NSPrintPanelShowsPaperSize |
                                        NSPrintPanelShowsOrientation |
                                        NSPrintPanelShowsScaling |
                                        NSPrintPanelShowsPreview);
        [operation.printPanel addAccessoryController:accessory];
    }
    [operation runOperation];
}

#pragma mark - NSTextInputClient

- (void)doCommandBySelector:(SEL)aSelector {
    [_keyboardHandler doCommandBySelector:aSelector];
}

- (void)insertText:(id)aString replacementRange:(NSRange)replacementRange {
    [_keyboardHandler insertText:aString replacementRange:replacementRange];
}

// Legacy NSTextInput method, probably not used by the system but used internally.
- (void)insertText:(id)aString {
    // TODO: The replacement range is wrong
    [self insertText:aString replacementRange:NSMakeRange(0, [_drawingHelper.markedText length])];
}

// TODO: Respect replacementRange
- (void)setMarkedText:(id)aString
    selectedRange:(NSRange)selRange
    replacementRange:(NSRange)replacementRange {
    DLog(@"setMarkedText%@ selectedRange%@ replacementRange:%@",
         aString, NSStringFromRange(selRange), NSStringFromRange(replacementRange));
    if ([aString isKindOfClass:[NSAttributedString class]]) {
        _drawingHelper.markedText = [[[NSAttributedString alloc] initWithString:[aString string]
                                                                  attributes:[self markedTextAttributes]] autorelease];
    } else {
        _drawingHelper.markedText = [[[NSAttributedString alloc] initWithString:aString
                                                                  attributes:[self markedTextAttributes]] autorelease];
    }
    _drawingHelper.inputMethodMarkedRange = NSMakeRange(0, [_drawingHelper.markedText length]);
    _drawingHelper.inputMethodSelectedRange = selRange;

    // Compute the proper imeOffset.
    int dirtStart;
    int dirtEnd;
    int dirtMax;
    _drawingHelper.numberOfIMELines = 0;
    do {
        dirtStart = ([_dataSource cursorY] - 1 - _drawingHelper.numberOfIMELines) * [_dataSource width] + [_dataSource cursorX] - 1;
        dirtEnd = dirtStart + [self inputMethodEditorLength];
        dirtMax = [_dataSource height] * [_dataSource width];
        if (dirtEnd > dirtMax) {
            _drawingHelper.numberOfIMELines = _drawingHelper.numberOfIMELines + 1;
        }
    } while (dirtEnd > dirtMax);

    if (![_drawingHelper.markedText length]) {
        // The call to refresh won't invalidate the IME rect because
        // there is no IME any more. If the user backspaced over the only
        // char in the IME buffer then this causes it be erased.
        [self invalidateInputMethodEditorRect];
    }
    [_delegate refresh];
    [self scrollEnd];
}

- (void)setMarkedText:(id)aString selectedRange:(NSRange)selRange {
    [self setMarkedText:aString selectedRange:selRange replacementRange:NSMakeRange(0, 0)];
}

- (void)unmarkText {
    DLog(@"unmarkText");
    // As far as I can tell this is never called.
    _drawingHelper.inputMethodMarkedRange = NSMakeRange(0, 0);
    _drawingHelper.numberOfIMELines = 0;
    [self invalidateInputMethodEditorRect];
    [_delegate refresh];
    [self scrollEnd];
}

- (BOOL)hasMarkedText {
    return [_keyboardHandler hasMarkedText];
}

- (NSRange)markedRange {
    NSRange range;
    if (_drawingHelper.inputMethodMarkedRange.length > 0) {
        range = NSMakeRange([_dataSource cursorX]-1, _drawingHelper.inputMethodMarkedRange.length);
    } else {
        range = NSMakeRange([_dataSource cursorX]-1, 0);
    }
    DLog(@"markedRange->%@", NSStringFromRange(range));
    return range;
}

- (NSRange)selectedRange {
    return NSMakeRange(0, 0);
}

- (NSArray *)validAttributesForMarkedText {
    return @[ NSForegroundColorAttributeName,
              NSBackgroundColorAttributeName,
              NSUnderlineStyleAttributeName,
              NSFontAttributeName ];
}

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)theRange {
    return [self attributedSubstringForProposedRange:theRange actualRange:NULL];
}

- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)proposedRange
    actualRange:(NSRangePointer)actualRange {
    DLog(@"attributedSubstringForProposedRange:%@", NSStringFromRange(proposedRange));
    NSRange aRange = NSIntersectionRange(proposedRange,
                                         NSMakeRange(0, _drawingHelper.markedText.length));
    if (proposedRange.length > 0 && aRange.length == 0) {
        aRange.location = NSNotFound;
    }
    if (actualRange) {
        *actualRange = aRange;
    }
    if (aRange.location == NSNotFound) {
        return nil;
    }
    return [_drawingHelper.markedText attributedSubstringFromRange:NSMakeRange(0, aRange.length)];
}

- (NSUInteger)characterIndexForPoint:(NSPoint)thePoint {
    return MAX(0, thePoint.x / _charWidth);
}

- (long)conversationIdentifier {
    return (long)self; // not sure about this
}

- (NSRect)firstRectForCharacterRange:(NSRange)theRange actualRange:(NSRangePointer)actualRange {
    int y = [_dataSource cursorY] - 1;
    int x = [_dataSource cursorX] - 1;

    NSRect rect=NSMakeRect(x * _charWidth + [iTermPreferences intForKey:kPreferenceKeySideMargins],
                           (y + [_dataSource numberOfLines] - [_dataSource height] + 1) * _lineHeight,
                           _charWidth * theRange.length,
                           _lineHeight);
    rect.origin = [[self window] pointToScreenCoords:[self convertPoint:rect.origin toView:nil]];
    if (actualRange) {
        *actualRange = theRange;
    }

    return rect;
}

- (NSRect)firstRectForCharacterRange:(NSRange)theRange {
    return [self firstRectForCharacterRange:theRange actualRange:NULL];
}

#pragma mark - Find on page

- (IBAction)performFindPanelAction:(id)sender {
    NSMenuItem *menuItem = [NSMenuItem castFrom:sender];
    if (!menuItem) {
        return;
    }
    switch ((NSFindPanelAction)menuItem.tag) {
    case NSFindPanelActionNext:
    case NSFindPanelActionReplace:
    case NSFindPanelActionPrevious:
    case NSFindPanelActionSelectAll:
    case NSFindPanelActionReplaceAll:
    case NSFindPanelActionShowFindPanel:
    case NSFindPanelActionReplaceAndFind:
    case NSFindPanelActionSelectAllInSelection:
    case NSFindPanelActionReplaceAllInSelection:
        // For now we use a nonstandard way of doing these things for no good reason.
        // This will be fixed over time.
        return;
    case NSFindPanelActionSetFindString: {
        NSString *selection = [self selectedText];
        if (selection) {
            [[iTermFindPasteboard sharedInstance] setStringValue:selection];
            [[iTermFindPasteboard sharedInstance] updateObservers];
        }
        break;
    }
    }
}

- (BOOL)findInProgress {
    return _findOnPageHelper.findInProgress;
}

- (void)addSearchResult:(SearchResult *)searchResult {
    [_findOnPageHelper addSearchResult:searchResult width:[_dataSource width]];
}

- (FindContext *)findContext {
    return _findOnPageHelper.copiedContext;
}

- (BOOL)continueFind:(double *)progress {
    return [_findOnPageHelper continueFind:progress
                              context:[_dataSource findContext]
                              width:[_dataSource width]
                              numberOfLines:[_dataSource numberOfLines]
                              overflowAdjustment:[_dataSource totalScrollbackOverflow] - [_dataSource scrollbackOverflow]];
}

- (BOOL)continueFindAllResults:(NSMutableArray *)results inContext:(FindContext *)context {
    return [_dataSource continueFindAllResults:results inContext:context];
}

- (void)findOnPageSetFindString:(NSString*)aString
    forwardDirection:(BOOL)direction
    mode:(iTermFindMode)mode
    startingAtX:(int)x
    startingAtY:(int)y
    withOffset:(int)offset
    inContext:(FindContext*)context
    multipleResults:(BOOL)multipleResults {
    [_dataSource setFindString:aString
                 forwardDirection:direction
                 mode:mode
                 startingAtX:x
                 startingAtY:y
                 withOffset:offset
                 inContext:context
                 multipleResults:multipleResults];
}

- (void)selectCoordRange:(VT100GridCoordRange)range {
    [_selection clearSelection];
    VT100GridAbsCoordRange absRange = VT100GridAbsCoordRangeFromCoordRange(range, _dataSource.totalScrollbackOverflow);
    iTermSubSelection *sub =
        [iTermSubSelection subSelectionWithAbsRange:VT100GridAbsWindowedRangeMake(absRange, 0, 0)
                           mode:kiTermSelectionModeCharacter
                           width:_dataSource.width];
    [_selection addSubSelection:sub];
    [_delegate textViewDidSelectRangeForFindOnPage:range];
}

- (NSRect)frameForCoord:(VT100GridCoord)coord {
    return NSMakeRect(MAX(0, floor(coord.x * _charWidth + [iTermPreferences intForKey:kPreferenceKeySideMargins])),
                      MAX(0, coord.y * _lineHeight),
                      _charWidth,
                      _lineHeight);
}

- (void)findOnPageSelectRange:(VT100GridCoordRange)range wrapped:(BOOL)wrapped {
    [self selectCoordRange:range];
    if (!wrapped) {
        [self setNeedsDisplay:YES];
    }
}

- (void)findOnPageSaveFindContextAbsPos {
    [_dataSource saveFindContextAbsPos];
}

- (void)findOnPageDidWrapForwards:(BOOL)directionIsForwards {
    if (directionIsForwards) {
        [self beginFlash:kiTermIndicatorWrapToTop];
    } else {
        [self beginFlash:kiTermIndicatorWrapToBottom];
    }
}

- (void)findOnPageRevealRange:(VT100GridCoordRange)range {
    // Lock scrolling after finding text
    [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];

    [self _scrollToCenterLine:range.end.y];
    [self setNeedsDisplay:YES];
}

- (void)findOnPageFailed {
    [_selection clearSelection];
    [self setNeedsDisplay:YES];
}

- (long long)findOnPageOverflowAdjustment {
    return [_dataSource totalScrollbackOverflow] - [_dataSource scrollbackOverflow];
}

- (void)resetFindCursor {
    [_findOnPageHelper resetFindCursor];
}

- (void)findString:(NSString *)aString
    forwardDirection:(BOOL)direction
    mode:(iTermFindMode)mode
    withOffset:(int)offset
    scrollToFirstResult:(BOOL)scrollToFirstResult {
    [_findOnPageHelper findString:aString
                       forwardDirection:direction
                       mode:mode
                       withOffset:offset
                       context:[_dataSource findContext]
                       numberOfLines:[_dataSource numberOfLines]
                       totalScrollbackOverflow:[_dataSource totalScrollbackOverflow]
                       scrollToFirstResult:scrollToFirstResult];
}

- (void)clearHighlights:(BOOL)resetContext {
    [_findOnPageHelper clearHighlights];
    if (resetContext) {
        [_findOnPageHelper resetCopiedFindContext];
    } else {
        [_findOnPageHelper removeAllSearchResults];
    }
}

- (NSRange)findOnPageRangeOfVisibleLines {
    return NSMakeRange(_dataSource.totalScrollbackOverflow, _dataSource.numberOfLines);
}

- (void)findOnPageLocationsDidChange {
    [_delegate textViewFindOnPageLocationsDidChange];
}

- (void)findOnPageSelectedResultDidChange {
    [_delegate textViewFindOnPageSelectedResultDidChange];
}

#pragma mark - Services

- (id)validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType
{
    NSSet *acceptedReturnTypes = [NSSet setWithArray:@[ (NSString *)kUTTypeUTF8PlainText,
                                        NSPasteboardTypeString ]];
    NSSet *acceptedSendTypes = nil;
    if ([_selection hasSelection] && [_selection length] <= [_dataSource width] * 10000) {
        acceptedSendTypes = acceptedReturnTypes;
    }
    if ((sendType == nil || [acceptedSendTypes containsObject:sendType]) &&
            (returnType == nil || [acceptedReturnTypes containsObject:returnType])) {
        return self;
    } else {
        return nil;
    }
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types {
    // It is agonizingly slow to copy hundreds of thousands of lines just because the context
    // menu is opening. Services use this to get access to the clipboard contents but
    // it's lousy to hang for a few minutes for a feature that won't be used very much, esp. for
    // such large selections. In OS 10.9 this is called when opening the context menu, even though
    // it is deprecated by 10.9.
    NSString *copyString =
        [self selectedTextCappedAtSize:[iTermAdvancedSettingsModel maximumBytesToProvideToServices]];

    if (copyString && [copyString length] > 0) {
        [pboard declareTypes:@[ NSPasteboardTypeString ] owner:self];
        [pboard setString:copyString forType:NSPasteboardTypeString];
        return YES;
    }

    return NO;
}

- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard {
    NSString *string = [pboard stringForType:NSPasteboardTypeString];
    if (string.length) {
        [_delegate insertText:string];
        return YES;
    } else {
        return NO;
    }
}

#pragma mark - Miscellaneous APIs

// This textview is about to be hidden behind another tab.
- (void)aboutToHide {
    [_selectionScrollHelper mouseUp];
}

#pragma mark - Find Cursor

- (NSRect)cursorFrame {
    int lineStart = [_dataSource numberOfLines] - [_dataSource height];
    int cursorX = [_dataSource cursorX] - 1;
    int cursorY = [_dataSource cursorY] - 1;
    return NSMakeRect([iTermPreferences intForKey:kPreferenceKeySideMargins] + cursorX * _charWidth,
                      (lineStart + cursorY) * _lineHeight,
                      _charWidth,
                      _lineHeight);
}

- (CGFloat)verticalOffset {
    return self.frame.size.height - NSMaxY(self.enclosingScrollView.documentVisibleRect);
}

- (NSPoint)cursorCenterInScreenCoords {
    NSPoint cursorCenter;
    if ([self hasMarkedText]) {
        cursorCenter = _drawingHelper.imeCursorLastPos;
    } else {
        cursorCenter = [self cursorFrame].origin;
    }
    cursorCenter.x += _charWidth / 2;
    cursorCenter.y += _lineHeight / 2;
    NSPoint cursorCenterInWindowCoords = [self convertPoint:cursorCenter toView:nil];
    return  [[self window] pointToScreenCoords:cursorCenterInWindowCoords];
}

// Returns the location of the cursor relative to the origin of self.findCursorWindow.
- (NSPoint)cursorCenterInFindCursorWindowCoords {
    NSPoint centerInScreenCoords = [self cursorCenterInScreenCoords];
    return [_findCursorWindow pointFromScreenCoords:centerInScreenCoords];
}

// Returns the proper frame for self.findCursorWindow, including every screen that the
// "hole" will be in.
- (NSRect)cursorScreenFrame {
    NSRect frame = NSZeroRect;
    for (NSScreen *aScreen in [NSScreen screens]) {
        NSRect screenFrame = [aScreen frame];
        if (NSIntersectsRect([[self window] frame], screenFrame)) {
            frame = NSUnionRect(frame, screenFrame);
        }
    }
    if (NSEqualRects(frame, NSZeroRect)) {
        frame = [[self window] frame];
    }
    return frame;
}

- (void)createFindCursorWindowWithFireworks:(BOOL)forceFireworks {
    [self scrollRectToVisible:[self cursorFrame]];
    self.findCursorWindow = [[[NSWindow alloc] initWithContentRect:NSZeroRect
                                                styleMask:NSWindowStyleMaskBorderless
                                                backing:NSBackingStoreBuffered
                                                defer:YES] autorelease];
    [_findCursorWindow setLevel:NSFloatingWindowLevel];
    NSRect screenFrame = [self cursorScreenFrame];
    [_findCursorWindow setFrame:screenFrame display:YES];
    _findCursorWindow.backgroundColor = [NSColor clearColor];
    _findCursorWindow.opaque = NO;
    [_findCursorWindow makeKeyAndOrderFront:nil];

    if (forceFireworks) {
        self.findCursorView = [iTermFindCursorView newFireworksViewWithFrame:NSMakeRect(0,
                                                   0,
                                                   screenFrame.size.width,
                                                   screenFrame.size.height)];
    } else {
        self.findCursorView = [[iTermFindCursorView alloc] initWithFrame:NSMakeRect(0,
                                                           0,
                                                           screenFrame.size.width,
                                                           screenFrame.size.height)];
    }
    _findCursorView.delegate = self;
    NSPoint p = [self cursorCenterInFindCursorWindowCoords];
    _findCursorView.cursorPosition = p;
    [_findCursorWindow setContentView:_findCursorView];
}

- (void)beginFindCursor:(BOOL)hold {
    [self beginFindCursor:hold forceFireworks:NO];
}

- (void)beginFindCursor:(BOOL)hold forceFireworks:(BOOL)forceFireworks {
    _drawingHelper.cursorVisible = YES;
    [self setNeedsDisplayInRect:self.cursorFrame];
    if (!_findCursorView) {
        [self createFindCursorWindowWithFireworks:forceFireworks];
    }
    if (hold) {
        [_findCursorView startTearDownTimer];
    } else {
        [_findCursorView stopTearDownTimer];
    }
    _findCursorView.autohide = NO;
}

- (void)placeFindCursorOnAutoHide {
    _findCursorView.autohide = YES;
}

- (BOOL)isFindingCursor {
    return _findCursorView != nil;
}

- (void)findCursorViewDismiss {
    [self endFindCursor];
}

- (void)endFindCursor {
    [NSAnimationContext beginGrouping];
    NSWindow *theWindow = [_findCursorWindow retain];
    [[NSAnimationContext currentContext] setCompletionHandler:^ {
                                            [theWindow close];  // This sends release to the window
                                        }];
    [[_findCursorWindow animator] setAlphaValue:0];
    [NSAnimationContext endGrouping];

    [_findCursorView stopTearDownTimer];
    self.findCursorWindow = nil;
    _findCursorView.stopping = YES;
    self.findCursorView = nil;
}

- (void)setFindCursorView:(iTermFindCursorView *)view {
    [_findCursorView autorelease];
    _findCursorView = [view retain];
}

- (void)showFireworks {
    [self beginFindCursor:YES forceFireworks:YES];
    [self placeFindCursorOnAutoHide];
}

#pragma mark - Semantic History Delegate

- (void)semanticHistoryLaunchCoprocessWithCommand:(NSString *)command {
    [_delegate launchCoprocessWithCommand:command];
}

- (PTYFontInfo *)getFontForChar:(UniChar)ch
    isComplex:(BOOL)isComplex
    renderBold:(BOOL *)renderBold
    renderItalic:(BOOL *)renderItalic {
    return [PTYFontInfo fontForAsciiCharacter:(!isComplex && (ch < 128))
                        asciiFont:_primaryFont
                        nonAsciiFont:_secondaryFont
                        useBoldFont:_useBoldFont
                        useItalicFont:_useItalicFont
                        usesNonAsciiFont:_useNonAsciiFont
                        renderBold:renderBold
                        renderItalic:renderItalic];
}

#pragma mark - Miscellaneous Notifications

- (void)applicationDidResignActive:(NSNotification *)notification {
    DLog(@"applicationDidResignActive: reset _numTouches to 0");
    _mouseHandler.numTouches = 0;
    [self refuseFirstResponderAtCurrentMouseLocation];
}

- (void)_settingsChanged:(NSNotification *)notification {
    [self setNeedsDisplay:YES];
    _colorMap.dimOnlyText = [iTermPreferences boolForKey:kPreferenceKeyDimOnlyText];
}

#pragma mark - iTermSelectionDelegate

- (void)selectionDidChange:(iTermSelection *)selection {
    NSString *selectionString = @"";
    DLog(@"selectionDidChange to %@", selection);
    [_delegate refresh];
    if (!_selection.live && selection.hasSelection) {
        const NSInteger MAX_SELECTION_SIZE = 10 * 1000 * 1000;
        selectionString = [self selectedTextCappedAtSize:MAX_SELECTION_SIZE minimumLineNumber:0];
        [[iTermController sharedInstance] setLastSelection:
                                          selectionString.length < MAX_SELECTION_SIZE ? selectionString : nil];
    }
    [_delegate textViewSelectionDidChangeToTruncatedString:selectionString];
    DLog(@"Selection did change: selection=%@. stack=%@",
         selection, [NSThread callStackSymbols]);
}

- (VT100GridRange)selectionRangeOfTerminalNullsOnAbsoluteLine:(long long)absLineNumber {
    const long long lineNumber = absLineNumber - _dataSource.totalScrollbackOverflow;
    if (lineNumber < 0 || lineNumber > INT_MAX) {
        return VT100GridRangeMake(0, 0);
    }

    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    int length = [extractor lengthOfLine:lineNumber];
    int width = [_dataSource width];
    return VT100GridRangeMake(length, width - length);
}

- (VT100GridAbsWindowedRange)selectionAbsRangeForParentheticalAt:(VT100GridAbsCoord)absCoord {
    BOOL ok;
    const VT100GridCoord coord = VT100GridCoordFromAbsCoord(absCoord, _dataSource.totalScrollbackOverflow, &ok);
    if (!ok) {
        const long long totalScrollbackOverflow = _dataSource.totalScrollbackOverflow;
        return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, totalScrollbackOverflow, 0, totalScrollbackOverflow), -1, -1);
    }
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    [extractor restrictToLogicalWindowIncludingCoord:coord];
    const VT100GridWindowedRange relative = [extractor rangeOfParentheticalSubstringAtLocation:coord];
    return VT100GridAbsWindowedRangeFromWindowedRange(relative, _dataSource.totalScrollbackOverflow);
}

- (VT100GridAbsWindowedRange)selectionAbsRangeForWordAt:(VT100GridAbsCoord)absCoord {
    BOOL ok;
    const VT100GridCoord coord = VT100GridCoordFromAbsCoord(absCoord, _dataSource.totalScrollbackOverflow, &ok);
    const long long totalScrollbackOverflow = _dataSource.totalScrollbackOverflow;
    if (!ok) {
        return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, totalScrollbackOverflow, 0, totalScrollbackOverflow), -1, -1);
    }
    VT100GridWindowedRange range;
    [self getWordForX:coord.x
          y:coord.y
          range:&range
          respectDividers:[self liveSelectionRespectsSoftBoundaries]];
    return VT100GridAbsWindowedRangeFromWindowedRange(range, totalScrollbackOverflow);
}

- (VT100GridAbsWindowedRange)selectionAbsRangeForSmartSelectionAt:(VT100GridAbsCoord)absCoord {
    VT100GridAbsWindowedRange absRange;
    [_urlActionHelper smartSelectAtAbsoluteCoord:absCoord
                      to:&absRange
                      ignoringNewlines:NO
                      actionRequired:NO
                      respectDividers:[self liveSelectionRespectsSoftBoundaries]];
    return absRange;
}

- (VT100GridAbsWindowedRange)selectionAbsRangeForWrappedLineAt:(VT100GridAbsCoord)absCoord {
    __block VT100GridWindowedRange relativeRange = { 0 };
    const BOOL ok =
    [self withRelativeCoord:absCoord block:^(VT100GridCoord coord) {
             iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
        if ([self liveSelectionRespectsSoftBoundaries]) {
            [extractor restrictToLogicalWindowIncludingCoord:coord];
        }
        relativeRange = [extractor rangeForWrappedLineEncompassing:coord
                                   respectContinuations:NO
                                   maxChars:-1];
    }];
    const long long totalScrollbackOverflow = _dataSource.totalScrollbackOverflow;
    if (!ok) {
        return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, totalScrollbackOverflow, 0, totalScrollbackOverflow), -1, -1);
    }
    return VT100GridAbsWindowedRangeFromWindowedRange(relativeRange, totalScrollbackOverflow);
}

- (int)selectionViewportWidth {
    return [_dataSource width];
}

- (VT100GridAbsWindowedRange)selectionAbsRangeForLineAt:(VT100GridAbsCoord)absCoord {
    __block VT100GridAbsWindowedRange result = { 0 };
    const long long totalScrollbackOverflow = _dataSource.totalScrollbackOverflow;
    const BOOL ok =
    [self withRelativeCoord:absCoord block:^(VT100GridCoord coord) {
             if (![self liveSelectionRespectsSoftBoundaries]) {
                 result = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0,
                                                   absCoord.y,
                                                   [_dataSource width],
                                                   absCoord.y),
                                                   0, 0);
                 return;
             }
        iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
        [extractor restrictToLogicalWindowIncludingCoord:coord];
        result = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(extractor.logicalWindow.location,
                                               absCoord.y,
                                               VT100GridRangeMax(extractor.logicalWindow) + 1,
                                               absCoord.y),
                                               extractor.logicalWindow.location,
                                               extractor.logicalWindow.length);
    }];
    if (!ok) {
        return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, totalScrollbackOverflow, 0, totalScrollbackOverflow), -1, -1);
    }
    return result;
}

- (VT100GridAbsCoord)selectionPredecessorOfAbsCoord:(VT100GridAbsCoord)absCoord {
    __block VT100GridAbsCoord result = { 0 };
    const long long totalScrollbackOverflow = _dataSource.totalScrollbackOverflow;
    const BOOL ok =
    [self withRelativeCoord:absCoord block:^(VT100GridCoord relativeCoord) {
             VT100GridCoord coord = relativeCoord;
             screen_char_t *theLine;
             do {
                 coord.x--;
                 if (coord.x < 0) {
                coord.x = [_dataSource width] - 1;
                coord.y--;
                if (coord.y < 0) {
                    coord.x = coord.y = 0;
                    break;
                }
            }

            theLine = [_dataSource getLineAtIndex:coord.y];
        } while (theLine[coord.x].code == DWC_RIGHT);
        result = VT100GridAbsCoordFromCoord(coord, totalScrollbackOverflow);
    }];
    if (!ok) {
        return VT100GridAbsCoordMake(0, totalScrollbackOverflow);
    }
    return result;
}

- (long long)selectionTotalScrollbackOverflow {
    return _dataSource.totalScrollbackOverflow;
}

- (NSIndexSet *)selectionIndexesOnAbsoluteLine:(long long)absLine
    containingCharacter:(unichar)c
    inRange:(NSRange)range {
    const long long totalScrollbackOverflow = _dataSource.totalScrollbackOverflow;
    if (absLine < totalScrollbackOverflow || absLine - totalScrollbackOverflow > INT_MAX) {
        return nil;
    }
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    return [extractor indexesOnLine:absLine - totalScrollbackOverflow
                      containingCharacter:c
                      inRange:range];
}

#pragma mark - iTermColorMapDelegate

- (void)colorMap:(iTermColorMap *)colorMap didChangeColorForKey:(iTermColorMapKey)theKey {
    if (theKey == kColorMapBackground) {
        [self updateScrollerForBackgroundColor];
        [[self enclosingScrollView] setBackgroundColor:[colorMap colorForKey:theKey]];
        [self recomputeBadgeLabel];
        [_delegate textViewBackgroundColorDidChange];
        [_delegate textViewProcessedBackgroundColorDidChange];
    } else if (theKey == kColorMapForeground) {
        [self recomputeBadgeLabel];
    } else if (theKey == kColorMapSelection) {
        _drawingHelper.unfocusedSelectionColor = [[_colorMap colorForKey:theKey] colorDimmedBy:2.0/3.0
                                               towardsGrayLevel:0.5];
    }
    [self setNeedsDisplay:YES];
}

- (void)colorMap:(iTermColorMap *)colorMap
    dimmingAmountDidChangeTo:(double)dimmingAmount {
    [_delegate textViewProcessedBackgroundColorDidChange];
    [[self superview] setNeedsDisplay:YES];
}

- (void)colorMap:(iTermColorMap *)colorMap
    mutingAmountDidChangeTo:(double)mutingAmount {
    [_delegate textViewProcessedBackgroundColorDidChange];
    [[self superview] setNeedsDisplay:YES];
}

#pragma mark - iTermIndicatorsHelperDelegate

- (NSColor *)indicatorFullScreenFlashColor {
    return [self defaultTextColor];
}

#pragma mark - Mouse reporting

- (NSRect)liveRect {
    int numLines = [_dataSource numberOfLines];
    NSRect rect;
    int height = [_dataSource height];
    rect.origin.y = numLines - height;
    rect.origin.y *= _lineHeight;
    rect.origin.x = [iTermPreferences intForKey:kPreferenceKeySideMargins];
    rect.size.width = _charWidth * [_dataSource width];
    rect.size.height = _lineHeight * [_dataSource height];
    return rect;
}

- (NSPoint)pointForEvent:(NSEvent *)event {
    return [self convertPoint:[event locationInWindow] fromView:nil];
}

#pragma mark - Selection Scroll

- (void)selectionScrollWillStart {
    PTYScroller *scroller = (PTYScroller *)self.enclosingScrollView.verticalScroller;
    scroller.userScroll = YES;
    [_mouseHandler selectionScrollWillStart];
}

#pragma mark - Color

- (NSColor*)colorForCode:(int)theIndex
    green:(int)green
    blue:(int)blue
    colorMode:(ColorMode)theMode
    bold:(BOOL)isBold
    faint:(BOOL)isFaint
    isBackground:(BOOL)isBackground {
    iTermColorMapKey key = [self colorMapKeyForCode:theIndex
                                 green:green
                                 blue:blue
                                 colorMode:theMode
                                 bold:isBold
                                 isBackground:isBackground];
    NSColor *color;
    iTermColorMap *colorMap = self.colorMap;
    if (isBackground) {
        color = [colorMap colorForKey:key];
    } else {
        color = [self.colorMap colorForKey:key];
        if (isFaint) {
            color = [color colorWithAlphaComponent:0.5];
        }
    }
    return color;
}

- (BOOL)charBlinks:(screen_char_t)sct {
    return self.blinkAllowed && sct.blink;
}

- (iTermColorMapKey)colorMapKeyForCode:(int)theIndex
    green:(int)green
    blue:(int)blue
    colorMode:(ColorMode)theMode
    bold:(BOOL)isBold
    isBackground:(BOOL)isBackground {
    BOOL isBackgroundForDefault = isBackground;
    switch (theMode) {
    case ColorModeAlternate:
        switch (theIndex) {
        case ALTSEM_SELECTED:
            if (isBackground) {
                return kColorMapSelection;
            } else {
                return kColorMapSelectedText;
            }
        case ALTSEM_CURSOR:
            if (isBackground) {
                return kColorMapCursor;
            } else {
                return kColorMapCursorText;
            }
        case ALTSEM_SYSTEM_MESSAGE:
            return [_colorMap keyForSystemMessageForBackground:isBackground];
        case ALTSEM_REVERSED_DEFAULT:
            isBackgroundForDefault = !isBackgroundForDefault;
        // Fall through.
        case ALTSEM_DEFAULT:
            if (isBackgroundForDefault) {
                return kColorMapBackground;
            } else {
                if (isBold && self.useCustomBoldColor) {
                    return kColorMapBold;
                } else {
                    return kColorMapForeground;
                }
            }
        }
        break;
    case ColorMode24bit:
        return [iTermColorMap keyFor8bitRed:theIndex green:green blue:blue];
    case ColorModeNormal:
        // Render bold text as bright. The spec (ECMA-48) describes the intense
        // display setting (esc[1m) as "bold or bright". We make it a
        // preference.
        if (isBold &&
                self.brightenBold &&
                (theIndex < 8) &&
                !isBackground) { // Only colors 0-7 can be made "bright".
            theIndex |= 8;  // set "bright" bit.
        }
        return kColorMap8bitBase + (theIndex & 0xff);

    case ColorModeInvalid:
        return kColorMapInvalid;
    }
    ITAssertWithMessage(ok, @"Bogus color mode %d", (int)theMode);
    return kColorMapInvalid;
}

#pragma mark - iTermTextDrawingHelperDelegate

- (void)drawingHelperDrawBackgroundImageInRect:(NSRect)rect
    blendDefaultBackground:(BOOL)blend {
    [_delegate textViewDrawBackgroundImageInView:self viewRect:rect blendDefaultBackground:blend];
}

- (VT100ScreenMark *)drawingHelperMarkOnLine:(int)line {
    return [_dataSource markOnLine:line];
}

- (screen_char_t *)drawingHelperLineAtIndex:(int)line {
    return [_dataSource getLineAtIndex:line];
}

- (screen_char_t *)drawingHelperLineAtScreenIndex:(int)line {
    return [_dataSource getLineAtScreenIndex:line];
}

- (screen_char_t *)drawingHelperCopyLineAtIndex:(int)line toBuffer:(screen_char_t *)buffer {
    return [_dataSource getLineAtIndex:line withBuffer:buffer];
}

- (iTermTextExtractor *)drawingHelperTextExtractor {
    return [[[iTermTextExtractor alloc] initWithDataSource:_dataSource] autorelease];
}

- (NSArray *)drawingHelperCharactersWithNotesOnLine:(int)line {
    return [_dataSource charactersWithNotesOnLine:line];
}

- (void)drawingHelperUpdateFindCursorView {
    if ([self isFindingCursor]) {
        NSPoint cp = [self cursorCenterInFindCursorWindowCoords];
        if (!NSEqualPoints(_findCursorView.cursorPosition, cp)) {
            _findCursorView.cursorPosition = cp;
            [_findCursorView setNeedsDisplay:YES];
        }
    }
}

- (NSDate *)drawingHelperTimestampForLine:(int)line {
    return [self.dataSource timestampForLine:line];
}

- (NSColor *)drawingHelperColorForCode:(int)theIndex
    green:(int)green
    blue:(int)blue
    colorMode:(ColorMode)theMode
    bold:(BOOL)isBold
    faint:(BOOL)isFaint
    isBackground:(BOOL)isBackground {
    return [self colorForCode:theIndex
                 green:green
                 blue:blue
                 colorMode:theMode
                 bold:isBold
                 faint:isFaint
                 isBackground:isBackground];
}

- (PTYFontInfo *)drawingHelperFontForChar:(UniChar)ch
    isComplex:(BOOL)isComplex
    renderBold:(BOOL *)renderBold
    renderItalic:(BOOL *)renderItalic {
    return [self getFontForChar:ch
                 isComplex:isComplex
                 renderBold:renderBold
                 renderItalic:renderItalic];
}

- (NSData *)drawingHelperMatchesOnLine:(int)line {
    return _findOnPageHelper.highlightMap[@(line + _dataSource.totalScrollbackOverflow)];
}

- (void)drawingHelperDidFindRunOfAnimatedCellsStartingAt:(VT100GridCoord)coord
    ofLength:(int)length {
    [_dataSource setRangeOfCharsAnimated:NSMakeRange(coord.x, length) onLine:coord.y];
}

- (NSString *)drawingHelperLabelForDropTargetOnLine:(int)line {
    SCPPath *scpFile = [_dataSource scpPathForFile:@"" onLine:line];
    if (!scpFile) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@@%@:%@", scpFile.username, scpFile.hostname, scpFile.path];
}

#pragma mark - Accessibility

// See WebCore's FrameSelectionMac.mm for the inspiration.
- (CGRect)accessibilityConvertScreenRect:(CGRect)bounds {
    NSArray *screens = [NSScreen screens];
    if ([screens count]) {
        CGFloat screenHeight = NSHeight([(NSScreen *)[screens objectAtIndex:0] frame]);
        NSRect rect = bounds;
        rect.origin.y = (screenHeight - (bounds.origin.y + bounds.size.height));
        return rect;
    }
    return CGRectZero;
}

- (BOOL)isAccessibilityElement {
    return YES;
}

- (NSInteger)accessibilityLineForIndex:(NSInteger)index {
    const NSInteger line = [_accessibilityHelper lineForIndex:index];
    DLog(@"Line for index %@ is %@", @(index), @(line));
    return line;
}

- (NSRange)accessibilityRangeForLine:(NSInteger)line {
    const NSRange range = [_accessibilityHelper rangeForLine:line];
    DLog(@"Range for line %@ is %@", @(line), NSStringFromRange(range));
    return range;
}

- (NSString *)accessibilityStringForRange:(NSRange)range {
    NSString *const string = [_accessibilityHelper stringForRange:range];
    DLog(@"string for range %@ is %@", NSStringFromRange(range), string);
    return string;
}

- (NSRange)accessibilityRangeForPosition:(NSPoint)point {
    const NSRange range = [_accessibilityHelper rangeForPosition:point];
    DLog(@"Range for position %@ is %@", NSStringFromPoint(point), NSStringFromRange(range));
    return range;
}

- (NSRange)accessibilityRangeForIndex:(NSInteger)index {
    const NSRange range = [_accessibilityHelper rangeOfIndex:index];
    DLog(@"Range for index %@ is %@", @(index), NSStringFromRange(range));
    return range;
}

- (NSRect)accessibilityFrameForRange:(NSRange)range {
    const NSRect frame = [_accessibilityHelper boundsForRange:range];
    DLog(@"Frame for range %@ is %@", NSStringFromRange(range), NSStringFromRect(frame));
    return frame;
}

- (NSAttributedString *)accessibilityAttributedStringForRange:(NSRange)range {
    NSAttributedString *string = [_accessibilityHelper attributedStringForRange:range];
    DLog(@"Attributed string for range %@ is %@", NSStringFromRange(range), string);
    return string;
}

- (NSAccessibilityRole)accessibilityRole {
    const NSAccessibilityRole role = [_accessibilityHelper role];
    DLog(@"accessibility role is %@", role);
    return role;
}

- (NSString *)accessibilityRoleDescription {
    NSString *const description = [_accessibilityHelper roleDescription];
    DLog(@"Acccessibility description is %@", description);
    return description;
}

- (NSString *)accessibilityHelp {
    NSString *help = [_accessibilityHelper help];
    DLog(@"accessibility help is %@", help);
    return help;
}

- (BOOL)isAccessibilityFocused {
    const BOOL focused = [_accessibilityHelper focused];
    DLog(@"focused is %@", @(focused));
    return focused;
}

- (NSString *)accessibilityLabel {
    NSString *const label = [_accessibilityHelper label];
    DLog(@"label is %@", label);
    return label;
}

- (id)accessibilityValue {
    id value = [_accessibilityHelper allText];
    DLog(@"value is %@", value);
    return value;
}

- (NSInteger)accessibilityNumberOfCharacters {
    const NSInteger number = [_accessibilityHelper numberOfCharacters];
    DLog(@"Number of characters is %@", @(number));
    return number;
}

- (NSString *)accessibilitySelectedText {
    NSString *selected = [_accessibilityHelper selectedText];
    DLog(@"selected text is %@", selected);
    return selected;
}

- (NSRange)accessibilitySelectedTextRange {
    const NSRange range = [_accessibilityHelper selectedTextRange];
    DLog(@"selected text range is %@", NSStringFromRange(range));
    return range;
}

- (NSArray<NSValue *> *)accessibilitySelectedTextRanges {
    NSArray<NSValue *> *ranges = [_accessibilityHelper selectedTextRanges];
    DLog(@"ranges are %@", [[ranges mapWithBlock:^id(NSValue *anObject) {
        return NSStringFromRange([anObject rangeValue]);
    }] componentsJoinedByString:@", "]);
    return ranges;
}

- (NSInteger)accessibilityInsertionPointLineNumber {
    const NSInteger line = [_accessibilityHelper insertionPointLineNumber];
    DLog(@"insertion point line number is %@", @(line));
    return line;
}

- (NSRange)accessibilityVisibleCharacterRange {
    const NSRange range = [_accessibilityHelper visibleCharacterRange];
    DLog(@"visible range is %@", NSStringFromRange(range));
    return range;
}

- (NSString *)accessibilityDocument {
    NSString *const doc = [[_accessibilityHelper currentDocumentURL] absoluteString];
    DLog(@"document is %@", doc);
    return doc;
}

- (void)setAccessibilitySelectedTextRange:(NSRange)accessibilitySelectedTextRange {
    [_accessibilityHelper setSelectedTextRange:accessibilitySelectedTextRange];
}

#pragma mark - Accessibility Helper Delegate

- (int)accessibilityHelperAccessibilityLineNumberForLineNumber:(int)actualLineNumber {
    int numberOfLines = [_dataSource numberOfLines];
    int offset = MAX(0, numberOfLines - [iTermAdvancedSettingsModel numberOfLinesForAccessibility]);
    return actualLineNumber - offset;
}

- (int)accessibilityHelperLineNumberForAccessibilityLineNumber:(int)accessibilityLineNumber {
    int numberOfLines = [_dataSource numberOfLines];
    int offset = MAX(0, numberOfLines - [iTermAdvancedSettingsModel numberOfLinesForAccessibility]);
    return accessibilityLineNumber + offset;
}

- (VT100GridCoord)accessibilityHelperCoordForPoint:(NSPoint)screenPosition {
    NSRect screenRect = NSMakeRect(screenPosition.x,
                                   screenPosition.y,
                                   0,
                                   0);
    NSRect windowRect = [self.window convertRectFromScreen:screenRect];
    NSPoint locationInTextView = [self convertPoint:windowRect.origin fromView:nil];
    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    int x = (locationInTextView.x - [iTermPreferences intForKey:kPreferenceKeySideMargins] - visibleRect.origin.x) / _charWidth;
    int y = locationInTextView.y / _lineHeight;
    return VT100GridCoordMake(x, [self accessibilityHelperAccessibilityLineNumberForLineNumber:y]);
}

- (NSRect)accessibilityHelperFrameForCoordRange:(VT100GridCoordRange)coordRange {
    coordRange.start.y = [self accessibilityHelperLineNumberForAccessibilityLineNumber:coordRange.start.y];
    coordRange.end.y = [self accessibilityHelperLineNumberForAccessibilityLineNumber:coordRange.end.y];
    NSRect result = NSMakeRect(MAX(0, floor(coordRange.start.x * _charWidth + [iTermPreferences intForKey:kPreferenceKeySideMargins])),
                               MAX(0, coordRange.start.y * _lineHeight),
                               MAX(0, (coordRange.end.x - coordRange.start.x) * _charWidth),
                               MAX(0, (coordRange.end.y - coordRange.start.y + 1) * _lineHeight));
    result = [self convertRect:result toView:nil];
    result = [self.window convertRectToScreen:result];
    return result;
}

- (VT100GridCoord)accessibilityHelperCursorCoord {
    int y = [_dataSource numberOfLines] - [_dataSource height] + [_dataSource cursorY] - 1;
    return VT100GridCoordMake([_dataSource cursorX] - 1,
                              [self accessibilityHelperAccessibilityLineNumberForLineNumber:y]);
}

- (void)accessibilityHelperSetSelectedRange:(VT100GridCoordRange)coordRange {
    coordRange.start.y =
        [self accessibilityHelperLineNumberForAccessibilityLineNumber:coordRange.start.y];
    coordRange.end.y =
        [self accessibilityHelperLineNumberForAccessibilityLineNumber:coordRange.end.y];
    [_selection clearSelection];
    const long long overflow = _dataSource.totalScrollbackOverflow;
    [_selection beginSelectionAtAbsCoord:VT100GridAbsCoordFromCoord(coordRange.start, overflow)
                mode:kiTermSelectionModeCharacter
                resume:NO
                append:NO];
    [_selection moveSelectionEndpointTo:VT100GridAbsCoordFromCoord(coordRange.end, overflow)];
    [_selection endLiveSelection];
}

- (VT100GridCoordRange)accessibilityRangeOfCursor {
    VT100GridCoord coord = [self accessibilityHelperCursorCoord];
    return VT100GridCoordRangeMake(coord.x, coord.y, coord.x, coord.y);
}

- (VT100GridCoordRange)accessibilityHelperSelectedRange {
    iTermSubSelection *sub = _selection.allSubSelections.lastObject;

    if (!sub) {
        return [self accessibilityRangeOfCursor];
    }
    __block VT100GridCoordRange coordRange = [self accessibilityRangeOfCursor];
    [self withRelativeCoordRange:sub.absRange.coordRange block:^(VT100GridCoordRange initialCoordRange) {
             coordRange = initialCoordRange;
             int minY = _dataSource.numberOfLines - _dataSource.height;
             if (coordRange.start.y < minY) {
            coordRange.start.y = 0;
            coordRange.start.x = 0;
        } else {
            coordRange.start.y -= minY;
        }
        if (coordRange.end.y < minY) {
            coordRange = [self accessibilityRangeOfCursor];
        } else {
            coordRange.end.y -= minY;
        }
    }];
    return coordRange;
}

- (NSString *)accessibilityHelperSelectedText {
    return [self selectedTextWithStyle:iTermCopyTextStylePlainText
                 cappedAtSize:0
                 minimumLineNumber:[self accessibilityHelperLineNumberForAccessibilityLineNumber:0]];
}

- (NSURL *)accessibilityHelperCurrentDocumentURL {
    return [_delegate textViewCurrentLocation];
}

- (screen_char_t *)accessibilityHelperLineAtIndex:(int)accessibilityIndex {
    return [_dataSource getLineAtIndex:[self accessibilityHelperLineNumberForAccessibilityLineNumber:accessibilityIndex]];
}

- (int)accessibilityHelperWidth {
    return [_dataSource width];
}

- (int)accessibilityHelperNumberOfLines {
    return MIN([iTermAdvancedSettingsModel numberOfLinesForAccessibility],
               [_dataSource numberOfLines]);
}

#pragma mark - NSPopoverDelegate

- (void)popoverDidClose:(NSNotification *)notification {
    NSPopover *popover = notification.object;
    iTermWebViewWrapperViewController *viewController = (iTermWebViewWrapperViewController *)popover.contentViewController;
    [viewController terminateWebView];

}

#pragma mark - iTermKeyboardHandlerDelegate

- (BOOL)keyboardHandler:(iTermKeyboardHandler *)keyboardhandler
    shouldHandleKeyDown:(NSEvent *)event {
    if (![_delegate textViewShouldAcceptKeyDownEvent:event]) {
        return NO;
    }
    if (!_selection.live && [iTermAdvancedSettingsModel typingClearsSelection]) {
        // Remove selection when you type, unless the selection is live because it's handy to be
        // able to scroll up, click, hit a key, and then drag to select to (near) the end. See
        // issue 3340.
        [self deselect];
    }
    // Generally, find-on-page continues from the last result. If you press a
    // key then it starts searching from the bottom again.
    [_findOnPageHelper resetFindCursor];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^ {
        iTermApplicationDelegate *appDelegate = [iTermApplication.sharedApplication delegate];
        [appDelegate userDidInteractWithASession];
    });
    if ([_delegate isPasting]) {
        [_delegate queueKeyDown:event];
        return NO;
    }
    if ([_delegate textViewDelegateHandlesAllKeystrokes]) {
        DLog(@"PTYTextView keyDown: in instant replay, send to delegate");
        // Delegate has special handling for this case.
        [_delegate keyDown:event];
        return NO;
    }

    return YES;
}

- (void)keyboardHandler:(iTermKeyboardHandler *)keyboardhandler
    loadContext:(iTermKeyboardHandlerContext *)context
    forEvent:(NSEvent *)event {
    context->hasActionableKeyMapping = [_delegate hasActionableKeyMappingForEvent:event];
    context->leftOptionKey = [_delegate optionKey];
    context->rightOptionKey = [_delegate rightOptionKey];
    context->autorepeatMode = [[_dataSource terminal] autorepeatMode];
}

- (void)keyboardHandler:(iTermKeyboardHandler *)keyboardhandler
    interpretKeyEvents:(NSArray<NSEvent *> *)events {
    [self interpretKeyEvents:events];
}

- (void)keyboardHandler:(iTermKeyboardHandler *)keyboardhandler
    sendEventToController:(NSEvent *)event {
    [self.delegate keyDown:event];
}

- (NSRange)keyboardHandlerMarkedTextRange:(iTermKeyboardHandler *)keyboardhandler {
    return _drawingHelper.inputMethodMarkedRange;
}

- (void)keyboardHandler:(iTermKeyboardHandler *)keyboardhandler
    insertText:(NSString *)aString {
    if ([self hasMarkedText]) {
        DLog(@"insertText: clear marked text");
        [self invalidateInputMethodEditorRect];
        _drawingHelper.inputMethodMarkedRange = NSMakeRange(0, 0);
        _drawingHelper.markedText = nil;
        _drawingHelper.numberOfIMELines = 0;
    }

    if (![_selection hasSelection]) {
        [self resetFindCursor];
    }

    if ([aString length] > 0) {
        if ([_delegate respondsToSelector:@selector(insertText:)]) {
            [_delegate insertText:aString];
        } else {
            [super insertText:aString];
        }
    }
    if ([self hasMarkedText]) {
        // In case imeOffset changed, the frame height must adjust.
        [_delegate refresh];
    }
}

#pragma mark - iTermBadgeLabelDelegate

- (NSSize)badgeLabelSizeFraction {
    return [self.delegate badgeLabelSizeFraction];
}

- (NSFont *)badgeLabelFontOfSize:(CGFloat)pointSize {
    return [self.delegate badgeLabelFontOfSize:pointSize];
}

@end

@implementation PTYTextView(MouseHandler)

- (BOOL)mouseHandlerViewHasFocus:(PTYMouseHandler *)handler {
    return [[iTermController sharedInstance] frontTextView] == self;
}

- (void)mouseHandlerMakeKeyAndOrderFrontAndMakeFirstResponderAndActivateApp:(PTYMouseHandler *)sender {
    [[self window] makeKeyAndOrderFront:nil];
    [[self window] makeFirstResponder:self];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)mouseHandlerMakeFirstResponder:(PTYMouseHandler *)handler {
    [[self window] makeFirstResponder:self];
}

- (void)mouseHandlerWillBeginDragPane:(PTYMouseHandler *)handler {
    [_delegate textViewBeginDrag];
}

- (BOOL)mouseHandlerIsInKeyWindow:(PTYMouseHandler *)handler {
    return ([NSApp keyWindow] == [self window]);
}

- (VT100GridCoord)mouseHandler:(PTYMouseHandler *)handler
    clickPoint:(NSEvent *)event
    allowOverflow:(BOOL)allowRightMarginOverflow {
    const NSPoint temp =
        [self clickPoint:event allowRightMarginOverflow:allowRightMarginOverflow];
    return VT100GridCoordMake(temp.x, temp.y);
}

- (BOOL)mouseHandler:(PTYMouseHandler *)handler
    coordIsMutable:(VT100GridCoord)coord {
    return [self coordinateIsInMutableArea:coord];
}

- (MouseMode)mouseHandlerMouseMode:(PTYMouseHandler *)handler {
    return _dataSource.terminal.mouseMode;
}

- (void)mouseHandlerDidSingleClick:(PTYMouseHandler *)handler {
    for (NSView *view in [self subviews]) {
        if ([view isKindOfClass:[PTYNoteView class]]) {
            PTYNoteView *noteView = (PTYNoteView *)view;
            [noteView.delegate.noteViewController setNoteHidden:YES];
        }
    }
}

- (iTermSelection *)mouseHandlerCurrentSelection:(PTYMouseHandler *)handler {
    return _selection;
}

- (iTermImageInfo *)mouseHandler:(PTYMouseHandler *)handler imageAt:(VT100GridCoord)coord {
    return [self imageInfoAtCoord:coord];
}

- (BOOL)mouseHandlerReportingAllowed:(PTYMouseHandler *)handler {
    return [self.delegate xtermMouseReporting];
}

- (void)mouseHandlerLockScrolling:(PTYMouseHandler *)handler {
    // Lock auto scrolling while the user is selecting text, but not for a first-mouse event
    // because drags are ignored for those.
    [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];
}

- (void)mouseHandlerDidMutateState:(PTYMouseHandler *)handler {
    [_delegate refresh];
}

- (void)mouseHandlerDidInferScrollingIntent:(PTYMouseHandler *)handler trying:(BOOL)trying {
    [_delegate textViewThinksUserIsTryingToSendArrowKeysWithScrollWheel:trying];
}

- (void)mouseHandlerOpenTargetWithEvent:(NSEvent *)event
    inBackground:(BOOL)inBackground {
    [_urlActionHelper openTargetWithEvent:event inBackground:inBackground];
}

- (BOOL)mouseHandlerIsScrolledToBottom:(PTYMouseHandler *)handler {
    return (([self visibleRect].origin.y + [self visibleRect].size.height - [self excess]) / _lineHeight ==
            [_dataSource numberOfLines]);
}

- (void)mouseHandlerUnlockScrolling:(PTYMouseHandler *)handler {
    [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:NO];
}

- (VT100GridCoord)mouseHandlerCoordForPointInWindow:(NSPoint)point {
    return [self coordForPointInWindow:point];
}

- (VT100GridCoord)mouseHandlerCoordForPointInView:(NSPoint)point {
    NSRect liveRect = [self liveRect];
    VT100GridCoord coord = VT100GridCoordMake((point.x - liveRect.origin.x) / _charWidth,
                           (point.y - liveRect.origin.y) / _lineHeight);
    coord.x = MAX(0, coord.x);
    coord.y = MAX(0, coord.y);
    return coord;
}

- (BOOL)mouseHandler:(PTYMouseHandler *)handler viewCoordIsReportable:(NSPoint)point {
    const NSRect liveRect = [self liveRect];
    return NSPointInRect(point, liveRect);
}

- (void)mouseHandlerMoveCursorToCoord:(VT100GridCoord)coord
    forEvent:(NSEvent *)event {
    BOOL verticalOk;
    if ([_delegate textViewShouldPlaceCursorAt:coord verticalOk:&verticalOk]) {
        [self placeCursorOnCurrentLineWithEvent:event verticalOk:verticalOk];
    }
}

- (void)mouseHandlerSetFindOnPageCursorCoord:(VT100GridCoord)clickPoint {
    VT100GridAbsCoord absCoord =
        VT100GridAbsCoordMake(clickPoint.x,
                              [_dataSource totalScrollbackOverflow] + clickPoint.y);
    [_findOnPageHelper setStartPoint:absCoord];
}

- (BOOL)mouseHandlerAtPasswordPrompt:(PTYMouseHandler *)handler {
    return _delegate.textViewPasswordInput;
}

- (VT100GridCoord)mouseHandlerCursorCoord:(PTYMouseHandler *)handler {
    return VT100GridCoordMake([_dataSource cursorX] - 1,
                              [_dataSource numberOfLines] - [_dataSource height] + [_dataSource cursorY] - 1);
}

- (void)mouseHandlerOpenPasswordManager:(PTYMouseHandler *)handler {
    [_delegate textViewDidSelectPasswordPrompt];
}

- (BOOL)mouseHandler:(PTYMouseHandler *)handler
    getFindOnPageCursor:(VT100GridCoord *)coord {
    if (!_findOnPageHelper.haveFindCursor) {
        return NO;
    }
    const VT100GridAbsCoord findOnPageCursor = [_findOnPageHelper findCursorAbsCoord];
    *coord = VT100GridCoordMake(findOnPageCursor.x,
                                findOnPageCursor.y -
                                [_dataSource totalScrollbackOverflow]);
    return YES;
}

- (void)mouseHandlerResetFindOnPageCursor:(PTYMouseHandler *)handler {
    [_findOnPageHelper resetFindCursor];
}

- (BOOL)mouseHandlerIsValid:(PTYMouseHandler *)handler {
    return _delegate != nil;
}

- (void)mouseHandlerCopy:(PTYMouseHandler *)handler {
    [self copySelectionAccordingToUserPreferences];
}

- (NSPoint)mouseHandler:(PTYMouseHandler *)handler
    viewCoordForEvent:(NSEvent *)event
    clipped:(BOOL)clipped {
    if (!clipped) {
        return [self pointForEvent:event];
    }
    return [self locationInTextViewFromEvent:event];
}

- (void)mouseHandler:(PTYMouseHandler *)handler sendFakeOtherMouseUp:(NSEvent *)event {
    [self otherMouseUp:event];
}

- (BOOL)mouseHandler:(PTYMouseHandler *)handler
    reportMouseEvent:(NSEventType)eventType
    modifiers:(NSUInteger)modifiers
    button:(MouseButtonNumber)button
    coordinate:(VT100GridCoord)coord
    event:(NSEvent *)event
    deltaY:(CGFloat)deltaY
    allowDragBeforeMouseDown:(BOOL)allowDragBeforeMouseDown
    testOnly:(BOOL)testOnly {
    return [_delegate textViewReportMouseEvent:eventType
                      modifiers:modifiers
                      button:button
                      coordinate:coord
                      deltaY:deltaY
                      allowDragBeforeMouseDown:allowDragBeforeMouseDown
                      testOnly:testOnly];
}

- (BOOL)mouseHandlerViewIsFirstResponder:(PTYMouseHandler *)mouseHandler {
    return self.window.firstResponder == self;
}

- (BOOL)mouseHandlerShouldReportClicksAndDrags:(PTYMouseHandler *)mouseHandler {
    return [[self delegate] xtermMouseReportingAllowClicksAndDrags];
}

- (BOOL)mouseHandlerShouldReportScroll:(PTYMouseHandler *)mouseHandler {
    return [[self delegate] xtermMouseReportingAllowMouseWheel];
}

- (void)mouseHandlerJiggle:(PTYMouseHandler *)mouseHandler {
    [self scrollLineUp:nil];
    [self scrollLineDown:nil];
}

- (CGFloat)mouseHandler:(PTYMouseHandler *)mouseHandler accumulateVerticalScrollFromEvent:(NSEvent *)event {
    PTYScrollView *scrollView = (PTYScrollView *)self.enclosingScrollView;
    return [scrollView accumulateVerticalScrollFromEvent:event];
}

- (void)mouseHandler:(PTYMouseHandler *)handler
    sendString:(NSString *)stringToSend
    latin1:(BOOL)forceLatin1 {
    if (forceLatin1) {
        [_delegate writeStringWithLatin1Encoding:stringToSend];
    } else {
        [_delegate writeTask:stringToSend];
    }
}

- (void)mouseHandlerRemoveSelection:(PTYMouseHandler *)mouseHandler {
    [self deselect];
}

- (BOOL)mouseHandler:(PTYMouseHandler *)mouseHandler moveSelectionToPointInEvent:(NSEvent *)event {
    const NSPoint locationInTextView = [self locationInTextViewFromEvent:event];
    const NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:YES];
    const int x = clickPoint.x;
    const int y = clickPoint.y;
    DLog(@"Update live selection during SCROLL");
    return [self moveSelectionEndpointToX:x Y:y locationInTextView:locationInTextView];
}

- (BOOL)mouseHandler:(PTYMouseHandler *)mouseHandler moveSelectionToGridCoord:(VT100GridCoord)coord
    viewCoord:(NSPoint)locationInTextView {
    [self refresh];
    return [self moveSelectionEndpointToX:coord.x
                 Y:coord.y
                 locationInTextView:locationInTextView];
}

- (NSString *)mouseHandler:(PTYMouseHandler *)mouseHandler
    stringForUp:(BOOL)up  // if NO, then down
    flags:(NSEventModifierFlags)flags
    latin1:(out BOOL *)forceLatin1 {
    const BOOL down = !up;

    if ([iTermAdvancedSettingsModel alternateMouseScroll]) {
        *forceLatin1 = YES;
        NSData *data = down ? [_dataSource.terminal.output keyArrowDown:flags] :
                       [_dataSource.terminal.output keyArrowUp:flags];
        return [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    } else {
        *forceLatin1 = NO;
        NSString *string = down ? [iTermAdvancedSettingsModel alternateMouseScrollStringForDown] :
                           [iTermAdvancedSettingsModel alternateMouseScrollStringForUp];
        return [string stringByExpandingVimSpecialCharacters];
    }
}

- (BOOL)mouseHandlerShowingAlternateScreen:(PTYMouseHandler *)mouseHandler {
    return [self.dataSource.terminal softAlternateScreenMode];
}

- (void)mouseHandlerWillDrag:(PTYMouseHandler *)mouseHandler {
    [self removeUnderline];
}

- (void)mouseHandler:(PTYMouseHandler *)mouseHandler
    dragImage:(iTermImageInfo *)image
    forEvent:(NSEvent *)event {
    [self _dragImage:image forEvent:event];
}

- (NSString *)mouseHandlerSelectedText:(PTYMouseHandler *)mouseHandler {
    return [self selectedText];
}

- (void)mouseHandler:(PTYMouseHandler *)mouseHandler
    dragText:(NSString *)text
    forEvent:(NSEvent *)event {
    [self _dragText:text forEvent:event];
}

- (void)mouseHandler:(PTYMouseHandler *)mouseHandler
    dragSemanticHistoryWithEvent:(NSEvent *)event
    coord:(VT100GridCoord)coord {
    [self handleSemanticHistoryItemDragWithEvent:event coord:coord];
}

- (id<iTermSwipeHandler>)mouseHandlerSwipeHandler:(PTYMouseHandler *)sender {
    return [self.delegate textViewSwipeHandler];
}

- (CGFloat)mouseHandlerAccumulatedDeltaY:(PTYMouseHandler *)sender
    forEvent:(NSEvent *)event {
    return [_scrollAccumulator deltaYForEvent:event
                               lineHeight:self.enclosingScrollView.verticalLineScroll];
}

- (long long)mouseHandlerTotalScrollbackOverflow:(nonnull PTYMouseHandler *)sender {
    return _dataSource.totalScrollbackOverflow;
}


#pragma mark - iTermSecureInputRequesting

- (BOOL)isRequestingSecureInput {
    return [self.delegate textViewPasswordInput];
}

@end
