//
//  iTermScriptHistory.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/19/18.
//

#import "iTermScriptHistory.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "iTermAPIHelper.h"
#import "iTermAPIServer.h"
#import "iTermUserDefaults.h"
#import "iTermWebSocketConnection.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const iTermScriptHistoryEntryDidChangeNotification =
    @"iTermScriptHistoryEntryDidChangeNotification";
NSString *const iTermScriptHistoryEntryDelta = @"delta";
NSString *const iTermScriptHistoryEntryFieldKey = @"field";
NSString *const iTermScriptHistoryEntryFieldLogsValue = @"logs";
NSString *const iTermScriptHistoryEntryFieldRPCValue = @"rpc";

static NSDateFormatter *gScriptHistoryDateFormatter;

@implementation iTermScriptHistoryEntry {
  NSMutableArray<NSString *> *_logLines;
  NSMutableArray<NSString *> *_callEntries;
}

+ (instancetype)globalEntry {
  static id instance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[self alloc] initWithName:@"iTerm2 App"
                                 fullPath:nil
                               identifier:@"iTerm2"
                                 relaunch:nil];
  });
  return instance;
}

+ (instancetype)apsEntry {
  static id instance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[self alloc] initWithName:@"Automatic Profile Switching"
                                 fullPath:nil
                               identifier:@"__APS"
                                 relaunch:nil];
  });
  return instance;
}

+ (instancetype)dynamicProfilesEntry {
  static id instance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[self alloc] initWithName:@"Dynamic Profiles"
                                 fullPath:nil
                               identifier:@"__DP"
                                 relaunch:nil];
  });
  return instance;
}

+ (instancetype)smartSelectionAnctionsEntry {
  static id instance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[self alloc] initWithName:@"Smart Selection Actions"
                                 fullPath:nil
                               identifier:@"__SSA"
                                 relaunch:nil];
  });
  return instance;
}

- (instancetype)initWithName:(NSString *)name
                    fullPath:(nullable NSString *)fullPath
                  identifier:(NSString *)identifier
                    relaunch:(void (^_Nullable)(void))relaunch {
  self = [super init];
  if (self) {
    _name = [name copy];
    _fullPath = [fullPath copy];
    _identifier = [identifier copy];
    _relaunch = [relaunch copy];
    _startDate = [NSDate date];
    _isRunning = YES;

    _logLines = [NSMutableArray array];
    _callEntries = [NSMutableArray array];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      gScriptHistoryDateFormatter = [[NSDateFormatter alloc] init];
      gScriptHistoryDateFormatter.dateFormat =
          [NSDateFormatter dateFormatFromTemplate:@"Ld jj:mm:ssSSS"
                                          options:0
                                           locale:[NSLocale currentLocale]];
    });
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(apiServerDidReceiveMessage:)
               name:iTermAPIServerDidReceiveMessage
             object:identifier];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(apiServerWillSendMessage:)
               name:iTermAPIServerWillSendMessage
             object:identifier];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(apiDidStop:)
               name:iTermAPIHelperDidStopNotification
             object:nil];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)apiServerDidReceiveMessage:(NSNotification *)notification {
  ITMClientOriginatedMessage *request = notification.userInfo[@"request"];
  [self addClientOriginatedRPC:[request.description
                                   stringByAppendingString:@"\n"]];
}

- (void)apiServerWillSendMessage:(NSNotification *)notification {
  ITMServerOriginatedMessage *message = notification.userInfo[@"message"];
  [self addServerOriginatedRPC:[message.description
                                   stringByAppendingString:@"\n"]];
}

