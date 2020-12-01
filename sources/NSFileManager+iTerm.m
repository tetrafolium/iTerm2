//
//  NSFileManager+DirectoryLocations.m
//
//  Created by Matt Gallagher on 06 May 2010
//
//  This software is provided 'as-is', without any express or implied
//  warranty. In no event will the authors be held liable for any damages
//  arising from the use of this software. Permission is granted to anyone to
//  use this software for any purpose, including commercial applications, and to
//  alter it and redistribute it freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//  3. This notice may not be removed or altered from any source
//     distribution.
//

// This code has been altered.

#import "NSFileManager+iTerm.h"

#import "DebugLogging.h"
#import "RegexKitLite.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAutoMasterParser.h"
#import "iTermWarning.h"
#include <sys/mount.h>
#include <sys/param.h>

enum {
  DirectoryLocationErrorNoPathFound,
  DirectoryLocationErrorFileExistsAtLocation
};

NSString *const DirectoryLocationDomain = @"DirectoryLocationDomain";

@implementation NSFileManager (iTerm)

/**
 * Locate a standard directory. Optionally append a subdirectory to the path.
 * Create the chain of directories if needed.
 *
 * @param searchPathDirectory Search path for @c
 * NSSearchPathForDirectoriesInDomains.
 * @param domainMask Domain mask for @c NSSearchPathForDirectoriesInDomains
 * @param appendComponent Subdirectory to append to path. Optional.
 * @param errorOut Optional, will be set to NSError on failure
 *
 * @return Path or nil
 */
- (NSString *)findOrCreateDirectory:(NSSearchPathDirectory)searchPathDirectory
                           inDomain:(NSSearchPathDomainMask)domainMask
                appendPathComponent:(NSString *)appendComponent
                              error:(NSError **)errorOut {
  NSArray *paths =
      NSSearchPathForDirectoriesInDomains(searchPathDirectory, domainMask, YES);
  DLog(@"Search paths are %@", paths);
  if (!paths.count) {
    if (errorOut) {
      NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey : @"No path found for directory in domain.",
        @"NSSearchPathDirectory" : @(searchPathDirectory),
        @"NSSearchPathDomainMask" : @(domainMask)
      };
      *errorOut = [NSError errorWithDomain:DirectoryLocationDomain
                                      code:DirectoryLocationErrorNoPathFound
                                  userInfo:userInfo];
    }
    DLog(@"Fail, no paths");
    return nil;
  }

  // Only the first one returned is interesting. Append subdirectory if needed.
  NSString *resolvedPath = paths[0];
  if (appendComponent) {
    resolvedPath =
        [resolvedPath stringByAppendingPathComponent:appendComponent];
    DLog(@"After appending %@, have %@", appendComponent, resolvedPath);
  }

  // Create if needed.
  NSError *error = nil;
  BOOL success = [self createDirectoryAtPath:resolvedPath
                 withIntermediateDirectories:YES
                                  attributes:nil
                                       error:&error];
  if (!success) {
    if (errorOut) {
      *errorOut = error;
    }
    DLog(@"Create dir of %@ failed with %@, return nil", resolvedPath, error);
    return nil;
  }

  if (errorOut) {
    *errorOut = nil;
  }
  DLog(@"Return %@", resolvedPath);
  return resolvedPath;
}

//
// applicationSupportDirectory
//
// Returns the path to the applicationSupportDirectory (creating it if it
// doesn't exist).
//
- (NSString *)applicationSupportDirectory {
  NSString *executableName = [[[NSBundle mainBundle] infoDictionary]
      objectForKey:(id)kCFBundleExecutableKey];
  NSError *error;
  DLog(@"Want app support directory");
  NSString *result = [self findOrCreateDirectory:NSApplicationSupportDirectory
                                        inDomain:NSUserDomainMask
                             appendPathComponent:executableName
                                           error:&error];
  if (result == nil) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      [iTermWarning
          showWarningWithTitle:
              [NSString stringWithFormat:
                            @"There was a problem finding or creating your "
                            @"application support directory. iTerm2 won't work "
                            @"very well until this problem is fixed.\n\nIt "
                            @"should be at ~/Library/Application "
                            @"Support/iTerm2.\n\nThe error was:\n%@",
                            error.localizedDescription]
                       actions:@[ @"OK" ]
                     accessory:nil
                    identifier:@"NoSyncAppSupportFail"
                   silenceable:kiTermWarningTypePersistent
                       heading:@"Problem with Application Support Directory"
                        window:nil];
    });
  }

  return result;
}

