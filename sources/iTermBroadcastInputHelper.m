//
//  iTermBroadcastInputHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/4/18.
//

#import "iTermBroadcastInputHelper.h"

#import "iTermApplicationDelegate.h"
#import "iTermWarning.h"

#import "NSArray+iTerm.h"
#import "NSSet+iTerm.h"

NSString *const iTermBroadcastDomainsDidChangeNotification =
    @"iTermBroadcastDomainsDidChangeNotification";

@implementation iTermBroadcastInputHelper {
  BroadcastMode _broadcastMode;

  // Only relevant when the mode is CUSTOM
  NSSet<NSSet<NSString *> *> *_broadcastDomains;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _broadcastDomains = [NSSet set];
  }
  return self;
}

- (BroadcastMode)broadcastMode {
  if ([self.delegate broadcastInputHelperCurrentTabIsBroadcasting:self]) {
    return BROADCAST_TO_ALL_PANES;
  } else {
    return _broadcastMode;
  }
}

- (void)toggleSession:(NSString *)sessionID {
  switch ([self broadcastMode]) {
  case BROADCAST_TO_ALL_PANES: {
    [self.delegate broadcastInputHelper:self setCurrentTabBroadcasting:NO];
    NSArray<NSString *> *sessionIDs =
        [self.delegate broadcastInputHelperSessionsInCurrentTab:self
                                                  includeExited:YES]
            ?: @[];
    _broadcastDomains =
        [NSSet setWithArray:@[ [NSSet setWithArray:sessionIDs] ]];
    break;
  }
  case BROADCAST_TO_ALL_TABS: {
    NSArray<NSString *> *sessionIDs =
        [self.delegate broadcastInputHelperSessionsInAllTabs:self
                                               includeExited:YES]
            ?: @[];
    _broadcastDomains =
        [NSSet setWithArray:@[ [NSSet setWithArray:sessionIDs] ]];
    break;
  }
  case BROADCAST_OFF:
    _broadcastDomains = [NSSet set];
    break;

  case BROADCAST_CUSTOM:
    break;
  }
  _broadcastMode = BROADCAST_CUSTOM;

  // If the session belongs to any domain, remove it.
  __block BOOL removed = NO;
  _broadcastDomains = [_broadcastDomains
      mapWithBlock:^id _Nonnull(NSSet<NSString *> *_Nonnull strings) {
        return [strings filteredSetUsingBlock:^BOOL(NSString *_Nonnull string) {
          if (![string isEqualToString:sessionID]) {
            return YES;
          }
          removed = YES;
          return NO;
        }];
      }];
  if (removed) {
    // Remove domains with a single session. Note that we do this on remove but
    // not on add because focus-follows-mouse users can't toggle any but the
    // current session so they need to be able to exist at least temporarily in
    // a world with a domain that has a single session in it.
    _broadcastDomains = [_broadcastDomains
        filteredSetUsingBlock:^BOOL(NSSet<NSString *> *_Nonnull set) {
          return set.count > 1;
        }];
  } else {
    // We need to add the session.
    if (_broadcastDomains.count == 0) {
      // No domains. Add this and the current session.
      NSString *currentSession =
          [self.delegate broadcastInputHelperCurrentSession:self];
      _broadcastDomains = [NSSet
          setWithObject:[NSSet setWithObjects:sessionID, currentSession, nil]];
    } else if (_broadcastDomains.count == 1) {
      // If there is exactly one domain, add it to that domain
      _broadcastDomains = [_broadcastDomains
          mapWithBlock:^id _Nonnull(NSSet<NSString *> *_Nonnull set) {
            return [set setByAddingObject:sessionID];
          }];
    } else { // at least 2 domains
      // Add to the domain with the current session; if none exists, pick one at
      // random.
      NSString *currentSession =
          [self.delegate broadcastInputHelperCurrentSession:self];
      NSSet<NSString *> *domainToAddTo =
          [_broadcastDomains
              anyObjectPassingTest:^BOOL(NSSet<NSString *> *_Nonnull element) {
                return [element containsObject:currentSession];
              }]
              ?: _broadcastDomains.anyObject;
      _broadcastDomains = [_broadcastDomains
          mapWithBlock:^id _Nonnull(NSSet<NSString *> *_Nonnull existingSet) {
            if (existingSet != domainToAddTo) {
              return existingSet;
            }
            return [existingSet setByAddingObject:sessionID];
          }];
    }
  }
  if (_broadcastDomains.count == 0) {
    _broadcastMode = BROADCAST_OFF;
  }
  [self.delegate broadcastInputHelperDidUpdate:self];
  [[NSNotificationCenter defaultCenter]
      postNotificationName:iTermBroadcastDomainsDidChangeNotification
                    object:nil];
}

