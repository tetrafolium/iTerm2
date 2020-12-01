//
//  iTermSwipeTracker.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/26/20.
//

#import "iTermSwipeTracker.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTimer+iTerm.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermGCDTimer.h"
#import "iTermScrollWheelStateMachine.h"
#import "iTermSquash.h"
#import "iTermSwipeState+Private.h"

NSString *const iTermSwipeHandlerCancelSwipe = @"iTermSwipeHandlerCancelSwipe";

@implementation iTermSwipeTracker {
  iTermScrollWheelStateMachine *_stateMachine;
  iTermSwipeState *_liveState;
  iTermGCDTimer *_timer;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _stateMachine = [[iTermScrollWheelStateMachine alloc] init];
  }
  return self;
}

- (BOOL)shouldTrack {
  return _liveState.shouldTrack;
}

- (BOOL)handleEvent:(NSEvent *)event {
  if (!event.window) {
    return NO;
  }
  DLog(@"Handle event before tracking loop: %@", event);
  const BOOL handled = [self internalHandleEvent:event];
  if (!handled) {
    DLog(@"Event not used");
    return NO;
  }

  if (![self shouldTrack]) {
    DLog(@"Not starting tracking loop");
    return NO;
  }

  DLog(@"Start tracking loop");
  // A bit of hard-won wisdom: if you don't start tracking right away, the
  // behavior of the event reporting changes and you miss a lot of drags. For
  // that reason, -internalHandleEvent uses a very rough test (is it more
  // horizontal than vertical?) to avoid tracking on vertical scroll events, but
  // then we use a more precise test in shouldDrag that rejects drags that
  // aren't horizontal enough after collecting more data.
  const NSEventMask eventMask = NSEventMaskScrollWheel;
  event = [NSApp nextEventMatchingMask:eventMask
                             untilDate:[NSDate distantFuture]
                                inMode:NSEventTrackingRunLoopMode
                               dequeue:YES];
  DLog(@"Got event %@", iTermShortEventPhasesString(event));
  while (1) {
    @autoreleasepool {
      DLog(@"Continue tracking.");
      if (event) {
        [self internalHandleEvent:event];
      }
      [self updateTimer];
      if (![self shouldTrack]) {
        break;
      }
      event = [NSApp
          nextEventMatchingMask:eventMask
                      untilDate:[NSDate dateWithTimeIntervalSinceNow:1.0 / 60.0]
                         inMode:NSEventTrackingRunLoopMode
                        dequeue:YES];
      DLog(@"Got event %@", event);
    }
  }
  DLog(@"Exit tracking loop");
  return YES;
}

- (BOOL)internalHandleEvent:(NSEvent *)event {
  DLog(@"internalHandleEvent: %@", iTermShortEventPhasesString(event));
  if (![NSEvent isSwipeTrackingFromScrollEventsEnabled] ||
      ![iTermAdvancedSettingsModel allowInteractiveSwipeBetweenTabs]) {
    DLog(@"Swipe tracking not enabled");
    return NO;
  }

  iTermScrollWheelStateMachineStateTransition transition = {
      .before = _stateMachine.state};
  [_stateMachine handleEvent:event];
  transition.after = _stateMachine.state;

  if (!_liveState || _liveState.isRetired) {
    if (fabs(event.scrollingDeltaX) < fabs(event.scrollingDeltaY)) {
      DLog(@"Not creating new state because not horizontal: %@", event);
      return NO;
    }
    if (transition.before != iTermScrollWheelStateMachineStateGround) {
      DLog(@"Not creating a new state because not starting in ground state");
      return NO;
    }
    if (![self.delegate swipeTrackerShouldBeginNewSwipe:self]) {
      DLog(@"Delegate declined to begin new swipe");
      return NO;
    }
    return [self createStateForEventIfNeeded:event transition:transition];
  }
  return [_liveState handleEvent:event transition:transition];
}

- (BOOL)createStateForEventIfNeeded:(NSEvent *)event
                         transition:
                             (iTermScrollWheelStateMachineStateTransition)
                                 transition {
  if (transition.before == iTermScrollWheelStateMachineStateStartDrag ||
      transition.after == iTermScrollWheelStateMachineStateDrag ||
      transition.after == iTermScrollWheelStateMachineStateGround) {
    DLog(@"Can't create state for transition %@ -> %@", @(transition.before),
         @(transition.after));
    return NO;
  }
  DLog(@"Create new live state");
  _liveState = [self.delegate swipeTrackerWillBeginNewSwipe:self];
  [_liveState handleEvent:event transition:transition];
  [self updateTimer];
  if (!_liveState) {
    DLog(@"fail: live state is nil");
    return NO;
  }
  DLog(@"Success - created a new live event");
  return YES;
}

- (void)updateTimer {
  if (!_liveState ||
      _liveState.momentumStage == iTermSwipeStateMomentumStageNone) {
    DLog(@"Cancel timer");
    [_timer invalidate];
    _timer = nil;
    return;
  }
  if (_timer) {
    DLog(@"Already have timer");
    return;
  }
  DLog(@"Schedule timer");
  _timer = [[iTermGCDTimer alloc] initWithInterval:1.0 / 60
                                            target:self
                                          selector:@selector(update:)];
}

- (void)update:(iTermGCDTimer *)timer {
  DLog(@"Timer fired");
  if (_liveState.isRetired) {
    DLog(@"nil out retired live state");
    _liveState = nil;
  }
  DLog(@"Update live state %@", _liveState);
  [_liveState update:timer.actualInterval];
  [self updateTimer];
}

@end