- (void)addOutput:(NSString *)output {
  NSString *timestamp =
      [NSString stringWithFormat:@"\n%@: ", [gScriptHistoryDateFormatter
                                                stringFromDate:[NSDate date]]];
  BOOL trimmed = [output hasSuffix:@"\n"];
  if (trimmed) {
    output = [output substringWithRange:NSMakeRange(0, output.length - 1)];
  }
  output = [output stringByReplacingOccurrencesOfString:@"\n"
                                             withString:timestamp];
  if (trimmed) {
    output = [output stringByAppendingString:@"\n"];
  }

  if (!_lastLogLineContinues) {
    output = [NSString stringWithFormat:@"%@: %@",
                                        [gScriptHistoryDateFormatter
                                            stringFromDate:[NSDate date]],
                                        output];
  }

  [self appendLogs:output];
  [[NSNotificationCenter defaultCenter]
      postNotificationName:iTermScriptHistoryEntryDidChangeNotification
                    object:self
                  userInfo:@{
                    iTermScriptHistoryEntryDelta : output,
                    iTermScriptHistoryEntryFieldKey :
                        iTermScriptHistoryEntryFieldLogsValue
                  }];
}

- (void)addClientOriginatedRPC:(NSString *)rpc {
  NSString *string =
      [NSString stringWithFormat:@"Script → iTerm2 %@:\n%@\n",
                                 [gScriptHistoryDateFormatter
                                     stringFromDate:[NSDate date]],
                                 rpc];
  [self appendCalls:string];
  [[NSNotificationCenter defaultCenter]
      postNotificationName:iTermScriptHistoryEntryDidChangeNotification
                    object:self
                  userInfo:@{
                    iTermScriptHistoryEntryDelta : string,
                    iTermScriptHistoryEntryFieldKey :
                        iTermScriptHistoryEntryFieldRPCValue
                  }];
}

- (void)addServerOriginatedRPC:(NSString *)rpc {
  NSString *string =
      [NSString stringWithFormat:@"Script ← iTerm2 %@:\n%@\n",
                                 [gScriptHistoryDateFormatter
                                     stringFromDate:[NSDate date]],
                                 rpc];
  [self appendCalls:string];
  [[NSNotificationCenter defaultCenter]
      postNotificationName:iTermScriptHistoryEntryDidChangeNotification
                    object:self
                  userInfo:@{
                    iTermScriptHistoryEntryDelta : string,
                    iTermScriptHistoryEntryFieldKey :
                        iTermScriptHistoryEntryFieldRPCValue
                  }];
}

- (pid_t)onlyPid {
  if (self.pids.count != 1) {
    return 0;
  }
  return self.pids.firstObject.intValue;
}

- (void)apiDidStop:(NSNotification *)notification {
  self.terminatedByUser = YES;
  if (self.onlyPid > 0) {
    [self kill:9];
  }
  [self stopRunning];
}

- (void)kill {
  [self addOutput:@"\n*Terminate button pressed*\n"];
  self.terminatedByUser = YES;
  if (self.onlyPid > 0) {
    [self kill:1];
  }
  [self.websocketConnection abortWithCompletion:nil];
}

- (void)kill:(int)signal {
  const pid_t pid = self.onlyPid;
  if (pid <= 0) {
    return;
  }
  pid_t pgid = getpgid(pid);
  if (pgid <= 0) {
    DLog(@"Failed to get the process group id %@", @(errno));
    kill(pid, signal);
    return;
  }

  killpg(pgid, signal);
}
- (void)stopRunning {
  _isRunning = NO;
  [[NSNotificationCenter defaultCenter]
      postNotificationName:iTermScriptHistoryEntryDidChangeNotification
                    object:self];
}

- (void)appendLogs:(NSString *)delta {
  if (delta.length == 0) {
    return;
  }
  BOOL endsWithNewline = [delta hasSuffix:@"\n"];
  if (endsWithNewline) {
    delta = [delta substringWithRange:NSMakeRange(0, delta.length - 1)];
  }
  NSArray<NSString *> *newLines = [delta componentsSeparatedByString:@"\n"];
  if (_lastLogLineContinues) {
    NSString *amended =
        [_logLines.lastObject stringByAppendingString:newLines.firstObject];
    newLines = [newLines subarrayWithRange:NSMakeRange(1, newLines.count - 1)];
    _logLines[_logLines.count - 1] = amended;
  }
  [_logLines addObjectsFromArray:newLines];
  _lastLogLineContinues = !endsWithNewline;

  while (_logLines.count > 1000) {
    [_logLines removeObjectAtIndex:0];
  }
}

