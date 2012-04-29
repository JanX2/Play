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

#import "AudioStream.h"
#import "CollectionManager.h"
#import "AudioStreamManager.h"
#import "AudioPropertiesReader.h"
#import "AudioMetadataReader.h"
#import "AudioMetadataWriter.h"
#import "AudioLibrary.h"
#import "AudioDecoder.h"
#import "LoopableRegionDecoder.h"

NSString * const	StreamURLKey							= @"url";
NSString * const	StreamURLBookmarkKey					= @"urlBookmark";
NSString * const	StreamStartingFrameKey					= @"startingFrame";
NSString * const	StreamFrameCountKey						= @"frameCount";

NSString * const	StatisticsDateAddedKey					= @"dateAdded";
NSString * const	StatisticsFirstPlayedDateKey			= @"firstPlayed";
NSString * const	StatisticsLastPlayedDateKey				= @"lastPlayed";
NSString * const	StatisticsLastSkippedDateKey			= @"lastSkipped";
NSString * const	StatisticsPlayCountKey					= @"playCount";
NSString * const	StatisticsSkipCountKey					= @"skipCount";
NSString * const	StatisticsRatingKey						= @"rating";

NSString * const	MetadataTitleKey						= @"title";
NSString * const	MetadataAlbumTitleKey					= @"albumTitle";
NSString * const	MetadataArtistKey						= @"artist";
NSString * const	MetadataAlbumArtistKey					= @"albumArtist";
NSString * const	MetadataGenreKey						= @"genre";
NSString * const	MetadataComposerKey						= @"composer";
NSString * const	MetadataDateKey							= @"date";
NSString * const	MetadataCompilationKey					= @"compilation";
NSString * const	MetadataTrackNumberKey					= @"trackNumber";
NSString * const	MetadataTrackTotalKey					= @"trackTotal";
NSString * const	MetadataDiscNumberKey					= @"discNumber";
NSString * const	MetadataDiscTotalKey					= @"discTotal";
NSString * const	MetadataCommentKey						= @"comment";
NSString * const	MetadataISRCKey							= @"isrc";
NSString * const	MetadataMCNKey							= @"mcn";
NSString * const	MetadataBPMKey							= @"bpm";
NSString * const	MetadataMusicDNSPUIDKey					= @"musicDNSPUID";
NSString * const	MetadataMusicBrainzIDKey				= @"musicBrainzID";

NSString * const	ReplayGainReferenceLoudnessKey			= @"referenceLoudness";
NSString * const	ReplayGainTrackGainKey					= @"trackGain";
NSString * const	ReplayGainTrackPeakKey					= @"trackPeak";
NSString * const	ReplayGainAlbumGainKey					= @"albumGain";
NSString * const	ReplayGainAlbumPeakKey					= @"albumPeak";

NSString * const	PropertiesFileTypeKey					= @"fileType";
NSString * const	PropertiesDataFormatKey					= @"dataFormat";
NSString * const	PropertiesFormatDescriptionKey			= @"formatDescription";
NSString * const	PropertiesBitsPerChannelKey				= @"bitsPerChannel";
NSString * const	PropertiesChannelsPerFrameKey			= @"channelsPerFrame";
NSString * const	PropertiesSampleRateKey					= @"sampleRate";
NSString * const	PropertiesTotalFramesKey				= @"totalFrames";
NSString * const	PropertiesBitrateKey					= @"bitrate";

// ========================================
// KVC key names
// ========================================
NSString * const	IsPlayingKey							= @"isPlaying";

@interface AudioStream (private)
- (void) updateURLBookmark;
@end

@implementation AudioStream

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
	if ([key isEqualToString:@"trackString"]) {
		return [NSSet setWithObjects:MetadataTrackNumberKey, MetadataTrackTotalKey, nil];
	}
	else if ([key isEqualToString:@"discString"]) {
		return [NSSet setWithObjects:MetadataDiscNumberKey, MetadataDiscTotalKey, nil];
	}
	else if ([key isEqualToString:@"isPlayingValue"]) {
		return [NSSet setWithObject:IsPlayingKey];
	}
	else if ([key isEqualToString:@"isExternalReferenceOrAvailableFile"]) {
		return [NSSet setWithObject:StreamURLKey];
	}
	else {
		return [super keyPathsForValuesAffectingValueForKey:key];
	}
}

