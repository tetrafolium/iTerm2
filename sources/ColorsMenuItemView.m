/*
 **  ColorsMenuItemView.m
 **
 **  Copyright (c) 2012
 **
 **  Author: Andrea Bonomi
 **
 **  Project: iTerm
 **
 **  Description: Colored Tabs.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "ColorsMenuItemView.h"

#import "NSAppearance+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"

@implementation iTermTabColorMenuItem

- (ColorsMenuItemView *)colorsView {
  return [ColorsMenuItemView castFrom:self.view];
}

@end

@interface ColorsMenuItemView ()
@property(nonatomic, retain) NSColor *color;
@end

@implementation ColorsMenuItemView {
  NSTrackingArea *_trackingArea;
  NSInteger _selectedIndex;
  BOOL _mouseDown;
  NSInteger _mouseDownIndex;
}

const int kNumberOfColors = 8;
const int kColorAreaOffsetX = 20;
const int kColorAreaOffsetY = 10;
const int kColorAreaDistanceX = 18;
const int kColorAreaDimension = 12;
const int kColorAreaBorder = 1;
const int kDefaultColorOffset = 2;
const int kDefaultColorDimension = 8;
const int kDefaultColorStokeWidth = 2;
const int kMenuFontSize = 14;
const int kMenuLabelOffsetX = 20;
const int kMenuLabelOffsetY = 32;

const CGFloat iTermColorsMenuItemViewDisabledAlpha = 0.3;

typedef NS_ENUM(NSUInteger, kMenuItem) {
  kMenuItemDefault = 0,
  kMenuItemRed = 1,
  kMenuItemOrange = 2,
  kMenuItemYellow = 3,
  kMenuItemGreen = 4,
  kMenuItemBlue = 5,
  kMenuItemPurple = 6,
  kMenuItemGray = 7
};

- (void)viewDidMoveToWindow {
  _selectedIndex = NSNotFound;
  [super viewDidMoveToWindow];
  [self updateTrackingAreas];
}

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (_trackingArea) {
    [self removeTrackingArea:_trackingArea];
  }

  _trackingArea = [[NSTrackingArea alloc]
      initWithRect:self.bounds
           options:(NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                    NSTrackingActiveAlways)
             owner:self
          userInfo:nil];
  [self addTrackingArea:_trackingArea];
}

- (NSInteger)indexForPoint:(NSPoint)p {
  for (NSInteger i = 0; i < kNumberOfColors; i++) {
    if (NSPointInRect(p, [self rectForIndex:i enlarged:YES])) {
      return i;
    }
  }
  return NSNotFound;
}

- (BOOL)enabled {
  NSMenuItem *enclosingMenuItem = [self enclosingMenuItem];
  return enclosingMenuItem.isEnabled;
}

- (void)mouseDown:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }
  _mouseDown = YES;
  _mouseDownIndex = [self
      indexForPoint:[self convertPoint:event.locationInWindow fromView:nil]];
  [self setNeedsDisplay:YES];
  [super mouseDown:event];
}

- (void)mouseMoved:(NSEvent *)event {
  [self updateSelectedIndexForEvent:event];
}

- (void)mouseEntered:(NSEvent *)event {
  _selectedIndex = NSNotFound;
  [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
  _selectedIndex = NSNotFound;
  [self setNeedsDisplay:YES];
}

- (void)updateSelectedIndexForEvent:(NSEvent *)event {
  const NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  const NSInteger currentIndex = [self indexForPoint:point];
  if (currentIndex != _selectedIndex) {
    _selectedIndex = currentIndex;
    [self setNeedsDisplay:YES];
  }
}

- (NSRect)rectForIndex:(NSInteger)i enlarged:(BOOL)enlarged {
  if (i == NSNotFound) {
    return NSZeroRect;
  }
  CGFloat growth = enlarged ? 2 : 0;
  return NSMakeRect(kColorAreaOffsetX + kColorAreaDistanceX * i - growth,
                    kColorAreaOffsetY - growth,
                    kColorAreaDimension + growth * 2,
                    kColorAreaDimension + growth * 2);
}

- (NSColor *)outlineColorAtIndex:(NSInteger)i enabled:(BOOL)enabled {
  NSColor *color = [self colorAtIndex:i enabled:enabled];
  if (self.effectiveAppearance.it_isDark) {
    const CGFloat perceivedBrightness = color.perceivedBrightness;
    const CGFloat outlineBrightness =
        color.brightnessComponent + 0.1 + (0.05 * pow(20, perceivedBrightness));
    return [NSColor
        colorWithHue:color.hueComponent
          saturation:color.saturationComponent * 0.8
          brightness:outlineBrightness
               alpha:enabled ? 1 : iTermColorsMenuItemViewDisabledAlpha];
  }
  const CGFloat brightness =
      color.brightnessComponent; // color.perceivedBrightness;
  const CGFloat perceivedBrightness = color.perceivedBrightness;
  const CGFloat outlineBrightness =
      brightness * (1 - 0.025 * pow(40, perceivedBrightness));
  color =
      [NSColor colorWithHue:color.hueComponent
                 saturation:MAX(1, color.saturationComponent * 1.1)
                 brightness:outlineBrightness
                      alpha:enabled ? 1 : iTermColorsMenuItemViewDisabledAlpha];
  return color;
}

// Draw the menu item (label and colors)
- (void)drawRect:(NSRect)rect {
  const BOOL enabled = self.enabled;

  // draw the "x" (reset color to default)
  CGFloat savedWidth = [NSBezierPath defaultLineWidth];
  [NSBezierPath setDefaultLineWidth:kDefaultColorStokeWidth];
  CGFloat defaultX0 = kColorAreaOffsetX + kDefaultColorOffset;
  CGFloat defaultX1 = defaultX0 + kDefaultColorDimension;
  CGFloat defaultY0 = kColorAreaOffsetY + kDefaultColorOffset;
  CGFloat defaultY1 = defaultY0 + kDefaultColorDimension;
  NSColor *color;
  if (0 == _selectedIndex) {
    color = self.effectiveAppearance.it_isDark ? [NSColor whiteColor]
                                               : [NSColor blackColor];
  } else {
    color = self.effectiveAppearance.it_isDark
                ? [NSColor lightGrayColor]
                : [NSColor colorWithWhite:0.35 alpha:1];
  }
  if (!enabled) {
    color =
        [color colorWithAlphaComponent:iTermColorsMenuItemViewDisabledAlpha];
  }
  [color set];
  [NSBezierPath strokeLineFromPoint:NSMakePoint(defaultX0, defaultY0)
                            toPoint:NSMakePoint(defaultX1, defaultY1)];
  [NSBezierPath strokeLineFromPoint:NSMakePoint(defaultX1, defaultY0)
                            toPoint:NSMakePoint(defaultX0, defaultY1)];

  // draw the colors
  for (NSInteger i = 1; i < kNumberOfColors; i++) {
    const BOOL highlighted = enabled && i == _selectedIndex;
    const NSRect outlineArea = [self rectForIndex:i enlarged:highlighted];
    // draw the outline
    [[self outlineColorAtIndex:i enabled:enabled] set];
    NSRectFill(outlineArea);

    // draw the color
    const NSRect colorArea =
        NSInsetRect(outlineArea, kColorAreaBorder, kColorAreaBorder);
    NSColor *color = [self colorAtIndex:i enabled:enabled];
    [color set];
    NSRectFill(colorArea);

    BOOL showCheck;
    if (_mouseDown && _selectedIndex != NSNotFound) {
      showCheck = highlighted;
    } else {
      showCheck = [self.currentColor isEqual:[self colorAtIndex:i enabled:YES]];
      if (_mouseDown) {
        showCheck = NO;
      }
    }
    if (enabled && showCheck) {
      static NSImage *lightImage;
      static NSImage *darkImage;
      static dispatch_once_t onceToken;
      dispatch_once(&onceToken, ^{
        lightImage = [[NSImage imageNamed:NSImageNameMenuOnStateTemplate]
            it_imageWithTintColor:[NSColor whiteColor]];
        darkImage = [[NSImage imageNamed:NSImageNameMenuOnStateTemplate]
            it_imageWithTintColor:[NSColor blackColor]];
      });
      CGFloat threshold = self.effectiveAppearance.it_isDark ? 0.0 : 0.7;
      NSImage *image =
          color.perceivedBrightness < threshold ? lightImage : darkImage;
      const NSSize checkSize = NSInsetRect(colorArea, 1, 1).size;
      NSRect rect = NSMakeRect(NSMidX(outlineArea) - checkSize.width / 2,
                               NSMidY(outlineArea) - checkSize.height / 2,
                               checkSize.width, checkSize.height);
      [image drawInRect:rect];
    }
  }

  // draw the menu label
  NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
  attributes[NSFontAttributeName] = [NSFont menuFontOfSize:kMenuFontSize];

  NSMenu *rootMenu = self.enclosingMenuItem.menu;
  while (rootMenu.supermenu) {
    rootMenu = rootMenu.supermenu;
  }
  if ([self darkTheme]) {
    attributes[NSForegroundColorAttributeName] = [NSColor whiteColor];
  } else {
    attributes[NSForegroundColorAttributeName] = [NSColor blackColor];
  }
  if (!enabled) {
    const CGFloat alpha = self.effectiveAppearance.it_isDark ? 0.30 : 0.25;
    attributes[NSForegroundColorAttributeName] =
        [attributes[NSForegroundColorAttributeName]
            colorWithAlphaComponent:alpha];
  }
  NSString *labelTitle = @"Tab Color:";
  [labelTitle drawAtPoint:NSMakePoint(kMenuLabelOffsetX, kMenuLabelOffsetY)
           withAttributes:attributes];
  [NSBezierPath setDefaultLineWidth:savedWidth];
}

- (BOOL)darkTheme {
  return [self.window.appearance.name isEqual:NSAppearanceNameVibrantDark];
}

- (NSColor *)colorAtIndex:(kMenuItem)index enabled:(BOOL)enabled {
  const CGFloat alpha = enabled ? 1 : iTermColorsMenuItemViewDisabledAlpha;
  switch (index) {
  case kMenuItemDefault:
    return nil;
  case kMenuItemRed:
    return [NSColor colorWithSRGBRed:251.0 / 255.0
                               green:107.0 / 255.0
                                blue:98.0 / 255.0
                               alpha:alpha];
  case kMenuItemOrange:
    return [NSColor colorWithSRGBRed:246.0 / 255.0
                               green:172.0 / 255.0
                                blue:71.0 / 255.0
                               alpha:alpha];
  case kMenuItemYellow:
    return [NSColor colorWithSRGBRed:240.0 / 255.0
                               green:220.0 / 255.0
                                blue:79.0 / 255.0
                               alpha:alpha];
  case kMenuItemGreen:
    return [NSColor colorWithSRGBRed:181.0 / 255.0
                               green:215.0 / 255.0
                                blue:73.0 / 255.0
                               alpha:alpha];
  case kMenuItemBlue:
    return [NSColor colorWithSRGBRed:95.0 / 255.0
                               green:163.0 / 255.0
                                blue:248.0 / 255.0
                               alpha:alpha];
  case kMenuItemPurple:
    return [NSColor colorWithSRGBRed:193.0 / 255.0
                               green:142.0 / 255.0
                                blue:217.0 / 255.0
                               alpha:alpha];
  case kMenuItemGray:
    return [NSColor colorWithSRGBRed:120.0 / 255.0
                               green:120.0 / 255.0
                                blue:120.0 / 255.0
                               alpha:alpha];
  }
}

- (void)mouseUp:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }
  _mouseDown = NO;
  [self setNeedsDisplay:YES];

  NSInteger i = [self indexForPoint:[self convertPoint:event.locationInWindow
                                              fromView:nil]];
  if (i != _mouseDownIndex || i == NSNotFound) {
    [super mouseUp:event];
    return;
  }

  NSMenuItem *enclosingMenuItem = [self enclosingMenuItem];
  NSMenu *menu = [enclosingMenuItem menu];
  NSInteger menuIndex = [menu indexOfItem:enclosingMenuItem];
  self.color = [self colorAtIndex:i enabled:YES];
  [menu cancelTracking];
  [menu performActionForItemAtIndex:menuIndex];
}

- (void)mouseDragged:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }
  _mouseDownIndex = [self
      indexForPoint:[self convertPoint:event.locationInWindow fromView:nil]];
  [self updateSelectedIndexForEvent:event];
}

@end
