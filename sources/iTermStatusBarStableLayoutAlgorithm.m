//
//  iTermStatusBarStableLayoutAlgorithm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/20/19.
//

#import "iTermStatusBarStableLayoutAlgorithm.h"

#import "DebugLogging.h"
#import "iTermStatusBarComponent.h"
#import "iTermStatusBarContainerView.h"
#import "iTermStatusBarFixedSpacerComponent.h"
#import "iTermStatusBarSpringComponent.h"
#import "NSArray+iTerm.h"

@implementation iTermStatusBarStableLayoutAlgorithm

- (iTermStatusBarContainerView *)containerViewWithLargestMinimumWidthFromViews:(NSArray<iTermStatusBarContainerView *> *)views {
    return [views maxWithBlock:^NSComparisonResult(iTermStatusBarContainerView *obj1, iTermStatusBarContainerView *obj2) {
              return [@(obj1.minimumWidthIncludingIcon) compare:@(obj2.minimumWidthIncludingIcon)];
          }];
}

- (NSArray<iTermStatusBarContainerView *> *)allPossibleCandidateViews {
    return [self unhiddenContainerViews];
}

- (BOOL)componentIsSpacer:(id<iTermStatusBarComponent>)component {
    return ([component isKindOfClass:[iTermStatusBarSpringComponent class]] ||
            [component isKindOfClass:[iTermStatusBarFixedSpacerComponent class]]);
}

- (BOOL)views:(NSArray<iTermStatusBarContainerView *> *)views
    haveSpacersOnBothSidesOfIndex:(NSInteger)index
    left:(out id<iTermStatusBarComponent>*)leftOut
    right:(out id<iTermStatusBarComponent>*)rightOut {
    if (index == 0) {
        return NO;
    }
    if (index + 1 == views.count) {
        return NO;
    }
    id<iTermStatusBarComponent> left = views[index - 1].component;
    id<iTermStatusBarComponent> right = views[index + 1].component;
    if (![self componentIsSpacer:left] || ![self componentIsSpacer:right]) {
        return NO;
    }
    *leftOut = left;
    *rightOut = right;
    return YES;
}

- (CGFloat)minimumWidthOfContainerViews:(NSArray<iTermStatusBarContainerView *> *)views {
    iTermStatusBarContainerView *viewWithLargestMinimumWidth = [self containerViewWithLargestMinimumWidthFromViews:views];
    const CGFloat largestMinimumSize = viewWithLargestMinimumWidth.minimumWidthIncludingIcon;
    NSArray<iTermStatusBarContainerView *> *viewsExFixedSpacers = [self viewsExcludingFixedSpacers:views];
    const CGFloat widthOfAllFixedSpacers = [self widthOfFixedSpacersAmongViews:views];
    return largestMinimumSize * viewsExFixedSpacers.count + widthOfAllFixedSpacers;
}

- (NSArray<iTermStatusBarContainerView *> *)visibleContainerViewsAllowingEqualSpacingFromViews:(NSArray<iTermStatusBarContainerView *> *)visibleContainerViews {
    NSArray<iTermStatusBarContainerView *> *sortedViews = [self containerViewsSortedByPriority:visibleContainerViews];
    return [self visibleContainerViewsAllowingEqualSpacingFromSortedViews:sortedViews
                 orderedViews:visibleContainerViews];
}

