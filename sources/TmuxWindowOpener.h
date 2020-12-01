//
//  TmuxWindowOpener.h
//  iTerm
//
//  Created by George Nachman on 11/29/11.
//

#import "FutureMethods.h"
#import "ProfileModel.h"
#import "TmuxGateway.h"
#import <Foundation/Foundation.h>

extern NSString *const kTmuxWindowOpenerStatePendingOutput;

extern NSString *const kTmuxWindowOpenerWindowOptionStyle;
extern NSString *const kTmuxWindowOpenerWindowOptionStyleValueFullScreen;

@class TmuxGateway;
@class TmuxController;
@class PTYTab;

@interface TmuxWindowOpener : NSObject <NSControlTextEditingDelegate>

@property(nonatomic, assign) int windowIndex;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, assign) NSSize size;
@property(nonatomic, copy) NSString *layout;
@property(nonatomic, assign) int maxHistory;
@property(nonatomic, retain) TmuxGateway *gateway;
@property(nonatomic, retain) NSMutableDictionary *parseTree;
@property(nonatomic, assign) TmuxController *controller; // weak
@property(nonatomic, retain) id target;
// Selector is called even if the window is already open and nothing is done.
@property(nonatomic, assign) SEL selector;
@property(nonatomic, assign) BOOL ambiguousIsDoubleWidth;
// Nil means make no change, otherwise is a bool.
@property(nonatomic, retain) NSNumber *zoomed;
@property(nonatomic, assign) NSInteger unicodeVersion;

// Maps a window ID as a string to a dictionary of window flags (see WindowFlag
// constants above).
@property(nonatomic, retain) NSDictionary *windowOptions;
@property(nonatomic, assign) BOOL manuallyOpened;
@property(nonatomic, copy) NSDictionary<NSNumber *, NSString *> *tabColors;
@property(nonatomic, copy) Profile *profile;
@property(nonatomic, assign) BOOL initial;
@property(nonatomic, copy) void (^completion)(int windowIndex);
@property(nonatomic, assign) NSDecimalNumber *minimumServerVersion;
@property(nonatomic, readonly) NSInteger errorCount;
@property(nonatomic, readonly) NSArray<NSNumber *> *unpausingWindowPanes;
@property(nonatomic, strong)
    NSNumber *tabIndex; // open tab at this index, or nil to put at the end
@property(nonatomic, copy) void (^newWindowBlock)(NSString *terminalGUID)
    ; // called after creating a new window.

+ (TmuxWindowOpener *)windowOpener;
- (BOOL)openWindows:(BOOL)initial;

// Returns YES if the tab's layout was updated.
- (BOOL)updateLayoutInTab:(PTYTab *)term;

- (void)unpauseWindowPanes:(NSArray<NSNumber *> *)windowPanes;

// These access the results of unpauseWindowPanes:
- (NSArray<NSData *> *)historyLinesForWindowPane:(int)wp
                                 alternateScreen:(BOOL)altScreen;
- (NSDictionary *)stateForWindowPane:(int)wp;

@end
