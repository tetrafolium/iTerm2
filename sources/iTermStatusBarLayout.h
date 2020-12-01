//
//  iTermStatusBarLayout.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import <Cocoa/Cocoa.h>

#import "iTermStatusBarAutoRainbowController.h"
#import "iTermStatusBarComponent.h"
#import "iTermStatusBarLayoutAlgorithm.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermStatusBarLayoutKeyComponents;
extern NSString *const iTermStatusBarLayoutKeyAdvancedConfiguration;

@class iTermStatusBarLayout;

@protocol iTermStatusBarLayoutDelegate <NSObject>

- (void)statusBarLayoutDidChange:(iTermStatusBarLayout *)layout;

@end

@interface iTermStatusBarAdvancedConfiguration
    : NSObject <NSCopying, NSSecureCoding>
@property(nullable, nonatomic, strong) NSColor *separatorColor;
@property(nullable, nonatomic, strong) NSColor *backgroundColor;
@property(nullable, nonatomic, strong) NSColor *defaultTextColor;
@property(nullable, nonatomic, strong) NSFont *font;
@property(nonatomic) iTermStatusBarLayoutAlgorithmSetting layoutAlgorithm;
@property(nonatomic) iTermStatusBarAutoRainbowStyle autoRainbowStyle;
@property(nonatomic) BOOL removeEmptyComponents;

+ (instancetype)advancedConfigurationFromDictionary:(NSDictionary *)dict;
+ (NSFont *)defaultFont;

- (NSDictionary *)dictionaryValue;

@end

@interface iTermStatusBarLayout : NSObject <NSSecureCoding>

@property(nonatomic, weak) id<iTermStatusBarLayoutDelegate> delegate;
@property(nonatomic, strong) NSArray<id<iTermStatusBarComponent>> *components;
@property(nonatomic, readonly)
    iTermStatusBarAdvancedConfiguration *advancedConfiguration;

- (instancetype)initWithComponents:
                    (NSArray<id<iTermStatusBarComponent>> *)components
             advancedConfiguration:
                 (iTermStatusBarAdvancedConfiguration *)advancedConfiguration
    NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithDictionary:(NSDictionary *)layout
                             scope:(nullable iTermVariableScope *)scope;
- (instancetype)initWithScope:(nullable iTermVariableScope *)scope;
- (instancetype)init NS_UNAVAILABLE;

- (NSDictionary *)dictionaryValue;

@end

NS_ASSUME_NONNULL_END
