//
//  iTermFocusReportingTextField.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/22/18.
//

#import "iTermFocusReportingTextField.h"
#import "PTYWindow.h"
#import "iTermSearchFieldCell.h"

@implementation iTermFocusReportingTextField

@dynamic delegate;

- (BOOL)becomeFirstResponder {
  BOOL result = [super becomeFirstResponder];
  if (result &&
      [self.delegate respondsToSelector:@selector
                     (focusReportingTextFieldWillBecomeFirstResponder:)]) {
    [self.delegate focusReportingTextFieldWillBecomeFirstResponder:self];
  }
  return result;
}

@end

@interface iTermFocusReportingSearchField () <iTermSearchFieldControl>
@end

@implementation iTermFocusReportingSearchField

@dynamic delegate;

- (BOOL)enclosingTerminalWindowIsBecomingKey {
  id<PTYWindow> window = (id<PTYWindow>)self.window;
  if (![window conformsToProtocol:@protocol(PTYWindow)]) {
    return NO;
  }
  return window.it_becomingKey;
}

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent {
  return [super performKeyEquivalent:theEvent];
}
- (void)doCommandBySelector:(SEL)selector {
  [super doCommandBySelector:selector];
}
- (BOOL)becomeFirstResponder {
  BOOL result = [super becomeFirstResponder];
  if ([self enclosingTerminalWindowIsBecomingKey]) {
    return NO;
  }
  if (result &&
      [self.delegate respondsToSelector:@selector
                     (focusReportingSearchFieldWillBecomeFirstResponder:)]) {
    [self.delegate focusReportingSearchFieldWillBecomeFirstResponder:self];
  }
  return result;
}

#pragma mark - iTermSearchFieldControl

- (BOOL)searchFieldControlHasCounts:(iTermSearchFieldCell *)cell {
  return ([self.delegate respondsToSelector:@selector
                         (focusReportingSearchFieldNumberOfResults:)] &&
          [self.delegate respondsToSelector:@selector
                         (focusReportingSearchFieldCurrentIndex:)]);
}

- (iTermSearchFieldCounts)searchFieldControlGetCounts:
    (iTermSearchFieldCell *)cell {
  return (iTermSearchFieldCounts){
      .currentIndex =
          [self.delegate focusReportingSearchFieldCurrentIndex:self],
      .numberOfResults =
          [self.delegate focusReportingSearchFieldNumberOfResults:self]};
}

@end
