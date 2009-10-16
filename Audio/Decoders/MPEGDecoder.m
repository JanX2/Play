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

#import "MPEGDecoder.h"
#import "AudioStream.h"

#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>

#define INPUT_BUFFER_SIZE	(5 * 8192)
#define LAME_HEADER_SIZE	((8 * 5) + 4 + 4 + 8 + 32 + 16 + 16 + 4 + 4 + 8 + 12 + 12 + 8 + 8 + 2 + 3 + 11 + 32 + 32 + 32)

#define BIT_RESOLUTION		24

// From vbrheadersdk:
// ========================================
// A Xing header may be present in the ancillary
// data field of the first frame of an mp3 bitstream
// The Xing header (optionally) contains
//      frames      total number of audio frames in the bitstream
//      bytes       total number of bytes in the bitstream
//      toc         table of contents

// toc (table of contents) gives seek points
// for random access
// the ith entry determines the seek point for
// i-percent duration
// seek point in bytes = (toc[i]/256.0) * total_bitstream_bytes
// e.g. half duration seek point = (toc[50]/256.0) * total_bitstream_bytes

#define FRAMES_FLAG     0x0001
#define BYTES_FLAG      0x0002
#define TOC_FLAG        0x0004
#define VBR_SCALE_FLAG  0x0008

// Clipping and rounding code from madplay(audio.c):
/*
 * madplay - MPEG audio decoder and player
 * Copyright (C) 2000-2004 Robert Leslie
 */
static int32_t 
audio_linear_round(unsigned int bits, 
				   mad_fixed_t sample)
{
	enum {
		MIN = -MAD_F_ONE,
		MAX =  MAD_F_ONE - 1
	};
	
	/* round */
	sample += (1L << (MAD_F_FRACBITS - bits));
	
	/* clip */
	if(MAX < sample)
		sample = MAX;
	else if(MIN > sample)
		sample = MIN;
	
	/* quantize and scale */
	return sample >> (MAD_F_FRACBITS + 1 - bits);
}
// End madplay code

@interface MPEGDecoder (Private)
- (BOOL) scanFile;
- (SInt64) seekToFrameApproximately:(SInt64)frame;
- (SInt64) seekToFrameAccurately:(SInt64)frame;
@end

@implementation MPEGDecoder

- (id) initWithURL:(NSURL *)url error:(NSError **)error
{
	NSParameterAssert(nil != url);
	
	if((self = [super initWithURL:url error:error])) {
		_inputBuffer = (unsigned char *)calloc(INPUT_BUFFER_SIZE + MAD_BUFFER_GUARD, sizeof(unsigned char));
		NSAssert(NULL != _inputBuffer, @"Unable to allocate memory");
		
		_file = fopen([[[self URL] path] fileSystemRepresentation], "r");
		if(NULL == _file) {
			if(nil != error) {
				NSMutableDictionary *errorDictionary = [NSMutableDictionary dictionary];
				
//				[errorDictionary setObject:[NSString stringWithFormat:NSLocalizedStringFromTable(@"The format of the file \"%@\" was not recognized.", @"Errors", @""), [[NSFileManager defaultManager] displayNameAtPath:path]] forKey:NSLocalizedDescriptionKey];
//				[errorDictionary setObject:NSLocalizedStringFromTable(@"File Format Not Recognized", @"Errors", @"") forKey:NSLocalizedFailureReasonErrorKey];
//				[errorDictionary setObject:NSLocalizedStringFromTable(@"The file's extension may not match the file's type.", @"Errors", @"") forKey:NSLocalizedRecoverySuggestionErrorKey];
				
				*error = [NSError errorWithDomain:NSPOSIXErrorDomain 
											 code:errno 
										 userInfo:errorDictionary];
			}
			
			[self release];
			return nil;
		}
		
		mad_stream_init(&_mad_stream);
		mad_frame_init(&_mad_frame);
		mad_synth_init(&_mad_synth);
		
		// Scan file to determine sample rate, channels, total frames, etc
		if(NO == [self scanFile]) {
			[self release];
			return nil;
		}
		
		// The source's PCM format
		_sourceFormat.mFormatID				= kAudioFormatLinearPCM;
		_sourceFormat.mFormatFlags			= kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian;
		
		_sourceFormat.mSampleRate			= _format.mSampleRate;
		_sourceFormat.mChannelsPerFrame		= _format.mChannelsPerFrame;
		_sourceFormat.mBitsPerChannel		= 16;
		
		_sourceFormat.mBytesPerPacket		= ((_sourceFormat.mBitsPerChannel + 7) / 8) * _sourceFormat.mChannelsPerFrame;
		_sourceFormat.mFramesPerPacket		= 1;
		_sourceFormat.mBytesPerFrame		= _sourceFormat.mBytesPerPacket * _sourceFormat.mFramesPerPacket;		
		
		// Allocate the buffer list
		_bufferList = calloc(sizeof(AudioBufferList) + (sizeof(AudioBuffer) * (_format.mChannelsPerFrame - 1)), 1);
		NSAssert(NULL != _bufferList, @"Unable to allocate memory");
		
		_bufferList->mNumberBuffers = _format.mChannelsPerFrame;
		
		unsigned i;
		for(i = 0; i < _bufferList->mNumberBuffers; ++i) {
			_bufferList->mBuffers[i].mData = calloc(_samplesPerMPEGFrame, sizeof(float));
			NSAssert(NULL != _bufferList->mBuffers[i].mData, @"Unable to allocate memory");
			
			_bufferList->mBuffers[i].mNumberChannels = 1;
		}		
	}
	return self;
}

