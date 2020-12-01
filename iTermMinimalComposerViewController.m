//
//  iTermMinimalComposerViewController.m
//  iTerm2
//
//  Created by George Nachman on 3/31/20.
//

#import "iTermMinimalComposerViewController.h"

#import "iTermStatusBarLargeComposerViewController.h"

static float kAnimationDuration = 0.25;
static CGFloat desiredHeight = 135;

@interface iTermMinimalComposerViewController () <iTermComposerTextViewDelegate>
@end

@implementation iTermMinimalComposerViewController {
  IBOutlet iTermStatusBarLargeComposerViewController
      *_largeComposerViewController;
  IBOutlet NSView *_containerView;
  IBOutlet NSVisualEffectView *_vev;
}

- (instancetype)init {
  self = [super initWithNibName:NSStringFromClass(self.class)
                         bundle:[NSBundle bundleForClass:self.class]];
  return self;
}

- (void)awakeFromNib {
  [_containerView addSubview:_largeComposerViewController.view];
  _containerView.autoresizesSubviews = YES;

  _largeComposerViewController.view.frame = _containerView.bounds;
  _largeComposerViewController.textView.composerDelegate = self;
  _largeComposerViewController.view.autoresizingMask =
      (NSViewWidthSizable | NSViewHeightSizable);
  _vev.layer.cornerRadius = 6;
  _vev.layer.borderColor = [[NSColor grayColor] CGColor];
  _vev.layer.borderWidth = 1;
}

- (void)updateFrame {
  NSRect newFrame = self.view.frame;
  newFrame.origin.y = self.view.superview.frame.size.height;
  self.view.frame = newFrame;

  newFrame.origin.y += self.view.frame.size.height;
  const CGFloat maxWidth =
      self.view.superview.bounds.size.width - self.view.frame.origin.x - 19;
  newFrame = NSMakeRect(self.view.frame.origin.x,
                        self.view.superview.frame.size.height - desiredHeight,
                        MAX(217, maxWidth), desiredHeight);
  [[NSAnimationContext currentContext] setDuration:kAnimationDuration];
  self.view.frame = newFrame;
  self.view.animator.alphaValue = 1;
}

- (void)makeFirstResponder {
  [_largeComposerViewController.textView.window
      makeFirstResponder:_largeComposerViewController.textView];
}

- (IBAction)performClose:(id)sender {
  [self.delegate minimalComposer:self sendCommand:@""];
}

- (NSString *)stringValue {
  return _largeComposerViewController.textView.string;
}

- (void)setStringValue:(NSString *)stringValue {
  _largeComposerViewController.textView.string = stringValue;
}

#pragma mark - iTermComposerTextViewDelegate

- (void)composerTextViewDidFinishWithCancel:(BOOL)cancel {
  NSString *string =
      cancel ? @"" : _largeComposerViewController.textView.string;
  [self.delegate minimalComposer:self sendCommand:string ?: @""];
}

- (void)composerTextViewDidResignFirstResponder {
  [self.delegate minimalComposer:self sendCommand:@""];
}

@end
