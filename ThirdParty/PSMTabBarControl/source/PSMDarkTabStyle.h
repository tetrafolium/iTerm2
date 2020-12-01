//
//  PSMDarkTabStyle.h
//  iTerm
//
//  Created by Brian Mock on 10/28/14.
//
//

#import "PSMTabStyle.h"
#import "PSMYosemiteTabStyle.h"
#import <Cocoa/Cocoa.h>

@interface PSMDarkTabStyle : PSMYosemiteTabStyle <PSMTabStyle>
+ (NSColor *)tabBarColorWhenMainAndActive:(BOOL)keyMainAndActive;
@end