- (void) dealloc
{
	mad_synth_finish(&_mad_synth);
	mad_frame_finish(&_mad_frame);
	mad_stream_finish(&_mad_stream);
	
	free(_inputBuffer), _inputBuffer = NULL;
	fclose(_file), _file = NULL;
	
	if(_bufferList) {
		unsigned i;
		for(i = 0; i < _bufferList->mNumberBuffers; ++i)
			free(_bufferList->mBuffers[i].mData), _bufferList->mBuffers[i].mData = NULL;	
		free(_bufferList), _bufferList = NULL;
	}
	
	[super dealloc];
}

- (SInt64)			totalFrames						{ return _totalFrames; }
- (SInt64)			currentFrame					{ return _currentFrame; }

- (BOOL)			supportsSeeking					{ return YES; }

- (SInt64) seekToFrame:(SInt64)frame
{
	if(/*[[NSUserDefaults standardUserDefaults] boolForKey:@"accurateMP3Seeking"] &&*/ _foundLAMEHeader)
		return [self seekToFrameAccurately:frame];
	else
		return [self seekToFrameApproximately:frame];
}

- (UInt32) readAudio:(AudioBufferList *)bufferList frameCount:(UInt32)frameCount
{
	NSParameterAssert(NULL != bufferList);
	NSParameterAssert(bufferList->mNumberBuffers == _format.mChannelsPerFrame);
	NSParameterAssert(0 < frameCount);
	
	UInt32			bytesToRead;
	UInt32			bytesRemaining;
	unsigned char	*readStartPointer;
	int32_t			audioSample;
	
	BOOL			readEOF					= NO;
	float			scaleFactor				= (1L << (BIT_RESOLUTION - 1));
	
	UInt32			framesRead				= 0;

	// Reset output buffer data size
	unsigned i;
	for(i = 0; i < bufferList->mNumberBuffers; ++i)
		bufferList->mBuffers[i].mDataByteSize = 0;
	
	for(;;) {
		
		UInt32	framesRemaining	= frameCount - framesRead;
		UInt32	framesToSkip	= bufferList->mBuffers[0].mDataByteSize / sizeof(float);
		UInt32	framesInBuffer	= _bufferList->mBuffers[0].mDataByteSize / sizeof(float);
		UInt32	framesToCopy	= (framesInBuffer > framesRemaining ? framesRemaining : framesInBuffer);
		
		// Copy data from the buffer to output
		for(i = 0; i < _bufferList->mNumberBuffers; ++i) {
			float *floatBuffer = bufferList->mBuffers[i].mData;
			memcpy(floatBuffer + framesToSkip, _bufferList->mBuffers[i].mData, framesToCopy * sizeof(float));
			bufferList->mBuffers[i].mDataByteSize += (framesToCopy * sizeof(float));
			
			// Move remaining data in buffer to beginning
			if(framesToCopy != framesInBuffer) {
				floatBuffer = _bufferList->mBuffers[i].mData;
				memmove(floatBuffer, floatBuffer + framesToCopy, (framesInBuffer - framesToCopy) * sizeof(float));
			}
			
			_bufferList->mBuffers[i].mDataByteSize -= (framesToCopy * sizeof(float));
		}
		
		framesRead += framesToCopy;

		// All requested frames were read
		if(framesRead == frameCount)
			break;
		
		// If the file contains a Xing header but not LAME gapless information,
		// decode the number of MPEG frames specified by the Xing header
		if(_foundXingHeader && NO == _foundLAMEHeader && 1 + _mpegFramesDecoded == _totalMPEGFrames)
			break;
		
		// The LAME header indicates how many samples are in the file
		if(_foundLAMEHeader && [self totalFrames] == _samplesDecoded)
			break;
		
		// Feed the input buffer if necessary
		if(NULL == _mad_stream.buffer || MAD_ERROR_BUFLEN == _mad_stream.error) {
			if(NULL != _mad_stream.next_frame) {
				bytesRemaining = _mad_stream.bufend - _mad_stream.next_frame;
				memmove(_inputBuffer, _mad_stream.next_frame, bytesRemaining);
				
				readStartPointer	= _inputBuffer + bytesRemaining;
				bytesToRead			= INPUT_BUFFER_SIZE - bytesRemaining;
			}
			else {
				bytesToRead			= INPUT_BUFFER_SIZE,
				readStartPointer	= _inputBuffer,
				bytesRemaining		= 0;
			}
			
			// Read raw bytes from the MP3 file
			size_t bytesRead = fread(readStartPointer, 1, bytesToRead, _file);
			if(ferror(_file)) {
#if DEBUG
				NSLog(@"Read error: %s.", strerror(errno));
#endif
				break;
			}
			
			// MAD_BUFFER_GUARD zeroes are required to decode the last frame of the file
			if(feof(_file)) {
				memset(readStartPointer + bytesRead, 0, MAD_BUFFER_GUARD);
				bytesRead	+= MAD_BUFFER_GUARD;
				readEOF		= YES;
			}
			
			mad_stream_buffer(&_mad_stream, _inputBuffer, bytesRead + bytesRemaining);
			_mad_stream.error = MAD_ERROR_NONE;
		}
		
		// Decode the MPEG frame
		int result = mad_frame_decode(&_mad_frame, &_mad_stream);
		if(-1 == result) {
			if(MAD_RECOVERABLE(_mad_stream.error)) {
				// Prevent ID3 tags from reporting recoverable frame errors
				const uint8_t	*buffer			= _mad_stream.this_frame;
				unsigned		buflen			= _mad_stream.bufend - _mad_stream.this_frame;
				uint32_t		id3_length		= 0;
				
				if(10 <= buflen && 0x49 == buffer[0] && 0x44 == buffer[1] && 0x33 == buffer[2]) {
					id3_length = (((buffer[6] & 0x7F) << (3 * 7)) | ((buffer[7] & 0x7F) << (2 * 7)) |
								  ((buffer[8] & 0x7F) << (1 * 7)) | ((buffer[9] & 0x7F) << (0 * 7)));
					
					// Add 10 bytes for ID3 header
					id3_length += 10;
					
					mad_stream_skip(&_mad_stream, id3_length);
				}
#if DEBUG
				else
					NSLog(@"Recoverable frame level error (%s)", mad_stream_errorstr(&_mad_stream));
#endif
				
				continue;
			}
			// EOS for non-Xing streams occurs when EOF is reached and no further frames can be decoded
			else if(MAD_ERROR_BUFLEN == _mad_stream.error && readEOF)
				break;
			else if(MAD_ERROR_BUFLEN == _mad_stream.error)
				continue;
			else {
#if DEBUG
				NSLog(@"Unrecoverable frame level error (%s)", mad_stream_errorstr(&_mad_stream));
#endif
				break;
			}
		}
		
		// Housekeeping
		++_mpegFramesDecoded;
		
		// Synthesize the frame into PCM
		mad_synth_frame(&_mad_synth, &_mad_frame);
		
		// Skip any samples that remain from last frame
		// This can happen if the encoder delay is greater than the number of samples in a frame
		unsigned startingSample = _samplesToSkipInNextFrame;
		
		// Skip the Xing header (it contains empty audio)
		if(_foundXingHeader && 1 == _mpegFramesDecoded)
			continue;
		// Adjust the first real audio frame for gapless playback
		else if(_foundLAMEHeader && 2 == _mpegFramesDecoded)
			startingSample += _encoderDelay;

		// The number of samples in this frame
		unsigned sampleCount = _mad_synth.pcm.length;

		// Skip this entire frame if necessary
		if(startingSample > sampleCount) {
			_samplesToSkipInNextFrame += startingSample - sampleCount;
			continue;
		}
		else
			_samplesToSkipInNextFrame = 0;
		
		// If a LAME header was found, the total number of audio frames (AKA samples) 
		// is known.  Ensure only that many are output
		if(_foundLAMEHeader && [self totalFrames] < _samplesDecoded + (sampleCount - startingSample))
			sampleCount = [self totalFrames] - _samplesDecoded;
		
		// Output samples in 32-bit float PCM
		unsigned channel, sample;
		for(channel = 0; channel < MAD_NCHANNELS(&_mad_frame.header); ++channel) {
			float *floatBuffer = _bufferList->mBuffers[channel].mData;
			
			for(sample = startingSample; sample < sampleCount; ++sample) {
				audioSample = audio_linear_round(BIT_RESOLUTION, _mad_synth.pcm.samples[channel][sample]);
				*floatBuffer++ = (float)(audioSample / scaleFactor);
			}
			
			_bufferList->mBuffers[channel].mNumberChannels	= 1;
			_bufferList->mBuffers[channel].mDataByteSize	= (sampleCount - startingSample) * sizeof(float);
		}
		
		_samplesDecoded += (sampleCount - startingSample);
	}
	
	_currentFrame += framesRead;
	
	return framesRead;
}

