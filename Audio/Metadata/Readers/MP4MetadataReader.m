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

#import "MP4MetadataReader.h"
#import "AudioStream.h"
#include <mp4v2/mp4v2.h>

@implementation MP4MetadataReader

- (BOOL) readMetadata:(NSError **)error
{
	NSMutableDictionary				*metadataDictionary;
	NSString						*path					= [_url path];
	MP4FileHandle					mp4FileHandle			= MP4Read([path fileSystemRepresentation]);
	
	if(MP4_INVALID_FILE_HANDLE == mp4FileHandle) {
		if(nil != error) {
			NSMutableDictionary *errorDictionary = [NSMutableDictionary dictionary];
			
			[errorDictionary setObject:[NSString stringWithFormat:NSLocalizedStringFromTable(@"The file \"%@\" is not a valid MPEG file.", @"Errors", @""), [[NSFileManager defaultManager] displayNameAtPath:path]] forKey:NSLocalizedDescriptionKey];
			[errorDictionary setObject:NSLocalizedStringFromTable(@"Not an MPEG file", @"Errors", @"") forKey:NSLocalizedFailureReasonErrorKey];
			[errorDictionary setObject:NSLocalizedStringFromTable(@"The file's extension may not match the file's type.", @"Errors", @"") forKey:NSLocalizedRecoverySuggestionErrorKey];						
			
			*error = [NSError errorWithDomain:AudioMetadataReaderErrorDomain 
										 code:AudioMetadataReaderFileFormatNotRecognizedError 
									 userInfo:errorDictionary];
		}
		
		return NO;
	}
	
	u_int16_t		trackNumber, totalTracks;
	
	metadataDictionary = [NSMutableDictionary dictionary];

	const MP4Tags* new_tags = MP4TagsAlloc();
	MP4TagsFetch(new_tags, mp4FileHandle);
	
	// Album title
	if(new_tags->album)
		[metadataDictionary setValue:[NSString stringWithUTF8String:new_tags->album] forKey:MetadataAlbumTitleKey];
	
	// Artist
	if(new_tags->artist)
		[metadataDictionary setValue:[NSString stringWithUTF8String:new_tags->artist] forKey:MetadataArtistKey];

	// Album Artist
	if(new_tags->albumArtist)
		[metadataDictionary setValue:[NSString stringWithUTF8String:new_tags->albumArtist] forKey:MetadataAlbumArtistKey];
	
	// Genre
	if(new_tags->genre)
		[metadataDictionary setValue:[NSString stringWithUTF8String:new_tags->genre] forKey:MetadataGenreKey];
	
	// Year
	if((new_tags->releaseDate) && (strlen(new_tags->releaseDate) > 0))
		[metadataDictionary setValue:[NSString stringWithUTF8String:new_tags->releaseDate] forKey:MetadataDateKey];
	
	// Composer
	if(new_tags->composer)
		[metadataDictionary setValue:[NSString stringWithUTF8String:new_tags->composer] forKey:MetadataComposerKey];
	
	// Comment
	if(new_tags->comments)
		[metadataDictionary setValue:[NSString stringWithUTF8String:new_tags->comments] forKey:MetadataCommentKey];
	
	// Track title
	if(new_tags->name)
		[metadataDictionary setValue:[NSString stringWithUTF8String:new_tags->name] forKey:MetadataTitleKey];
	
	// Track number
	if(new_tags->track) {
		if(0 != trackNumber)
			[metadataDictionary setValue:[NSNumber numberWithInteger:(NSInteger)new_tags->track->index] forKey:MetadataTrackNumberKey];
		
		if(0 != totalTracks)
			[metadataDictionary setValue:[NSNumber numberWithInteger:(NSInteger)new_tags->track->total] forKey:MetadataTrackTotalKey];
	}
	
	// Disc number
	if(new_tags->disk) {
		if(0 != new_tags->disk->index)
			[metadataDictionary setValue:[NSNumber numberWithInteger:(NSInteger)new_tags->disk->index] forKey:MetadataDiscNumberKey];

		if(0 != new_tags->disk->total)
			[metadataDictionary setValue:[NSNumber numberWithInteger:(NSInteger)new_tags->disk->total] forKey:MetadataDiscTotalKey];
	}
	
	// Compilation
	if(new_tags->compilation)
		[metadataDictionary setValue:[NSNumber numberWithBool:(BOOL)(new_tags->compilation)] forKey:MetadataCompilationKey];

	// BPM
	if(new_tags->tempo)
		[metadataDictionary setValue:[NSNumber numberWithInteger:(NSInteger)new_tags->tempo] forKey:MetadataBPMKey];
	
	// Album art
/*	artCount = MP4GetMetadataCoverArtCount(mp4FileHandle);
	if(0 < artCount) {
		MP4GetMetadataCoverArt(mp4FileHandle, &bytes, &length, 0);
		NSImage				*image	= [[NSImage alloc] initWithData:[NSData dataWithBytes:bytes length:length]];
		if(nil != image) {
			[metadataDictionary setValue:[image TIFFRepresentation] forKey:@"albumArt"];
		}
	}*/
	
#if 0
	// ReplayGain
	u_int8_t *rawValue;
	u_int32_t rawValueSize;

	if(MP4GetMetadataFreeForm(mp4FileHandle, "replaygain_reference_loudness", &rawValue, &rawValueSize, NULL)) {
		NSString	*value			= [[NSString alloc] initWithBytes:rawValue length:rawValueSize encoding:NSUTF8StringEncoding];
		NSScanner	*scanner		= [NSScanner scannerWithString:value];
		double		doubleValue		= 0.0;
		
		if([scanner scanDouble:&doubleValue])
			[metadataDictionary setValue:[NSNumber numberWithDouble:doubleValue] forKey:ReplayGainReferenceLoudnessKey];
	}
	
	if(MP4GetMetadataFreeForm(mp4FileHandle, "replaygain_track_gain", &rawValue, &rawValueSize, NULL)) {
		NSString	*value			= [[NSString alloc] initWithBytes:rawValue length:rawValueSize encoding:NSUTF8StringEncoding];
		NSScanner	*scanner		= [NSScanner scannerWithString:value];
		double		doubleValue		= 0.0;
		
		if([scanner scanDouble:&doubleValue])
			[metadataDictionary setValue:[NSNumber numberWithDouble:doubleValue] forKey:ReplayGainTrackGainKey];
	}

	if(MP4GetMetadataFreeForm(mp4FileHandle, "replaygain_track_peak", &rawValue, &rawValueSize, NULL)) {
		NSString *value = [[NSString alloc] initWithBytes:rawValue length:rawValueSize encoding:NSUTF8StringEncoding];
		[metadataDictionary setValue:[NSNumber numberWithDouble:[value doubleValue]] forKey:ReplayGainTrackPeakKey];
	}

	if(MP4GetMetadataFreeForm(mp4FileHandle, "replaygain_album_gain", &rawValue, &rawValueSize, NULL)) {
		NSString	*value			= [[NSString alloc] initWithBytes:rawValue length:rawValueSize encoding:NSUTF8StringEncoding];
		NSScanner	*scanner		= [NSScanner scannerWithString:value];
		double		doubleValue		= 0.0;
		
		if([scanner scanDouble:&doubleValue])
			[metadataDictionary setValue:[NSNumber numberWithDouble:doubleValue] forKey:ReplayGainAlbumGainKey];
	}
	
	if(MP4GetMetadataFreeForm(mp4FileHandle, "replaygain_album_peak", &rawValue, &rawValueSize, NULL)) {
		NSString *value = [[NSString alloc] initWithBytes:rawValue length:rawValueSize encoding:NSUTF8StringEncoding];
		[metadataDictionary setValue:[NSNumber numberWithDouble:[value doubleValue]] forKey:ReplayGainAlbumPeakKey];
	}
#endif
	
	MP4TagsFree(new_tags);
	MP4Close(mp4FileHandle, 0);
	
	[self setValue:metadataDictionary forKey:@"metadata"];
	
	return YES;
}

@end
