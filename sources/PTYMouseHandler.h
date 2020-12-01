//
//  PTYMouseHandler.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/29/20.
//

#import <Cocoa/Cocoa.h>

#import "PointerController.h"
#import "VT100GridTypes.h"
#import "VT100Terminal.h"
#import "iTermSwipeHandler.h"

NS_ASSUME_NONNULL_BEGIN

@protocol iTermMouseReportingFrustrationDetectorDelegate;
@class iTermSelection;
@class iTermSelectionScrollHelper;
@class PTYMouseHandler;
@class ThreeFingerTapGestureRecognizer;

@protocol PTYMouseHandlerDelegate <NSObject>
- (BOOL)mouseHandlerViewHasFocus:(PTYMouseHandler *)handler;
- (void)mouseHandlerMakeFirstResponder:(PTYMouseHandler *)handler;
- (void)mouseHandlerWillBeginDragPane:(PTYMouseHandler *)handler;
- (BOOL)mouseHandlerIsInKeyWindow:(PTYMouseHandler *)handler;
- (VT100GridCoord)mouseHandler:(PTYMouseHandler *)handler
                    clickPoint:(NSEvent *)event
                 allowOverflow:(BOOL)allowRightMarginOverflow;
- (BOOL)mouseHandler:(PTYMouseHandler *)handler
      coordIsMutable:(VT100GridCoord)coord;
- (MouseMode)mouseHandlerMouseMode:(PTYMouseHandler *)handler;
- (BOOL)mouseHandlerReportingAllowed:(PTYMouseHandler *)handler;
- (void)mouseHandlerDidSingleClick:(PTYMouseHandler *)handler;
- (iTermSelection *)mouseHandlerCurrentSelection:(PTYMouseHandler *)handler;
- (iTermImageInfo *)mouseHandler:(PTYMouseHandler *)handler
                         imageAt:(VT100GridCoord)coord;
- (void)mouseHandlerLockScrolling:(PTYMouseHandler *)handler;
- (void)mouseHandlerUnlockScrolling:(PTYMouseHandler *)handler;
- (void)mouseHandlerDidMutateState:(PTYMouseHandler *)handler;
- (void)mouseHandlerDidInferScrollingIntent:(PTYMouseHandler *)handler
                                     trying:(BOOL)trying;
- (void)mouseHandlerOpenTargetWithEvent:(NSEvent *)event
                           inBackground:(BOOL)inBackground;
- (BOOL)mouseHandlerIsScrolledToBottom:(PTYMouseHandler *)handler;
- (VT100GridCoord)mouseHandlerCoordForPointInWindow:(NSPoint)point;
- (VT100GridCoord)mouseHandlerCoordForPointInView:(NSPoint)point;
- (void)mouseHandlerMoveCursorToCoord:(VT100GridCoord)coord
                             forEvent:(NSEvent *)event;
- (void)mouseHandlerSetFindOnPageCursorCoord:(VT100GridCoord)clickPoint;
- (BOOL)mouseHandlerAtPasswordPrompt:(PTYMouseHandler *)handler;
- (VT100GridCoord)mouseHandlerCursorCoord:(PTYMouseHandler *)handler;
- (void)mouseHandlerOpenPasswordManager:(PTYMouseHandler *)handler;
- (BOOL)mouseHandler:(PTYMouseHandler *)handler
    getFindOnPageCursor:(VT100GridCoord *)coord;
- (void)mouseHandlerResetFindOnPageCursor:(PTYMouseHandler *)handler;
- (BOOL)mouseHandlerIsValid:(PTYMouseHandler *)handler;
- (void)mouseHandlerCopy:(PTYMouseHandler *)handler;
- (NSPoint)mouseHandler:(PTYMouseHandler *)handler
      viewCoordForEvent:(NSEvent *)event
                clipped:(BOOL)clipped;
- (void)mouseHandler:(PTYMouseHandler *)handler
    sendFakeOtherMouseUp:(NSEvent *)event;
- (BOOL)mouseHandler:(PTYMouseHandler *)handler
            reportMouseEvent:(NSEventType)eventType
                   modifiers:(NSUInteger)modifiers
                      button:(MouseButtonNumber)button
                  coordinate:(VT100GridCoord)coord
                       event:(NSEvent *)vent
                      deltaY:(CGFloat)deltaY
    allowDragBeforeMouseDown:(BOOL)allowDragBeforeMouseDown
                    testOnly:(BOOL)testOnly;
- (BOOL)mouseHandler:(PTYMouseHandler *)handler
    viewCoordIsReportable:(NSPoint)coord;
- (BOOL)mouseHandlerViewIsFirstResponder:(PTYMouseHandler *)mouseHandler;
- (BOOL)mouseHandlerShouldReportClicksAndDrags:(PTYMouseHandler *)mouseHandler;
- (BOOL)mouseHandlerShouldReportScroll:(PTYMouseHandler *)mouseHandler;
- (void)mouseHandlerJiggle:(PTYMouseHandler *)mouseHandler;
- (CGFloat)mouseHandler:(PTYMouseHandler *)mouseHandler
    accumulateVerticalScrollFromEvent:(NSEvent *)event;
