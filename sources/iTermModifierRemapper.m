/*
 * Copyright (c) 2009, 2010 <andrew iain mcdermott via gmail>
 *
 * Source can be cloned from:
 *
 *  git://github.com/aim-stuff/cmd-key-happy.git
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

#import <Cocoa/Cocoa.h>

#import "iTermModifierRemapper.h"

#import "DebugLogging.h"
#import "NSEvent+iTerm.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermEventTap.h"
#import "iTermHotKeyController.h"
#import "iTermKeyMappings.h"
#import "iTermKeystroke.h"
#import "iTermShortcutInputView.h"
#import "iTermSystemVersion.h"

@interface iTermModifierRemapper () <iTermEventTapRemappingDelegate>
@end

@implementation iTermModifierRemapper {
  iTermEventTap *_keyDown;
}

+ (NSInteger)_cgMaskForMod:(int)mod {
  switch (mod) {
  case kPreferencesModifierTagControl:
    return kCGEventFlagMaskControl;

  case kPreferencesModifierTagLeftOption:
  case kPreferencesModifierTagRightOption:
  case kPreferencesModifierTagEitherOption:
    return kCGEventFlagMaskAlternate;

  case kPreferencesModifierTagEitherCommand:
  case kPreferencesModifierTagLeftCommand:
  case kPreferencesModifierTagRightCommand:
    return kCGEventFlagMaskCommand;

  case kPreferencesModifierTagCommandAndOption:
    return kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate;

  default:
    return 0;
  }
}

+ (NSInteger)_nxMaskForLeftMod:(int)mod {
  switch (mod) {
  case kPreferencesModifierTagControl:
    return NX_DEVICELCTLKEYMASK;

  case kPreferencesModifierTagLeftOption:
    return NX_DEVICELALTKEYMASK;

  case kPreferencesModifierTagRightOption:
    return NX_DEVICERALTKEYMASK;

  case kPreferencesModifierTagEitherOption:
    return NX_DEVICELALTKEYMASK;

  case kPreferencesModifierTagRightCommand:
    return NX_DEVICERCMDKEYMASK;

  case kPreferencesModifierTagLeftCommand:
  case kPreferencesModifierTagEitherCommand:
    return NX_DEVICELCMDKEYMASK;

  case kPreferencesModifierTagCommandAndOption:
    return NX_DEVICELCMDKEYMASK | NX_DEVICELALTKEYMASK;

  default:
    return 0;
  }
}

+ (NSInteger)_nxMaskForRightMod:(int)mod {
  switch (mod) {
  case kPreferencesModifierTagControl:
    return NX_DEVICERCTLKEYMASK;

  case kPreferencesModifierTagLeftOption:
    return NX_DEVICELALTKEYMASK;

  case kPreferencesModifierTagRightOption:
    return NX_DEVICERALTKEYMASK;

  case kPreferencesModifierTagEitherOption:
    return NX_DEVICERALTKEYMASK;

  case kPreferencesModifierTagLeftCommand:
    return NX_DEVICELCMDKEYMASK;

  case kPreferencesModifierTagRightCommand:
  case kPreferencesModifierTagEitherCommand:
    return NX_DEVICERCMDKEYMASK;

  case kPreferencesModifierTagCommandAndOption:
    return NX_DEVICERCMDKEYMASK | NX_DEVICERALTKEYMASK;

  default:
    return 0;
  }
}

+ (NSInteger)_cgMaskForLeftCommandKey {
  return [self _cgMaskForMod:[[iTermModifierRemapper sharedInstance]
                                 leftCommandRemapping]];
}

+ (NSInteger)_cgMaskForRightCommandKey {
  return [self _cgMaskForMod:[[iTermModifierRemapper sharedInstance]
                                 rightCommandRemapping]];
}

+ (NSInteger)_nxMaskForLeftCommandKey {
  return [self _nxMaskForLeftMod:[[iTermModifierRemapper sharedInstance]
                                     leftCommandRemapping]];
}

+ (NSInteger)_nxMaskForRightCommandKey {
  return [self _nxMaskForRightMod:[[iTermModifierRemapper sharedInstance]
                                      rightCommandRemapping]];
}

+ (NSInteger)_cgMaskForLeftAlternateKey {
  return [self _cgMaskForMod:[[iTermModifierRemapper sharedInstance]
                                 leftOptionRemapping]];
}

+ (NSInteger)_cgMaskForRightAlternateKey {
  return [self _cgMaskForMod:[[iTermModifierRemapper sharedInstance]
                                 rightOptionRemapping]];
}

+ (NSInteger)_nxMaskForLeftAlternateKey {
  return [self _nxMaskForLeftMod:[[iTermModifierRemapper sharedInstance]
                                     leftOptionRemapping]];
}

+ (NSInteger)_nxMaskForRightAlternateKey {
  return [self _nxMaskForRightMod:[[iTermModifierRemapper sharedInstance]
                                      rightOptionRemapping]];
}

+ (NSInteger)_cgMaskForLeftControlKey {
  return [self
      _cgMaskForMod:[[iTermModifierRemapper sharedInstance] controlRemapping]];
}

+ (NSInteger)_cgMaskForRightControlKey {
  return [self
      _cgMaskForMod:[[iTermModifierRemapper sharedInstance] controlRemapping]];
}

+ (NSInteger)_nxMaskForLeftControlKey {
  return [self _nxMaskForLeftMod:[[iTermModifierRemapper sharedInstance]
                                     controlRemapping]];
}

+ (NSInteger)_nxMaskForRightControlKey {
  return [self _nxMaskForRightMod:[[iTermModifierRemapper sharedInstance]
                                      controlRemapping]];
}

+ (CGEventRef)remapModifiersInCGEvent:(CGEventRef)cgEvent {
  // This function copied from cmd-key happy. See copyright notice at top.
  CGEventFlags flags = CGEventGetFlags(cgEvent);
  DLog(@"Performing remapping. On input CGEventFlags=%@", @(flags));
  CGEventFlags andMask = -1;
  CGEventFlags orMask = 0;

  // flags contains both device-dependent flags and device-independent flags.
  // The device-independent flags are named kCGEventFlagMaskXXX or NX_xxxMASK
  // The device-dependent flags are named NX_DEVICExxxKEYMASK
  // Device-independent flags do not indicate leftness or rightness.
  // Device-dependent flags do.
  // Generally, you get both sets of flags. But this does not have to be the
  // case if an event is synthesized, as seen in issue 5207 where Flycut does
  // not set the device-dependent flags. If the event lacks device-specific
  // flags we'll add them when synergyModifierRemappingEnabled is on. Otherwise,
  // we don't remap them.
  if (flags & kCGEventFlagMaskCommand) {
    BOOL hasDeviceIndependentFlagsForCommandKey =
        ((flags & (NX_DEVICELCMDKEYMASK | NX_DEVICERCMDKEYMASK)) != 0);
    if (!hasDeviceIndependentFlagsForCommandKey) {
      if ([iTermAdvancedSettingsModel synergyModifierRemappingEnabled]) {
        flags |= NX_DEVICELCMDKEYMASK;
        hasDeviceIndependentFlagsForCommandKey = YES;
      }
    }
    if (hasDeviceIndependentFlagsForCommandKey) {
      andMask &= ~kCGEventFlagMaskCommand;
      if (flags & NX_DEVICELCMDKEYMASK) {
        andMask &= ~NX_DEVICELCMDKEYMASK;
        orMask |= [self _cgMaskForLeftCommandKey];
        orMask |= [self _nxMaskForLeftCommandKey];
      }
      if (flags & NX_DEVICERCMDKEYMASK) {
        andMask &= ~NX_DEVICERCMDKEYMASK;
        orMask |= [self _cgMaskForRightCommandKey];
        orMask |= [self _nxMaskForRightCommandKey];
      }
    }
  }
  if (flags & kCGEventFlagMaskAlternate) {
    BOOL hasDeviceIndependentFlagsForOptionKey =
        ((flags & (NX_DEVICELALTKEYMASK | NX_DEVICERALTKEYMASK)) != 0);
    if (!hasDeviceIndependentFlagsForOptionKey) {
      if ([iTermAdvancedSettingsModel synergyModifierRemappingEnabled]) {
        flags |= NX_DEVICELALTKEYMASK;
        hasDeviceIndependentFlagsForOptionKey = YES;
      }
    }
    if (hasDeviceIndependentFlagsForOptionKey) {
      andMask &= ~kCGEventFlagMaskAlternate;
      if (flags & NX_DEVICELALTKEYMASK) {
        andMask &= ~NX_DEVICELALTKEYMASK;
        orMask |= [self _cgMaskForLeftAlternateKey];
        orMask |= [self _nxMaskForLeftAlternateKey];
      }
      if (flags & NX_DEVICERALTKEYMASK) {
        andMask &= ~NX_DEVICERALTKEYMASK;
        orMask |= [self _cgMaskForRightAlternateKey];
        orMask |= [self _nxMaskForRightAlternateKey];
      }
    }
  }
  if (flags & kCGEventFlagMaskControl) {
    BOOL hasDeviceIndependentFlagsForControlKey =
        ((flags & (NX_DEVICELCTLKEYMASK | NX_DEVICERCTLKEYMASK)) != 0);
    if (!hasDeviceIndependentFlagsForControlKey) {
      if ([iTermAdvancedSettingsModel synergyModifierRemappingEnabled]) {
        flags |= NX_DEVICELCTLKEYMASK;
        hasDeviceIndependentFlagsForControlKey = YES;
      }
    }
    if (hasDeviceIndependentFlagsForControlKey) {
      andMask &= ~kCGEventFlagMaskControl;
      if (flags & NX_DEVICELCTLKEYMASK) {
        andMask &= ~NX_DEVICELCTLKEYMASK;
        orMask |= [self _cgMaskForLeftControlKey];
        orMask |= [self _nxMaskForLeftControlKey];
      }
      if (flags & NX_DEVICERCTLKEYMASK) {
        andMask &= ~NX_DEVICERCTLKEYMASK;
        orMask |= [self _cgMaskForRightControlKey];
        orMask |= [self _nxMaskForRightControlKey];
      }
    }
  }
  DLog(@"On output CGEventFlags=%@", @((flags & andMask) | orMask));

  CGEventSetFlags(cgEvent, (flags & andMask) | orMask);
  return cgEvent;
}

+ (NSEvent *)remapModifiers:(NSEvent *)event {
  return
      [NSEvent eventWithCGEvent:[self remapModifiersInCGEvent:[event CGEvent]]];
}

+ (instancetype)sharedInstance {
  static dispatch_once_t onceToken;
  static id instance;
  dispatch_once(&onceToken, ^{
    instance = [[self alloc] init];
  });
  return instance;
}

- (void)dealloc {
  [_keyDown release];
  [super dealloc];
}

#pragma mark - APIs

- (void)setRemapModifiers:(BOOL)remapModifiers {
  if (remapModifiers) {
    [self beginRemappingModifiers];
  } else {
    [self stopRemappingModifiers];
  }
}

- (BOOL)isRemappingModifiers {
  return [_keyDown isEnabled];
}

- (iTermPreferencesModifierTag)controlRemapping {
  return [iTermPreferences intForKey:kPreferenceKeyControlRemapping];
}

- (iTermPreferencesModifierTag)leftOptionRemapping {
  return [iTermPreferences intForKey:kPreferenceKeyLeftOptionRemapping];
}

- (iTermPreferencesModifierTag)rightOptionRemapping {
  return [iTermPreferences intForKey:kPreferenceKeyRightOptionRemapping];
}

- (iTermPreferencesModifierTag)leftCommandRemapping {
  return [iTermPreferences intForKey:kPreferenceKeyLeftCommandRemapping];
}

- (iTermPreferencesModifierTag)rightCommandRemapping {
  return [iTermPreferences intForKey:kPreferenceKeyRightCommandRemapping];
}

- (BOOL)isAnyModifierRemapped {
  return ([self controlRemapping] != kPreferencesModifierTagControl ||
          [self leftOptionRemapping] != kPreferencesModifierTagLeftOption ||
          [self rightOptionRemapping] != kPreferencesModifierTagRightOption ||
          [self leftCommandRemapping] != kPreferencesModifierTagLeftCommand ||
          [self rightCommandRemapping] != kPreferencesModifierTagRightCommand);
}

#pragma mark - Private

- (iTermEventTap *)keyDown {
  if ([iTermAdvancedSettingsModel remapModifiersWithoutEventTap]) {
    return nil;
  }
  if (!_keyDown) {
    _keyDown = [[iTermEventTap alloc]
        initWithEventTypes:CGEventMaskBit(kCGEventKeyDown)];
  }
  return _keyDown;
}

- (void)beginRemappingModifiers {
  DLog(@"Begin remapping modifiers");
  [self.keyDown setRemappingDelegate:self];
  if ([iTermAdvancedSettingsModel remapModifiersWithoutEventTap]) {
    return;
  }

  [[iTermFlagsChangedEventTap sharedInstance] setRemappingDelegate:self];

  if (![_keyDown isEnabled]) {
    DLog(@"The event tap is NOT enabled");
    [self requestAccessibilityPermission];
  }
}

- (void)stopRemappingModifiers {
  [_keyDown setRemappingDelegate:nil];
  [[iTermFlagsChangedEventTap sharedInstanceCreatingIfNeeded:NO]
      setRemappingDelegate:nil];
}

- (void)requestAccessibilityPermission {
  if ([iTermAdvancedSettingsModel remapModifiersWithoutEventTap]) {
    return;
  }

  DLog(@"Requesting accessibility permission");
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSDictionary *options = @{(NSString *)kAXTrustedCheckOptionPrompt : @YES};
    // Show a dialog prompting the user to open system prefs.
    if (!AXIsProcessTrustedWithOptions((CFDictionaryRef)options)) {
      return;
    }
  });
}

- (NSString *)accessibilityMessageForModifier {
  return @"You have chosen to remap certain modifier keys. For this to work "
         @"for all key "
         @"combinations (such as cmd-tab), you must turn on \"access for "
         @"assistive devices\" "
         @"in the Universal Access preferences panel in System Preferences and "
         @"restart iTerm2.";
}

- (NSString *)accessibilityActionMessage {
  return @"Open System Preferences";
}

#pragma mark - iTermEventTapRemappingDelegate

- (CGEventRef)remappedEventFromEventTappedWithType:(CGEventType)type
                                             event:(CGEventRef)event {
  DLog(@"Modifier remapper got an event");
  if ([NSApp isActive]) {
    DLog(@"App is active, performing remapping");
    // Remap modifier keys only while iTerm2 is active; otherwise you could just
    // use the OS's remap feature.
    return [self eventByRemappingEvent:event];
  } else {
    DLog(@"iTerm2 not active. The active app is %@",
         [[NSWorkspace sharedWorkspace] frontmostApplication]);
    return event;
  }
}

// Only called when the app is active.
- (CGEventRef)eventByRemappingEvent:(CGEventRef)event {
  NSEvent *cocoaEvent = [NSEvent eventWithCGEvent:event];

  DLog(@"Remapping event %@ from keyboard of type %@", cocoaEvent,
       @(CGEventGetIntegerValueField(event, kCGKeyboardEventKeyboardType)));

  iTermShortcutInputView *shortcutView = nil;
  NSResponder *firstResponder = [[NSApp keyWindow] firstResponder];
  if ([firstResponder isKindOfClass:[iTermShortcutInputView class]]) {
    shortcutView = (iTermShortcutInputView *)firstResponder;
  }

  if (shortcutView.disableKeyRemapping) {
    DLog(@"Shortcut view is active so return nil");
    // Send keystroke directly to preference panel when setting do-not-remap for
    // a key; for system keys, NSApp sendEvent: is never called so this is the
    // last chance.
    [shortcutView handleShortcutEvent:cocoaEvent];
    return nil;
  }

  switch ([self boundActionForEvent:cocoaEvent]) {
  case KEY_ACTION_REMAP_LOCALLY:
    DLog(@"Calling sendEvent:");
    [self.class remapModifiersInCGEvent:event];
    [NSApp sendEvent:[NSEvent eventWithCGEvent:event]];
    return nil;

  case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
    DLog(@"Action is do not remap");
    return event;

  default:
    DLog(@"Remapping as usual");
    [self.class remapModifiersInCGEvent:event];
    return event;
  }
}

- (KEY_ACTION)boundActionForEvent:(NSEvent *)cocoaEvent {
  if (cocoaEvent.type == NSEventTypeFlagsChanged) {
    return -1;
  }
  iTermKeystroke *keystroke = [iTermKeystroke withEvent:cocoaEvent];
  iTermKeyBindingAction *action = [iTermKeyMappings actionForKeystroke:keystroke
                                                           keyMappings:nil];
  return action ? action.keyAction : KEY_ACTION_INVALID;
}

@end
