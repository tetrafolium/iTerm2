//
//  iTermStatusBarBaseLayoutAlgorithm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/20/19.
//

#import "iTermStatusBarLayoutAlgorithm.h"

NS_ASSUME_NONNULL_BEGIN

@protocol iTermStatusBarComponent;

@interface iTermStatusBarBaseLayoutAlgorithm : iTermStatusBarLayoutAlgorithm {
@protected
  CGFloat _statusBarWidth;
  NSArray<iTermStatusBarContainerView *> *_containerViews;
}

- (NSArray<iTermStatusBarContainerView *> *)unhiddenContainerViews;
- (NSArray<iTermStatusBarContainerView *> *)fittingSubsetOfContainerViewsFrom:
    (NSArray<iTermStatusBarContainerView *> *)views;
- (void)updateMargins:(NSArray<iTermStatusBarContainerView *> *)views;
- (CGFloat)totalMarginWidthForViews:
    (NSArray<iTermStatusBarContainerView *> *)views;
- (CGFloat)minimumWidthOfContainerViews:
    (NSArray<iTermStatusBarContainerView *> *)views;
- (NSArray<iTermStatusBarContainerView *> *)containerViewsSortedByPriority:
    (NSArray<iTermStatusBarContainerView *> *)eligibleContainerViews;
- (void)makeWidthsAndOriginsIntegers:
    (NSArray<iTermStatusBarContainerView *> *)views;
- (CGFloat)minimumWidthForComponent:(id<iTermStatusBarComponent>)component;
- (CGFloat)maximumWidthForComponent:(id<iTermStatusBarComponent>)component;

@end

NS_ASSUME_NONNULL_END
