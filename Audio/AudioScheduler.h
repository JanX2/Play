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
#include <mach/mach.h>

// ========================================
// Dictionary Keys
// ========================================
extern NSString * const		AudioSchedulerObjectKey;			// AudioScheduler
extern NSString * const		ScheduledAudioRegionObjectKey;		// ScheduledAudioRegion

@class ScheduledAudioRegion;

@interface AudioScheduler : NSObject
{
	NSUInteger				_numberSlices;
	NSUInteger				_framesPerSlice;
	
	AudioTimeStamp			_scheduledStartTime;

	NSMutableArray			*_scheduledAudioRegions;

	ScheduledAudioRegion	*_regionBeingScheduled;
	ScheduledAudioRegion	*_regionBeingRendered;

	semaphore_t				_semaphore;
	
	id						_delegate;
}

// Buffer size information (set at object creation)
- (NSUInteger) numberOfSlicesInBuffer;
- (NSUInteger) numberOfFramesPerSlice;

// The ScheduledSoundPlayer AudioUnit on which to schedule audio slices
@property (atomic, readwrite, assign) AudioUnit audioUnit;

// An optional delegate to receive notifications
- (id) delegate;
- (void) setDelegate:(id)delegate;

// The time to play the first slice
- (AudioTimeStamp) scheduledStartTime;
- (void) setScheduledStartTime:(AudioTimeStamp)scheduledStartTime;

// Add or remove a ScheduledAudioRegion to be played
- (void) scheduleAudioRegion:(ScheduledAudioRegion *)scheduledAudioRegion;
- (void) unscheduleAudioRegion:(ScheduledAudioRegion *)scheduledAudioRegion;

// The current ScheduledAudioRegion being rendered
- (ScheduledAudioRegion *) regionBeingScheduled;
- (ScheduledAudioRegion *) regionBeingRendered;

// Start scheduling audio
- (void) startScheduling;

// Stop scheduling audio (doesn't reset internal state)
- (void) stopScheduling;

// YES if this object is actively scheduling audio for rendering, NO otherwise
@property (atomic, readonly, assign, getter=isScheduling) BOOL scheduling;

// YES if this object's scheduled audio is rendering, NO otherwise
- (BOOL) isRendering;

// Unschedule any scheduled audio and reset current play time (preserves scheduling and rendering regions)
- (void) reset;

// Same as reset, but also unschedules all scheduled regions and clears the scheduling and rendering regions
- (void) clear;

// The current play time (only valid while scheduling)
- (AudioTimeStamp) currentPlayTime;

// Query the number of audio frames scheduled and rendered (since startScheduling was called)
@property (atomic, readonly, assign) SInt64 framesScheduled;
@property (atomic, readonly, assign) SInt64 framesRendered;

@end

// Delegate methods
@interface NSObject (AudioSchedulerDelegateMethods)
- (void) audioSchedulerStartedScheduling:(AudioScheduler *)scheduler;
- (void) audioSchedulerStoppedScheduling:(AudioScheduler *)scheduler;

- (void) audioSchedulerStartedSchedulingRegion:(NSDictionary *)schedulerAndRegion;
- (void) audioSchedulerFinishedSchedulingRegion:(NSDictionary *)schedulerAndRegion;

- (void) audioSchedulerStartedRenderingRegion:(NSDictionary *)schedulerAndRegion;
- (void) audioSchedulerFinishedRenderingRegion:(NSDictionary *)schedulerAndRegion;
@end