@end

@implementation MPEGDecoder (Private)

- (BOOL) scanFile
{
	uint32_t			framesDecoded = 0;
	UInt32				bytesToRead, bytesRemaining;
	size_t				bytesRead;
	unsigned char		*readStartPointer;
	BOOL				readEOF;
	
	struct mad_stream	stream;
	struct mad_frame	frame;
	
	int					result;
	struct stat			stat;
	uint32_t			id3_length		= 0;
	
	// Set up	
	mad_stream_init(&stream);
	mad_frame_init(&frame);
	
	readEOF = NO;
	
	result = fstat(fileno(_file), &stat);
	if(-1 == result)
		return NO;
	
	_fileBytes = stat.st_size;
	
	for(;;) {
		if(NULL == stream.buffer || MAD_ERROR_BUFLEN == stream.error) {
			if(stream.next_frame) {
				bytesRemaining = stream.bufend - stream.next_frame;
				memmove(_inputBuffer, stream.next_frame, bytesRemaining);
				
				readStartPointer	= _inputBuffer + bytesRemaining;
				bytesToRead			= INPUT_BUFFER_SIZE - bytesRemaining;
			}
			else {
				bytesToRead			= INPUT_BUFFER_SIZE,
				readStartPointer	= _inputBuffer,
				bytesRemaining		= 0;
			}
			
			// Read raw bytes from the MP3 file
			bytesRead = fread(readStartPointer, 1, bytesToRead, _file);
			if(ferror(_file)) {
#if DEBUG
				NSLog(@"Read error: %s.", strerror(errno));
#endif
				break;
			}
			
			// MAD_BUFFER_GUARD zeroes are required to decode the last frame of the file
			if(feof(_file)) {
				memset(readStartPointer + bytesRead, 0, MAD_BUFFER_GUARD);
				bytesRead	+= MAD_BUFFER_GUARD;
				readEOF		= YES;
			}
			
			mad_stream_buffer(&stream, _inputBuffer, bytesRead + bytesRemaining);
			stream.error = MAD_ERROR_NONE;
		}
		
		result = mad_frame_decode(&frame, &stream);
		if(-1 == result) {
			if(MAD_RECOVERABLE(stream.error)) {
				// Prevent ID3 tags from reporting recoverable frame errors
				const uint8_t	*buffer			= stream.this_frame;
				unsigned		buflen			= stream.bufend - stream.this_frame;
				
				if(10 <= buflen && 0x49 == buffer[0] && 0x44 == buffer[1] && 0x33 == buffer[2]) {
					id3_length = (((buffer[6] & 0x7F) << (3 * 7)) | ((buffer[7] & 0x7F) << (2 * 7)) |
								  ((buffer[8] & 0x7F) << (1 * 7)) | ((buffer[9] & 0x7F) << (0 * 7)));
					
					// Add 10 bytes for ID3 header
					id3_length += 10;
					
					mad_stream_skip(&stream, id3_length);
				}
#if DEBUG
				else
					NSLog(@"Recoverable frame level error (%s)", mad_stream_errorstr(&stream));
#endif
				
				continue;
			}
			// EOS for non-Xing streams occurs when EOF is reached and no further frames can be decoded
			else if(MAD_ERROR_BUFLEN == stream.error && readEOF)
				break;
			else if(MAD_ERROR_BUFLEN == stream.error)
				continue;
			else {
#if DEBUG
				NSLog(@"Unrecoverable frame level error (%s)", mad_stream_errorstr(&stream));
#endif
				break;
			}
		}
		
		++framesDecoded;
		
		// Look for a Xing header in the first frame that was successfully decoded
		// Reference http://www.codeproject.com/audio/MPEGAudioInfo.asp
		if(1 == framesDecoded) {
			_format.mSampleRate			= frame.header.samplerate;
			_format.mChannelsPerFrame	= MAD_NCHANNELS(&frame.header);
			
			// MAD_NCHANNELS always returns 1 or 2
			_channelLayout.mChannelLayoutTag	= (1 == MAD_NCHANNELS(&frame.header) ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo);
			_samplesPerMPEGFrame				= 32 * MAD_NSBSAMPLES(&frame.header);
			
			unsigned ancillaryBitsRemaining = stream.anc_bitlen;
			if(32 > ancillaryBitsRemaining)
				continue;
			
			uint32_t magic = mad_bit_read(&stream.anc_ptr, 32);
			ancillaryBitsRemaining -= 32;
			
			if('Xing' == magic || 'Info' == magic) {
				if(32 > ancillaryBitsRemaining)
					continue;
				
				uint32_t flags = mad_bit_read(&stream.anc_ptr, 32);
				ancillaryBitsRemaining -= 32;
				
				// 4 byte value containing total frames
				// For LAME-encoded MP3s, the number of MPEG frames in the file is one greater than this frame
				if(FRAMES_FLAG & flags) {
					if(32 > ancillaryBitsRemaining)
						continue;
					
					uint32_t frames = mad_bit_read(&stream.anc_ptr, 32);
					ancillaryBitsRemaining -= 32;
					
					_totalMPEGFrames = frames;
					
					// Determine number of samples, discounting encoder delay and padding
					// Our concept of a frame is the same as CoreAudio's- one sample across all channels
					_totalFrames = frames * _samplesPerMPEGFrame;
				}
				
				// 4 byte value containing total bytes
				if(BYTES_FLAG & flags) {
					if(32 > ancillaryBitsRemaining)
						continue;
					
					/*uint32_t bytes =*/ mad_bit_read(&stream.anc_ptr, 32);
					ancillaryBitsRemaining -= 32;
				}
				
				// 100 bytes containing TOC information
				if(TOC_FLAG & flags) {
					if(8 * 100 > ancillaryBitsRemaining)
						continue;
					
					unsigned i;
					for(i = 0; i < 100; ++i)
						_xingTOC[i] = mad_bit_read(&stream.anc_ptr, 8);
					
					ancillaryBitsRemaining -= (8* 100);
				}
				
				// 4 byte value indicating encoded vbr scale
				if(VBR_SCALE_FLAG & flags) {
					if(32 > ancillaryBitsRemaining)
						continue;
					
					/*uint32_t vbrScale =*/ mad_bit_read(&stream.anc_ptr, 32);
					ancillaryBitsRemaining -= 32;
				}
				
				_foundXingHeader = YES;
				
				// Loook for the LAME header next
				// http://gabriel.mp3-tech.org/mp3infotag.html				
				if(32 > ancillaryBitsRemaining)
					continue;
				magic = mad_bit_read(&stream.anc_ptr, 32);
				
				ancillaryBitsRemaining -= 32;
				
				if('LAME' == magic) {
					
					if(LAME_HEADER_SIZE > ancillaryBitsRemaining)
						continue;
					
					/*unsigned char versionString [5 + 1];
					memset(versionString, 0, 6);*/
					
					unsigned i;
					for(i = 0; i < 5; ++i)
						/*versionString[i] =*/ mad_bit_read(&stream.anc_ptr, 8);
					
					/*uint8_t infoTagRevision =*/ mad_bit_read(&stream.anc_ptr, 4);
					/*uint8_t vbrMethod =*/ mad_bit_read(&stream.anc_ptr, 4);
					
					/*uint8_t lowpassFilterValue =*/ mad_bit_read(&stream.anc_ptr, 8);
					
					/*float peakSignalAmplitude =*/ mad_bit_read(&stream.anc_ptr, 32);
					/*uint16_t radioReplayGain =*/ mad_bit_read(&stream.anc_ptr, 16);
					/*uint16_t audiophileReplayGain =*/ mad_bit_read(&stream.anc_ptr, 16);
					
					/*uint8_t encodingFlags =*/ mad_bit_read(&stream.anc_ptr, 4);
					/*uint8_t athType =*/ mad_bit_read(&stream.anc_ptr, 4);
					
					/*uint8_t lameBitrate =*/ mad_bit_read(&stream.anc_ptr, 8);
					
					uint16_t encoderDelay = mad_bit_read(&stream.anc_ptr, 12);
					uint16_t encoderPadding = mad_bit_read(&stream.anc_ptr, 12);
										
					// Adjust encoderDelay and encoderPadding for MDCT/filterbank delays
					_encoderDelay = encoderDelay + 528 + 1;
					_encoderPadding = encoderPadding - (528 + 1);

					_totalFrames = [self totalFrames] - (_encoderDelay + _encoderPadding);
					
					/*uint8_t misc =*/ mad_bit_read(&stream.anc_ptr, 8);
					
					/*uint8_t mp3Gain =*/ mad_bit_read(&stream.anc_ptr, 8);
					
					/*uint8_t unused =*/mad_bit_read(&stream.anc_ptr, 2);
					/*uint8_t surroundInfo =*/ mad_bit_read(&stream.anc_ptr, 3);
					/*uint16_t presetInfo =*/ mad_bit_read(&stream.anc_ptr, 11);
					
					/*uint32_t musicGain =*/ mad_bit_read(&stream.anc_ptr, 32);
					
					/*uint32_t musicCRC =*/ mad_bit_read(&stream.anc_ptr, 32);
					
					/*uint32_t tagCRC =*/ mad_bit_read(&stream.anc_ptr, 32);
					
					ancillaryBitsRemaining -= LAME_HEADER_SIZE;
					
					_foundLAMEHeader = YES;
					break;
				}
			}
		}
		else {
			// Just estimate the number of frames based on the file's size
			_totalFrames = (double)frame.header.samplerate * ((_fileBytes - id3_length) / (frame.header.bitrate / 8.0));
			
			// For now, quit after second frame
			break;
		}		
	}
	
	// Clean up
	mad_frame_finish(&frame);
	mad_stream_finish(&stream);
	
	// Rewind to the beginning of file
	if(-1 == fseek(_file, 0, SEEK_SET))
		return NO;
	
	return YES;
}

