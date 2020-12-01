//
//  iTermsStatusBarComposerViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/18.
//

#import "iTermsStatusBarComposerViewController.h"

#import "iTermStatusBarLargeComposerViewController.h"
#import "NSImage+iTerm.h"
#import "NSTextField+iTerm.h"

static NSString *const iTermComposerComboBoxDidBecomeFirstResponder = @"iTermComposerComboBoxDidBecomeFirstResponder";

@interface iTermsStatusBarComposerViewController ()<iTermComposerTextViewDelegate, NSComboBoxDelegate, NSPopoverDelegate>
@end

@interface iTermComposerComboBox : NSComboBox
@end

@implementation iTermComposerComboBox

- (BOOL)becomeFirstResponder {
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermComposerComboBoxDidBecomeFirstResponder
                                          object:self];
    return [super becomeFirstResponder];
}

@end

@implementation iTermsStatusBarComposerViewController {
    BOOL _open;
    BOOL _wantsReload;
    IBOutlet NSComboBox *_comboBox;
    IBOutlet iTermStatusBarLargeComposerViewController *_popoverVC;
    IBOutlet NSPopover *_popover;
    IBOutlet NSButton *_button;
}

- (void)setDelegate:(id)delegate {
    _delegate = delegate;
    [self reallyReloadData];
}

- (void)reloadData {
    if (_open) {
        _wantsReload = YES;
        return;
    }
    [self reallyReloadData];
}

- (void)makeFirstResponder {
    if ([_comboBox textFieldIsFirstResponder]) {
        [self showPopover:nil];
        return;
    }
    [_comboBox.window makeFirstResponder:_comboBox];
}

- (BOOL)dismissPopover {
    if (![_popover isShown]) {
        return NO;
    }
    [_comboBox.window makeFirstResponder:_comboBox];
    return YES;
}

- (void)setTintColor:(NSColor *)tintColor {
    NSImage *image = [NSImage it_imageNamed:@"PopoverIcon" forClass:self.class];
    _button.image = [image it_imageWithTintColor:tintColor];
}

- (void)awakeFromNib {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                          selector:@selector(comboBoxDidBecomeFirstResponder:)
                                          name:iTermComposerComboBoxDidBecomeFirstResponder
                                          object:_comboBox];
}

- (NSString *)stringValue {
    if (_popover.isShown) {
        return _popoverVC.textView.string;
    }
    return _comboBox.stringValue;
}

- (void)setStringValue:(NSString *)stringValue {
    _popoverVC.textView.string = stringValue;
    _comboBox.stringValue = stringValue;
}

#pragma mark - Private

- (void)comboBoxDidBecomeFirstResponder:(NSNotification *)notification {
    [_popover close];
}

- (IBAction)send:(id)sender {
}

- (IBAction)showPopover:(id)sender {
    _popover.behavior = NSPopoverBehaviorSemitransient;
    _popover.delegate = self;
    [_popoverVC view];
    if ([self.delegate statusBarComposerShouldForceDarkAppearance:self]) {
        if (@available(macOS 10.14, *)) {
            _popoverVC.view.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        }
    } else {
        if (@available(macOS 10.14, *)) {
            _popoverVC.view.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        }
    }
    _popoverVC.textView.string = _comboBox.stringValue;
    _popoverVC.textView.font = [self.delegate statusBarComposerFont:self];
    _popoverVC.textView.composerDelegate = self;
    [_popover showRelativeToRect:_comboBox.frame
              ofView:self.view
              preferredEdge:NSRectEdgeMaxY];

}
- (void)reallyReloadData {
    _wantsReload = NO;
    [_comboBox removeAllItems];
    [_comboBox addItemsWithObjectValues:[self.delegate statusBarComposerSuggestions:self] ?: @[]];
}

- (void)sendCommand {
    [self.delegate statusBarComposer:self sendCommand:_comboBox.stringValue];
    _comboBox.stringValue = @"";
}

#pragma mark - NSComboBoxDelegate

- (void)comboBoxWillPopUp:(NSNotification *)notification {
    _open = YES;
}

- (void)comboBoxWillDismiss:(NSNotification *)notification {
    _open = NO;
    if (_wantsReload) {
        [self reloadData];
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    if (!_popover.isShown) {
        [self.delegate statusBarComposerDidEndEditing:self];
    }
}

- (void)cancelOperation:(id)sender {
    if (!_popover.isShown) {
        [self.delegate statusBarComposerDidEndEditing:self];
    }
}

#pragma mark - NSPopoverDelegate

- (void)popoverDidClose:(NSNotification *)notification {
    _comboBox.stringValue = _popoverVC.textView.string ?: @"";

}

- (BOOL)control:(NSControl *)control
    textView:(NSTextView *)textView
    doCommandBySelector:(SEL)commandSelector {
    if (control != _comboBox) {
        return NO;
    }

    if (commandSelector == @selector(insertNewline:)) {
        if (!_open) {
            [self sendCommand];
        }
        return YES;
    } else {
        return NO;
    }
}

#pragma mark - iTermComposerTextViewDelegate

- (void)composerTextViewDidFinishWithCancel:(BOOL)cancel {
    NSString *string = cancel ? @"" : _popoverVC.textView.string;
    if (cancel) {
        [_popover close];
    } else {
        _comboBox.stringValue = string ?: @"";
        [self.delegate statusBarComposer:self sendCommand:string];
        _popoverVC.textView.string = @"";
    }
}

@end
