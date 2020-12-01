//
//  iTermFullScreenWindowManager.h
//  iTerm2
//
//  Created by George Nachman on 2/6/16.
//
//

#import "iTermWeakReference.h"
#import <Cocoa/Cocoa.h>

@interface iTermFullScreenWindowManager : NSObject

@property(nonatomic, readonly) NSUInteger numberOfQueuedTransitions;

+ (instancetype)sharedInstance;

- (void)makeWindowEnterFullScreen:(NSWindow<iTermWeaklyReferenceable> *)window;
- (void)makeWindowExitFullScreen:(NSWindow<iTermWeaklyReferenceable> *)window;

@end
