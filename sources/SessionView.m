#import "SessionView.h"
#import "DebugLogging.h"
#import "FutureMethods.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAnnouncementViewController.h"
#import "iTermBackgroundColorView.h"
#import "iTermDropDownFindViewController.h"
#import "iTermFindDriver.h"
#import "iTermFindPasteboard.h"
#import "iTermGenericStatusBarContainer.h"
#import "iTermImageView.h"
#import "iTermIntervalTreeObserver.h"
#import "iTermMetalClipView.h"
#import "iTermMetalDeviceProvider.h"
#import "iTermPreferences.h"
#import "iTermSearchResultsMinimapView.h"
#import "iTermStatusBarContainerView.h"
#import "iTermStatusBarLayout.h"
#import "iTermStatusBarSearchFieldComponent.h"
#import "iTermStatusBarViewController.h"
#import "iTermTheme.h"
#import "iTermUnobtrusiveMessage.h"
#import "NSAppearance+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSView+iTerm.h"
#import "NSView+RecursiveDescription.h"
#import "MovePaneController.h"
#import "NSResponder+iTerm.h"
#import "PSMMinimalTabStyle.h"
#import "PSMTabDragAssistant.h"
#import "PTYScrollView.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PTYTextView.h"
#import "PTYWindow.h"
#import "SessionTitleView.h"
#import "SplitSelectionView.h"

#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>

static int nextViewId;

static const CGFloat iTermGetSessionViewTitleHeight() {
    return iTermGetStatusBarHeight() + 1;
}

// Last time any window was resized TODO(georgen):it would be better to track per window.
static NSDate* lastResizeDate_;

NSString *const SessionViewWasSelectedForInspectionNotification = @"SessionViewWasSelectedForInspectionNotification";

@interface iTermMTKView : MTKView
@end

@implementation iTermMTKView
@end

@interface iTermHoverContainerView : NSView
@property (nonatomic, copy) NSString *url;
@end

@implementation iTermHoverContainerView {
    NSVisualEffectView *_vev NS_AVAILABLE_MAC(10_14);
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        if (@available(macOS 10.14, *)) {
            const CGFloat radius = 4;
            _vev = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
            _vev.wantsLayer = YES;
            _vev.blendingMode = NSVisualEffectBlendingModeWithinWindow;
            _vev.material = NSVisualEffectMaterialSheet;
            _vev.state = NSVisualEffectStateActive;
            _vev.layer.cornerRadius = radius;
            [self addSubview:_vev positioned:NSWindowBelow relativeTo:self.subviews.firstObject];
            _vev.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
            self.autoresizesSubviews = YES;
        }
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    if (@available(macOS 10.14, *)) {
        return;
    }
    NSBezierPath *path = [NSBezierPath bezierPath];
    NSSize size = self.bounds.size;
    size.width -= 1.5;
    size.height -= 1.5;
    const CGFloat radius = 4;
    [path moveToPoint:NSMakePoint(0, 0)];
    [path lineToPoint:NSMakePoint(0, size.height)];
    [path lineToPoint:NSMakePoint(size.width - radius, size.height)];
    [path curveToPoint:NSMakePoint(size.width, size.height - radius)
          controlPoint1:NSMakePoint(size.width, size.height)
          controlPoint2:NSMakePoint(size.width, size.height)];
    [path lineToPoint:NSMakePoint(size.width, 0)];
    [path lineToPoint:NSMakePoint(0, 0)];

    [[NSColor darkGrayColor] setStroke];
    [[NSColor lightGrayColor] setFill];

    [path stroke];
    [path fill];
}

@end

@interface SessionView () <
    iTermAnnouncementDelegate,
    iTermFindDriverDelegate,
    iTermGenericStatusBarContainer,
    iTermSearchResultsMinimapViewDelegate,
    NSDraggingSource,
    PTYScrollerDelegate,
    SplitSelectionViewDelegate>
@property(nonatomic, strong) PTYScrollView *scrollview;
@end

@implementation SessionView {
    NSMutableArray *_announcements;
    BOOL _inDealloc;
    iTermAnnouncementViewController *_currentAnnouncement;

    BOOL _dim;
    BOOL _backgroundDimmed;

    // Saved size for unmaximizing.
    NSSize _savedSize;

    // When moving a pane, a view is put over all sessions to help the user
    // choose how to split the destination.
    SplitSelectionView *_splitSelectionView;

    BOOL _showTitle;
    BOOL _showBottomStatusBar;
    SessionTitleView *_title;

    iTermHoverContainerView *_hoverURLView;
    NSTextField *_hoverURLTextField;

    BOOL _useMetal;
    iTermMetalClipView *_metalClipView;
    iTermDropDownFindViewController *_dropDownFindViewController;
    iTermFindDriver *_dropDownFindDriver;
    iTermFindDriver *_permanentStatusBarFindDriver;
    iTermFindDriver *_temporaryStatusBarFindDriver;
    iTermGenericStatusBarContainer *_genericStatusBarContainer;
    iTermImageView *_imageView NS_AVAILABLE_MAC(10_14);
    NSColor *_terminalBackgroundColor;

    // For macOS 10.14+ when subpixel AA is turned on and the scroller style is legacy, this draws
    // some blended default background color under the vertical scroller. In all other conditions
    // its frame is 0x0.
    iTermBackgroundColorView *_legacyScrollerBackgroundView NS_AVAILABLE_MAC(10_14);
    iTermUnobtrusiveMessage *_unobtrusiveMessage;
}

+ (double)titleHeight {
    return iTermGetSessionViewTitleHeight();
}

+ (void)initialize {
    if (self == [SessionView self]) {
        lastResizeDate_ = [NSDate date];
    }
}

+ (void)windowDidResize {
    lastResizeDate_ = [NSDate date];
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self registerForDraggedTypes:@[ iTermMovePaneDragType, @"com.iterm2.psm.controlitem" ]];
        lastResizeDate_ = [NSDate date];
        _announcements = [[NSMutableArray alloc] init];

        if (@available(macOS 10.14, *)) {
            _imageView = [[iTermImageView alloc] init];
            _imageView.hidden = YES;
            _imageView.frame = NSMakeRect(0, 0, frame.size.width, frame.size.height);
            _imageView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            [self addSubview:_imageView];

            _backgroundColorView = [[iTermBackgroundColorView alloc] init];
            _backgroundColorView.layer = [[CALayer alloc] init];
            _backgroundColorView.wantsLayer = YES;
            _backgroundColorView.frame = NSMakeRect(0, 0, frame.size.width, frame.size.height);
            _backgroundColorView.layer.actions = @ {@"backgroundColor": [NSNull null]};
            [self addSubview:_backgroundColorView];

            _legacyScrollerBackgroundView = [[iTermBackgroundColorView alloc] init];
            _legacyScrollerBackgroundView.layer = [[CALayer alloc] init];
            _legacyScrollerBackgroundView.wantsLayer = YES;
            _legacyScrollerBackgroundView.frame = NSMakeRect(0, 0, 0, 0);
            _legacyScrollerBackgroundView.layer.actions = @ {@"backgroundColor": [NSNull null]};
            _legacyScrollerBackgroundView.hidden = YES;
            [self addSubview:_legacyScrollerBackgroundView];
        }

        // Set up find view
        _dropDownFindViewController = [self newDropDownFindView];
        _dropDownFindDriver = [[iTermFindDriver alloc] initWithViewController:_dropDownFindViewController];

        // Assign a globally unique view ID.
        _viewId = nextViewId++;

        // Allocate a scrollview
        NSRect aRect = self.frame;
        _scrollview = [[PTYScrollView alloc] initWithFrame:NSMakeRect(0,
                                             0,
                                             aRect.size.width,
                                             aRect.size.height)
                                             hasVerticalScroller:NO];
        self.verticalScroller.ptyScrollerDelegate = self;
        [_scrollview setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

        if (@available(macOS 10.11, *)) {
            _metalClipView = [[iTermMetalClipView alloc] initWithFrame:_scrollview.contentView.frame];
            _metalClipView.metalView = _metalView;
            _scrollview.contentView = _metalClipView;
            _scrollview.drawsBackground = NO;
        }

        _scrollview.contentView.copiesOnScroll = NO;

        // assign the main view
        [self addSubviewBelowFindView:_scrollview];

        if (@available(macOS 10.14, *)) {
            if ([iTermAdvancedSettingsModel showLocationsInScrollbar]) {
                _searchResultsMinimap = [[iTermSearchResultsMinimapView alloc] init];
                _searchResultsMinimap.delegate = self;
                [self addSubviewBelowFindView:_searchResultsMinimap];
                iTermTuple<NSColor *, NSColor *> *(^tuple)(NSColor *) = ^iTermTuple<NSColor *, NSColor *> *(NSColor *color) {
                    NSColor *saturated = [NSColor colorWithHue:color.hueComponent
                                                  saturation:1
                                                  brightness:1
                                                  alpha:1];
                    return [iTermTuple tupleWithObject:saturated
                                       andObject:[saturated colorDimmedBy:0.2 towardsGrayLevel:1]];
                };
                // This order must match the iTermIntervalTreeObjectType enum.
                NSArray<iTermTuple<NSColor *, NSColor *> *> *colors = @[
                // Blue mark
                tuple([iTermTextDrawingHelper successMarkColor]),

                // Yellow mark
                [iTermTuple tupleWithObject:[iTermTextDrawingHelper otherMarkColor]
                andObject:[[iTermTextDrawingHelper otherMarkColor] colorDimmedBy:0.2 towardsGrayLevel:1]],

                // Red mark
                tuple([iTermTextDrawingHelper errorMarkColor]),

                // Manually created mark or prompt without code
                [iTermTuple tupleWithObject:[NSColor colorWithWhite:0.5 alpha:1]
                andObject:[NSColor colorWithWhite:0.7 alpha:1]],

                // Annotation
                tuple([NSColor colorWithSRGBRed:1 green:1 blue:0 alpha:1]),

                ];
                _marksMinimap = [[iTermIncrementalMinimapView alloc] initWithColors:colors];
                [self addSubviewBelowFindView:_marksMinimap];
            }
        }

#if ENABLE_LOW_POWER_GPU_DETECTION
        if (@available(macOS 10.11, *)) {
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                  selector:@selector(preferredMetalDeviceDidChange:)
                                                  name:iTermMetalDeviceProviderPreferredDeviceDidChangeNotification
                                                  object:nil];
        }