+ (id) insertStreamForURL:(NSURL *)URL withInitialValues:(NSDictionary *)keyedValues
{
	return [self insertStreamForURL:URL startingFrame:[NSNumber numberWithInt:-1] frameCount:[NSNumber numberWithInt:-1] withInitialValues:keyedValues];
}

+ (id) insertStreamForURL:(NSURL *)URL startingFrame:(NSNumber *)startingFrame withInitialValues:(NSDictionary *)keyedValues
{
	return [self insertStreamForURL:URL startingFrame:startingFrame frameCount:[NSNumber numberWithInt:-1] withInitialValues:keyedValues];
}

+ (id) insertStreamForURL:(NSURL *)URL startingFrame:(NSNumber *)startingFrame frameCount:(NSNumber *)frameCount withInitialValues:(NSDictionary *)keyedValues
{
	NSParameterAssert(nil != URL);
	NSParameterAssert(nil != startingFrame);
	NSParameterAssert(nil != frameCount);
	
	AudioStream *stream = [[AudioStream alloc] init];
	
	// Call init: methods here to avoid sending change notifications
	[stream initValue:URL forKey:StreamURLKey];
	[stream initValue:startingFrame forKey:StreamStartingFrameKey];
	[stream initValue:frameCount forKey:StreamFrameCountKey];
	
	[stream initValue:[NSDate date] forKey:StatisticsDateAddedKey];
	[stream initValuesForKeysWithDictionary:keyedValues];
	
	[stream updateURLBookmark];
	
	if(NO == [[[CollectionManager manager] streamManager] insertStream:stream])
		[stream release], stream = nil;
	
	return [stream autorelease];
}

- (IBAction) resetPlayCount:(id)sender
{
	[self setValue:nil forKey:StatisticsPlayCountKey];
	[self setValue:nil forKey:StatisticsLastPlayedDateKey];
}

- (IBAction) resetSkipCount:(id)sender
{
	[self setValue:nil forKey:StatisticsSkipCountKey];
	[self setValue:nil forKey:StatisticsLastSkippedDateKey];
}

- (IBAction) clearProperties:(id)sender
{
	[self setValue:nil forKey:PropertiesFileTypeKey];
	[self setValue:nil forKey:PropertiesDataFormatKey];
	[self setValue:nil forKey:PropertiesFormatDescriptionKey];
	[self setValue:nil forKey:PropertiesBitsPerChannelKey];
	[self setValue:nil forKey:PropertiesChannelsPerFrameKey];
	[self setValue:nil forKey:PropertiesSampleRateKey];
	[self setValue:nil forKey:PropertiesTotalFramesKey];
	[self setValue:nil forKey:PropertiesBitrateKey];
}

- (IBAction) clearMetadata:(id)sender
{
	[self setValue:nil forKey:MetadataTitleKey];
	[self setValue:nil forKey:MetadataAlbumTitleKey];
	[self setValue:nil forKey:MetadataArtistKey];
	[self setValue:nil forKey:MetadataAlbumArtistKey];
	[self setValue:nil forKey:MetadataGenreKey];
	[self setValue:nil forKey:MetadataComposerKey];
	[self setValue:nil forKey:MetadataDateKey];
	[self setValue:nil forKey:MetadataCompilationKey];
	[self setValue:nil forKey:MetadataTrackNumberKey];
	[self setValue:nil forKey:MetadataTrackTotalKey];
	[self setValue:nil forKey:MetadataDiscNumberKey];
	[self setValue:nil forKey:MetadataDiscTotalKey];
	[self setValue:nil forKey:MetadataCommentKey];
	[self setValue:nil forKey:MetadataISRCKey];
	[self setValue:nil forKey:MetadataMCNKey];
	[self setValue:nil forKey:MetadataBPMKey];
	[self setValue:nil forKey:MetadataMusicDNSPUIDKey];
	[self setValue:nil forKey:MetadataMusicBrainzIDKey];
}