- (SInt64) seekToFrameApproximately:(SInt64)frame
{
	double	fraction	= (double)frame / [self totalFrames];
	long	seekPoint	= 0;
	
	// If a Xing header was found, interpolate in TOC
	if(_foundXingHeader) {
		double		percent		= 100 * fraction;
		unsigned	firstIndex	= percent;
		
		if(99 < firstIndex)
			firstIndex = 99;
		
		double firstOffset	= _xingTOC[firstIndex];
		double secondOffset	= 256;
		
		if(99 > firstIndex)
			secondOffset = _xingTOC[firstIndex + 1];;
			
			double x = firstOffset + (secondOffset - firstOffset) * (percent - firstIndex);
			seekPoint = (long)((1.0 / 256.0) * x * _fileBytes); 
	}
	else
		seekPoint = (long)_fileBytes * fraction;
	
	int result = fseek(_file, seekPoint, SEEK_SET);
	if(0 == result) {
		mad_stream_buffer(&_mad_stream, NULL, 0);
		
		// Reset frame count to prevent early termination of playback
		_mpegFramesDecoded			= 0;
		_samplesDecoded				= 0;
		_samplesToSkipInNextFrame	= 0;
		
		_currentFrame				= frame;
	}
	
	// Right now it's only possible to return an approximation of the audio frame
	return (-1 == result ? -1 : frame);
}

