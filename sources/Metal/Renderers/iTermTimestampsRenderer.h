#import "iTermMetalCellRenderer.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermTimestampsRendererTransientState
    : iTermMetalCellRendererTransientState
@property(nonatomic) NSColor *backgroundColor;
@property(nonatomic) NSColor *textColor;
@property(nonatomic, strong) NSArray<NSDate *> *timestamps;
@property(nonatomic) BOOL useThinStrokes;
@property(nonatomic) BOOL antialiased;
@end

@interface iTermTimestampsRenderer : NSObject <iTermMetalCellRenderer>

@property(nonatomic) BOOL enabled;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
