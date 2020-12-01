//
//  SIGVerificationAlgorithm.m
//  SignedArchive
//
//  Created by George Nachman on 12/18/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGSHA2VerificationAlgorithm.h"
#import <Foundation/Foundation.h>

NSArray<NSString *> *SIGVerificationDigestAlgorithmNames(void) {
  return @[ [SIGSHA2VerificationAlgorithm name] ];
}