- (void)mouseHandler:(PTYMouseHandler *)handler
          sendString:(NSString *)string
              latin1:(BOOL)forceLatin1;
- (void)mouseHandlerRemoveSelection:(PTYMouseHandler *)mouseHandler;
- (BOOL)mouseHandler:(PTYMouseHandler *)mouseHandler
    moveSelectionToPointInEvent:(NSEvent *)event;
- (BOOL)mouseHandler:(PTYMouseHandler *)mouseHandler
    moveSelectionToGridCoord:(VT100GridCoord)coord
                   viewCoord:(NSPoint)locationInTextView;
- (NSString *)mouseHandler:(PTYMouseHandler *)mouseHandler
               stringForUp:(BOOL)up // if NO, then down
                     flags:(NSEventModifierFlags)flags
                    latin1:(out BOOL *)forceLatin1;
- (BOOL)mouseHandlerShowingAlternateScreen:(PTYMouseHandler *)mouseHandler;
- (void)mouseHandlerWillDrag:(PTYMouseHandler *)mouseHandler;

- (void)mouseHandler:(PTYMouseHandler *)mouseHandler
           dragImage:(iTermImageInfo *)image
            forEvent:(NSEvent *)event;

- (NSString *)mouseHandlerSelectedText:(PTYMouseHandler *)mouseHandler;

- (void)mouseHandler:(PTYMouseHandler *)mouseHandler
            dragText:(NSString *)text
            forEvent:(NSEvent *)event;

- (void)mouseHandler:(PTYMouseHandler *)mouseHandler
    dragSemanticHistoryWithEvent:(NSEvent *)event
                           coord:(VT100GridCoord)coord;
- (void)mouseHandlerMakeKeyAndOrderFrontAndMakeFirstResponderAndActivateApp:
    (PTYMouseHandler *)sender;

- (id<iTermSwipeHandler>)mouseHandlerSwipeHandler:(PTYMouseHandler *)sender;
- (CGFloat)mouseHandlerAccumulatedDeltaY:(PTYMouseHandler *)sender
                                forEvent:(NSEvent *)event;
- (long long)mouseHandlerTotalScrollbackOverflow:(PTYMouseHandler *)sender;
@end

@interface PTYMouseHandler : NSObject

@property(nonatomic, weak) id<PTYMouseHandlerDelegate> mouseDelegate;

// Number of fingers currently down (only valid if three finger click
// emulates middle button). This is directly set by the owner.
@property(nonatomic) int numTouches;
// Flag to make sure a Semantic History drag check is only one once per drag
@property(nonatomic, readonly) BOOL semanticHistoryDragged;
@property(nonatomic, readonly) BOOL terminalWantsMouseReports;

- (instancetype)initWithSelectionScrollHelper:
                    (iTermSelectionScrollHelper *)selectionScrollHelper
              threeFingerTapGestureRecognizer:
                  (ThreeFingerTapGestureRecognizer *)
                      threeFingerTapGestureRecognizer
                    pointerControllerDelegate:
                        (id<PointerControllerDelegate>)pointerControllerDelegate
    mouseReportingFrustrationDetectorDelegate:
        (id<iTermMouseReportingFrustrationDetectorDelegate>)
            mouseReportingFrustrationDetectorDelegate NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Left mouse

- (void)mouseDown:(NSEvent *)event superCaller:(void (^)(void))superCaller;
- (BOOL)mouseDownImpl:(NSEvent *)event;
- (void)mouseUp:(NSEvent *)event;
- (void)mouseDragged:(NSEvent *)event;

#pragma mark - Right mouse

- (void)rightMouseDown:(NSEvent *)event superCaller:(void (^)(void))superCaller;
- (void)rightMouseUp:(NSEvent *)event superCaller:(void (^)(void))superCaller;
- (void)rightMouseDragged:(NSEvent *)event
              superCaller:(void (^)(void))superCaller;

#pragma mark - Other mouse

- (void)otherMouseUp:(NSEvent *)event superCaller:(void (^)(void))superCaller;
- (void)otherMouseDown:(NSEvent *)event;
- (void)otherMouseDragged:(NSEvent *)event
              superCaller:(void (^)(void))superCaller;

#pragma mark - Responder

- (void)didResignFirstResponder;
- (void)didBecomeFirstResponder;

#pragma mark - Misc mouse

- (BOOL)scrollWheel:(NSEvent *)event pointInView:(NSPoint)point;
- (void)swipeWithEvent:(NSEvent *)event;
- (void)mouseMoved:(NSEvent *)event;
- (void)pressureChangeWithEvent:(NSEvent *)event;
- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent;

#pragma mark - Other APIs

- (void)performBlockWithThreeTouches:(void (^)(void))block;
- (BOOL)threeFingerTap:(NSEvent *)ev;
- (void)keyDown:(NSEvent *)event;
- (void)selectionScrollWillStart;
- (void)didDragSemanticHistory;
- (BOOL)mouseReportingAllowedForEvent:(NSEvent *)event;
- (void)didCopyToPasteboardWithControlSequence;
- (BOOL)wantsScrollWheelMomentumEvents;

@end

NS_ASSUME_NONNULL_END
