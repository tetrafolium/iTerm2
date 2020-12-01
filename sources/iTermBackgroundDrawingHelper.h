//
//  iTermBackgroundDrawingHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/5/18.
//

#import <Cocoa/Cocoa.h>

#import "ITAddressBookMgr.h"

@class SessionView;

@protocol iTermBackgroundDrawingHelperDelegate<NSObject>
- (SessionView *)backgroundDrawingHelperView;  // _view
- (NSImage *)backgroundDrawingHelperImage;  // _backgroundImage
- (BOOL)backgroundDrawingHelperUseTransparency;  // _textview.useTransparency
- (CGFloat)backgroundDrawingHelperTransparency;  // _textview.transparency
- (iTermBackgroundImageMode)backgroundDrawingHelperBackgroundImageMode;  // _backgroundImageMode
- (NSColor *)backgroundDrawingHelperDefaultBackgroundColor;  // [self processedBackgroundColor];
- (CGFloat)backgroundDrawingHelperBlending;  // _textview.blend
@end

@interface iTermBackgroundDrawingHelper : NSObject
@property (nonatomic, weak) id<iTermBackgroundDrawingHelperDelegate> delegate;

- (void)drawBackgroundImageInView:(NSView *)view
    container:(NSView *)container
    dirtyRect:(NSRect)rect
    visibleRectInContainer:(NSRect)visibleRectInContainer
    blendDefaultBackground:(BOOL)blendDefaultBackground
    flip:(BOOL)shouldFlip;

// Call this when the image changes.
- (void)invalidate;

// imageSize is the size of the source image, which may have a different aspect ratio than the area it's being drawn into.
// destinationRect is the frame of the area to draw into.
// dirty rect is the region that needs to be redrawn.
// drawRect is filled with the destination rect to draw into. It will be within dirtyRect.
// boxRect1,2 are the frames of the column/pillar boxes. They will be within dirtyRect.
+ (NSRect)scaleAspectFitSourceRectForForImageSize:(NSSize)imageSize
    destinationRect:(NSRect)destinationRect
    dirtyRect:(NSRect)dirtyRect
    drawRect:(out NSRect *)drawRect
    boxRect1:(out NSRect *)boxRect1
    boxRect2:(out NSRect *)boxRect2;

@end