- (NSString *)libraryDirectoryFor:(NSString *)app {
  NSError *error;
  NSString *result = [self findOrCreateDirectory:NSLibraryDirectory
                                        inDomain:NSUserDomainMask
                             appendPathComponent:app
                                           error:&error];
  if (!result) {
    ELog(@"Unable to find or create application support directory:\n%@", error);
  }
  return result;
}

- (NSString *)legacyApplicationSupportDirectory {
  NSError *error;
  NSString *result = [self findOrCreateDirectory:NSApplicationSupportDirectory
                                        inDomain:NSUserDomainMask
                             appendPathComponent:@"iTerm"
                                           error:&error];
  if (!result) {
    ELog(@"Unable to find or create application support directory:\n%@", error);
  }
  return result;
}

- (NSString *)versionNumberFilename {
  return [[self applicationSupportDirectory]
      stringByAppendingPathComponent:@"version.txt"];
}

- (NSString *)scriptsPath {
  return [[self applicationSupportDirectory]
      stringByAppendingPathComponent:@"Scripts"];
}

- (NSString *)legacyAutolaunchScriptPath {
  return [[self scriptsPath] stringByAppendingPathComponent:@"AutoLaunch.scpt"];
}

- (NSString *)autolaunchScriptPath {
  return [[self scriptsPath] stringByAppendingPathComponent:@"AutoLaunch"];
}

- (NSString *)quietFilePath {
  return [[self applicationSupportDirectory]
      stringByAppendingPathComponent:@"quiet"];
}

- (NSString *)temporaryDirectory {
  // Create a unique directory in the system temporary directory
  NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString];
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:guid];
  if (![self createDirectoryAtPath:path
          withIntermediateDirectories:NO
                           attributes:nil
                                error:nil]) {
    return nil;
  }
  return path;
}

- (NSString *)downloadsDirectory {
  NSString *override = [iTermAdvancedSettingsModel downloadsDirectory];
  if (override.length && [self isWritableFileAtPath:override]) {
    return override;
  }

  NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
      NSDownloadsDirectory, NSUserDomainMask, YES);
  for (NSString *path in paths) {
    if ([self isWritableFileAtPath:path]) {
      return path;
    }
  }

  return nil;
}

- (NSString *)desktopDirectory {
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory,
                                                       NSUserDomainMask, YES);
  return [paths firstObject];
}

- (NSString *)homeDirectoryDotDir {
  NSString *homedir = NSHomeDirectory();
  NSString *dotdir = [homedir stringByAppendingPathComponent:@".iterm2"];

  BOOL isdir = NO;

  // Try to create ~/.iterm2 if needed
  if (![self fileExistsAtPath:dotdir isDirectory:&isdir]) {
    NSError *error = nil;
    [self createDirectoryAtPath:dotdir
        withIntermediateDirectories:NO
                         attributes:nil
                              error:&error];
    if (error) {
      DLog(@"Couldn't create %@: %@", dotdir, error);
      return nil;
    }
  }
  if (!isdir) {
    return nil;
  }
  return dotdir;
}

- (BOOL)directoryIsWritable:(NSString *)dir {
  if ([[dir stringByTrimmingCharactersInSet:[NSCharacterSet
                                                whitespaceCharacterSet]]
          length] == 0) {
    return NO;
  }

  NSString *filename =
      [NSString stringWithFormat:@"%@/.testwritable.%d", dir, (int)getpid()];
  NSError *error = nil;
  [@"test" writeToFile:filename
            atomically:YES
              encoding:NSUTF8StringEncoding
                 error:&error];
  if (error) {
    return NO;
  }
  unlink([filename UTF8String]);
  return YES;
}

- (BOOL)fileHasForbiddenPrefix:(NSString *)filename
        additionalNetworkPaths:(NSArray<NSString *> *)additionalNetworkPaths {
  DLog(@"Additional network paths are: %@", additionalNetworkPaths);
  // Augment list of additional paths with nfs automounter mount points.
  NSMutableArray *networkPaths = [additionalNetworkPaths mutableCopy];
  [networkPaths
      addObjectsFromArray:[[iTermAutoMasterParser sharedInstance] mountpoints]];
  DLog(@"Including automounter paths, ignoring: %@", networkPaths);

  for (NSString *networkPath in networkPaths) {
    if (!networkPath.length) {
      continue;
    }
    NSString *path;
    if (![networkPath hasSuffix:@"/"]) {
      path = [networkPath stringByAppendingString:@"/"];
    } else {
      path = networkPath;
    }
    if ([filename hasPrefix:path]) {
      DLog(@"Filename %@ has prefix of ignored path %@", filename, networkPath);
      return YES;
    }
  }
  return NO;
}