- (NSArray<iTermStatusBarContainerView *> *)visibleContainerViewsAllowingEqualSpacingFromSortedViews:(NSArray<iTermStatusBarContainerView *> *)sortedViews
    orderedViews:(NSArray<iTermStatusBarContainerView *> *)orderedViews {
    if (_statusBarWidth >= [self minimumWidthOfContainerViews:orderedViews]) {
        return orderedViews;
    }
    if (orderedViews.count == 0) {
        return @[];
    }
    NSArray<iTermStatusBarContainerView *> *removalCandidates = sortedViews;
    if (self.mandatoryView) {
        removalCandidates = [removalCandidates arrayByRemovingObject:self.mandatoryView];
    }
    if (removalCandidates.count == 0) {
        return orderedViews;
    }
    iTermStatusBarContainerView *viewWithLargestMinimumWidth = [self bestViewToRemoveFrom:removalCandidates];
    iTermStatusBarContainerView *adjacentViewToRemove = [self viewToRemoveAdjacentToViewBeingRemoved:viewWithLargestMinimumWidth
                 fromViews:orderedViews];
    if (adjacentViewToRemove) {
        sortedViews = [sortedViews arrayByRemovingObject:adjacentViewToRemove];
        orderedViews = [orderedViews arrayByRemovingObject:adjacentViewToRemove];
    }
    sortedViews = [sortedViews arrayByRemovingObject:viewWithLargestMinimumWidth];
    orderedViews = [orderedViews arrayByRemovingObject:viewWithLargestMinimumWidth];
    return [self visibleContainerViewsAllowingEqualSpacingFromSortedViews:sortedViews
                 orderedViews:orderedViews];
}

// views are sorted ascending by priority. First remove spacers regardless of priority, then remove
// views from lowest to highest priority.
- (iTermStatusBarContainerView *)bestViewToRemoveFrom:(NSArray<iTermStatusBarContainerView *> *)views {
    if (views.count == 0) {
        return nil;
    }
    NSInteger (^score)(iTermStatusBarContainerView *) = ^NSInteger(iTermStatusBarContainerView *view) {
        if ([view.component isKindOfClass:[iTermStatusBarSpringComponent class]]) {
            return 2;
        }
        if ([view.component isKindOfClass:[iTermStatusBarFixedSpacerComponent class]]) {
            return 1;
        }
        return 0;
    };
    return [views maxWithComparator:^NSComparisonResult(iTermStatusBarContainerView *a, iTermStatusBarContainerView *b) {
              NSInteger aScore = score(a);
              NSInteger bScore = score(b);
        if (aScore == 0 && bScore == 0) {
            // Tiebreak by priority
            const double aPriority = a.component.statusBarComponentPriority;
            const double bPrioirty = b.component.statusBarComponentPriority;
            NSComparisonResult result = [@(bPrioirty) compare:@(aPriority)];  // Backwards so we score lower priority higher for removal
            if (result != NSOrderedSame) {
                return result;
            }

            // Tiebreak nonspacers by minimum width
            aScore = a.minimumWidthIncludingIcon;
            bScore = b.minimumWidthIncludingIcon;
            result = [@(aScore) compare:@(bScore)];
            if (result != NSOrderedSame) {
                return result;
            }

            // Tiebreak by index (prefer larger index)
            aScore = [views indexOfObject:a];
            bScore = [views indexOfObject:b];
        }
        return [@(aScore) compare:@(bScore)];
    }];
}

- (NSArray<iTermStatusBarContainerView *> *)visibleContainerViewsAllowingEqualSpacing {
    if (_statusBarWidth <= 0) {
        return @[];
    }
    return [self visibleContainerViewsAllowingEqualSpacingFromViews:[self allPossibleCandidateViews]];
}

- (iTermStatusBarContainerView *)viewToRemoveAdjacentToViewBeingRemoved:(iTermStatusBarContainerView *)viewBeingRemoved
    fromViews:(NSArray<iTermStatusBarContainerView *> *)views {
    NSInteger index = [views indexOfObject:viewBeingRemoved];
    assert(index != NSNotFound);
    id<iTermStatusBarComponent> left;
    id<iTermStatusBarComponent> right;
    if (![self views:views haveSpacersOnBothSidesOfIndex:[views indexOfObject:viewBeingRemoved] left:&left right:&right]) {
        return nil;
    }
    if (left.statusBarComponentSpringConstant > right.statusBarComponentSpringConstant) {
        return views[index - 1];
    } else if (left.statusBarComponentSpringConstant < right.statusBarComponentSpringConstant) {
        return views[index + 1];
    } else if (index < views.count / 2) {
        return views[index + 1];
    } else {
        return views[index - 1];
    }
}