- (IBAction) clearReplayGain:(id)sender
{
	[self setValue:nil forKey:ReplayGainReferenceLoudnessKey];
	[self setValue:nil forKey:ReplayGainTrackGainKey];
	[self setValue:nil forKey:ReplayGainTrackPeakKey];
	[self setValue:nil forKey:ReplayGainAlbumGainKey];
	[self setValue:nil forKey:ReplayGainAlbumPeakKey];
}

- (IBAction) rescanProperties:(id)sender
{
	NSError					*error				= nil;
	AudioPropertiesReader	*propertiesReader	= [AudioPropertiesReader propertiesReaderForURL:[self currentStreamURL] error:&error];
	
	if(nil == propertiesReader) {
/*		if(nil != error)
			[[AudioLibrary library] presentError:error];
		 */
		return;
	}
	
	BOOL result = [propertiesReader readProperties:&error];
	if(NO == result) {
/*		if(nil != error)
			[[AudioLibrary library] presentError:error];
		 */
		return;
	}
	
	// Empty old properties
	[self clearProperties:sender];
	
	NSDictionary	*properties		= [propertiesReader properties];
	id				value;
	
	for(NSString *key in [properties allKeys]) {
		value = [properties valueForKey:key];
		[self setValue:value forKey:key];
	}
	
	[self updateURLBookmark];

}

- (IBAction) rescanMetadata:(id)sender
{
	NSError					*error				= nil;
	AudioMetadataReader		*metadataReader		= [AudioMetadataReader metadataReaderForURL:[self currentStreamURL] error:&error];

	if(nil == metadataReader) {
/*		if(nil != error)
			[[AudioLibrary library] presentError:error];
		*/
		return;
	}
	
	BOOL result = [metadataReader readMetadata:&error];
	if(NO == result) {
/*		if(nil != error)
			[[AudioLibrary library] presentError:error];
		*/
		return;
	}
	
	// Empty old metadata
	[self clearMetadata:sender];

	NSDictionary	*metadata		= [metadataReader metadata];
	id				value;
	
	for(NSString *thisKey in [metadata allKeys]) {
		value = [metadata valueForKey:thisKey];
		[self setValue:value forKey:thisKey];
	}
}

- (NSString *) currentStreamURLString
{
	return [[self currentStreamURL] absoluteString];
}

- (NSURL *) currentStreamURL
{
    NSURL* originalURL;

	originalURL = [self valueForKey:StreamURLKey];
	
	if ([NSURL respondsToSelector:@selector(URLByResolvingBookmarkData:options:relativeToURL:bookmarkDataIsStale:error:)]) {
		if ((nil == originalURL) || ([originalURL isFileURL] && ([originalURL checkResourceIsReachableAndReturnError:NULL] == NO))) {
			NSData *bookmarkData = [self valueForKey:StreamURLBookmarkKey];
			if (!bookmarkData || ![bookmarkData isKindOfClass:[NSData class]]) {
				return originalURL;
			} 
			else {
				NSURL* resolvedFileURL;
				
				// test if the file still exists
				resolvedFileURL = [NSURL URLByResolvingBookmarkData:bookmarkData
															options:(NSURLBookmarkResolutionWithoutUI | NSURLBookmarkResolutionWithoutMounting)
													  relativeToURL:nil bookmarkDataIsStale:NULL error:NULL];
				if (resolvedFileURL) {
					[self setCurrentStreamURL:resolvedFileURL];
					return resolvedFileURL;
				}
				else {
					return originalURL;
				}
				
			}
			
		}
	
	}
	
	return originalURL;
}

- (void) setCurrentStreamURL:(NSURL *)newURL
{
	[self setValue:newURL forKey:StreamURLKey];
	[self updateURLBookmark];
}