#endif
        if (@available(macOS 10.14, *)) {
            if (PTYScrollView.shouldDismember) {
                [self addSubviewBelowFindView:_scrollview.verticalScroller];
                _scrollview.verticalScroller.frame = [self frameForScroller];
            }
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                  selector:@selector(scrollerStyleDidChange:)
                                                  name:@"NSPreferredScrollerStyleDidChangeNotification"
                                                  object:nil];
        }
    }
    return self;
}

- (void)setImage:(NSImage *)image {
    if (@available(macOS 10.14, *)) {
        if (image) {
            _imageView.image = image;
        }
        [self updateImageAndBackgroundViewVisibility];
    }
}

- (NSImage *)image {
    if (@available(macOS 10.14, *)) {
        if (_imageView.hidden) {
            return nil;
        }
        return _imageView.image;
    }
    return nil;
}

- (void)setImageMode:(iTermBackgroundImageMode)imageMode {
    if (@available(macOS 10.14, *)) {
        _imageMode = imageMode;
        _imageView.contentMode = imageMode;
    }
}

- (void)setTerminalBackgroundColor:(NSColor *)color {
    if (@available(macOS 10.14, *)) {
        if ([NSObject object:_terminalBackgroundColor isEqualToObject:color]) {
            return;
        }
        _terminalBackgroundColor = color;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];

        _imageView.backgroundColor = color;
        _legacyScrollerBackgroundView.backgroundColor = color;
        _backgroundColorView.backgroundColor = color;

        DLog(@"setTerminalBackgroundColor:%@ %@\n%@", color, self.delegate, [NSThread callStackSymbols]);
        if (color && _metalView.alphaValue < 1) {
            _backgroundColorView.hidden = !iTermTextIsMonochrome();
            _legacyScrollerBackgroundView.hidden = iTermTextIsMonochrome();
        } else {
            _backgroundColorView.hidden = YES;
            _legacyScrollerBackgroundView.hidden = YES;
        }
        [CATransaction commit];
        [self updateMinimapAlpha];
    }
}

- (void)setTransparencyAlpha:(CGFloat)transparencyAlpha
    blend:(CGFloat)blend {
    if (@available(macOS 10.14, *)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _backgroundColorView.transparency = 1 - transparencyAlpha;
        _backgroundColorView.blend = blend;
        if (![iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
            // This is unfortunate but because I can't use an imageview behind everything when
            // subpixel AA is enabled, I have to draw *something* behind the legacy scrollers.
            // NSImageView is not equipped to do the job.
            _legacyScrollerBackgroundView.transparency = 0;
            _legacyScrollerBackgroundView.blend = 0;
        } else {
            _legacyScrollerBackgroundView.transparency = 1 - transparencyAlpha;
            _legacyScrollerBackgroundView.blend = blend;
        }
        _imageView.transparency = 1 - transparencyAlpha;
        _imageView.blend = blend;
        [CATransaction commit];
    }
}

- (NSRect)frameForScroller NS_AVAILABLE_MAC(10_14) {
    [_scrollview.verticalScroller sizeToFit];
    NSSize size = _scrollview.verticalScroller.frame.size;
    NSSize mySize = self.bounds.size;
    NSRect frame = NSMakeRect(mySize.width - size.width, 0, size.width, mySize.height);
    return frame;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _inDealloc = YES;
    if (self.verticalScroller.ptyScrollerDelegate == self) {
        self.verticalScroller.ptyScrollerDelegate = nil;
    }
    [_title removeFromSuperview];
    [self unregisterDraggedTypes];
    [_currentAnnouncement dismiss];
    while (self.trackingAreas.count) {
        [self removeTrackingArea:self.trackingAreas[0]];
    }
    _metalView.delegate = nil;
}

- (iTermDropDownFindViewController *)newDropDownFindView {
    NSString *nibName;
    if ([iTermAdvancedSettingsModel useOldStyleDropDownViews]) {
        nibName = @"FindView";
    } else {
        nibName = @"MinimalFindView";
    }

    iTermDropDownFindViewController *dropDownViewController =
        [[iTermDropDownFindViewController alloc] initWithNibName:nibName
                                                 bundle:[NSBundle bundleForClass:self.class]];
    [[dropDownViewController view] setHidden:YES];
    [super addSubview:dropDownViewController.view];
    NSRect aRect = [self frame];
    NSSize size = [[dropDownViewController view] frame].size;
    [dropDownViewController setFrameOrigin:NSMakePoint(aRect.size.width - size.width - 30,
                                   aRect.size.height - size.height)];
    return dropDownViewController;
}

- (BOOL)isDropDownSearchVisible {
    return _findDriverType == iTermSessionViewFindDriverDropDown && _dropDownFindDriver.isVisible;
}

- (void)setFindDriverDelegate:(id<iTermFindDriverDelegate>)delegate {
    _dropDownFindDriver.delegate = delegate;
    _temporaryStatusBarFindDriver.delegate = delegate;
    _permanentStatusBarFindDriver.delegate = delegate;
}

- (id<iTermFindDriverDelegate>)findDriverDelegate {
    return _dropDownFindDriver.delegate;
}

- (BOOL)findViewHasKeyboardFocus {
    switch (_findDriverType) {
    case iTermSessionViewFindDriverDropDown:
        return !_dropDownFindDriver.isVisible;
    case iTermSessionViewFindDriverPermanentStatusBar:
        return NO;
    case iTermSessionViewFindDriverTemporaryStatusBar:
        return !_temporaryStatusBarFindDriver.isVisible;
    }
    assert(false);
    return YES;
}

- (BOOL)findViewIsHidden {

    switch (_findDriverType) {
    case iTermSessionViewFindDriverDropDown:
        return !_dropDownFindDriver.isVisible;
    case iTermSessionViewFindDriverPermanentStatusBar:
        return NO;
    case iTermSessionViewFindDriverTemporaryStatusBar:
        return self.delegate.sessionViewStatusBarViewController.temporaryLeftComponent == nil;
    }
    assert(false);
    return YES;
}

- (iTermFindDriver *)findDriver {
    switch (_findDriverType) {
    case iTermSessionViewFindDriverDropDown:
        return _dropDownFindDriver;
    case iTermSessionViewFindDriverPermanentStatusBar:
        return _permanentStatusBarFindDriver;
    case iTermSessionViewFindDriverTemporaryStatusBar:
        return _temporaryStatusBarFindDriver;
    }
    assert(false);
    return nil;
}

- (NSSize)internalDecorationSize {
    NSSize size = NSZeroSize;
    if (_showTitle) {
        size.height += _title.frame.size.height;
    }
    if (_showBottomStatusBar) {
        size.height += iTermGetStatusBarHeight();
    }
    return size;
}

- (void)loadTemporaryStatusBarFindDriverWithStatusBarViewController:(iTermStatusBarViewController *)statusBarViewController {
    NSString *query = [[iTermFindPasteboard sharedInstance] stringValue] ?: @"";
    _findDriverType = iTermSessionViewFindDriverTemporaryStatusBar;
    NSDictionary *knobs = @ { iTermStatusBarPriorityKey:
                              @(INFINITY),
                              iTermStatusBarSearchComponentIsTemporaryKey:
                              @YES
                            };
    NSDictionary *configuration = @ { iTermStatusBarComponentConfigurationKeyKnobValues: knobs};
    iTermStatusBarSearchFieldComponent *component =
        [[iTermStatusBarSearchFieldComponent alloc] initWithConfiguration:configuration
                                                    scope:self.delegate.sessionViewScope];
    _temporaryStatusBarFindDriver = [[iTermFindDriver alloc] initWithViewController:component.statusBarComponentSearchViewController];
    _temporaryStatusBarFindDriver.delegate = _dropDownFindDriver.delegate;
    _temporaryStatusBarFindDriver.findString = query;
    component.statusBarComponentSearchViewController.driver = _temporaryStatusBarFindDriver;
    statusBarViewController.temporaryLeftComponent = component;
    [_temporaryStatusBarFindDriver open];
}

- (void)showFindUI {
    iTermStatusBarViewController *statusBarViewController = self.delegate.sessionViewStatusBarViewController;
    if (_findDriverType == iTermSessionViewFindDriverPermanentStatusBar) {
        statusBarViewController.mustShowSearchComponent = YES;
    } else if (self.findViewIsHidden) {
        if (statusBarViewController) {
            if (!statusBarViewController.temporaryLeftComponent) {
                [self loadTemporaryStatusBarFindDriverWithStatusBarViewController:statusBarViewController];
            }
        } else {
            _findDriverType = iTermSessionViewFindDriverDropDown;
            [_temporaryStatusBarFindDriver open];
        }
    } else if (self.findDriver == nil) {
        assert(statusBarViewController);
        assert(statusBarViewController.temporaryLeftComponent);
        _temporaryStatusBarFindDriver = [[iTermFindDriver alloc] initWithViewController:statusBarViewController.temporaryLeftComponent.statusBarComponentSearchViewController];
        _temporaryStatusBarFindDriver.delegate = _dropDownFindDriver.delegate;
        [_temporaryStatusBarFindDriver open];
    }
    [self.findDriver makeVisible];
}

- (void)findViewDidHide {
    self.delegate.sessionViewStatusBarViewController.mustShowSearchComponent = NO;
    self.delegate.sessionViewStatusBarViewController.temporaryLeftComponent = nil;
}

- (BOOL)useMetal {
    return _useMetal;
}

- (void)setUseMetal:(BOOL)useMetal dataSource:(id<iTermMetalDriverDataSource>)dataSource NS_AVAILABLE_MAC(10_11) {
    if (useMetal != _useMetal) {
        _useMetal = useMetal;
        DLog(@"setUseMetal:%@ dataSource:%@", @(useMetal), dataSource);
        if (useMetal) {
            [self installMetalViewWithDataSource:dataSource];
        } else {
            [self removeMetalView];
        }

        iTermMetalClipView *metalClipView = (iTermMetalClipView *)_scrollview.contentView;
        metalClipView.useMetal = useMetal;

        [self updateLayout];
        [self setNeedsDisplay:YES];
    }
}

- (void)preferredMetalDeviceDidChange:(NSNotification *)notification NS_AVAILABLE_MAC(10_11) {
    if (_metalView) {
        [self.delegate sessionViewRecreateMetalView];
    }
}

- (id<MTLDevice>)metalDevice {
    static id<MTLDevice> chosenDevice;
    static BOOL preferIntegrated;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^ {
        preferIntegrated = [iTermPreferences boolForKey:kPreferenceKeyPreferIntegratedGPU];
        if (preferIntegrated) {
            NSArray<id<MTLDevice>> *devices = MTLCopyAllDevices();

            id<MTLDevice> gpu = nil;

            for (id<MTLDevice> device in devices) {
                if (device.isLowPower) {
                    gpu = device;
                    break;
                }
            }

            if (!gpu) {
                gpu = MTLCreateSystemDefaultDevice();
            }
            // I'm intentionally leaking devices and gpu because I'm seeing crazy crashes where
            // metal occasionally thinks something is over-released. There's no reason to do that
            // dangerous dance here.
            chosenDevice = gpu;
        } else {
            static id<MTLDevice> device;
            static dispatch_once_t once;
            dispatch_once(&once, ^ {
                device = MTLCreateSystemDefaultDevice();
            });
            chosenDevice = device;
        }
    });
    return chosenDevice;
}