- (NSArray<iTermStatusBarContainerView *> *)viewsExcludingFixedSpacers:(NSArray<iTermStatusBarContainerView *> *)views {
    return [views filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *view) {
              return ![view.component isKindOfClass:[iTermStatusBarFixedSpacerComponent class]];
          }];
}

- (NSArray<iTermStatusBarContainerView *> *)viewsExcludingPreallocatedViews:(NSArray<iTermStatusBarContainerView *> *)views {
    return [views filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *view) {
              return view.component.statusBarComponentPriority != INFINITY;
          }];
}

- (CGFloat)widthOfFixedSpacersAmongViews:(NSArray<iTermStatusBarContainerView *> *)views {
    return [[views reduceWithFirstValue:@0 block:^id(NSNumber *partialSum, iTermStatusBarContainerView *view) {
        if (![view.component isKindOfClass:[iTermStatusBarFixedSpacerComponent class]]) {
            return partialSum;
        }
        return @(partialSum.doubleValue + view.minimumWidthIncludingIcon);
    }] doubleValue];
}

- (double)sumOfSpringConstantsInViews:(NSArray<iTermStatusBarContainerView *> *)views {
    return [[views reduceWithFirstValue:@0 block:^id(NSNumber *partialSum, iTermStatusBarContainerView *view) {
        return @(partialSum.doubleValue + view.component.statusBarComponentSpringConstant);
    }] doubleValue];
}

- (CGFloat)preallocatedWidthInViews:(NSArray<iTermStatusBarContainerView *> *)views
    fromWidth:(CGFloat)totalWidth {
    NSArray<iTermStatusBarContainerView *> *preallocatedViews = [views filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *view) {
              return view.component.statusBarComponentPriority == INFINITY;
          }];
    if (preallocatedViews.count == 0) {
        // Normal case
        return 0;
    }
    const CGFloat singleUnitWidth = floor(totalWidth / views.count);
    const CGFloat sumOfPreferredSizesOfPreallocatedViews = round([[views mapWithBlock:^id(iTermStatusBarContainerView *view) {
        return @(MAX(MIN([self maximumWidthForComponent:view.component],
                         singleUnitWidth),
                     view.minimumWidthIncludingIcon));
    }] sumOfNumbers]);
    if (sumOfPreferredSizesOfPreallocatedViews <= totalWidth) {
        // Can use larger of min width or the standard 1-unit size for all preallocated views.
        __block CGFloat preallocation = 0;
        [preallocatedViews enumerateObjectsUsingBlock:^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
                              const CGFloat width = MAX(singleUnitWidth, view.minimumWidthIncludingIcon);
                              view.desiredWidth = width;
                              preallocation += width;
                          }];
        return preallocation;
    } else {
        // Not enough space. Divide all available space among preallocated views, leaving nothing for others.
        // Start by initializing all desired widths to 0.
        [preallocatedViews enumerateObjectsUsingBlock:^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop)  {
                              view.desiredWidth = 0;
                          }];

        // Assign totalWidth evenly, up to max size of each component.
        __block CGFloat available = totalWidth;
        __block CGFloat numberOfGrowableViews = preallocatedViews.count;
        __block CGFloat preallocation = 0;
        while (round(available) > 0 && available >= numberOfGrowableViews) {
            const CGFloat apportionment = floor(available / numberOfGrowableViews);
            numberOfGrowableViews = 0;
            [preallocatedViews enumerateObjectsUsingBlock:^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
                                  const CGFloat maxWidth = MAX([self minimumWidthForComponent:view.component],
                                             [self maximumWidthForComponent:view.component]);
                                  const CGFloat oldWidth = view.desiredWidth;
                                  const CGFloat newWidth = MIN(maxWidth, oldWidth + apportionment);
                if (round(newWidth) == round(oldWidth)) {
                    return;
                }
                view.desiredWidth = newWidth;
                const CGFloat growth = (newWidth - oldWidth);
                available -= growth;
                preallocation += growth;
                if (round(newWidth) < maxWidth) {
                    numberOfGrowableViews += 1;
                }
            }];
        }
        return preallocation;
    }
}

