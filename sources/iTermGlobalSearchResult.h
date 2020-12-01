//
//  iTermGlobalSearchResult.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

#import "VT100GridTypes.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class NSAttributedString;
@class PTYSession;
@class SearchResult;

@interface iTermGlobalSearchResult : NSObject
@property(nonatomic, readonly) VT100GridCoordRange coordRange;

@property(nonatomic, weak) PTYSession *session;
@property(nonatomic, strong) SearchResult *result;
@property(nonatomic, copy) NSAttributedString *snippet;

- (void)highlightLines;
@end

NS_ASSUME_NONNULL_END
