//
//  iTermShellIntegrationSecondPageViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/19.
//

#import <Cocoa/Cocoa.h>

#import "iTermShellIntegrationInstaller.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermShellIntegrationSecondPageViewController : NSViewController<iTermShellIntegrationInstallerViewController>
@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
@end

NS_ASSUME_NONNULL_END
