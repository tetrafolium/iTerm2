//
//  VT100OtherParser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "VT100Token.h"
#import <Foundation/Foundation.h>

@interface VT100OtherParser : NSObject

+ (void)decodeBytes:(unsigned char *)datap
             length:(int)datalen
          bytesUsed:(int *)rmlen
              token:(VT100Token *)result
           encoding:(NSStringEncoding)encoding;

@end
