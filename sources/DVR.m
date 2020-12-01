// -*- mode:objc -*-
/*
 **  DVR.m
 **
 **  Copyright 2010
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Implements a "digital video recorder" for iTerm2.
 **    This is used by the "instant replay" feature to record and
 **    play back the screen contents.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "DVR.h"
#import "DVRIndexEntry.h"
#import "NSData+iTerm.h"
#import "ScreenChar.h"
#include <sys/time.h>

@implementation DVR {
    DVRBuffer* buffer_;
    int capacity_;
    NSMutableArray* decoders_;
    DVREncoder* encoder_;
}

@synthesize readOnly = readOnly_;

- (instancetype)initWithBufferCapacity:(int)bytes {
    self = [super init];
    if (self) {
        buffer_ = [DVRBuffer alloc];
        [buffer_ initWithBufferCapacity:bytes];
        capacity_ = bytes;
        decoders_ = [[NSMutableArray alloc] init];
        encoder_ = [DVREncoder alloc];
        [encoder_ initWithBuffer:buffer_];
    }
    return self;
}

- (void)dealloc
{
    [decoders_ release];
    [encoder_ release];
    [buffer_ release];
    [super dealloc];
}

- (void)appendFrame:(NSArray<NSData *> *)frameLines
    length:(int)length
    cleanLines:(NSIndexSet *)cleanLines
    info:(DVRFrameInfo*)info
{
    if (readOnly_) {
        return;
    }
    if (length > [buffer_ capacity] / 2) {
        // Protect the buffer from overflowing if you have a really big window.
        return;
    }
    _empty = NO;
    int prevFirst = [buffer_ firstKey];
    if ([encoder_ reserve:length]) {
        // Leading frames were freed. Invalidate them in all decoders.
        for (DVRDecoder* decoder in decoders_) {
            int newFirst = [buffer_ firstKey];
            for (int i = prevFirst; i < newFirst; ++i) {
                [decoder invalidateIndex:i];
            }
        }
    }
    [encoder_ appendFrame:frameLines
              length:length
              cleanLines:cleanLines
              info:info];
}

- (DVRDecoder*)getDecoder
{
    DVRDecoder* decoder = [[DVRDecoder alloc] initWithBuffer:buffer_];
    [decoders_ addObject:decoder];
    [decoder release];
    return decoder;
}

- (void)releaseDecoder:(DVRDecoder*)decoder
{
    [decoders_ removeObject:decoder];
}

- (long long)lastTimeStamp
{
    DVRIndexEntry* entry = [buffer_ entryForKey:[buffer_ lastKey]];
    if (!entry) {
        return 0;
    }
    return entry->info.timestamp;
}

- (long long)firstTimeStamp
{
    DVRIndexEntry* entry = [buffer_ entryForKey:[buffer_ firstKey]];
    if (!entry) {
        return 0;
    }
    return entry->info.timestamp;
}

- (long long)firstTimestampAfter:(long long)timestamp {
    DVRIndexEntry *entry = [buffer_ firstEntryWithTimestampAfter:timestamp];
    if (!entry) {
        return 0;
    }
    return entry->info.timestamp;
}

- (NSDictionary *)dictionaryValue {
    return [self dictionaryValueFrom:self.firstTimeStamp to:self.lastTimeStamp];
}

- (NSDictionary *)dictionaryValueFrom:(long long)from to:(long long)to {
    DVR *dvr;
    if (from == self.firstTimeStamp && to == self.lastTimeStamp) {
        dvr = self;
    } else {
        dvr = [[self copyWithFramesFrom:from to:to] autorelease];
    }
    return @ { @"version":
               @1,
               @"capacity":
               @(dvr->capacity_),
               @"buffer":
               dvr->buffer_.dictionaryValue
             };
}

- (BOOL)loadDictionary:(NSDictionary *)dict {
    if (!dict) {
        return NO;
    }
    if ([dict[@"version"] integerValue] != 1) {
        return NO;
    }
    int capacity = [dict[@"capacity"] intValue];
    if (capacity == 0) {
        return NO;
    }
    NSDictionary *bufferDict = dict[@"buffer"];
    if (!bufferDict) {
        return NO;
    }

    [buffer_ release];
    buffer_ = [DVRBuffer alloc];
    [buffer_ initWithBufferCapacity:capacity];
    capacity_ = capacity;

    [decoders_ release];
    decoders_ = [[NSMutableArray alloc] init];

    [encoder_ release];
    encoder_ = [DVREncoder alloc];
    [encoder_ initWithBuffer:buffer_];

    if (![buffer_ loadFromDictionary:bufferDict]) {
        return NO;
    }
    readOnly_ = YES;
    return YES;
}

- (instancetype)copyWithFramesFrom:(long long)from to:(long long)to {
    DVR *theCopy = [[DVR alloc] initWithBufferCapacity:capacity_];
    DVRDecoder *decoder = [self getDecoder];
    if ([decoder seek:from]) {
        while (decoder.timestamp <= to || to == -1) {
            screen_char_t *frame = (screen_char_t *)[decoder decodedFrame];
            NSMutableArray *lines = [NSMutableArray array];
            DVRFrameInfo info = [decoder info];
            int offset = 0;
            const int lineLength = info.width + 1;
            for (int i = 0; i < info.height; i++) {
                NSMutableData *data = [NSMutableData dataWithBytes:frame + offset length:lineLength * sizeof(screen_char_t)];
                [lines addObject:data];
                offset += lineLength;
            }
            [theCopy appendFrame:lines
                     length:[decoder length]
                     cleanLines:nil
                     info:&info];
            if (![decoder next]) {
                break;
            }
        }
    }
    [self releaseDecoder:decoder];
    return theCopy;
}

@end