- (void)installMetalViewWithDataSource:(id<iTermMetalDriverDataSource>)dataSource NS_AVAILABLE_MAC(10_11) {
    if (_metalView) {
        [self removeMetalView];
    }
    // Allocate a new metal view
    _metalView = [[iTermMTKView alloc] initWithFrame:_scrollview.contentView.frame
                                       device:[self metalDevice]];
#if ENABLE_TRANSPARENT_METAL_WINDOWS
    if (iTermTextIsMonochrome()) {
        _metalView.layer.opaque = NO;
    } else {
        _metalView.layer.opaque = YES;
    }
#else
    _metalView.layer.opaque = YES;
#endif
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    _metalView.colorspace = colorSpace;
    CFRelease(colorSpace);

    // Tell the clip view about it so it can ask the metalview to draw itself on scroll.
    _metalClipView.metalView = _metalView;

    if (@available(macOS 10.14, *)) {
        // Image view and background color view go under it.
        [self insertSubview:_metalView atIndex:2];
    } else {
        [self insertSubview:_metalView atIndex:0];
    }

    // Configure and hide the metal view. It will be shown by PTYSession after it has rendered its
    // first frame. Until then it's just a solid gray rectangle.
    _metalView.paused = YES;
    _metalView.enableSetNeedsDisplay = NO;
    _metalView.hidden = NO;
    _metalView.alphaValue = 0;

    // Start the metal driver going. It will receive delegate calls from MTKView that kick off
    // frame rendering.
    _driver = [[iTermMetalDriver alloc] initWithDevice:_metalView.device];
    _driver.dataSource = dataSource;
    [_driver mtkView:_metalView drawableSizeWillChange:_metalView.drawableSize];
    _metalView.delegate = _driver;
    [self metalViewVisibilityDidChange];
}

- (void)removeMetalView NS_AVAILABLE_MAC(10_11) {
    _metalView.delegate = nil;
    [_metalView removeFromSuperview];
    _metalView = nil;
    _driver = nil;
    _metalClipView.useMetal = NO;
    _metalClipView.metalView = nil;
    [self metalViewVisibilityDidChange];
}

- (void)setMetalViewNeedsDisplayInTextViewRect:(NSRect)textViewRect NS_AVAILABLE_MAC(10_11) {
    if (_useMetal) {
        // TODO: Would be nice to draw only the rect, but I don't see a way to do that with MTKView
        // that doesn't involve doing something nutty like saving a copy of the drawable.
        [_metalView setNeedsDisplay:YES];
        [_scrollview setNeedsDisplay:YES];
    }
}

- (void)didChangeMetalViewAlpha {
    [self metalViewVisibilityDidChange];
}

- (void)metalViewVisibilityDidChange {
    [self updateImageAndBackgroundViewVisibility];
}

- (void)updateImageAndBackgroundViewVisibility {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (_metalView.alphaValue == 0) {
        _imageView.hidden = (_imageView.image == nil);
        _backgroundColorView.hidden = !iTermTextIsMonochrome();
        _legacyScrollerBackgroundView.hidden = iTermTextIsMonochrome();
    } else {
        _imageView.hidden = YES;
        _backgroundColorView.hidden = YES;
        _legacyScrollerBackgroundView.hidden = YES;
    }
    [CATransaction commit];
}

- (void)tabColorDidChange {
    [_title updateBackgroundColor];
}

- (void)setNeedsDisplay:(BOOL)needsDisplay {
    [super setNeedsDisplay:needsDisplay];
    [_title updateBackgroundColor];
    if (@available(macOS 10.11, *)) {
        if (needsDisplay) {
            [_metalView setNeedsDisplay:YES];
            [_title setNeedsDisplay:YES];
            [_genericStatusBarContainer setNeedsDisplay:YES];
        }
    }
}

