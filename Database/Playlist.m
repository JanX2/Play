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

#import "Playlist.h"
#import "CollectionManager.h"
#import "PlaylistManager.h"
#import "AudioStreamManager.h"
#import "AudioLibrary.h"

NSString * const	PlaylistNameKey							= @"name";
NSString * const	PlaylistStreamsKey						= @"streams";

NSString * const	StatisticsDateCreatedKey				= @"dateCreated";

@implementation Playlist

+ (void) initialize
{
	[self exposeBinding:PlaylistStreamsKey];
}

+ (id) insertPlaylistWithInitialValues:(NSDictionary *)keyedValues
{
	Playlist *playlist = [[Playlist alloc] init];
	
	// Call init: methods here to avoid sending change notifications
	[playlist initValue:[NSDate date] forKey:StatisticsDateCreatedKey];
	[playlist initValuesForKeysWithDictionary:keyedValues];
	
	if(NO == [[[CollectionManager manager] playlistManager] insertPlaylist:playlist])
		[playlist release], playlist = nil;
	
	return [playlist autorelease];
}

- (id) init
{
	if((self = [super init]))
		_streams = [[NSMutableArray alloc] init];
	return self;
}

- (void) dealloc
{
	[_streams release], _streams = nil;
	
	[super dealloc];
}

#pragma mark Stream Management

- (NSArray *) streams
{
	return [[_streams retain] autorelease];
}

- (AudioStream *) streamAtIndex:(NSUInteger)thisIndex
{
	return [self objectInStreamsAtIndex:thisIndex];
}

- (void) addStream:(AudioStream *)stream
{
	[self insertObject:stream inStreamsAtIndex:[_streams count]];
}

- (void) insertStream:(AudioStream *)stream atIndex:(NSUInteger)thisIndex
{
	[self insertObject:stream inStreamsAtIndex:thisIndex];
}

- (void) addStreams:(NSArray *)streams
{
	NSParameterAssert(nil != streams);
	NSParameterAssert(0 != [streams count]);
	
	[[CollectionManager manager] beginUpdate];
	
	for(AudioStream *stream in streams)
		[self addStream:stream];
	
	[[CollectionManager manager] finishUpdate];
}