- (NSSet<NSString *> *)broadcastSessionIDs {
  switch ([self broadcastMode]) {
  case BROADCAST_OFF:
    return [NSSet set];

  case BROADCAST_TO_ALL_PANES:
    return
        [NSSet setWithArray:[self.delegate
                                broadcastInputHelperSessionsInCurrentTab:self
                                                           includeExited:NO]];

  case BROADCAST_TO_ALL_TABS:
    return [NSSet
        setWithArray:[self.delegate broadcastInputHelperSessionsInAllTabs:self
                                                            includeExited:NO]];
    break;

  case BROADCAST_CUSTOM: {
    NSString *currentSession =
        [self.delegate broadcastInputHelperCurrentSession:self];
    NSSet<NSString *> *domain = [_broadcastDomains
        anyObjectPassingTest:^BOOL(NSSet<NSString *> *_Nonnull set) {
          return [set containsObject:currentSession];
        }];
    NSSet<NSString *> *candidates = [NSSet
        setWithArray:[self.delegate broadcastInputHelperSessionsInAllTabs:self
                                                            includeExited:NO]];
    return [domain setByIntersectingWithSet:candidates];
  }
  }
  return [NSSet set];
}

- (NSSet<NSString *> *)allSessions {
  return [NSSet
      setWithArray:[self.delegate broadcastInputHelperSessionsInAllTabs:self
                                                          includeExited:YES]];
}

// Converts a set of broadcast domains that might contain bogus GUIDs,
// single-element domains, and overlapping domains into a disjoint set of
// 2+-count sets of all valid GUIDs.
- (NSSet<NSSet<NSString *> *> *)sanitizedDomains:
    (NSSet<NSSet<NSString *> *> *)broadcastDomains {
  NSSet<NSString *> *validIDs = [self allSessions];
  // Invert it to ensure broadcast domains will be disjoint.
  // sessionID -> domain number
  NSMutableDictionary<NSString *, NSNumber *> *sessionToIndex =
      [NSMutableDictionary dictionary];
  [broadcastDomains.allObjects
      enumerateObjectsUsingBlock:^(NSSet<NSString *> *_Nonnull domain,
                                   NSUInteger idx, BOOL *_Nonnull stop) {
        [domain enumerateObjectsUsingBlock:^(NSString *_Nonnull sessionID,
                                             BOOL *_Nonnull stop) {
          sessionToIndex[sessionID] = @(idx);
        }];
      }];

  // Group sessions in the same domain
  // domain number -> [sessionID, ...]
  NSDictionary<NSNumber *, NSArray<NSString *> *> *indexToSessions =
      [sessionToIndex.allKeys classifyWithBlock:^id(NSString *sessionID) {
        return sessionToIndex[sessionID];
      }];

  // Convert to set-of-sets, removing invalid session IDs and domains without at
  // least two sessions.
  return [[NSSet setWithArray:[indexToSessions.allValues
                                  mapWithBlock:^id(NSArray<NSString *> *ids) {
                                    return [[NSSet setWithArray:ids]
                                        setByIntersectingWithSet:validIDs];
                                  }]]
      filteredSetUsingBlock:^BOOL(NSSet<NSString *> *_Nonnull domain) {
        return domain.count > 1;
      }];
}

