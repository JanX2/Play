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

#import "AudioScheduler.h"
#import "ScheduledAudioRegion.h"

// ========================================
// Dictionary keys
// ========================================
NSString * const	AudioSchedulerObjectKey				= @"org.sbooth.Play.AudioScheduler";
NSString * const	ScheduledAudioRegionObjectKey		= @"org.sbooth.Play.ScheduledAudioRegion";

// ========================================
// Symbolic Constants
// ========================================
NSString * const	AudioSchedulerRunLoopMode			= @"org.sbooth.Play.AudioScheduler.RunLoopMode";


// ========================================
// Private properties
// ========================================
@interface AudioScheduler ()

@property (atomic, readonly, assign) semaphore_t semaphore;

@property (atomic, readwrite, assign) SInt64 framesScheduled;
@property (atomic, readwrite, assign) SInt64 framesRendered;

@property (atomic, readwrite, assign, getter=isScheduling, setter=scheduling:) BOOL scheduling;
@property (atomic, readwrite, assign) BOOL keepScheduling;

@end

// ========================================
// Private methods
// ========================================
@interface AudioScheduler (Private)

- (NSMutableArray *) scheduledAudioRegions;

- (void) setRegionBeingScheduled:(ScheduledAudioRegion *)region;
- (void) setRegionBeingRendered:(ScheduledAudioRegion *)region;

- (void) scheduledAdditionalFrames:(UInt32)frameCount;
- (void) renderedAdditionalFrames:(UInt32)frameCount;

- (void) processSlicesInThread:(id)dummy;
- (void) setThreadPolicy;
@end

// ========================================
// AudioUnit callbacks
// ========================================
static void
scheduledAudioSliceCompletionProc(void *userData, ScheduledAudioSlice *slice)
{
	NSCParameterAssert(NULL != userData);
	NSCParameterAssert(NULL != slice);
	
	@autoreleasepool {
		NSArray					*dataArray	= (__bridge_transfer NSArray *)userData;
		AudioScheduler			*scheduler	= (AudioScheduler *)[dataArray objectAtIndex:0];
		ScheduledAudioRegion	*region		= (ScheduledAudioRegion *)[dataArray objectAtIndex:1];
		
		[region lockSliceWithReference:slice];
		
#if DEBUG
		if(kScheduledAudioSliceFlag_BeganToRenderLate & slice->mFlags)
			NSLog(@"AudioScheduler error: kScheduledAudioSliceFlag_BeganToRenderLate (starting sample %"PRId64 ")", (SInt64)slice->mTimeStamp.mSampleTime);
#endif
		
		// Determine if this render represents a  new region
		if(/*(kScheduledAudioSliceFlag_BeganToRender & slice->mFlags) &&*/ nil == [scheduler regionBeingRendered]) {
			
			// Update the scheduler
			[scheduler setRegionBeingRendered:region];
			
			// Notify the delegate
			if(nil != [scheduler delegate] && [[scheduler delegate] respondsToSelector:@selector(audioSchedulerStartedRenderingRegion:)])
				[[scheduler delegate] performSelectorOnMainThread:@selector(audioSchedulerStartedRenderingRegion:)
													   withObject:[NSDictionary dictionaryWithObjectsAndKeys:scheduler, AudioSchedulerObjectKey, [scheduler regionBeingRendered], ScheduledAudioRegionObjectKey, nil]
													waitUntilDone:NO];
		}
		
		// Record the number of frames rendered
		//	if(kScheduledAudioSliceFlag_BeganToRender & slice->mFlags)
		[scheduler renderedAdditionalFrames:slice->mNumberFrames];
		
		[region unlockSliceWithReference:slice];
		
		// Signal the scheduling thread that a slice is available for filling
		semaphore_signal([scheduler semaphore]);
		
		// Determine if region rendering is complete
		if([[scheduler regionBeingRendered] atEnd] && (scheduler.regionBeingRendered.framesRendered == scheduler.regionBeingRendered.framesScheduled)) {
			
			// Notify the delegate
			if(nil != [scheduler delegate] && [[scheduler delegate] respondsToSelector:@selector(audioSchedulerFinishedRenderingRegion:)])
				[[scheduler delegate] performSelectorOnMainThread:@selector(audioSchedulerFinishedRenderingRegion:)
													   withObject:[NSDictionary dictionaryWithObjectsAndKeys:scheduler, AudioSchedulerObjectKey, [scheduler regionBeingRendered], ScheduledAudioRegionObjectKey, nil]
													waitUntilDone:NO];
			
			// Update the scheduler
			[scheduler setRegionBeingRendered:nil];
		}
	}
}

