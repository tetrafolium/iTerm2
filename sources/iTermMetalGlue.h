//
//  iTermMetalGlue.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/8/17.
//

#import "iTermMetalDriver.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermTextDrawingHelper;
@class VT100Screen;
@class PTYTextView;

NS_CLASS_AVAILABLE(10_11, NA)
@protocol iTermMetalGlueDelegate <NSObject>
- (void)metalGlueDidDrawFrameAndNeedsRedraw:(BOOL)redrawAsap;
- (CGContextRef)metalGlueContext;
- (NSImage *)metalGlueBackgroundImage;
- (iTermBackgroundImageMode)metalGlueBackgroundImageMode;
- (CGFloat)metalGlueBackgroundImageBlend;

@end

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalGlue : NSObject <iTermMetalDriverDataSource>

@property(nullable, nonatomic, strong) PTYTextView *textView;
@property(nonatomic, strong) VT100Screen *screen;
@property(nonatomic, weak) id<iTermMetalGlueDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
