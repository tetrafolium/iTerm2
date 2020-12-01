//
//  iTermMetalClipView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/2/17.
//

#import "iTermMetalClipView.h"

#import "DebugLogging.h"
#import "iTermRateLimitedUpdate.h"
#import <MetalKit/MetalKit.h>

@interface NSClipView (Private)
- (BOOL)_shouldShowOverlayScrollersForScrollToPoint:(CGPoint)point;
@end

@implementation iTermMetalClipView {
  NSInteger _disableShowingOverlayScrollers;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.copiesOnScroll = NO;
  }
  return self;
}

- (void)scrollToPoint:(NSPoint)newOrigin {
  [super scrollToPoint:newOrigin];
  if (_useMetal) {
    [_metalView setNeedsDisplay:YES];
  }
}

- (void)performBlockWithoutShowingOverlayScrollers:
    (void (^NS_NOESCAPE)(void))block {
  _disableShowingOverlayScrollers += 1;
  block();
  _disableShowingOverlayScrollers -= 1;
}

- (BOOL)_shouldShowOverlayScrollersForScrollToPoint:(CGPoint)point {
  if (_disableShowingOverlayScrollers) {
    return NO;
  }
  return [super _shouldShowOverlayScrollersForScrollToPoint:point];
}

@end
