//
//  iTermSelectionScrollHelper.h
//  iTerm2
//
//  Created by George Nachman on 11/24/14.
//
//

#import "VT100GridTypes.h"
#import <Cocoa/Cocoa.h>

@protocol iTermSelectionScrollHelperDelegate <NSObject>

- (CGFloat)lineHeight;
- (CGFloat)excess;
- (BOOL)moveSelectionEndpointToX:(int)x
                               Y:(int)y
              locationInTextView:(NSPoint)locationInTextView;
- (void)selectionScrollWillStart;

@end

@interface iTermSelectionScrollHelper : NSObject

@property(nonatomic, assign)
    NSView<iTermSelectionScrollHelperDelegate> *delegate;

- (void)mouseUp;
- (void)mouseDraggedTo:(NSPoint)locationInTextView coord:(VT100GridCoord)coord;
- (void)disableUntilMouseUp;

@end
