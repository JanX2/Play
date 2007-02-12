/*
 *  $Id$
 *
 *  Copyright (C) 2006 - 2007 Stephen F. Booth <me@sbooth.org>
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

#import "OggVorbisStreamDecoder.h"
#import "AudioStream.h"

@implementation OggVorbisStreamDecoder

- (NSString *) sourceFormatDescription
{
	return [NSString stringWithFormat:@"%@, %u channels, %u Hz", NSLocalizedStringFromTable(@"Ogg (Vorbis)", @"General", @""), [self pcmFormat].mChannelsPerFrame, (unsigned)[self pcmFormat].mSampleRate];
}

- (BOOL) supportsSeeking
{
	return YES;
}

- (SInt64) performSeekToFrame:(SInt64)frame
{
	int		result		= ov_pcm_seek(&_vf, frame); 
	return (0 == result ? frame : -1);
}

- (BOOL) setupDecoder:(NSError **)error
{
	vorbis_info						*ovInfo;
	FILE							*file;
	int								result;
	
	[super setupDecoder:error];

	file							= fopen([[[[self stream] valueForKey:StreamURLKey] path] fileSystemRepresentation], "r");
	NSAssert1(NULL != file, @"Unable to open the input file (%s).", strerror(errno));	
	
	result							= ov_test(file, &_vf, NULL, 0);
	NSAssert(0 == result, NSLocalizedStringFromTable(@"The file does not appear to be a valid Ogg Vorbis file.", @"Exceptions", @""));
	
	result							= ov_test_open(&_vf);
	NSAssert(0 == result, NSLocalizedStringFromTable(@"Unable to open the input file.", @"Exceptions", @""));
	
	// Get input file information
	ovInfo							= ov_info(&_vf, -1);
	
	NSAssert(NULL != ovInfo, @"Unable to get information on Ogg Vorbis stream.");
	
	[self setTotalFrames:ov_pcm_total(&_vf, -1)];

	// Setup input format descriptor
	_pcmFormat.mFormatID			= kAudioFormatLinearPCM;
	_pcmFormat.mFormatFlags			= kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsPacked;
	
	_pcmFormat.mSampleRate			= ovInfo->rate;
	_pcmFormat.mChannelsPerFrame	= ovInfo->channels;
	_pcmFormat.mBitsPerChannel		= 16;
	
	_pcmFormat.mBytesPerPacket		= (_pcmFormat.mBitsPerChannel / 8) * _pcmFormat.mChannelsPerFrame;
	_pcmFormat.mFramesPerPacket		= 1;
	_pcmFormat.mBytesPerFrame		= _pcmFormat.mBytesPerPacket * _pcmFormat.mFramesPerPacket;
	
	return YES;
}

- (BOOL) cleanupDecoder:(NSError **)error
{
	int		result		= ov_clear(&_vf); 
	
	if(0 != result) {
		NSLog(@"ov_clear failed");
	}

	[super cleanupDecoder:error];
	
	return YES;
}

- (void) fillPCMBuffer
{
	UInt32				bytesToWrite, bytesAvailableToWrite;
	UInt32				bytesRead, bytesWritten;
	int					currentSection;
	void				*writePointer;

	for(;;) {
		bytesToWrite				= RING_BUFFER_WRITE_CHUNK_SIZE;
		bytesAvailableToWrite		= [[self pcmBuffer] lengthAvailableToWriteReturningPointer:&writePointer];
		currentSection				= 0;
		bytesWritten				= 0;

		if(bytesToWrite > bytesAvailableToWrite) {
			break;
		}

		for(;;) {
			bytesRead			= ov_read(&_vf, writePointer + bytesWritten, bytesAvailableToWrite - bytesWritten, YES, sizeof(int16_t), YES, &currentSection);
			NSAssert(0 <= bytesRead, @"Ogg Vorbis decode error.");
			
			bytesWritten		+= bytesRead;
			
			if(0 == bytesRead || bytesWritten >= bytesAvailableToWrite) {
				break;
			}
		}

		if(0 < bytesWritten) {
			[[self pcmBuffer] didWriteLength:bytesWritten];				
		}
		
		if(0 == bytesRead) {
			[self setAtEndOfStream:YES];
			break;
		}
	}
}

@end
