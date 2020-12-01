//
//  SessionTitleView.h
//  iTerm
//
//  Created by George Nachman on 10/21/11.
//  Copyright 2011 George Nachman. All rights reserved.
//

#import "iTermStatusBarViewController.h"
#import <Cocoa/Cocoa.h>

@protocol SessionTitleViewDelegate <NSObject>

- (NSMenu *)menu;
- (void)close;
- (void)beginDrag;
- (void)doubleClickOnTitleView;
- (void)sessionTitleViewBecomeFirstResponder;
- (NSColor *)sessionTitleViewBackgroundColor;

@end

@interface SessionTitleView : NSView <iTermStatusBarContainer>

@property(nonatomic, copy) NSString *title;
@property(nonatomic, weak) id<SessionTitleViewDelegate> delegate;
@property(nonatomic, assign) double dimmingAmount;
@property(nonatomic, assign) int ordinal;

- (void)updateTextColor;
- (void)updateBackgroundColor;

@end