- (void)addSubviewBelowFindView:(NSView *)aView {
    if ([aView isKindOfClass:[PTYScrollView class]]) {
        NSInteger i = [self.subviews indexOfObjectPassingTest:^BOOL(__kindof NSView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                          return [obj isKindOfClass:[MTKView class]];
                      }];
        if (i != NSNotFound) {
            // Insert scrollview after metal view
            [self addSubview:aView positioned:NSWindowAbove relativeTo:self.subviews[i]];
            return;
        }
    }
    if ([aView isKindOfClass:[MTKView class]]) {
        NSInteger i = [self.subviews indexOfObjectPassingTest:^BOOL(__kindof NSView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                          return [obj isKindOfClass:[PTYScrollView class]];
                      }];
        if (i != NSNotFound) {
            // Insert metal view before scroll view
            [self addSubview:aView positioned:NSWindowBelow relativeTo:self.subviews[i]];
            return;
        }
    }
    if (_dropDownFindViewController.view && [self.subviews containsObject:_dropDownFindViewController.view]) {
        [self addSubview:aView positioned:NSWindowBelow relativeTo:[_dropDownFindViewController view]];
    } else {
        [super addSubview:aView];
    }
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldBoundsSize {
    [self updateLayout];
}

- (NSRect)frameForLegacyScroller {
    if (!_scrollview.isLegacyScroller) {
        return NSZeroRect;
    }
    return [_scrollview.verticalScroller convertRect:_scrollview.verticalScroller.bounds
                                         toView:self];
}

- (void)scrollerStyleDidChange:(NSNotification *)notification {
    [self updateLayout];
}

- (void)updateLayout {
    DLog(@"PTYSession begin updateLayout. delegate=%@\n%@", _delegate, [NSThread callStackSymbols]);
    DLog(@"Before:\n%@", [self iterm_recursiveDescription]);
    if ([_delegate sessionViewShouldUpdateSubviewsFramesAutomatically]) {
        DLog(@"Automatically updating subview frames");
        if (self.showTitle) {
            [self updateTitleFrame];
        } else {
            [self updateScrollViewFrame];
            [self updateFindViewFrame];
        }
        if (self.showBottomStatusBar) {
            [self updateBottomStatusBarFrame];
        }
    } else {
        DLog(@"Keep everything top aligned.");
        // Don't resize anything but do keep it all top-aligned.
        if (self.showTitle) {
            NSRect aRect = [self frame];
            CGFloat maxY = aRect.size.height;

            maxY -= _title.frame.size.height;
            [_title setFrame:NSMakeRect(0,
                                        maxY,
                                        _title.frame.size.width,
                                        _title.frame.size.height)];

            NSRect frame = _scrollview.frame;
            maxY -= frame.size.height;
            frame.origin.y = maxY;
            _scrollview.frame = frame;
            if (@available(macOS 10.14, *)) {
                if (PTYScrollView.shouldDismember) {
                    _scrollview.verticalScroller.frame = [self frameForScroller];
                }
            }
        }
        if (_showBottomStatusBar) {
            _genericStatusBarContainer.frame = NSMakeRect(0,
                                               0,
                                               self.frame.size.width,
                                               _genericStatusBarContainer.frame.size.height);
        }
        if (@available(macOS 10.14, *)) {
            NSRect frame = _imageView.frame;
            frame.origin.x = 0;
            frame.origin.y = self.bounds.size.height - frame.size.height;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            _imageView.frame = frame;
            _backgroundColorView.frame = frame;
            _legacyScrollerBackgroundView.frame = [self frameForLegacyScroller];
            [CATransaction commit];
        }
    }
    if (@available(macOS 10.14, *)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _imageView.frame = self.bounds;
        _backgroundColorView.frame = self.bounds;
        _legacyScrollerBackgroundView.frame = [self frameForLegacyScroller];
        [CATransaction commit];
    }

    if (_hoverURLView) {
        [_hoverURLTextField sizeToFit];
        NSRect frame = _hoverURLTextField.bounds;
        const CGFloat horizontalPadding = 8;
        const CGFloat verticalPadding = 4;
        frame.size.width += horizontalPadding * 2;
        frame.size.height += verticalPadding * 2;
        if (@available(macOS 10.14, *)) {
            frame.origin.x = 4;
            frame.origin.y = 4;
        }
        _hoverURLView.frame = frame;

        frame = _hoverURLTextField.frame;
        frame.origin = NSMakePoint(horizontalPadding, verticalPadding);
        _hoverURLTextField.frame = frame;
    }
    [self updateAnnouncementFrame];

    if (_useMetal) {
        [self updateMetalViewFrame];
    }
    DLog(@"After:\n%@", [self iterm_recursiveDescription]);
}

- (void)didBecomeVisible {
    [[self.delegate sessionViewStatusBarViewController] updateColors];
}

- (void)updateMetalViewFrame {
    DLog(@"update metalView frame");
    // The metal view looks awful while resizing because it insists on scaling
    // its contents. Just switch off the metal renderer until it catches up.
    [_delegate sessionViewNeedsMetalFrameUpdate];
}

- (void)reallyUpdateMetalViewFrame {
    if (@available(macOS 10.14, *)) {
        _metalView.frame = self.bounds;
    } else {
        NSRect frame = _scrollview.contentView.frame;
        if (self.showBottomStatusBar) {
            frame.origin.y += iTermGetStatusBarHeight();
        }
        _metalView.frame = [self frameByInsettingForMetal:frame];
    }
    [_driver mtkView:_metalView drawableSizeWillChange:_metalView.drawableSize];
}

- (NSRect)frameByInsettingForMetal:(NSRect)frame {
    if (@available(macOS 10.14, *)) {
        return frame;
    } else {
        return NSInsetRect(frame, 1, [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins]);
    }
}

- (void)setDelegate:(id<iTermSessionViewDelegate>)delegate {
    _delegate = delegate;
    [_delegate sessionViewDimmingAmountDidChange:[self adjustedDimmingAmount]];
    [self updateLayout];
}

- (void)_dimShadeToDimmingAmount:(float)newDimmingAmount {
    [_delegate sessionViewDimmingAmountDidChange:newDimmingAmount];
}

- (double)dimmedDimmingAmount {
    return [iTermPreferences floatForKey:kPreferenceKeyDimmingAmount];
}

- (double)adjustedDimmingAmount {
    int x = 0;
    if (_dim) {
        x++;
    }
    if (_backgroundDimmed) {
        x++;
    }
    double scale[] = { 0, 1.0, 1.5 };
    double amount = scale[x] * [self dimmedDimmingAmount];
    // Cap amount within reasonable bounds. Before 1.1, dimming amount was only changed by
    // twiddling the prefs file so it could have all kinds of crazy values.
    amount = MIN(0.9, amount);
    amount = MAX(0, amount);

    return amount;
}

- (void)updateDim {
    double amount = [self adjustedDimmingAmount];

    [self _dimShadeToDimmingAmount:amount];
    [_title setDimmingAmount:amount];
    iTermStatusBarViewController *statusBar = self.delegate.sessionViewStatusBarViewController;
    [statusBar updateColors];
}

- (void)updateColors {
    [_title updateTextColor];
}

- (void)setDimmed:(BOOL)isDimmed {
    if (isDimmed == _dim) {
        return;
    }
    if ([_delegate sessionViewIsVisible]) {
        _dim = isDimmed;
        [self updateDim];
    } else {
        _dim = isDimmed;
    }
}

- (void)setBackgroundDimmed:(BOOL)backgroundDimmed {
    BOOL orig = _backgroundDimmed;
    if ([iTermPreferences boolForKey:kPreferenceKeyDimBackgroundWindows]) {
        _backgroundDimmed = backgroundDimmed;
    } else {
        _backgroundDimmed = NO;
    }
    if (_backgroundDimmed != orig) {
        [self updateDim];
        [self setNeedsDisplay:YES];
    }
}

// It's very expensive for PTYTextView to own its own tracking events because its frame changes
// constantly, plus it can miss mouse exit events and spurious mouse enter events (issue 3345).
// I believe it also caused hangs (issue 3974).
- (void)updateTrackingAreas {
    if ([self window]) {
        int trackingOptions;
        trackingOptions = (NSTrackingMouseEnteredAndExited |
                           NSTrackingActiveAlways |
                           NSTrackingEnabledDuringMouseDrag |
                           NSTrackingMouseMoved);
        while (self.trackingAreas.count) {
            [self removeTrackingArea:self.trackingAreas[0]];
        }
        NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                               options:trackingOptions
                                                               owner:self
                                                               userInfo:nil];
        [self addTrackingArea:trackingArea];
    }
}

- (void)mouseEntered:(NSEvent *)theEvent {
    [_delegate sessionViewMouseEntered:theEvent];
}

- (void)mouseExited:(NSEvent *)theEvent {
    [_delegate sessionViewMouseExited:theEvent];
}

- (void)mouseMoved:(NSEvent *)theEvent {
    [_delegate sessionViewMouseMoved:theEvent];
}

- (void)rightMouseDown:(NSEvent*)event {
    if (!_splitSelectionView) {
        static int inme;
        if (inme) {
            // Avoid infinite recursion. Not quite sure why this happens, but a call
            // to -[PTYTextView rightMouseDown:] will sometimes (after a
            // few steps through the OS) bring you back here. It happens when randomly touching
            // a bunch of fingers on the trackpad.
            return;
        }
        ++inme;
        [_delegate sessionViewRightMouseDown:event];
        --inme;
    }
}