- (void) insertStreams:(NSArray *)streams atIndexes:(NSIndexSet *)indexes
{
	NSParameterAssert(nil != streams);
	NSParameterAssert(nil != indexes);
	NSParameterAssert(0 != [streams count]);
	NSParameterAssert([streams count] == [indexes count]);
	
	NSUInteger	i, count;
	NSUInteger	*indexBuffer	= (NSUInteger *)calloc([indexes count], sizeof(NSUInteger));
	NSAssert(NULL != indexBuffer, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Errors", @""));
	
	count = [indexes getIndexes:indexBuffer maxCount:[indexes count] inIndexRange:nil];
	NSAssert(count == [indexes count], @"Unable to extract all indexes.");
	
	[[CollectionManager manager] beginUpdate];

	for(i = 0; i < [streams count]; ++i)
		[self insertObject:[streams objectAtIndex:i] inStreamsAtIndex:indexBuffer[i]];
	
	[[CollectionManager manager] finishUpdate];

	free(indexBuffer);
}

- (void) addStreamWithID:(NSNumber *)objectID
{
	NSParameterAssert(nil != objectID);
	
	AudioStream *stream = [[[CollectionManager manager] streamManager] streamForID:objectID];
	[self insertObject:stream inStreamsAtIndex:[_streams count]];
}

- (void) insertStreamWithID:(NSNumber *)objectID atIndex:(NSUInteger)thisIndex
{
	NSParameterAssert(nil != objectID);

	AudioStream *stream = [[[CollectionManager manager] streamManager] streamForID:objectID];
	[self insertObject:stream inStreamsAtIndex:thisIndex];
}

- (void) addStreamsWithIDs:(NSArray *)objectIDs
{
	NSParameterAssert(nil != objectIDs);
	NSParameterAssert(0 != [objectIDs count]);

	AudioStream		*stream			= nil;
	
	[[CollectionManager manager] beginUpdate];

	for(NSNumber *objectID in objectIDs) {
		stream = [[[CollectionManager manager] streamManager] streamForID:objectID];
		[self addStream:stream];
	}

	[[CollectionManager manager] finishUpdate];	
}

- (void) insertStreamWithIDs:(NSArray *)objectIDs atIndexes:(NSIndexSet *)indexes
{
	NSParameterAssert(nil != objectIDs);
	NSParameterAssert(nil != indexes);
	NSParameterAssert(0 != [objectIDs count]);
	NSParameterAssert([objectIDs count] == [indexes count]);
	
	NSUInteger	i, count;
	NSUInteger	*indexBuffer	= (NSUInteger *)calloc([indexes count], sizeof(NSUInteger));
	NSAssert(NULL != indexBuffer, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Errors", @""));
	
	count = [indexes getIndexes:indexBuffer maxCount:[indexes count] inIndexRange:nil];
	NSAssert(count == [indexes count], @"Unable to extract all indexes.");
	
	[[CollectionManager manager] beginUpdate];
	
	for(i = 0; i < [objectIDs count]; ++i)
		[self insertStreamWithID:[objectIDs objectAtIndex:i] atIndex:indexBuffer[i]];
	
	[[CollectionManager manager] finishUpdate];	
	
	free(indexBuffer);
}

- (void) removeStreamAtIndex:(NSUInteger)thisIndex
{
	[self removeObjectFromStreamsAtIndex:thisIndex];
}

#pragma mark KVC Accessors

- (NSUInteger) countOfStreams
{
	return [_streams count];
}

- (AudioStream *) objectInStreamsAtIndex:(NSUInteger)thisIndex
{
	return [_streams objectAtIndex:thisIndex];
}

- (void) getStreams:(id *)buffer range:(NSRange)range
{
	return [_streams getObjects:buffer range:range];
}

#pragma mark KVC Mutators

- (void) insertObject:(AudioStream *)stream inStreamsAtIndex:(NSUInteger)thisIndex
{
	NSParameterAssert(nil != stream);

	[[[CollectionManager manager] playlistManager] playlist:self willInsertStream:stream atIndex:thisIndex];
	[_streams insertObject:stream atIndex:thisIndex];
	[[[CollectionManager manager] playlistManager] playlist:self didInsertStream:stream atIndex:thisIndex];
}

- (void) removeObjectFromStreamsAtIndex:(NSUInteger)thisIndex
{
	[[[CollectionManager manager] playlistManager] playlist:self willRemoveStreamAtIndex:thisIndex];
	[_streams removeObjectAtIndex:thisIndex];
	[[[CollectionManager manager] playlistManager] playlist:self didRemoveStreamAtIndex:thisIndex];
}

- (BOOL) isPlaying							{ return _playing; }
- (void) setIsPlaying:(BOOL)playing			{ _playing = playing; }

- (void) save
{
	[[[CollectionManager manager] playlistManager] savePlaylist:self];
}

- (void) delete
{
	[[[CollectionManager manager] playlistManager] deletePlaylist:self];
}

- (NSString *) description
{
	return [NSString stringWithFormat:@"[%@] %@", [self valueForKey:ObjectIDKey], [self valueForKey:PlaylistNameKey]];
}

- (NSString *) debugDescription
{
	return [NSString stringWithFormat:@"<%@, %p> [%@] %@", [self class], self, [self valueForKey:ObjectIDKey], [self valueForKey:PlaylistNameKey]];
}

#pragma mark Reimplementations

- (NSArray *) supportedKeys
{
	if(nil == _supportedKeys) {
		_supportedKeys	= [[NSArray alloc] initWithObjects:
			ObjectIDKey, 

			PlaylistNameKey, 
			
			StatisticsDateCreatedKey,
			StatisticsFirstPlayedDateKey,
			StatisticsLastPlayedDateKey,
			StatisticsPlayCountKey,
			
			nil];
	}	
	return _supportedKeys;
}

@end

@implementation Playlist (PlaylistNodeMethods)

- (void) loadStreams
{
	[self willChangeValueForKey:PlaylistStreamsKey];
	[_streams removeAllObjects];
	[_streams addObjectsFromArray:[[[CollectionManager manager] streamManager] streamsForPlaylist:self]];
	[self didChangeValueForKey:PlaylistStreamsKey];
}

@end

@implementation Playlist (ScriptingAdditions)

- (void) handleEnqueueScriptCommand:(NSScriptCommand *)command
{
	[self loadStreams];
	[[AudioLibrary library] addStreamsToPlayQueue:[self streams]];
}

- (NSScriptObjectSpecifier *) objectSpecifier
{
	id							libraryDescription	= [NSClassDescription classDescriptionForClass:[AudioLibrary class]];
	NSScriptObjectSpecifier		*librarySpecifier	= [[AudioLibrary library] objectSpecifier];
	NSScriptObjectSpecifier		*selfSpecifier		= [[NSUniqueIDSpecifier alloc] initWithContainerClassDescription:libraryDescription
																								  containerSpecifier:librarySpecifier 
																												 key:@"playlists" 
																											uniqueID:[self valueForKey:ObjectIDKey]];
	
	return [selfSpecifier autorelease];
}

@end