- (void) updateURLBookmark
{
	NSURL * newURL = [self valueForKey:StreamURLKey];
	NSParameterAssert(nil != newURL);
	
	if ([newURL isFileURL] && [newURL respondsToSelector:@selector(bookmarkDataWithOptions:includingResourceValuesForKeys:relativeToURL:error:)]) {
		NSData* bookmarkData = [newURL bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark includingResourceValuesForKeys:nil relativeToURL:nil error:NULL];
		if (bookmarkData) {
			//NSLog( @">>>> Updating bookmark data for: %@", [newURL absoluteURL] ); 
			[self setValue:bookmarkData forKey:StreamURLBookmarkKey];
		}
	}
}

- (IBAction) saveMetadata:(id)sender
{
	// FIXME: Save album-only metadata to original file?
	if([self isPartOfCueSheet])
		return;
	
	NSError					*error				= nil;
	AudioMetadataWriter		*metadataWriter		= [AudioMetadataWriter metadataWriterForURL:[self currentStreamURL] error:&error];
	
	if(nil == metadataWriter) {
/*		if(nil != error)
			[[AudioLibrary library] presentError:error];
		*/
		return;
	}
	
	BOOL result = [metadataWriter writeMetadata:self error:&error];
	if(NO == result) {
/*		if(nil != error)
			[[AudioLibrary library] presentError:error];
		*/
		return;
	}	
}

- (IBAction) refreshPath:(id)sender
{
	[self currentStreamURL];
}

- (NSString *) trackString
{
	NSNumber	*trackNumber	= [self valueForKey:MetadataTrackNumberKey];
	NSNumber	*trackTotal		= [self valueForKey:MetadataTrackTotalKey];
	
	if(nil != trackNumber && nil != trackTotal)
		return [NSString stringWithFormat:NSLocalizedStringFromTable(@"%@/%@", @"AudioStream", @""), trackNumber, trackTotal];
	else if(nil != trackNumber)
		return [trackNumber stringValue];
	else if(nil != trackTotal)
		return [NSString stringWithFormat:NSLocalizedStringFromTable(@"/%@", @"AudioStream", @""), trackTotal];

	return nil;
}

- (NSString *) discString
{
	NSNumber	*discNumber		= [self valueForKey:MetadataDiscNumberKey];
	NSNumber	*discTotal		= [self valueForKey:MetadataDiscTotalKey];
	
	if(nil != discNumber && nil != discTotal)
		return [NSString stringWithFormat:NSLocalizedStringFromTable(@"%@/%@", @"AudioStream", @""), discNumber, discTotal];
	else if(nil != discNumber)
		return [discNumber stringValue];
	else if(nil != discTotal)
		return [NSString stringWithFormat:NSLocalizedStringFromTable(@"/%@", @"AudioStream", @""), discTotal];
	
	return nil;
}

- (NSString *) filename
{
	return [[NSFileManager defaultManager] displayNameAtPath:[[self currentStreamURL] path]];
}

- (NSString *) pathname
{
	return [[self currentStreamURL] path];
}

- (NSNumber *) duration
{
	if([self isPartOfCueSheet])
		return [NSNumber numberWithDouble:[[self valueForKey:StreamFrameCountKey] longLongValue] / [[self valueForKey:PropertiesSampleRateKey] doubleValue]];
	else
		return [self totalDuration];
}

- (NSNumber *) totalDuration
{
	return [NSNumber numberWithDouble:[[self valueForKey:PropertiesTotalFramesKey] longLongValue] / [[self valueForKey:PropertiesSampleRateKey] doubleValue]];
}

- (BOOL) isPlaying							{ return _playing; }
- (void) setIsPlaying:(BOOL)playing			{ _playing = playing; }

- (NSNumber *) isPlayingValue				{ return [NSNumber numberWithBool:_playing]; }


- (BOOL) isPartOfCueSheet
{
	NSNumber	*startingFrame	= [self valueForKey:StreamStartingFrameKey];
	NSNumber	*frameCount		= [self valueForKey:StreamFrameCountKey];
	
	// For reasons related to SQLite (see http://sqlite.org/nulls.html), -1 is used instead of NULL
	return (-1 != [startingFrame longLongValue] && -1 != [frameCount intValue]);
}

