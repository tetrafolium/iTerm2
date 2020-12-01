//
//  iTermTabBarControlView.h
//  iTerm
//
//  Created by George Nachman on 5/29/14.
//
//

#import "PSMTabBarControl.h"

// If the superview conforms to this protocol then the willHide method gets
// called from -setHidden: and when the tabbar's alphaValue changes
// withsetAlphaValue:animated: then it also updates the alphaValue of its
// superview.
@protocol iTermTabBarControlViewContainer <NSObject>
- (void)tabBarControlViewWillHide:(BOOL)hidden;
@end

// NOTE: The delegate should nil out of itermTabBarDelegate when it gets
// dealloced; we may live on because of delayed performs.
@protocol iTermTabBarControlViewDelegate <NSObject>

- (BOOL)iTermTabBarShouldFlashAutomatically;
- (void)iTermTabBarWillBeginFlash;
- (void)iTermTabBarDidFinishFlash;
- (BOOL)iTermTabBarWindowIsFullScreen;
- (BOOL)iTermTabBarCanDragWindow;
- (BOOL)iTermTabBarShouldHideBacking;
@end

// A customized version of PSMTabBarControl.
@interface iTermTabBarControlView : PSMTabBarControl

@property(nonatomic, assign) id<iTermTabBarControlViewDelegate>
    itermTabBarDelegate;

// Set to yes when cmd pressed, no when released. We take care of the timing.
@property(nonatomic, assign) BOOL cmdPressed;

// Getter indicates if the tab bar is currently flashing. Setting starts or
// stops flashing. We take care of fading.
@property(nonatomic, assign) BOOL flashing;

// Call this when the result of iTermTabBarShouldFlash would change.
- (void)updateFlashing;

- (void)setAlphaValue:(CGFloat)alphaValue animated:(BOOL)animated;

@end