@implementation AudioScheduler {
	AudioUnit				_audioUnit;
}

- (id) init
{	
	if((self = [super init])) {
		kern_return_t result = semaphore_create(mach_task_self(), &_semaphore, SYNC_POLICY_FIFO, 0);		
		if(KERN_SUCCESS != result) {
			mach_error("Couldn't create semaphore", result);
			return nil;
		}
		
		_scheduledStartTime.mFlags		= kAudioTimeStampSampleTimeValid;
		_scheduledStartTime.mSampleTime	= 0;
		
		_numberSlices		= [[NSUserDefaults standardUserDefaults] integerForKey:@"numberOfAudioSlicesInBuffer"];
		_framesPerSlice		= [[NSUserDefaults standardUserDefaults] integerForKey:@"numberOfAudioFramesPerSlice"];
	}
	return self;
}

- (void) dealloc
{
	if (self.isScheduling)
		[self stopScheduling];
}

- (NSUInteger) numberOfSlicesInBuffer
{
	return _numberSlices;
}

- (NSUInteger) numberOfFramesPerSlice
{
	return _framesPerSlice;
}

- (AudioUnit) audioUnit
{
	return _audioUnit;
}

- (void) setAudioUnit:(AudioUnit)audioUnit
{
	NSParameterAssert(NULL != audioUnit);

//	// Ensure the audio unit is a ScheduledSoundPlayer
//	ComponentDescription componentDescription;
//    componentDescription.componentType = 0;
//	ComponentResult err = GetComponentInfo((Component)_audioUnit,
//										   &componentDescription,
//										   NULL,
//										   NULL,
//										   NULL);
//	if(noErr != err || 
//	   kAudioUnitType_Generator != componentDescription.componentType || 
//	   kAudioUnitSubType_ScheduledSoundPlayer != componentDescription.componentSubType) {
//		NSLog(@"Illegal audio unit passed to setAudioUnit");
//		return;
//	}

	_audioUnit = audioUnit;
}

- (id) delegate
{
	return _delegate;
}

- (void) setDelegate:(id)delegate
{
	_delegate = delegate;
}

- (AudioTimeStamp) scheduledStartTime
{
	return _scheduledStartTime;
}

- (void) setScheduledStartTime:(AudioTimeStamp)scheduledStartTime
{
	NSParameterAssert(kAudioTimeStampSampleTimeValid & scheduledStartTime.mFlags);
	_scheduledStartTime = scheduledStartTime;
}

- (void) scheduleAudioRegion:(ScheduledAudioRegion *)scheduledAudioRegion
{
	NSParameterAssert(nil != scheduledAudioRegion);
	
	// Setup the buffers inside the region we will be using
	[scheduledAudioRegion allocateBuffersWithSliceCount:[self numberOfSlicesInBuffer] frameCount:[self numberOfFramesPerSlice]];
	
	@synchronized([self scheduledAudioRegions]) {
		[[self scheduledAudioRegions] addObject:scheduledAudioRegion];
	}

	semaphore_signal(self.semaphore);
}

