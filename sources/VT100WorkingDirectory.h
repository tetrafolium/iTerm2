//
//  VT100WorkingDirectory.h
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import "IntervalTree.h"
#import <Foundation/Foundation.h>

@interface VT100WorkingDirectory : NSObject <IntervalTreeObject>

@property(nonatomic, copy) NSString *workingDirectory;

@end