- (void)appendCalls:(NSString *)delta {
  [_callEntries addObject:delta];
  while (_callEntries.count > 100) {
    [_callEntries removeObjectAtIndex:0];
  }
}

@end

NSString *const iTermScriptHistoryNumberOfEntriesDidChangeNotification =
    @"iTermScriptHistoryNumberOfEntriesDidChangeNotification";

@implementation iTermScriptHistory {
  NSMutableArray<iTermScriptHistoryEntry *> *_entries;
  NSMutableSet<NSNumber *> *_replPIDs;
  BOOL _haveAddedAPSLoggingEntry;
  BOOL _haveAddedDynamicProfilesLoggingEntry;
}

+ (instancetype)sharedInstance {
  static id instance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[self alloc] init];
  });
  return instance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _entries = [NSMutableArray array];
    [self addAPSLoggingEntryIfNeeded];
    [_entries addObject:[iTermScriptHistoryEntry globalEntry]];
    _replPIDs = [NSMutableSet set];
  }
  return self;
}

- (void)addAPSLoggingEntryIfNeeded {
  if (_haveAddedAPSLoggingEntry) {
    return;
  }
  if ([iTermUserDefaults enableAutomaticProfileSwitchingLogging]) {
    _haveAddedAPSLoggingEntry = YES;
    [_entries addObject:[iTermScriptHistoryEntry apsEntry]];
    if (_entries.count != 1) {
      [[NSNotificationCenter defaultCenter]
          postNotificationName:
              iTermScriptHistoryNumberOfEntriesDidChangeNotification
                        object:self];
    }
  }
}

- (void)addDynamicProfilesLoggingEntryIfNeeded {
  if (_haveAddedDynamicProfilesLoggingEntry) {
    return;
  }
  _haveAddedDynamicProfilesLoggingEntry = YES;
  [_entries addObject:[iTermScriptHistoryEntry dynamicProfilesEntry]];
  if (_entries.count != 1) {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:
            iTermScriptHistoryNumberOfEntriesDidChangeNotification
                      object:self];
  }
}

- (NSArray<iTermScriptHistoryEntry *> *)runningEntries {
  return [self.entries
      filteredArrayUsingBlock:^BOOL(iTermScriptHistoryEntry *anObject) {
        return anObject.isRunning;
      }];
}

- (void)addHistoryEntry:(iTermScriptHistoryEntry *)entry {
  [_entries addObject:entry];
  [[NSNotificationCenter defaultCenter]
      postNotificationName:
          iTermScriptHistoryNumberOfEntriesDidChangeNotification
                    object:self];
}

- (iTermScriptHistoryEntry *)entryWithIdentifier:(NSString *)identifier {
  return [_entries objectPassingTest:^BOOL(iTermScriptHistoryEntry *element,
                                           NSUInteger index, BOOL *stop) {
    return [element.identifier isEqualToString:identifier];
  }];
}

- (iTermScriptHistoryEntry *)runningEntryWithPath:(NSString *)path {
  return [self.runningEntries
      objectPassingTest:^BOOL(iTermScriptHistoryEntry *entry, NSUInteger index,
                              BOOL *stop) {
        return [NSObject object:entry.path isEqualToObject:path];
      }];
}

- (iTermScriptHistoryEntry *)runningEntryWithFullPath:(NSString *)fullPath {
  return [self.runningEntries
      objectPassingTest:^BOOL(iTermScriptHistoryEntry *entry, NSUInteger index,
                              BOOL *stop) {
        return [NSObject object:entry.fullPath isEqualToObject:fullPath];
      }];
}

@end

NS_ASSUME_NONNULL_END
