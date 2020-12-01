//
//  ToolPasteHistory.h
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//

#import <Cocoa/Cocoa.h>

#import "FutureMethods.h"
#import "PasteboardHistory.h"
#import "iTermToolbeltView.h"

@interface ToolPasteHistory
    : NSView <ToolbeltTool, NSTableViewDataSource, NSTableViewDelegate>

@end