- (BOOL) isExternalReferenceOrAvailableFile;
{
    NSURL* url = [self valueForKey:StreamURLKey];
	if ((nil == url) || ([url isFileURL] && ([[NSFileManager defaultManager] fileExistsAtPath:[url path]] == NO))) {
		return NO;
	}
	else {
		return YES;
	}
}

- (id <AudioDecoderMethods>) decoder:(NSError **)error
{
	if([self isPartOfCueSheet])
		return [LoopableRegionDecoder decoderWithURL:[self currentStreamURL] 
									  startingFrame:[[self valueForKey:StreamStartingFrameKey] longLongValue]
										 frameCount:[[self valueForKey:StreamFrameCountKey] unsignedIntegerValue]
											  error:error];
	else
		return [AudioDecoder decoderWithURL:[self currentStreamURL] error:error];
}

- (void) save
{
	[[[CollectionManager manager] streamManager] saveStream:self];
}

- (void) delete
{
	[[[CollectionManager manager] streamManager] deleteStream:self];
}

- (NSString *) description
{
	return [NSString stringWithFormat:@"[%@] %@", 
		[self valueForKey:ObjectIDKey], 
		[self filename]];
}

- (NSString *) debugDescription
{
	return [NSString stringWithFormat:@"<%@: %p> [%@] %@",
		[self class], 
		self, 
		[self valueForKey:ObjectIDKey], 
		[self filename]];
}

#pragma mark Reimplementations

- (NSArray *) supportedKeys
{
	if(nil == _supportedKeys) {
		_supportedKeys	= [[NSArray alloc] initWithObjects:
			ObjectIDKey, 
			StreamURLKey,
			StreamURLBookmarkKey,
			StreamStartingFrameKey,
			StreamFrameCountKey,
			
			StatisticsDateAddedKey,
			StatisticsFirstPlayedDateKey,
			StatisticsLastPlayedDateKey,
			StatisticsLastSkippedDateKey,
			StatisticsPlayCountKey,
			StatisticsSkipCountKey,
			StatisticsRatingKey,
			
			MetadataTitleKey,
			MetadataAlbumTitleKey,
			MetadataArtistKey,
			MetadataAlbumArtistKey,
			MetadataGenreKey,
			MetadataComposerKey,
			MetadataDateKey,
			MetadataCompilationKey,
			MetadataTrackNumberKey,
			MetadataTrackTotalKey,
			MetadataDiscNumberKey,
			MetadataDiscTotalKey,
			MetadataCommentKey,
			MetadataISRCKey,
			MetadataMCNKey,
			MetadataBPMKey,
			MetadataMusicDNSPUIDKey,
			MetadataMusicBrainzIDKey,

			ReplayGainReferenceLoudnessKey,
			ReplayGainTrackGainKey,
			ReplayGainTrackPeakKey,
			ReplayGainAlbumGainKey,
			ReplayGainAlbumPeakKey,
			
			PropertiesFileTypeKey,
			PropertiesDataFormatKey,
			PropertiesFormatDescriptionKey,
			PropertiesBitsPerChannelKey,
			PropertiesChannelsPerFrameKey,
			PropertiesSampleRateKey,
			PropertiesTotalFramesKey,
			PropertiesBitrateKey,
			
			nil];
	}	
	return _supportedKeys;
}

@end

@implementation AudioStream (ScriptingAdditions)

- (void) handleEnqueueScriptCommand:(NSScriptCommand *)command
{
	[[AudioLibrary library] addStreamToPlayQueue:self];
}

- (NSScriptObjectSpecifier *) objectSpecifier
{
	id							libraryDescription	= [NSClassDescription classDescriptionForClass:[AudioLibrary class]];
	NSScriptObjectSpecifier		*librarySpecifier	= [[AudioLibrary library] objectSpecifier];
	NSScriptObjectSpecifier		*selfSpecifier		= [[NSUniqueIDSpecifier alloc] initWithContainerClassDescription:libraryDescription
																									  containerSpecifier:librarySpecifier 
																													 key:@"tracks" 
																												uniqueID:[self valueForKey:ObjectIDKey]];
	
	return [selfSpecifier autorelease];
}

@end