- (void)updateDesiredWidthsForViews:(NSArray<iTermStatusBarContainerView *> *)views {
    [self updateMargins:views];
    NSArray<iTermStatusBarContainerView *> *viewsExFixedSpacers = [self viewsExcludingFixedSpacers:views];
    const CGFloat widthOfAllFixedSpacers = [self widthOfFixedSpacersAmongViews:views];
    const CGFloat totalMarginWidth = [self totalMarginWidthForViews:views];
    const CGFloat availableWidthBeforePreallocation = _statusBarWidth - totalMarginWidth - widthOfAllFixedSpacers;
    const CGFloat preallocatedWidth = [self preallocatedWidthInViews:viewsExFixedSpacers
                                            fromWidth:availableWidthBeforePreallocation];
    CGFloat availableWidth = availableWidthBeforePreallocation - preallocatedWidth;
    NSArray<iTermStatusBarContainerView *> *viewsExPreallocatedViews = [self viewsExcludingPreallocatedViews:views];

    // Initialize desired width to 0 for non-preallocated views.
    for (iTermStatusBarContainerView *view in viewsExPreallocatedViews) {
        view.desiredWidth = 0;
    }

    // Distribute remaining space in proportion to spring constants.
    while (round(availableWidth) > 0 && viewsExPreallocatedViews.count > 0) {
        availableWidth = [self distributeNonPreallocatedAvailableWidth:availableWidth
                               amongViews:viewsExPreallocatedViews];
        viewsExPreallocatedViews = [viewsExPreallocatedViews filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *view) {
                                     return view.desiredWidth < [self maximumWidthForComponent:view.component];
                                 }];
    }
}

- (CGFloat)distributeNonPreallocatedAvailableWidth:(CGFloat)availableWidth
    amongViews:(NSArray<iTermStatusBarContainerView *> *)views {
    NSArray<iTermStatusBarContainerView *> *viewsExFixedSpacers =
    [views filteredArrayUsingBlock:^BOOL(iTermStatusBarContainerView *view) {
              return ![view.component isKindOfClass:[iTermStatusBarFixedSpacerComponent class]];
          }];
    const double sumOfSpringConstants = [self sumOfSpringConstantsInViews:viewsExFixedSpacers];
    const CGFloat apportionment = availableWidth / sumOfSpringConstants;
    __block CGFloat remainingWidth = availableWidth;
    DLog(@"updateDesiredWidthsForViews available=%@ apportionment=%@", @(availableWidth), @(apportionment));
    // Allocate minimum widths
    [views enumerateObjectsUsingBlock:^(iTermStatusBarContainerView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
              if ([view.component isKindOfClass:[iTermStatusBarFixedSpacerComponent class]]) {
                  view.desiredWidth = view.minimumWidthIncludingIcon;
                  return;
              }
        const CGFloat maxSize = [self maximumWidthForComponent:view.component];
        const CGFloat minSize = [self minimumWidthForComponent:view.component];
        const CGFloat oldWidth = view.desiredWidth;
        const CGFloat newWidth = MIN(MAX(minSize, maxSize), oldWidth + apportionment * view.component.statusBarComponentSpringConstant);
        view.desiredWidth = newWidth;
        const CGFloat growth = newWidth - oldWidth;
        remainingWidth -= growth;
    }];
    return remainingWidth;
}

- (NSArray<iTermStatusBarContainerView *> *)visibleContainerViews {
    NSArray<iTermStatusBarContainerView *> *visibleContainerViews = [self visibleContainerViewsAllowingEqualSpacing];

    [self updateDesiredWidthsForViews:visibleContainerViews];
    [self makeWidthsAndOriginsIntegers:visibleContainerViews];
    return visibleContainerViews;
}

@end