- (void)mouseDown:(NSEvent*)event {
    static int inme;
    if (inme) {
        // Avoid infinite recursion. Not quite sure why this happens, but a call
        // to [_title mouseDown:] or [super mouseDown:] will sometimes (after a
        // few steps through the OS) bring you back here. It only happens
        // consistently when dragging the pane title bar, but it happens inconsistently
        // with clicks in the title bar too.
        return;
    }
    ++inme;
    // A click on the very top of the screen while in full screen mode may not be
    // in any subview!
    NSPoint p = [NSEvent mouseLocation];
    NSPoint pointInSessionView;
    NSRect windowRect = [self.window convertRectFromScreen:NSMakeRect(p.x, p.y, 0, 0)];
    pointInSessionView = [self convertRect:windowRect fromView:nil].origin;
    DLog(@"Point in screen coords=%@, point in window coords=%@, point in session view=%@",
         NSStringFromPoint(p),
         NSStringFromPoint(windowRect.origin),
         NSStringFromPoint(pointInSessionView));
    if (_title && NSPointInRect(pointInSessionView, [_title frame])) {
        [_title mouseDown:event];
        --inme;
        return;
    }
    if (_splitSelectionView) {
        [_splitSelectionView mouseDown:event];
    } else if (NSPointInRect(pointInSessionView, [[self scrollview] frame]) &&
               [_delegate sessionViewShouldForwardMouseDownToSuper:event]) {
        [super mouseDown:event];
    }
    --inme;
}

- (void)setFrameSize:(NSSize)frameSize {
    [self updateAnnouncementFrame];
    [super setFrameSize:frameSize];
    NSView *findView = _dropDownFindViewController.view;
    if (frameSize.width < 340) {
        [findView setFrameSize:NSMakeSize(MAX(150, frameSize.width - 50),
                                          [findView frame].size.height)];
        [_dropDownFindViewController setFrameOrigin:NSMakePoint(frameSize.width - [findView frame].size.width - 30,
                                            frameSize.height - [findView frame].size.height)];
    } else {
        [findView setFrameSize:NSMakeSize(290,
                                          [findView frame].size.height)];
        [_dropDownFindViewController setFrameOrigin:NSMakePoint(frameSize.width - [findView frame].size.width - 30,
                                            frameSize.height - [findView frame].size.height)];
    }
}

+ (NSDate *)lastResizeDate {
    return lastResizeDate_;
}

// This is called as part of the live resizing protocol when you let up the mouse button.
- (void)viewDidEndLiveResize {
    lastResizeDate_ = [NSDate date];
}

- (void)saveFrameSize {
    _savedSize = [self frame].size;
}

- (void)restoreFrameSize {
    [self setFrameSize:_savedSize];
}

