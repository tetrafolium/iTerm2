//
//  iTermScriptImporter.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Imports a script from a zip file.
@interface iTermScriptImporter : NSObject

// url is path to zip file
+ (void)importScriptFromURL:(NSURL *)url
              userInitiated:(BOOL)userInitiated
            offerAutoLaunch:(BOOL)offerAutoLaunch
                 completion:(void (^)(NSString *_Nullable errorMessage,
                                      BOOL quiet, NSURL *location))completion;

@end

NS_ASSUME_NONNULL_END
