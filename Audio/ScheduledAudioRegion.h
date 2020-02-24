/*
 *  $Id$
 *
 *  Copyright (C) 2007 Stephen F. Booth <me@sbooth.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#import <Cocoa/Cocoa.h>
#include <AudioToolbox/AudioToolbox.h>

#import "AudioDecoderMethods.h"

// A class encapsulating an AudioDecoder and the buffers and associated internal state that 
// AudioScheduler needs to use a decoder
@interface ScheduledAudioRegion : NSObject
{
	BOOL						_atEnd;
	
	AudioTimeStamp				_startTime;
	
	ScheduledAudioSlice			*_sliceBuffer;
	NSArray<NSLock *>			*_sliceLocks;

	NSUInteger					_numberSlices;
	NSUInteger					_framesPerSlice;
}

+ (ScheduledAudioRegion *) scheduledAudioRegionWithDecoder:(id <AudioDecoderMethods>)decoder;
+ (ScheduledAudioRegion *) scheduledAudioRegionWithDecoder:(id <AudioDecoderMethods>)decoder startTime:(AudioTimeStamp)startTime;

- (id) initWithDecoder:(id <AudioDecoderMethods>)decoder;
- (id) initWithDecoder:(id <AudioDecoderMethods>)decoder startTime:(AudioTimeStamp)startTime;

@property (atomic, readwrite, strong) id <AudioDecoderMethods> decoder;

- (BOOL) atEnd;

- (AudioTimeStamp) startTime;
- (void) setStartTime:(AudioTimeStamp)startTime;

@property (atomic, readonly, assign) SInt64 framesScheduled;
@property (atomic, readonly, assign) SInt64 framesRendered;

- (NSUInteger) numberOfSlicesInBuffer;
- (NSUInteger) numberOfFramesPerSlice;

- (void) allocateBuffersWithSliceCount:(NSUInteger)sliceCount frameCount:(NSUInteger)frameCount;
- (void) clearSliceBuffer;
- (void) clearSlice:(NSUInteger)sliceIndex;

- (void) clearFramesScheduled;
- (void) clearFramesRendered;

- (UInt32) readAudioInSlice:(NSUInteger)sliceIndex;

- (ScheduledAudioSlice *) buffer;
- (ScheduledAudioSlice *) sliceAtIndex:(NSUInteger)sliceIndex;

- (void) lockSlice:(NSUInteger)sliceIndex;
- (void) lockSliceWithReference:(ScheduledAudioSlice *)slice;
- (void) unlockSlice:(NSUInteger)sliceIndex;
- (void) unlockSliceWithReference:(ScheduledAudioSlice *)slice;

- (void) scheduledAdditionalFrames:(UInt32)frameCount;
- (void) renderedAdditionalFrames:(UInt32)frameCount;
@end