- (void)createSplitSelectionViewWithMode:(SplitSelectionViewMode)mode session:(id)session {
    id<SplitSelectionViewDelegate> delegate;
    switch (mode) {
    case SplitSelectionViewModeTargetSwap:
    case SplitSelectionViewModeTargetMove:
    case SplitSelectionViewModeSourceSwap:
    case SplitSelectionViewModeSourceMove:
        delegate = [MovePaneController sharedInstance];
        break;
    case SplitSelectionViewModeInspect:
        delegate = self;
        break;
    }
    _splitSelectionView = [[SplitSelectionView alloc] initWithMode:mode
                                                      withFrame:NSMakeRect(0,
                                                              0,
                                                              [self frame].size.width,
                                                              [self frame].size.height)
                                                      session:session
                                                      delegate:delegate];
    _splitSelectionView.wantsLayer = [iTermPreferences boolForKey:kPreferenceKeyUseMetal];
    [_splitSelectionView setFrameOrigin:NSMakePoint(0, 0)];
    [_splitSelectionView setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
    [self addSubviewBelowFindView:_splitSelectionView];
}

- (void)setSplitSelectionMode:(SplitSelectionMode)mode move:(BOOL)move session:(id)session {
    switch (mode) {
    case kSplitSelectionModeOn:
        if (_splitSelectionView) {
            return;
        }
        if (move) {
            [self createSplitSelectionViewWithMode:SplitSelectionViewModeTargetMove session:session];
        } else {
            [self createSplitSelectionViewWithMode:SplitSelectionViewModeTargetSwap session:session];
        }
        break;

    case kSplitSelectionModeOff:
        [_splitSelectionView removeFromSuperview];
        _splitSelectionView = nil;
        break;

    case kSplitSelectionModeCancel:
        if (move) {
            [self createSplitSelectionViewWithMode:SplitSelectionViewModeSourceMove session:session];
        } else {
            [self createSplitSelectionViewWithMode:SplitSelectionViewModeSourceSwap session:session];
        }
        break;

    case kSplitSelectionModeInspect:
        [self createSplitSelectionViewWithMode:SplitSelectionViewModeInspect session:session];
        break;
    }
}

- (void)drawBackgroundInRect:(NSRect)rect {
    [_delegate sessionViewDrawBackgroundImageInView:self
               viewRect:rect
               blendDefaultBackground:YES];
}

- (NSColor *)backgroundColorForDecorativeSubviews {
    return [[iTermTheme sharedInstance] backgroundColorForDecorativeSubviewsInSessionWithTabColor:self.tabColor
                                        effectiveAppearance:self.effectiveAppearance
                                        sessionBackgroundColor:[_delegate sessionViewBackgroundColor]
                                        isFirstResponder:[_delegate sessionViewTerminalIsFirstResponder]
                                        dimOnlyText:[_delegate sessionViewShouldDimOnlyText]
                                        adjustedDimmingAmount:[self adjustedDimmingAmount]];
}

- (void)drawRect:(NSRect)dirtyRect {
    if (@available(macOS 10.14, *)) {
        return;
    }
    // Fill in background color in the area around a scrollview if it's smaller
    // than the session view.
    [super drawRect:dirtyRect];
    if (_useMetal && _metalView.alphaValue == 1) {
        [self drawAroundFrame:_metalView.frame dirtyRect:dirtyRect];
    } else {
        NSRect frame = self.scrollview.frame;
        if (@available(macOS 10.14, *)) {
            // work around issue 7101. Draw a window background colored area under the legacy scroller.
            if (_scrollview.isLegacyScroller &&
                    ![iTermPreferences boolForKey:kPreferenceKeyHideScrollbar]) {
                frame.size.width -= 15;
            }
        }
        [self drawAroundFrame:frame dirtyRect:dirtyRect];
    }
    // 10.13 path: work around issue 6974
    if (_useMetal &&
            _scrollview.isLegacyScroller &&
            ![iTermPreferences boolForKey:kPreferenceKeyHideScrollbar] &&
            [_scrollview.effectiveAppearance.name isEqualToString:NSAppearanceNameVibrantDark]) {
        [[NSColor colorWithWhite:20.0 / 255.0 alpha:1] set];
        NSRectFill(NSMakeRect(self.frame.size.width - 15, 0, self.frame.size.height, self.frame.size.height));
    }
}

- (void)drawAroundFrame:(NSRect)svFrame dirtyRect:(NSRect)dirtyRect {
    // left
    if (svFrame.origin.x > 0) {
        [self drawBackgroundInRect:NSMakeRect(0, 0, svFrame.origin.x, self.frame.size.height)];
    }

    // right
    if (svFrame.size.width < self.frame.size.width) {
        double widthDiff = self.frame.size.width - svFrame.size.width;
        [self drawBackgroundInRect:NSMakeRect(self.frame.size.width - widthDiff,
                                              0,
                                              widthDiff,
                                              self.frame.size.height)];
    }
    // bottom
    if (svFrame.origin.y != 0) {
        [self drawBackgroundInRect:NSMakeRect(0, 0, self.frame.size.width, svFrame.origin.y)];
    }

    // top
    if (NSMaxY(svFrame) < self.frame.size.height) {
        [self drawBackgroundInRect:NSMakeRect(dirtyRect.origin.x,
                                              NSMaxY(svFrame),
                                              dirtyRect.size.width,
                                              self.frame.size.height - NSMaxY(svFrame))];
    }
}

- (NSEdgeInsets)extraMargins {
    NSEdgeInsets insets = NSEdgeInsetsZero;
    if (_showTitle) {
        insets.top = iTermGetSessionViewTitleHeight();
    }
    if (self.showBottomStatusBar) {
        insets.bottom = iTermGetStatusBarHeight();
    }
    return insets;
}

- (NSRect)insetRect:(NSRect)rect flipped:(BOOL)flipped includeBottomStatusBar:(BOOL)includeBottomStatusBar {
    CGFloat topInset = self.extraMargins.top;
    CGFloat bottomInset = 0;

    // Most callers don't inset for per-pane status bars because not all panes
    // might have status bars and this function is used to compute the window's
    // inset.
    if (includeBottomStatusBar) {
        bottomInset = self.extraMargins.bottom;
    }
    if (flipped) {
        CGFloat temp;
        temp = topInset;
        topInset = bottomInset;
        bottomInset = temp;
    }
    NSRect frame = rect;
    frame.origin.y += bottomInset;
    frame.size.height -= (topInset + bottomInset);
    return frame;
}

- (NSRect)contentRect {
    return [self insetRect:self.frame
                 flipped:NO
                 includeBottomStatusBar:![iTermPreferences boolForKey:kPreferenceKeySeparateStatusBarsPerPane]];
}

- (void)createSplitSelectionView {
    NSRect frame = self.frame;
    _splitSelectionView = [[SplitSelectionView alloc] initWithFrame:NSMakeRect(0,
                                                      0,
                                                      frame.size.width,
                                                      frame.size.height)];
    _splitSelectionView.wantsLayer = [iTermPreferences boolForKey:kPreferenceKeyUseMetal];
    [self addSubviewBelowFindView:_splitSelectionView];
    [[self window] orderFront:nil];
}

- (SplitSessionHalf)removeSplitSelectionView {
    SplitSessionHalf half = [_splitSelectionView half];
    [_splitSelectionView removeFromSuperview];
    _splitSelectionView = nil;
    return half;
}

- (BOOL)hasHoverURL {
    return _hoverURLView != nil;
}

- (BOOL)setHoverURL:(NSString *)url {
    if ([NSObject object:url isEqualToObject:_hoverURLView.url]) {
        return NO;
    }
    if (_hoverURLView == nil) {
        _hoverURLView = [[iTermHoverContainerView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        _hoverURLView.url = url;
        _hoverURLTextField = [[NSTextField alloc] initWithFrame:_hoverURLView.bounds];
        [_hoverURLTextField setDrawsBackground:NO];
        [_hoverURLTextField setBordered:NO];
        [_hoverURLTextField setEditable:NO];
        [_hoverURLTextField setSelectable:NO];
        [_hoverURLTextField setStringValue:url];
        [_hoverURLTextField setAlignment:NSTextAlignmentLeft];
        [_hoverURLTextField setAutoresizingMask:NSViewWidthSizable];
        [_hoverURLTextField setTextColor:[NSColor textColor]];
        _hoverURLTextField.autoresizingMask = NSViewNotSizable;
        [_hoverURLView addSubview:_hoverURLTextField];
        _hoverURLView.frame = _hoverURLTextField.bounds;
        [super addSubview:_hoverURLView];
        [_delegate sessionViewDidChangeHoverURLVisible:YES];
    } else if (url == nil) {
        [_hoverURLView removeFromSuperview];
        _hoverURLView = nil;
        _hoverURLTextField = nil;
        [_delegate sessionViewDidChangeHoverURLVisible:NO];
    } else {
        // _hoverurlView != nil && url != nil
        _hoverURLView.url = url;
        [_hoverURLTextField setStringValue:url];
    }

    [self updateLayout];
    return YES;
}

- (void)viewDidMoveToWindow {
    [_delegate sessionViewDidChangeWindow];
}

- (PTYScroller *)verticalScroller {
    return [PTYScroller castFrom:self.scrollview.verticalScroller];
}

#pragma mark NSDraggingSource protocol

- (void)draggingSession:(NSDraggingSession *)session movedToPoint:(NSPoint)screenPoint {
    [[NSCursor closedHandCursor] set];
}

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    const BOOL isLocal = (context == NSDraggingContextWithinApplication);
    return (isLocal ? NSDragOperationMove : NSDragOperationNone);
}

- (BOOL)ignoreModifierKeysForDraggingSession:(NSDraggingSession *)session {
    return YES;
}

- (void)draggingSession:(NSDraggingSession *)session
    endedAtPoint:(NSPoint)aPoint
    operation:(NSDragOperation)operation {
    if (![[MovePaneController sharedInstance] dragFailed]) {
        [[MovePaneController sharedInstance] dropInSession:nil half:kNoHalf atPoint:aPoint];
    }
}

#pragma mark NSDraggingDestination protocol

- (NSDragOperation)draggingEntered:(id < NSDraggingInfo >)sender {
    return [_delegate sessionViewDraggingEntered:sender];
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    [_delegate sessionViewDraggingExited:sender];
    [_splitSelectionView removeFromSuperview];
    _splitSelectionView = nil;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    if ([_delegate sessionViewShouldSplitSelectionAfterDragUpdate:sender]) {
        NSPoint point = [self convertPoint:[sender draggingLocation] fromView:nil];
        [_splitSelectionView updateAtPoint:point];
    }
    return NSDragOperationMove;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    BOOL result = [_delegate sessionViewPerformDragOperation:sender];
    [_delegate sessionViewDraggingExited:sender];
    return result;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    return YES;
}

- (BOOL)wantsPeriodicDraggingUpdates {
    return YES;
}

- (BOOL)showTitle {
    return _showTitle;
}

- (BOOL)setShowTitle:(BOOL)value adjustScrollView:(BOOL)adjustScrollView {
    if (value == _showTitle) {
        return NO;
    }
    _showTitle = value;
    PTYScrollView *scrollView = [self scrollview];
    NSRect frame = [scrollView frame];
    if (_showTitle) {
        frame.size.height -= iTermGetSessionViewTitleHeight();
        _title = [[SessionTitleView alloc] initWithFrame:NSMakeRect(0,
                                           self.frame.size.height - iTermGetSessionViewTitleHeight(),
                                           self.frame.size.width,
                                           iTermGetSessionViewTitleHeight())];
        [self invalidateStatusBar];
        if (adjustScrollView) {
            [_title setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        }
        _title.delegate = self;
        [_title setDimmingAmount:[self adjustedDimmingAmount]];
        [self addSubviewBelowFindView:_title];
    } else {
        frame.size.height += iTermGetSessionViewTitleHeight();
        [_title removeFromSuperview];
        _title = nil;
    }
    if (adjustScrollView) {
        [scrollView setFrame:frame];
        if (@available(macOS 10.14, *)) {
            if (PTYScrollView.shouldDismember) {
                _scrollview.verticalScroller.frame = [self frameForScroller];
            }
        }
    } else {
        [self updateTitleFrame];
    }
    [self setTitle:[_delegate sessionViewTitle]];
    [self updateScrollViewFrame];
    [self invalidateStatusBar];
    [self updateAnnouncementFrame];
    return YES;
}

- (BOOL)showBottomStatusBar {
    return _showBottomStatusBar;
}

- (BOOL)setShowBottomStatusBar:(BOOL)value adjustScrollView:(BOOL)adjustScrollView {
    if (value == _showBottomStatusBar) {
        return NO;
    }
    _showBottomStatusBar = value;

    PTYScrollView *scrollView = [self scrollview];
    NSRect frame = [scrollView frame];
    if (_showBottomStatusBar) {
        iTermStatusBarViewController *statusBar = self.delegate.sessionViewStatusBarViewController;
        _title.statusBarViewController = nil;
        frame.size.height -= iTermGetStatusBarHeight();
        _genericStatusBarContainer = [[iTermGenericStatusBarContainer alloc] initWithFrame:NSMakeRect(0,
                                                                             0,
                                                                             self.frame.size.width,
                                                                             iTermGetStatusBarHeight())];
        _genericStatusBarContainer.statusBarViewController = statusBar;
        _genericStatusBarContainer.delegate = self;
        [self invalidateStatusBar];
        if (adjustScrollView) {
            [_genericStatusBarContainer setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
        }
        [self addSubviewBelowFindView:_genericStatusBarContainer];
    } else {
        [_genericStatusBarContainer removeFromSuperview];
        _genericStatusBarContainer = nil;
        frame.size.height += iTermGetStatusBarHeight();
    }
    if (adjustScrollView) {
        [scrollView setFrame:frame];
    } else {
        [self updateBottomStatusBarFrame];
    }
    [self updateScrollViewFrame];
    [self invalidateStatusBar];
    return YES;
}

- (void)invalidateStatusBar {
    iTermStatusBarViewController *newVC = nil;
    if ([_delegate sessionViewUseSeparateStatusBarsPerPane]) {
        newVC = [self.delegate sessionViewStatusBarViewController];
    }
    switch ((iTermStatusBarPosition)[iTermPreferences unsignedIntegerForKey:kPreferenceKeyStatusBarPosition]) {
    case iTermStatusBarPositionTop:
        if (newVC != _title.statusBarViewController) {
            _title.statusBarViewController = newVC;
        }
        break;

    case iTermStatusBarPositionBottom:
        if (newVC != _genericStatusBarContainer.statusBarViewController) {
            _genericStatusBarContainer.statusBarViewController = newVC;
        }
        break;
    }
    [self updateFindDriver];
}

- (void)updateFindDriver {
    iTermStatusBarViewController *statusBarViewController = [self.delegate sessionViewStatusBarViewController];
    if (statusBarViewController.searchViewController && statusBarViewController.temporaryLeftComponent == nil) {
        _findDriverType = iTermSessionViewFindDriverPermanentStatusBar;
        _permanentStatusBarFindDriver = [[iTermFindDriver alloc] initWithViewController:statusBarViewController.searchViewController];
        _permanentStatusBarFindDriver.delegate = self.findDriverDelegate;
    } else if (statusBarViewController) {
        _findDriverType = iTermSessionViewFindDriverTemporaryStatusBar;
    } else {
        _findDriverType = iTermSessionViewFindDriverDropDown;
    }
}

- (void)setOrdinal:(int)ordinal {
    _ordinal = ordinal;
    _title.ordinal = ordinal;
}

- (NSSize)compactFrame {
    NSSize cellSize = [_delegate sessionViewCellSize];
    VT100GridSize gridSize = [_delegate sessionViewGridSize];
    DLog(@"Compute smallest frame that contains a grid of size %@ with cell size %@",
         VT100GridSizeDescription(gridSize), NSStringFromSize(cellSize));

    NSSize dim = NSMakeSize(gridSize.width, gridSize.height);
    NSSize innerSize = NSMakeSize(cellSize.width * dim.width + [iTermPreferences intForKey:kPreferenceKeySideMargins] * 2,
                                  cellSize.height * dim.height + [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2);
    const BOOL hasScrollbar = [[self scrollview] hasVerticalScroller];
    NSSize size =
        [PTYScrollView frameSizeForContentSize:innerSize
                       horizontalScrollerClass:nil
                       verticalScrollerClass:(hasScrollbar ? [PTYScroller class] : nil)
                       borderType:NSNoBorder
                       controlSize:NSControlSizeRegular
                       scrollerStyle:[[self scrollview] scrollerStyle]];

    if (_showTitle) {
        size.height += iTermGetSessionViewTitleHeight();
    }
    if (_showBottomStatusBar) {
        size.height += iTermGetStatusBarHeight();
    }
    DLog(@"Smallest such frame is %@", NSStringFromSize(size));
    return size;
}

- (NSSize)maximumPossibleScrollViewContentSize {
    NSSize size = self.frame.size;
    DLog(@"maximumPossibleScrollViewContentSize. size=%@", [NSValue valueWithSize:size]);
    if (_showTitle) {
        size.height -= iTermGetSessionViewTitleHeight();
        DLog(@"maximumPossibleScrollViewContentSize: sub title height. size=%@", [NSValue valueWithSize:size]);
    }
    if (_showBottomStatusBar) {
        size.height -= iTermGetStatusBarHeight();
        DLog(@"maximumPossibleScrollViewContentSize: sub bottom status bar height. size=%@", NSStringFromSize(size));
    }
    Class verticalScrollerClass = [[[self scrollview] verticalScroller] class];
    if (![[self scrollview] hasVerticalScroller]) {
        verticalScrollerClass = nil;
    }
    NSSize contentSize =
        [NSScrollView contentSizeForFrameSize:size
                      horizontalScrollerClass:nil
                      verticalScrollerClass:verticalScrollerClass
                      borderType:[[self scrollview] borderType]
                      controlSize:NSControlSizeRegular
                      scrollerStyle:[[[self scrollview] verticalScroller] scrollerStyle]];
    return contentSize;
}

- (void)updateTitleFrame {
    DLog(@"Update title frame");
    NSRect aRect = [self frame];
    if (_showTitle) {
        [_title setFrame:NSMakeRect(0,
                                    aRect.size.height - iTermGetSessionViewTitleHeight(),
                                    aRect.size.width,
                                    iTermGetSessionViewTitleHeight())];
        NSViewController *viewController = [self.delegate sessionViewStatusBarViewController];

        [[viewController view] setNeedsLayout:YES];
    }
    [self updateScrollViewFrame];
    [self updateFindViewFrame];
}

- (void)updateBottomStatusBarFrame {
    NSRect aRect = [self frame];
    if (_showBottomStatusBar) {
        _genericStatusBarContainer.frame = NSMakeRect(0,
                                           0,
                                           aRect.size.width,
                                           iTermGetStatusBarHeight());

        [_genericStatusBarContainer.statusBarViewController.view setNeedsLayout:YES];
    }
    [self updateScrollViewFrame];
    [self updateFindViewFrame];
}

- (void)updateFindViewFrame {
    DLog(@"update findview frame");
    NSRect aRect = self.frame;
    NSView *findView = _dropDownFindViewController.view;
    [_dropDownFindViewController setFrameOrigin:NSMakePoint(aRect.size.width - [findView frame].size.width - 30,
                                        aRect.size.height - [findView frame].size.height)];
}

- (void)updateScrollViewFrame {
    DLog(@"update scrollview frame");
    CGFloat titleHeight = _showTitle ? _title.frame.size.height : 0;
    CGFloat bottomStatusBarHeight = _showBottomStatusBar ? iTermGetStatusBarHeight() : 0;
    NSSize proposedSize = NSMakeSize(self.frame.size.width,
                                     self.frame.size.height - titleHeight - bottomStatusBarHeight);
    NSSize size = [_delegate sessionViewScrollViewWillResize:proposedSize];
    NSRect rect = NSMakeRect(0,
                             bottomStatusBarHeight + proposedSize.height - size.height,
                             size.width,
                             size.height);
    DLog(@"titleHeight=%@ bottomStatusBarHeight=%@ proposedSize=%@ size=%@ rect=%@",
         @(titleHeight), @(bottomStatusBarHeight), NSStringFromSize(proposedSize), NSStringFromSize(size),
         NSStringFromRect(rect));
    [self scrollview].frame = rect;
    if (@available(macOS 10.14, *)) {
        if (PTYScrollView.shouldDismember) {
            _scrollview.verticalScroller.frame = [self frameForScroller];
        }
    }
    rect.origin = NSZeroPoint;
    rect.size.width = _scrollview.contentSize.width;
    rect.size.height = [_delegate sessionViewDesiredHeightOfDocumentView];
    [_scrollview.documentView setFrame:rect];
    if (_useMetal) {
        [self updateMetalViewFrame];
    }
    [self updateMinimapFrameAnimated:NO];
    [_delegate sessionViewScrollViewDidResize];
}

- (void)updateMinimapFrameAnimated:(BOOL)animated {
    if (![iTermAdvancedSettingsModel showLocationsInScrollbar]) {
        return;
    }
    if (@available(macOS 10.14, *)) {
        NSRect frame = [self convertRect:_scrollview.verticalScroller.bounds
                             fromView:_scrollview.verticalScroller];
        PTYScroller *scroller = [PTYScroller castFrom:self.scrollview.verticalScroller];
        if (scroller.ptyScrollerState == PTYScrollerStateOverlayVisibleNarrow) {
            frame.size.width = 11;
            frame.origin.x += 5;
        }
        frame = NSInsetRect(frame, 0, 2);
        if (@available(macOS 10.15, *)) {
            if ([[NSApp effectiveAppearance] it_isDark]) {
                // Avoid overlapping the border on the right. It looks ugly
                // when the window's dark because the part that overlaps the
                // border is extra bright.
                frame.size.width -= 1;
            }
        }
        if (animated) {
            [NSView animateWithDuration:5.0 / 60.0
                   animations:^ {
                       [[NSAnimationContext currentContext] setTimingFunction:[CAMediaTimingFunction functionWithName:@"easeOut"]];
                       _searchResultsMinimap.animator.frame = frame;
                       _marksMinimap.animator.frame = frame;
                   }
                   completion:nil];
        } else {
            _searchResultsMinimap.frame = frame;
            _marksMinimap.frame = frame;
        }
    }
}

- (void)setTitle:(NSString *)title {
    if (!title) {
        title = @"";
    }
    _title.title = title;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@:%p frame:%@ size:%@>", [self class], self,
                     [NSValue valueWithRect:[self frame]], VT100GridSizeDescription([_delegate sessionViewGridSize])];
}

#pragma mark SessionTitleViewDelegate

- (NSColor *)tabColor {
    return [_delegate sessionViewTabColor];
}

- (NSMenu *)menu {
    return [_delegate sessionViewContextMenu];
}

- (void)close {
    [_delegate sessionViewConfirmAndClose];
}

- (void)beginDrag {
    [_delegate sessionViewBeginDrag];
}

- (void)doubleClickOnTitleView {
    [_delegate sessionViewDoubleClickOnTitleBar];
}

- (void)sessionTitleViewBecomeFirstResponder {
    [_delegate sessionViewBecomeFirstResponder];
}

- (NSColor *)sessionTitleViewBackgroundColor {
    if (!_showBottomStatusBar && _title.statusBarViewController) {
        NSColor *color = _title.statusBarViewController.layout.advancedConfiguration.backgroundColor;
        if (color) {
            return color;
        }
    }
    return [self backgroundColorForDecorativeSubviews];
}

- (void)addAnnouncement:(iTermAnnouncementViewController *)announcement {
    DLog(@"Add announcement %@ to %@", announcement.title, self.delegate);
    [_announcements addObject:announcement];
    announcement.delegate = self;
    if (!_currentAnnouncement) {
        [self showNextAnnouncement];
    }
}

- (void)updateAnnouncementFrame {
    // Set the width
    NSRect rect = _currentAnnouncement.view.frame;
    rect.size.width = self.frame.size.width;
    _currentAnnouncement.view.frame = rect;

    // Make it change its height
    [(iTermAnnouncementView *)_currentAnnouncement.view sizeToFit];

    // Fix the origin
    rect = _currentAnnouncement.view.frame;
    rect.origin.y = self.frame.size.height - _currentAnnouncement.view.frame.size.height;
    if (_showTitle) {
        rect.origin.y -= iTermGetSessionViewTitleHeight();
    }
    _currentAnnouncement.view.frame = rect;
}

- (iTermAnnouncementViewController *)nextAnnouncement {
    iTermAnnouncementViewController *possibleAnnouncement = nil;
    while (_announcements.count) {
        possibleAnnouncement = _announcements[0];
        [_announcements removeObjectAtIndex:0];
        if (possibleAnnouncement.shouldBecomeVisible) {
            return possibleAnnouncement;
        }
    }
    return nil;
}

- (void)showNextAnnouncement {
    _currentAnnouncement = nil;
    if (_announcements.count) {
        iTermAnnouncementViewController *possibleAnnouncement = [self nextAnnouncement];
        if (!possibleAnnouncement) {
            return;
        }
        _currentAnnouncement = possibleAnnouncement;
        [self updateAnnouncementFrame];

        // Animate in
        NSRect finalRect = NSMakeRect(0,
                                      self.frame.size.height - _currentAnnouncement.view.frame.size.height,
                                      self.frame.size.width,
                                      _currentAnnouncement.view.frame.size.height);

        NSRect initialRect = finalRect;
        initialRect.origin.y += finalRect.size.height;
        _title.hidden = YES;
        _currentAnnouncement.view.frame = initialRect;

        [_currentAnnouncement.view.animator setFrame:finalRect];

        _currentAnnouncement.view.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        [_currentAnnouncement didBecomeVisible];
        [self addSubviewBelowFindView:_currentAnnouncement.view];
    } else {
        _title.hidden = NO;
    }
    [self.delegate sessionViewAnnouncementDidChange:self];
}

#pragma mark - iTermAnnouncementDelegate

- (void)announcementWillDismiss:(iTermAnnouncementViewController *)announcement {
    [_announcements removeObject:announcement];
    if (announcement == _currentAnnouncement) {
        NSRect rect = announcement.view.frame;
        rect.origin.y += rect.size.height;
        [NSView animateWithDuration:0.25
               animations:^ {
                   [announcement.view.animator setFrame:rect];
               }
               completion:^(BOOL finished) {
            [announcement.view removeFromSuperview];
        }];

        if (!_inDealloc) {
            [self performSelector:@selector(showNextAnnouncement)
                  withObject:nil
                  afterDelay:[[NSAnimationContext currentContext] duration]];
        }
    }
}

#pragma mark - PTYScrollerDelegate

- (void)userScrollDidChange:(BOOL)userScroll {
    [self.delegate sessionViewUserScrollDidChange:userScroll];
}

- (void)viewDidChangeEffectiveAppearance {
    [self updateMinimapAlpha];
}

- (void)updateMinimapAlpha {
    if (![iTermAdvancedSettingsModel showLocationsInScrollbar]) {
        return;
    }
    PTYScroller *scroller = [PTYScroller castFrom:self.scrollview.verticalScroller];
    if (scroller) {
        [self ptyScrollerDidTransitionToState:scroller.ptyScrollerState];
    }
}

- (void)ptyScrollerDidTransitionToState:(PTYScrollerState)state {
    if (![iTermAdvancedSettingsModel showLocationsInScrollbar]) {
        return;
    }
    const CGFloat maxAlpha = _scrollview.verticalScroller.effectiveAppearance.it_isDark ? 0.5 : 0.75;
    switch (state) {
    case PTYScrollerStateLegacy:
        _searchResultsMinimap.alphaValue = maxAlpha;
        _marksMinimap.alphaValue = maxAlpha;
        [self updateMinimapFrameAnimated:YES];
        break;
    case PTYScrollerStateOverlayHidden: {
        [NSView animateWithDuration:5.0 / 60
               animations:^ {
                   [[NSAnimationContext currentContext] setTimingFunction:[CAMediaTimingFunction functionWithName:@"easeOut"]];
                   _searchResultsMinimap.animator.alphaValue = 0;
                   _marksMinimap.animator.alphaValue = 0;
               }
               completion:nil];
        break;
    }
    case PTYScrollerStateOverlayVisibleWide:
    case PTYScrollerStateOverlayVisibleNarrow: {
        _searchResultsMinimap.alphaValue = maxAlpha;
        _marksMinimap.alphaValue = maxAlpha;
        [self updateMinimapFrameAnimated:YES];
        break;
    }
    }
}

#pragma mark - iTermFindDriverDelegate

- (BOOL)canSearch {
    return [self.delegate canSearch];
}

- (void)resetFindCursor {
    [self.delegate resetFindCursor];
}

- (BOOL)findInProgress {
    return [self.delegate findInProgress];
}

- (BOOL)continueFind:(double *)progress {
    return [self.delegate continueFind:progress];
}

- (BOOL)growSelectionLeft {
    return [self.delegate growSelectionLeft];
}

- (void)growSelectionRight {
    [self.delegate growSelectionRight];
}

- (NSString *)selectedText {
    return [self.delegate selectedText];
}

- (NSString *)unpaddedSelectedText {
    return [self.delegate unpaddedSelectedText];
}

- (void)copySelection {
    [self.delegate copySelection];
}

- (void)pasteString:(NSString *)string {
    [self.delegate pasteString:string];
}

- (void)findViewControllerMakeDocumentFirstResponder {
    [self.delegate findViewControllerMakeDocumentFirstResponder];
}

- (void)findViewControllerClearSearch {
    [self.delegate findViewControllerClearSearch];
    self.delegate.sessionViewStatusBarViewController.temporaryLeftComponent = nil;
}

- (void)findString:(NSString *)aString
    forwardDirection:(BOOL)direction
    mode:(iTermFindMode)mode
    withOffset:(int)offset
    scrollToFirstResult:(BOOL)scrollToFirstResult {
    [self.delegate findString:aString
                   forwardDirection:direction
                   mode:mode
                   withOffset:offset
                   scrollToFirstResult:scrollToFirstResult];
}

- (void)findViewControllerVisibilityDidChange:(id<iTermFindViewController>)sender {
    [self.delegate findViewControllerVisibilityDidChange:sender];
}

- (void)findViewControllerDidCeaseToBeMandatory:(id<iTermFindViewController>)sender {
    [self.delegate findViewControllerDidCeaseToBeMandatory:sender];
}

- (NSInteger)findDriverCurrentIndex {
    return [self.delegate findDriverCurrentIndex];
}

- (NSInteger)findDriverNumberOfSearchResults {
    return [self.delegate findDriverNumberOfSearchResults];
}

- (void)showUnobtrusiveMessage:(NSString *)message {
    if (_unobtrusiveMessage) {
        return;
    }
    if (@available(macOS 10.14, *)) {
        _unobtrusiveMessage = [[iTermUnobtrusiveMessage alloc] initWithMessage:message];
        [self addSubviewBelowFindView:_unobtrusiveMessage];
        [_unobtrusiveMessage animateFromTopRightWithCompletion:^ {
                                [self->_unobtrusiveMessage removeFromSuperview];
                                self->_unobtrusiveMessage = nil;
                            }];
    }
}

#pragma mark - iTermGenericStatusBarContainer

- (NSColor *)genericStatusBarContainerBackgroundColor {
    return [self backgroundColorForDecorativeSubviews];
}

- (NSScrollView *)ptyScrollerScrollView NS_AVAILABLE_MAC(10_14) {
    return _scrollview;
}

#pragma mark - SplitSelectionViewDelegate

- (void)didSelectDestinationSession:(PTYSession *)session half:(SplitSessionHalf)half {
    [[NSNotificationCenter defaultCenter] postNotificationName:SessionViewWasSelectedForInspectionNotification object:self];
}

#pragma mark - iTermSearchResultsMinimapViewDelegate

- (NSIndexSet *)searchResultsMinimapViewLocations:(iTermSearchResultsMinimapView *)view NS_AVAILABLE_MAC(10_14) {
    return [self.searchResultsMinimapViewDelegate searchResultsMinimapViewLocations:view];
}

- (NSRange)searchResultsMinimapViewRangeOfVisibleLines:(iTermSearchResultsMinimapView *)view NS_AVAILABLE_MAC(10_14) {
    return [self.searchResultsMinimapViewDelegate searchResultsMinimapViewRangeOfVisibleLines:view];
}

@end