- (void)setBroadcastDomains:
    (NSSet<NSSet<NSString *> *> *)untrustedBroadcastDomains {
  NSSet<NSSet<NSString *> *> *broadcastDomains =
      [self sanitizedDomains:untrustedBroadcastDomains];
  if (broadcastDomains.count == 0 && _broadcastMode == BROADCAST_OFF) {
    return;
  }
  [self.delegate broadcastInputHelperSetNoTabBroadcasting:self];
  if (broadcastDomains.count > 0) {
    _broadcastMode = BROADCAST_CUSTOM;
    _broadcastDomains = broadcastDomains;
  } else {
    _broadcastDomains = [NSSet set];
    _broadcastMode = BROADCAST_OFF;
  }
  [self.delegate broadcastInputHelperDidUpdate:self];
  [[NSNotificationCenter defaultCenter]
      postNotificationName:iTermBroadcastDomainsDidChangeNotification
                    object:nil];
}

- (void)setBroadcastMode:(BroadcastMode)mode {
  if (mode != BROADCAST_CUSTOM && mode == self.broadcastMode) {
    mode = BROADCAST_OFF;
  }
  if (mode != BROADCAST_OFF && self.broadcastMode == BROADCAST_OFF) {
    NSWindow *window =
        [self.delegate broadcastInputHelperWindowForWarnings:self];
    if ([iTermWarning
            showWarningWithTitle:
                @"Keyboard input will be sent to multiple sessions."
                         actions:@[ @"OK", @"Cancel" ]
                      identifier:@"NoSyncSuppressBroadcastInputWarning"
                     silenceable:kiTermWarningTypePermanentlySilenceable
                          window:window] == kiTermWarningSelection1) {
      return;
    }
  }
  if (mode == BROADCAST_TO_ALL_PANES) {
    [self.delegate broadcastInputHelper:self setCurrentTabBroadcasting:YES];
  } else {
    [self.delegate broadcastInputHelper:self setCurrentTabBroadcasting:NO];
  }
  _broadcastMode = mode;
  [self.delegate broadcastInputHelperDidUpdate:self];
  [[NSNotificationCenter defaultCenter]
      postNotificationName:iTermBroadcastDomainsDidChangeNotification
                    object:nil];
}

- (BOOL)shouldBroadcastToSessionWithID:(NSString *)sessionID {
  switch (_broadcastMode) {
  case BROADCAST_OFF:
    return NO;
  case BROADCAST_TO_ALL_TABS:
    return YES;
  case BROADCAST_TO_ALL_PANES:
    return [self.delegate broadcastInputHelper:self
                  tabWithSessionIsBroadcasting:sessionID];
  case BROADCAST_CUSTOM:
    return [_broadcastDomains
               anyObjectPassingTest:^BOOL(NSSet<NSString *> *_Nonnull domain) {
                 return [domain containsObject:sessionID];
               }] != nil;
  }
}

- (NSSet<NSString *> *)currentDomain {
  switch (_broadcastMode) {
  case BROADCAST_OFF:
    return [NSSet set];
  case BROADCAST_TO_ALL_TABS:
    return [self allSessions];
  case BROADCAST_TO_ALL_PANES:
    if (![self.delegate broadcastInputHelperCurrentTabIsBroadcasting:self]) {
      return [NSSet set];
    }
    return
        [NSSet setWithArray:[self.delegate
                                broadcastInputHelperSessionsInCurrentTab:self
                                                           includeExited:YES]];
  case BROADCAST_CUSTOM: {
    NSString *sessionID =
        [self.delegate broadcastInputHelperCurrentSession:self];
    return [_broadcastDomains
        anyObjectPassingTest:^BOOL(NSSet<NSString *> *_Nonnull domain) {
          return [domain containsObject:sessionID];
        }];
  }
  }
  return [NSSet set];
}

@end
