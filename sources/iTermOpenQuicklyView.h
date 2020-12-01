#import "SolidColorView.h"
#import <Cocoa/Cocoa.h>

// This is a flipped view so that the scrollView can have its frame set
// according to its top left coordinate, which is simple to compute since the
// window changes height. On awakeFromNib, it flips its subviews so reality
// matches Interface Builder.
@interface iTermOpenQuicklyView : SolidColorView

@end