- (BOOL)fileIsLocal:(NSString *)filename
    additionalNetworkPaths:(NSArray<NSString *> *)additionalNetworkPaths {
  if ([iTermAdvancedSettingsModel enableSemanticHistoryOnNetworkMounts]) {
    DLog(@"** Skipping network-mount check because the advanced pref is on!!! "
         @"**");
    return YES;
  }
  if ([self fileHasForbiddenPrefix:filename
            additionalNetworkPaths:additionalNetworkPaths]) {
    return NO;
  }

  struct statfs buf;
  const int rc = statfs([filename UTF8String], &buf);
  if (rc != 0) {
    return YES;
  }
  if (buf.f_flags & MNT_LOCAL) {
    return YES;
  }
  return NO;
}

- (BOOL)fileExistsAtPathLocally:(NSString *)filename
         additionalNetworkPaths:(NSArray<NSString *> *)additionalNetworkPaths {
  if (![self fileIsLocal:filename
          additionalNetworkPaths:additionalNetworkPaths]) {
    return NO;
  }
  return [self fileExistsAtPath:filename];
}

- (BOOL)itemIsDirectory:(NSString *)path {
  NSDictionary<NSFileAttributeKey, id> *attributes =
      [self attributesOfItemAtPath:path error:nil];
  return [attributes[NSFileType] isEqual:NSFileTypeDirectory];
}

- (BOOL)itemIsSymlink:(NSString *)path {
  NSDictionary<NSFileAttributeKey, id> *attributes =
      [self attributesOfItemAtPath:path error:nil];
  return [attributes[NSFileType] isEqual:NSFileTypeSymbolicLink];
}

- (BOOL)directoryEmpty:(NSString *)path {
  NSDirectoryEnumerator *enumerator = [self enumeratorAtPath:path];
  for (NSString *file in enumerator) {
    if (file) {
      return NO;
    }
  }
  return YES;
}

- (NSArray<NSString *> *)it_itemsInDirectory:(NSString *)path {
  NSMutableArray<NSString *> *results = [NSMutableArray array];
  NSDirectoryEnumerator<NSString *> *enumerator = [self enumeratorAtPath:path];
  for (NSString *name in enumerator) {
    [results addObject:name];
    [enumerator skipDescendants];
  }
  return results;
}

+ (NSString *)pathToSaveFileInFolder:(NSString *)destinationDirectory
                       preferredName:(NSString *)preferredName {
  NSString *finalDestination = nil;
  int retries = 0;
  do {
    NSString *name =
        retries > 0
            ? [NSString
                  stringWithFormat:@"%@ (%d).%@",
                                   preferredName.stringByDeletingPathExtension,
                                   retries, preferredName.pathExtension]
            : preferredName;
    finalDestination =
        [destinationDirectory stringByAppendingPathComponent:name];
    ++retries;
  } while ([[NSFileManager defaultManager] fileExistsAtPath:finalDestination]);
  return finalDestination;
}

- (id)monitorFile:(NSString *)path block:(void (^)(long))block {
  DLog(@"monitor %@", path);
  const int fileDescriptor = open(path.UTF8String, O_EVTONLY);
  if (fileDescriptor < 0) {
    DLog(@"Failed to open %@", path);
    return nil;
  }

  dispatch_queue_t queue =
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  const unsigned long mask =
      (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND |
       DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_LINK | DISPATCH_VNODE_RENAME |
       DISPATCH_VNODE_REVOKE);
  __block dispatch_source_t source = dispatch_source_create(
      DISPATCH_SOURCE_TYPE_VNODE, fileDescriptor, mask, queue);
  dispatch_source_set_event_handler(source, ^{
    unsigned long flags = dispatch_source_get_data(source);
    dispatch_async(dispatch_get_main_queue(), ^{
      block(flags);
    });
  });
  dispatch_source_set_cancel_handler(source, ^(void) {
    close(fileDescriptor);
  });
  dispatch_resume(source);

  return source;
}

- (void)stopMonitoringFileWithToken:(id)token {
  if (!token) {
    return;
  }
  dispatch_source_t source = token;
  dispatch_source_cancel(source);
}

@end
