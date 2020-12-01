//
//  PseudoTerminalRestorer.h
//  iTerm
//
//  Created by George Nachman on 10/24/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface PseudoTerminalState : NSObject
@property(nonatomic, readonly) NSDictionary *arrangement;
- (instancetype)initWithCoder:(NSCoder *)coder;
- (instancetype)initWithDictionary:(NSDictionary *)arrangement;
@end

@interface PseudoTerminalRestorer : NSObject

@property(class, nonatomic) void (^postRestorationCompletionBlock)(void);

+ (void)restoreWindowWithIdentifier:(NSString *)identifier
                              state:(NSCoder *)state
                  completionHandler:
                      (void (^)(NSWindow *, NSError *))completionHandler;

+ (BOOL)willOpenWindows;

// Block is run when all windows are restored. It may be run immediately.
+ (void)setRestorationCompletionBlock:(void (^)(void))completion;

+ (void)runQueuedBlocks;

+ (void)restoreWindowWithIdentifier:(NSString *)identifier
                pseudoTerminalState:(PseudoTerminalState *)state
                             system:(BOOL)system
                  completionHandler:
                      (void (^)(NSWindow *, NSError *))completionHandler;
+ (BOOL)shouldIgnoreOpenUntitledFile;

// The db-backed restoration mechanism has completed and the post-restoration
// callback is now safe to run.
+ (void)externalRestorationDidComplete;

@end
