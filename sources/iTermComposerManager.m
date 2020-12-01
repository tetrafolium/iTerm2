//
//  iTermComposerManager.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/31/20.
//

#import "iTermComposerManager.h"

#import "iTermMinimalComposerViewController.h"
#import "iTermStatusBarComposerComponent.h"
#import "iTermStatusBarViewController.h"
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"

@interface iTermComposerManager()<
    iTermMinimalComposerViewControllerDelegate,
    iTermStatusBarComposerComponentDelegate>
@end

@implementation iTermComposerManager {
    iTermStatusBarComposerComponent *_component;
    iTermStatusBarViewController *_statusBarViewController;
    iTermMinimalComposerViewController *_minimalViewController;
    NSString *_saved;
}

- (void)reveal {
    iTermStatusBarViewController *statusBarViewController = [self.delegate composerManagerStatusBarViewController:self];
    if (statusBarViewController) {
        [self showComposerInStatusBar:statusBarViewController];
    } else {
        [self showMinimalComposerInView:[self.delegate composerManagerContainerView:self]];
    }
}

- (void)showComposerInStatusBar:(iTermStatusBarViewController *)statusBarViewController {
    iTermStatusBarComposerComponent *component;
    component = [statusBarViewController visibleComponentWithIdentifier:[iTermStatusBarComposerComponent statusBarComponentIdentifier]];
    if (component) {
        [component makeFirstResponder];
        return;
    }
    component = [iTermStatusBarComposerComponent castFrom:_statusBarViewController.temporaryRightComponent];
    if (component && component == _component) {
        [component makeFirstResponder];
        return;
    }
    NSDictionary *knobs = @ { iTermStatusBarPriorityKey: @(INFINITY) };
    NSDictionary *configuration = @ { iTermStatusBarComponentConfigurationKeyKnobValues: knobs};
    iTermVariableScope *scope = [self.delegate composerManagerScope:self];
    component = [[iTermStatusBarComposerComponent alloc] initWithConfiguration:configuration
                                                         scope:scope];
    _statusBarViewController = statusBarViewController;
    _statusBarViewController.temporaryRightComponent = component;
    _component = component;
    _component.stringValue = _saved ?: @"";
    component.composerDelegate = self;
    [component makeFirstResponder];
}

- (void)showMinimalComposerInView:(NSView *)superview {
    if (_minimalViewController) {
        _saved = _minimalViewController.stringValue;
        [self dismissMinimalView];
        return;
    }
    _minimalViewController = [[iTermMinimalComposerViewController alloc] init];
    _minimalViewController.delegate = self;
    _minimalViewController.view.frame = NSMakeRect(20,
                                        superview.frame.size.height - _minimalViewController.view.frame.size.height,
                                        _minimalViewController.view.frame.size.width,
                                        _minimalViewController.view.frame.size.height);
    _minimalViewController.view.appearance = [self.delegate composerManagerAppearance:self];
    [superview addSubview:_minimalViewController.view];
    if (_saved.length) {
        _minimalViewController.stringValue = _saved ?: @"";
        _saved = nil;
    }
    [_minimalViewController updateFrame];
    [_minimalViewController makeFirstResponder];
    _dropDownComposerViewIsVisible = YES;
}

- (BOOL)dismiss {
    if (_dropDownComposerViewIsVisible) {
        _saved = _minimalViewController.stringValue;
        [self dismissMinimalView];
        return YES;
    }

    iTermStatusBarViewController *statusBarViewController = [self.delegate composerManagerStatusBarViewController:self];
    if (!statusBarViewController) {
        return NO;
    }
    iTermStatusBarComposerComponent *component;
    component = [statusBarViewController visibleComponentWithIdentifier:[iTermStatusBarComposerComponent statusBarComponentIdentifier]];
    if (!component) {
        return NO;
    }
    NSString *value = component.stringValue;
    const BOOL dismissed = [component dismiss];
    if (dismissed) {
        _saved = [value copy];
    }
    return dismissed;
}

- (void)layout {
    [_minimalViewController updateFrame];
}

#pragma mark - iTermStatusBarComposerComponentDelegate

- (void)statusBarComposerComponentDidEndEditing:(iTermStatusBarComposerComponent *)component {
    if (_statusBarViewController.temporaryRightComponent == _component &&
            component == _component) {
        _saved = _component.stringValue;
        _statusBarViewController.temporaryRightComponent = nil;
        _component = nil;
        [self.delegate composerManagerDidRemoveTemporaryStatusBarComponent:self];
    }
}

#pragma mark - iTermMinimalComposerViewControllerDelegate

- (void)minimalComposer:(nonnull iTermMinimalComposerViewController *)composer
    sendCommand:(nonnull NSString *)command {
    NSString *string = composer.stringValue;
    [self dismissMinimalView];
    if (command.length == 0) {
        _saved = string;
        return;
    }
    _saved = nil;
    [self.delegate composerManager:self sendCommand:[command stringByAppendingString:@"\n"]];
}

- (void)dismissMinimalView {
    NSViewController *vc = _minimalViewController;
    [NSView animateWithDuration:0.125
           animations:^ {
               vc.view.animator.alphaValue = 0;
           }
           completion:^(BOOL finished) {
        [vc.view removeFromSuperview];
    }];
    _minimalViewController = nil;
    _dropDownComposerViewIsVisible = NO;
    // You get into infinite recursion if you do ths inside resignFirstResponder.
    dispatch_async(dispatch_get_main_queue(), ^ {
        [self.delegate composerManagerDidDismissMinimalView:self];
    });
}

@end