- (void) unscheduleAudioRegion:(ScheduledAudioRegion *)scheduledAudioRegion
{
	NSParameterAssert(nil != scheduledAudioRegion);
	
	if([self regionBeingScheduled] == scheduledAudioRegion) {
		if (self.isScheduling)
			NSLog(@"Cannot unschedule the current ScheduledAudioRegion while scheduling audio slices");
		else
			// This operation is thread safe as long as the scheduling thread isn't active
			_regionBeingScheduled = nil;
		
		return;
	}
	
	@synchronized([self scheduledAudioRegions]) {
		[[self scheduledAudioRegions] removeObjectIdenticalTo:scheduledAudioRegion];
	}
}

- (ScheduledAudioRegion *) regionBeingScheduled
{
	return _regionBeingScheduled;
}

- (ScheduledAudioRegion *) regionBeingRendered
{
	return _regionBeingRendered;
}

- (void) startScheduling
{
	if ((self.audioUnit == NULL) || self.isScheduling) {
		return;
	}

	self.framesScheduled	= 0;
	self.framesRendered		= 0;
	self.keepScheduling		= YES;
	self.scheduling			= YES;
	
	[[self regionBeingScheduled] clearFramesScheduled];
	[[self regionBeingScheduled] clearFramesRendered];

	// Rather than set regionBeingRendered to nil, just clear to avoid repeat startedRenderingRegion: notifications
	[[self regionBeingRendered] clearFramesScheduled];
	[[self regionBeingRendered] clearFramesRendered];

	[NSThread detachNewThreadSelector:@selector(processSlicesInThread:) toTarget:self withObject:nil];
}