- (SInt64) seekToFrameAccurately:(SInt64)frame
{
	NSParameterAssert(0 <= frame && frame < [self totalFrames]);
	
	// Brute force seeking is necessary since frame-accurate seeking is required
	
	UInt32			bytesToRead;
	UInt32			bytesRemaining;
	unsigned char	*readStartPointer;
	int32_t			audioSample;
	
	BOOL			readEOF					= NO;
	float			scaleFactor				= (1L << (BIT_RESOLUTION - 1));
	
	// To seek to a frame earlier in the file, rewind to the beginning
	if([self currentFrame] > frame) {
		if(-1 == fseek(_file, 0, SEEK_SET))
			return -1;
		
		// Reset decoder parameters
		_mpegFramesDecoded			= 0;
		_currentFrame				= 0;
		_samplesToSkipInNextFrame	= 0;
		_samplesDecoded				= 0;

		mad_stream_buffer(&_mad_stream, NULL, 0);
	}
	// Mark any buffered audio as read
	else
		_currentFrame += _bufferList->mBuffers[0].mDataByteSize / sizeof(float);
	
	// Zero the buffers
	unsigned i;
	for(i = 0; i < _bufferList->mNumberBuffers; ++i)
		_bufferList->mBuffers[i].mDataByteSize = 0;
	
	for(;;) {
		// All requested frames were skipped or read
		if(_samplesDecoded >= frame)
			break;

		// If the file contains a Xing header but not LAME gapless information,
		// decode the number of MPEG frames specified by the Xing header
		if(_foundXingHeader && NO == _foundLAMEHeader && 1 + _mpegFramesDecoded == _totalMPEGFrames)
			break;
		
		// The LAME header indicates how many samples are in the file
		if(_foundLAMEHeader && [self totalFrames] == _samplesDecoded)
			break;
		
		// Feed the input buffer if necessary
		if(NULL == _mad_stream.buffer || MAD_ERROR_BUFLEN == _mad_stream.error) {
			if(NULL != _mad_stream.next_frame) {
				bytesRemaining = _mad_stream.bufend - _mad_stream.next_frame;
				memmove(_inputBuffer, _mad_stream.next_frame, bytesRemaining);
				
				readStartPointer	= _inputBuffer + bytesRemaining;
				bytesToRead			= INPUT_BUFFER_SIZE - bytesRemaining;
			}
			else {
				bytesToRead			= INPUT_BUFFER_SIZE,
				readStartPointer	= _inputBuffer,
				bytesRemaining		= 0;
			}
			
			// Read raw bytes from the MP3 file
			size_t bytesRead = fread(readStartPointer, 1, bytesToRead, _file);
			if(ferror(_file)) {
#if DEBUG
				NSLog(@"Read error: %s.", strerror(errno));
#endif
				break;
			}
			
			// MAD_BUFFER_GUARD zeroes are required to decode the last frame of the file
			if(feof(_file)) {
				memset(readStartPointer + bytesRead, 0, MAD_BUFFER_GUARD);
				bytesRead	+= MAD_BUFFER_GUARD;
				readEOF		= YES;
			}
			
			mad_stream_buffer(&_mad_stream, _inputBuffer, bytesRead + bytesRemaining);
			_mad_stream.error = MAD_ERROR_NONE;
		}
		
		// Decode the MPEG frame
		int result = mad_frame_decode(&_mad_frame, &_mad_stream);
		if(-1 == result) {
			if(MAD_RECOVERABLE(_mad_stream.error)) {
				// Prevent ID3 tags from reporting recoverable frame errors
				const uint8_t	*buffer			= _mad_stream.this_frame;
				unsigned		buflen			= _mad_stream.bufend - _mad_stream.this_frame;
				uint32_t		id3_length		= 0;
				
				if(10 <= buflen && 0x49 == buffer[0] && 0x44 == buffer[1] && 0x33 == buffer[2]) {
					id3_length = (((buffer[6] & 0x7F) << (3 * 7)) | ((buffer[7] & 0x7F) << (2 * 7)) |
								  ((buffer[8] & 0x7F) << (1 * 7)) | ((buffer[9] & 0x7F) << (0 * 7)));
					
					// Add 10 bytes for ID3 header
					id3_length += 10;
					
					mad_stream_skip(&_mad_stream, id3_length);
				}
#if DEBUG
				else
					NSLog(@"Recoverable frame level error (%s)", mad_stream_errorstr(&_mad_stream));
#endif
				
				continue;
			}
			// EOS for non-Xing streams occurs when EOF is reached and no further frames can be decoded
			else if(MAD_ERROR_BUFLEN == _mad_stream.error && readEOF)
				break;
			else if(MAD_ERROR_BUFLEN == _mad_stream.error)
				continue;
			else {
#if DEBUG
				NSLog(@"Unrecoverable frame level error (%s)", mad_stream_errorstr(&_mad_stream));
#endif
				break;
			}
		}
		
		// Housekeeping
		++_mpegFramesDecoded;

		// Skip any samples that remain from last frame
		// This can happen if the encoder delay is greater than the number of samples in a frame
		unsigned startingSample = _samplesToSkipInNextFrame;
		
		// Skip the Xing header (it contains empty audio)
		if(_foundXingHeader && 1 == _mpegFramesDecoded)
			continue;
		// Adjust the first real audio frame for gapless playback
		else if(_foundLAMEHeader && 2 == _mpegFramesDecoded)
			startingSample += _encoderDelay;

		// The number of samples in this frame
		unsigned sampleCount = 32 * MAD_NSBSAMPLES(&_mad_frame.header);
		
		// Skip this entire frame if necessary
		if(startingSample > sampleCount) {
			_samplesToSkipInNextFrame += startingSample - sampleCount;
			continue;
		}
		else
			_samplesToSkipInNextFrame = 0;
		
		// If a LAME header was found, the total number of audio frames (AKA samples) 
		// is known.  Ensure only that many are output
		if(_foundLAMEHeader && [self totalFrames] < _samplesDecoded + (sampleCount - startingSample))
			sampleCount = [self totalFrames] - _samplesDecoded;

		// If this MPEG frame contains the desired seek frame, synthesize its audio to PCM
		if(_samplesDecoded + (sampleCount - startingSample) > frame) {
			// Synthesize the frame into PCM
			mad_synth_frame(&_mad_synth, &_mad_frame);

			// Skip any audio frames before the sample we are seeking to
			unsigned additionalSamplesToSkip = frame - _samplesDecoded;
			
			// Output samples in 32-bit float PCM
			unsigned channel, sample;
			for(channel = 0; channel < MAD_NCHANNELS(&_mad_frame.header); ++channel) {
				float *floatBuffer = _bufferList->mBuffers[channel].mData;
				
				for(sample = startingSample + additionalSamplesToSkip; sample < sampleCount; ++sample) {
					audioSample = audio_linear_round(BIT_RESOLUTION, _mad_synth.pcm.samples[channel][sample]);
					
					if(0 <= audioSample)
						*floatBuffer++ = (float)(audioSample / (scaleFactor - 1));
					else
						*floatBuffer++ = (float)(audioSample / scaleFactor);
				}
				
				_bufferList->mBuffers[channel].mNumberChannels	= 1;
				_bufferList->mBuffers[channel].mDataByteSize	= (sampleCount - (startingSample + additionalSamplesToSkip)) * sizeof(float);
			}

			// Only a portion of the frame was skipped- the rest was synthesized and stored in our buffers
			_samplesDecoded		+= (sampleCount - startingSample);
			_currentFrame		+= additionalSamplesToSkip;
		}
		// The entire frame was skipped
		else {
			_samplesDecoded		+= (sampleCount - startingSample);
			_currentFrame		+= (sampleCount - startingSample);
		}
	}
	
	return [self currentFrame];
}

@end
