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

#import "MP4MetadataWriter.h"
#import "AudioStream.h"
#import "UtilityFunctions.h"
#include <mp4v2/mp4v2.h>

@implementation MP4MetadataWriter

- (BOOL) writeMetadata:(id)metadata error:(NSError **)error
{
	NSString		*path			= [_url path];
	MP4FileHandle	mp4FileHandle	= MP4Modify([path fileSystemRepresentation], 0);
	BOOL			result			= NO;

	if(MP4_INVALID_FILE_HANDLE == mp4FileHandle) {
		if(nil != error) {
			NSMutableDictionary *errorDictionary = [NSMutableDictionary dictionary];
			
			[errorDictionary setObject:[NSString stringWithFormat:NSLocalizedStringFromTable(@"The file \"%@\" is not a valid MPEG file.", @"Errors", @""), [[NSFileManager defaultManager] displayNameAtPath:path]] forKey:NSLocalizedDescriptionKey];
			[errorDictionary setObject:NSLocalizedStringFromTable(@"Not an MPEG file", @"Errors", @"") forKey:NSLocalizedFailureReasonErrorKey];
			[errorDictionary setObject:NSLocalizedStringFromTable(@"The file's extension may not match the file's type.", @"Errors", @"") forKey:NSLocalizedRecoverySuggestionErrorKey];						
			
			*error = [NSError errorWithDomain:AudioMetadataWriterErrorDomain 
										 code:AudioMetadataWriterFileFormatNotRecognizedError 
									 userInfo:errorDictionary];
		}
		
		return NO;
	}
	
	// NOTE: The following is now taking advantage of the fact that calling a method on nill will return nil.
	
	// Album title
	NSString *album = [metadata valueForKey:MetadataAlbumTitleKey];
	result = MP4TagsSetAlbum(mp4FileHandle, [album UTF8String]);
	
	// Artist
	NSString *artist = [metadata valueForKey:MetadataArtistKey];
	result = MP4TagsSetArtist(mp4FileHandle, [artist UTF8String]);

	// Album Artist
	NSString *albumArtist = [metadata valueForKey:MetadataAlbumArtistKey];
	result = MP4TagsSetAlbumArtist(mp4FileHandle, [albumArtist UTF8String]);
	
	// Composer
	NSString *composer = [metadata valueForKey:MetadataComposerKey];
	result = MP4TagsSetComposer(mp4FileHandle, [composer UTF8String]);
	
	// Genre
	NSString *genre = [metadata valueForKey:MetadataGenreKey];
	result = MP4TagsSetGenre(mp4FileHandle, [genre UTF8String]);
	
	// Year
	NSString *date = [metadata valueForKey:MetadataDateKey];
	result = MP4TagsSetReleaseDate(mp4FileHandle, [date UTF8String]);
	
	// Comment
	NSString *comment = [metadata valueForKey:MetadataCommentKey];
	result = MP4TagsSetComments(mp4FileHandle, [comment UTF8String]);
	
	// Track title
	NSString *title = [metadata valueForKey:MetadataTitleKey];
	result = MP4TagsSetName(mp4FileHandle, [title UTF8String]);
	
	// Track number
	NSNumber *trackNumber	= [metadata valueForKey:MetadataTrackNumberKey];
	NSNumber *trackTotal	= [metadata valueForKey:MetadataTrackTotalKey];
	MP4TagTrack trackMeta = (MP4TagTrack){
		.index = (nil == trackNumber ? 0 : [trackNumber unsignedIntegerValue]),
		.total = (nil == trackTotal ? 0 : [trackTotal unsignedIntegerValue])
	};
	if(nil == trackNumber && nil == trackTotal)
		result = MP4TagsSetTrack(mp4FileHandle, NULL);
	else
		result = MP4TagsSetTrack(mp4FileHandle, &trackMeta);
	
	// Compilation
	NSNumber *compilationNum = [metadata valueForKey:MetadataCompilationKey];
	if(nil == compilationNum)
		result = MP4TagsSetCompilation(mp4FileHandle, NULL);
	else {
		uint8_t compilation = (uint8_t)[compilationNum boolValue];
		result = MP4TagsSetCompilation(mp4FileHandle, &compilation);
	}
	
	
	// Disc number
	NSNumber *discNumber	= [metadata valueForKey:MetadataDiscNumberKey];
	NSNumber *discTotal		= [metadata valueForKey:MetadataDiscTotalKey];
	MP4TagDisk discMeta = (MP4TagDisk){
		.index = (nil == discNumber ? 0 : [discNumber unsignedIntegerValue]),
		.total = (nil == discTotal ? 0 : [discTotal unsignedIntegerValue])
	};
	if(nil == discNumber && nil == discTotal)
		result = MP4TagsSetDisk(mp4FileHandle, NULL);
	else
		result = MP4TagsSetDisk(mp4FileHandle, &discMeta);
	
	// BPM
	NSNumber *bpmNum = [metadata valueForKey:MetadataBPMKey];
	if(nil == bpmNum)
		result = MP4TagsSetTempo(mp4FileHandle, NULL);
	else {
		uint16_t tempo = (uint16_t)[bpmNum unsignedShortValue];
		result = MP4TagsSetTempo(mp4FileHandle, &tempo);
	}
	
	// Album art
/*	NSImage *albumArt = [metadata valueForKey:@"albumArt"];
	if(nil != albumArt) {
		NSData *data = getPNGDataForImage(albumArt); 
		MP4TagsSetCoverArt(mp4FileHandle, (u_int8_t *)[data bytes], [data length]);
	}*/
	
#if 0
	// ReplayGain
	NSNumber *referenceLoudness = [metadata valueForKey:ReplayGainReferenceLoudnessKey];
	if(nil == referenceLoudness)
		MP4DeleteMetadataFreeForm(mp4FileHandle, "replaygain_reference_loudness", NULL);
	else {
		const char *value = [[NSString stringWithFormat:@"%2.1f dB", [referenceLoudness doubleValue]] UTF8String];
		result = MP4TagsSetFreeForm(mp4FileHandle, "replaygain_reference_loudness", (const u_int8_t *)value, strlen(value), NULL);
	}

	NSNumber *trackGain = [metadata valueForKey:ReplayGainTrackGainKey];
	if(nil == trackGain)
		MP4DeleteMetadataFreeForm(mp4FileHandle, "replaygain_track_gain", NULL);
	else {
		const char *value = [[NSString stringWithFormat:@"%+2.2f dB", [trackGain doubleValue]] UTF8String];
		result = MP4TagsSetFreeForm(mp4FileHandle, "replaygain_track_gain", (const u_int8_t *)value, strlen(value), NULL);
	}

	NSNumber *trackPeak = [metadata valueForKey:ReplayGainTrackPeakKey];
	if(nil == trackPeak)
		MP4DeleteMetadataFreeForm(mp4FileHandle, "repaaygain_track_peak", NULL);
	else {
		const char *value = [[NSString stringWithFormat:@"%1.8f", [trackPeak doubleValue]] UTF8String];
		result = MP4TagsSetFreeForm(mp4FileHandle, "replaygain_track_peak", (const u_int8_t *)value, strlen(value), NULL);
	}

	NSNumber *albumGain = [metadata valueForKey:ReplayGainAlbumGainKey];
	if(nil == albumGain)
		MP4DeleteMetadataFreeForm(mp4FileHandle, "replaygain_album_gain", NULL);
	else {
		const char *value = [[NSString stringWithFormat:@"%+2.2f dB", [albumGain doubleValue]] UTF8String];
		result = MP4TagsSetFreeForm(mp4FileHandle, "replaygain_album_gain", (const u_int8_t *)value, strlen(value), NULL);
	}

	NSNumber *albumPeak = [metadata valueForKey:ReplayGainAlbumPeakKey];
	if(nil == albumPeak)
		MP4DeleteMetadataFreeForm(mp4FileHandle, "replaygain_album_peak", NULL);
	else {
		const char *value = [[NSString stringWithFormat:@"%1.8f", [albumPeak doubleValue]] UTF8String];
		result = MP4TagsSetFreeForm(mp4FileHandle, "replaygain_album_peak", (const u_int8_t *)value, strlen(value), NULL);
	}
#endif
	
	// Make our mark
	NSString *bundleShortVersionString	= [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
//	NSString *bundleVersion				= [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
//	NSString *applicationVersionString	= [NSString stringWithFormat:@"Play %@ (%@)", bundleShortVersionString, bundleVersion];
	NSString *applicationVersionString	= [NSString stringWithFormat:@"Play %@", bundleShortVersionString];
	
	result = MP4TagsSetEncodingTool(mp4FileHandle, [applicationVersionString UTF8String]);
	
	MP4Close(mp4FileHandle, 0);
	
	return YES;
}

@end