- (void) stopScheduling
{
	if (self.isScheduling == NO)
		return;
	
	// Signal the scheduling thread that it may exit
	self.keepScheduling = NO;
	semaphore_signal(self.semaphore);

	// Wait for the thread to terminate
	while(self.isScheduling)
		[[NSRunLoop currentRunLoop] runMode:AudioSchedulerRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
}

- (void) reset
{
	if (self.isScheduling)
		return;
	
	// Remove any scheduled slices by resetting the AUScheduledSoundPlayer
	ComponentResult result = AudioUnitReset(self.audioUnit,
											kAudioUnitScope_Global, 
											0);
	if(noErr != result)
		NSLog(@"AudioUnitReset failed: %ld", result);

	if(nil != [self regionBeingScheduled])
		[[self regionBeingScheduled] clearSliceBuffer];
	if(nil != [self regionBeingRendered])
		[[self regionBeingRendered] clearSliceBuffer];
	
	_scheduledStartTime.mFlags			= kAudioTimeStampSampleTimeValid;
	_scheduledStartTime.mSampleTime		= 0;
}

- (void) clear
{
	if (self.isScheduling)
		return;
	
	[self reset];
	
	[self setRegionBeingScheduled:nil];
	[self setRegionBeingRendered:nil];
	
	// This is thread safe because the scheduling thread is inactive
	[[self scheduledAudioRegions] removeAllObjects];
}

- (BOOL) isRendering
{
	AudioTimeStamp timeStamp = [self currentPlayTime];
	return (kAudioTimeStampSampleTimeValid & timeStamp.mFlags && -1 != timeStamp.mSampleTime);
}

- (AudioTimeStamp) currentPlayTime
{
	// Determine the last sample that was rendered
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmissing-field-initializers"
	AudioTimeStamp		timeStamp	= { 0 };
#pragma clang diagnostic pop
	UInt32				dataSize	= sizeof(AudioTimeStamp);
	ComponentResult		result		= AudioUnitGetProperty(self.audioUnit,
														   kAudioUnitProperty_CurrentPlayTime,
														   kAudioUnitScope_Global,
														   0,
														   &timeStamp,
														   &dataSize);

	if(noErr != result)
		NSLog(@"Unable to query kAudioUnitProperty_CurrentPlayTime");
	
	return timeStamp;
}


@end

@implementation AudioScheduler (Private)

- (semaphore_t)		semaphore						{ return _semaphore; }

- (NSMutableArray *) scheduledAudioRegions
{
	if(nil == _scheduledAudioRegions)
		_scheduledAudioRegions = [[NSMutableArray alloc] init];
	return _scheduledAudioRegions;
}

- (void) setRegionBeingScheduled:(ScheduledAudioRegion *)region
{
	_regionBeingScheduled = region;
}

- (void) setRegionBeingRendered:(ScheduledAudioRegion *)region
{
	_regionBeingRendered = region;
}

- (void) scheduledAdditionalFrames:(UInt32)frameCount
{
	self.framesScheduled += frameCount;
	[[self regionBeingScheduled] scheduledAdditionalFrames:frameCount];
}

- (void) renderedAdditionalFrames:(UInt32)frameCount
{
	self.framesRendered += frameCount;
	[[self regionBeingRendered] renderedAdditionalFrames:frameCount];
}

- (void) processSlicesInThread
{
	mach_timespec_t			timeout				= { 2, 0 };
	ScheduledAudioSlice		*slice				= NULL;
	UInt32					frameCount			= 0;
	BOOL					allFramesScheduled	= NO;
	NSUInteger				i;
	
	// Make this a high-priority thread
	[self setThreadPolicy];
	
	// Notify the delegate that scheduling has started
	if(nil != [self delegate] && [[self delegate] respondsToSelector:@selector(audioSchedulerStartedScheduling:)])
		[[self delegate] performSelectorOnMainThread:@selector(audioSchedulerStartedScheduling:) withObject:self waitUntilDone:NO];

	// Outer scheduling loop, for looping over regions
	while (self.keepScheduling) {

		// Grab the next ScheduledAudioRegion to work with
		if(nil == [self regionBeingScheduled]) {

			@synchronized([self scheduledAudioRegions]) {
				[self setRegionBeingScheduled:[[self scheduledAudioRegions] lastObject]];
				if(nil != [self regionBeingScheduled])
					[[self scheduledAudioRegions] removeLastObject];
			}

			// If a new region was found, notify the delegate
			if(nil != [self regionBeingScheduled]) {
				allFramesScheduled = NO;

				// Notify the delegate that the scheduling has been started for the current region
				if(nil != [self delegate] && [[self delegate] respondsToSelector:@selector(audioSchedulerStartedSchedulingRegion:)])
					[[self delegate] performSelectorOnMainThread:@selector(audioSchedulerStartedSchedulingRegion:)
													  withObject:[NSDictionary dictionaryWithObjectsAndKeys:self, AudioSchedulerObjectKey, _regionBeingScheduled, ScheduledAudioRegionObjectKey, nil]
												   waitUntilDone:NO];
			}
		}
		
		// Inner scheduling loop, for processing an individual region
		while(self.keepScheduling && nil != [self regionBeingScheduled] && NO == allFramesScheduled) {

			// Iterate through the slice buffer, scheduling audio as completed slices become available
			for(i = 0; i < [[self regionBeingScheduled] numberOfSlicesInBuffer]; ++i) {
				slice = [[self regionBeingScheduled] sliceAtIndex:i];

				// If the slice is marked as complete, re-use it
				if(kScheduledAudioSliceFlag_Complete & slice->mFlags) {
					[self.regionBeingScheduled lockSlice:i];

					// Prepare the slice
					[[self regionBeingScheduled] clearSlice:i];
					
					// Read some data
					frameCount = [[self regionBeingScheduled] readAudioInSlice:i];
					
					// EOS?
					if(0 == frameCount) {
						allFramesScheduled = YES;
						
						// Notify the delegate that the last frame of the current region has been scheduled
						if(nil != [self delegate] && [[self delegate] respondsToSelector:@selector(audioSchedulerFinishedSchedulingRegion:)])
							[[self delegate] performSelectorOnMainThread:@selector(audioSchedulerFinishedSchedulingRegion:)
															  withObject:[NSDictionary dictionaryWithObjectsAndKeys:self, AudioSchedulerObjectKey, _regionBeingScheduled, ScheduledAudioRegionObjectKey, nil]
														   waitUntilDone:NO];
						
						// This region is finished
						[self setRegionBeingScheduled:nil];
						
						break;
					}
					
					// To handle the case where the file contains fewer frames than the buffer,
					// pass the region and self to the callback proc to ensure that the callback
					// knows the ScheduledAudioRegion the audio that was just rendered came from
					NSArray *array = [[NSArray alloc] initWithObjects:self, [self regionBeingScheduled], nil];
					
					// Schedule it
					slice->mTimeStamp.mFlags		= kAudioTimeStampSampleTimeValid;
					slice->mTimeStamp.mSampleTime	= [self scheduledStartTime].mSampleTime + self.framesScheduled;
					slice->mCompletionProc			= scheduledAudioSliceCompletionProc;
					slice->mCompletionProcUserData	= (__bridge_retained void *)array;
					slice->mFlags					= 0;
					slice->mNumberFrames			= frameCount;
					
					ComponentResult err = AudioUnitSetProperty(self.audioUnit,
															   kAudioUnitProperty_ScheduleAudioSlice,
															   kAudioUnitScope_Global,
															   0,
															   slice,
															   sizeof(ScheduledAudioSlice));
					if(noErr != err) {
						NSLog(@"AudioScheduler: Unable to schedule audio slice: %d", (int)err);
						slice->mFlags = kScheduledAudioSliceFlag_Complete;
						continue;
					}

#if EXTENDED_DEBUG
					NSLog(@"AudioScheduler: Scheduling slice %"PRId32 " (%"PRId32 " frames) to start at sample %"PRId64 "", i, frameCount, (SInt64)slice->mTimeStamp.mSampleTime);
#endif
					
					[self.regionBeingScheduled unlockSlice:i];

					[self scheduledAdditionalFrames:frameCount];
				}
			}

			// Sleep until we are signaled or the timeout happens
			semaphore_timedwait(self.semaphore, timeout);
		}		

		// Sleep until we are signaled or the timeout happens
		semaphore_timedwait(self.semaphore, timeout);
	}
	
	self.scheduling = NO;
	
	// Notify the delegate that scheduling has stopped
	if(nil != [self delegate] && [[self delegate] respondsToSelector:@selector(audioSchedulerStoppedScheduling:)])
		[[self delegate] performSelectorOnMainThread:@selector(audioSchedulerStoppedScheduling:) withObject:self waitUntilDone:NO];
}

- (void) processSlicesInThread:(id)dummy
{
	@autoreleasepool {
		[self processSlicesInThread];
	}
}

- (void) setThreadPolicy
{
	thread_extended_policy_data_t		extendedPolicy;
	thread_precedence_policy_data_t		precedencePolicy;
	
	extendedPolicy.timeshare		= 0;
	precedencePolicy.importance		= 6;
	
	kern_return_t result = thread_policy_set(mach_thread_self(), 
											 THREAD_EXTENDED_POLICY,  
											 (thread_policy_t)&extendedPolicy, 
											 THREAD_EXTENDED_POLICY_COUNT);
	
#if DEBUG
	if(KERN_SUCCESS != result)
		mach_error("Couldn't set AudioScheduler's scheduling thread's extended policy", result);
#endif
	
	result = thread_policy_set(mach_thread_self(), 
							   THREAD_PRECEDENCE_POLICY, 
							   (thread_policy_t)&precedencePolicy, 
							   THREAD_PRECEDENCE_POLICY_COUNT);
	
#if DEBUG
	if(KERN_SUCCESS != result)
		mach_error("Couldn't set AudioScheduler's scheduling thread's precedence policy", result);
#endif
}

@end
