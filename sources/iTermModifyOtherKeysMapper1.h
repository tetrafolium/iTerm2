//
//  iTermModifyOtherKeysMapper1.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/1/20.
//

#import "iTermModifyOtherKeysMapper.h"
#import "iTermStandardKeyMapper.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermModifyOtherKeysMapper1 : NSObject <iTermKeyMapper>
@property(nonatomic, weak)
    id<iTermStandardKeyMapperDelegate, iTermModifyOtherKeysMapperDelegate>
        delegate;
@end

NS_ASSUME_NONNULL_END
