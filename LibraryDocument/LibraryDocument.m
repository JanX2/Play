/*
 *  $Id$
 *
 *  Copyright (C) 2006 Stephen F. Booth <me@sbooth.org>
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

#import "LibraryDocument.h"
#import "AudioStreamDecoder.h"

@interface LibraryDocument (Private)

- (AudioPlayer *)			player;
- (NSManagedObject *)		fetchLibraryObject;
- (void)					addFilesOpenPanelDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode contextInfo:(void *)contextInfo;

@end

@implementation LibraryDocument

- (id) init
{
	if((self = [super init])) {
		_player = [[AudioPlayer alloc] init];
	}
	return self;
}

- (id) initWithType:(NSString *)type error:(NSError **)error
{
    if((self = [super initWithType:type error:error])) {
		NSManagedObjectContext	*managedObjectContext;
		NSManagedObject			*libraryObject;
		
		// Each LibraryDocument instance should contain one (and only one) Library entity
		managedObjectContext	= [self managedObjectContext];
        libraryObject			= [NSEntityDescription insertNewObjectForEntityForName:@"Library" inManagedObjectContext:managedObjectContext];

		// Disable undo registration for the create
        [managedObjectContext processPendingChanges];
        [[managedObjectContext undoManager] removeAllActions];

        [self updateChangeCount:NSChangeCleared];
    }
    return self;
}

- (void) dealloc
{
	[_player release];		_player = nil;
	
	[super dealloc];
}

- (NSString *) windowNibName 
{
    return @"LibraryDocument";
}

- (void) windowControllerDidLoadNib:(NSWindowController *)windowController 
{
    [super windowControllerDidLoadNib:windowController];

//	[windowController setWindowFrameAutosaveName:[NSString stringWithFormat:@"Play Library %@", @""]];	

	// Set up drag and drop
	[_streamTableView registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, @"NSURLsPboardType", NSURLPboardType, nil]];
	[_playlistTableView registerForDraggedTypes:[NSArray arrayWithObject:@"AudioStreamPboardType"]];
	
	// Set sort descriptors
	[_streamArrayController setSortDescriptors:[NSArray arrayWithObjects:
		[[[NSSortDescriptor alloc] initWithKey:@"metadata.artist" ascending:YES] autorelease],
		[[[NSSortDescriptor alloc] initWithKey:@"metadata.albumTitle" ascending:YES] autorelease],
		[[[NSSortDescriptor alloc] initWithKey:@"metadata.trackNumber" ascending:YES] autorelease],
		nil]];
	[_playlistArrayController setSortDescriptors:[NSArray arrayWithObjects:
		[[[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES] autorelease],
		nil]];	
}

#pragma mark Action Methods

- (IBAction) addFiles:(id)sender
{
	NSOpenPanel		*panel;
	NSArray			*types;
	
	panel	= [NSOpenPanel openPanel];
	types	= [NSArray arrayWithObjects:@"flac", nil];
	
	[panel setAllowsMultipleSelection:YES];
//	[panel setCanChooseDirectories:YES];
	
	[panel beginSheetForDirectory:nil file:nil types:types modalForWindow:[self windowForSheet] modalDelegate:self didEndSelector:@selector(addFilesOpenPanelDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

- (IBAction) insertPlaylistWithSelectedStreams:(id)sender
{
	NSManagedObjectContext		*managedObjectContext;
	NSArray						*selectedStreams;
	NSManagedObject				*playlistObject;
	NSManagedObject				*libraryObject;
	NSMutableSet				*streamsSet;
	BOOL						selectionChanged;

	managedObjectContext		= [self managedObjectContext];
	selectedStreams				= [_streamArrayController selectedObjects];
	playlistObject				= [NSEntityDescription insertNewObjectForEntityForName:@"Playlist" inManagedObjectContext:managedObjectContext];
	libraryObject				= [self fetchLibraryObject];
	
	[playlistObject setValue:libraryObject forKey:@"library"];
	
	streamsSet					= [playlistObject mutableSetValueForKey:@"streams"];
	
	[streamsSet addObjectsFromArray:selectedStreams];
	
	selectionChanged			= [_playlistArrayController setSelectedObjects:[NSArray arrayWithObject:playlistObject]];
}

- (IBAction) removeAudioStreams:(id)sender
{
	NSArray						*selectedStreams;
	NSArray						*selectedPlaylists;
	
	selectedStreams				= [_streamArrayController selectedObjects];
	selectedPlaylists			= [_playlistArrayController selectedObjects];

//	NSLog(@"stream=%@",[selectedStreams objectAtIndex:0]);
//	NSLog(@"playlist=%@",[selectedPlaylists objectAtIndex:0]);
//	[_streamArrayController remove:sender];
//	NSLog(@"stream=%@",[selectedStreams objectAtIndex:0]);
//	NSLog(@"playlist=%@",[selectedPlaylists objectAtIndex:0]);
//	return;
	
	if(0 == [selectedPlaylists count]) {
		[_streamArrayController remove:sender];
	}
	else {
		NSManagedObject			*streamObject;
		NSManagedObject			*playlistObject;
		NSMutableSet			*playlistSet;
		unsigned				i, j;

		for(i = 0; i < [selectedStreams count]; ++i) {
			streamObject	= [selectedStreams objectAtIndex:i];
			playlistSet		= [streamObject mutableSetValueForKey:@"playlists"];

			for(j = 0; j < [selectedPlaylists count]; ++j) {
				playlistObject	= [selectedPlaylists objectAtIndex:j];
				[playlistSet removeObject:playlistObject];
			}
		}
	}
}

#pragma mark File Addition

- (void) addFileToLibrary:(NSString *)path
{
	[self addURLToLibrary:[NSURL fileURLWithPath:path]];
}

- (void) addURLToLibrary:(NSURL *)url
{
	NSParameterAssert([url isFileURL]);
	
	NSString					*absoluteURL;
	NSManagedObject				*streamObject;
	NSManagedObjectContext		*managedObjectContext;
	NSEntityDescription			*streamEntityDescription;
	NSManagedObject				*libraryObject;
	NSFetchRequest				*fetchRequest;
	NSPredicate					*predicate;
	NSError						*error;
	NSArray						*fetchResult;
	NSMutableSet				*playlistSet;
	AudioStreamDecoder			*streamDecoder;
	NSManagedObject				*propertiesObject;
	NSManagedObject				*metadataObject;
	BOOL						result;
	unsigned					i;
	
	managedObjectContext		= [self managedObjectContext];

	// Convert the URL to a string for storage and comparison
	absoluteURL					= [url absoluteString];
	
	// ========================================
	// Verify that the requested AudioStream does not already exist in this Library, as identified by URL
	streamEntityDescription		= [NSEntityDescription entityForName:@"AudioStream" inManagedObjectContext:managedObjectContext];
	fetchRequest				= [[[NSFetchRequest alloc] init] autorelease];
	predicate					= [NSPredicate predicateWithFormat:@"url = %@", absoluteURL];
	error						= nil;
	
	[fetchRequest setEntity:streamEntityDescription];
	[fetchRequest setPredicate:predicate];
	
	fetchResult					= [managedObjectContext executeFetchRequest:fetchRequest error:&error];
	
	if(nil == fetchResult) {
		result					= [self presentError:error];
	}
	
	// ========================================
	// If the AudioStream does exist in the Library, just add it to any playlists that are selected
	if(0 < [fetchResult count]) {
		for(i = 0; i < [fetchResult count]; ++i) {
			streamObject		= [fetchResult objectAtIndex:i];
			
			playlistSet			= [streamObject mutableSetValueForKey:@"playlists"];
			[playlistSet addObjectsFromArray:[_playlistArrayController selectedObjects]];
		}
		
		return;
	}
	
	// ========================================
	// Now that we know the AudioStream isn't in the Library, add it
	streamObject				= [NSEntityDescription insertNewObjectForEntityForName:@"AudioStream" inManagedObjectContext:managedObjectContext];
	
	// Fetch the Library entity from the store
	libraryObject				= [self fetchLibraryObject];
	
	// ========================================
	// Fill in properties and relationships
	[streamObject setValue:absoluteURL forKey:@"url"];
	[streamObject setValue:libraryObject forKey:@"library"];
	[streamObject setValue:[NSDate date] forKey:@"dateAdded"];
	
	playlistSet					= [streamObject mutableSetValueForKey:@"playlists"];
	[playlistSet addObjectsFromArray:[_playlistArrayController selectedObjects]];

	// ========================================
	// Read properties and metadata
	streamDecoder				= [AudioStreamDecoder streamDecoderForURL:url error:&error];
	
	if(nil == streamDecoder) {
		result					= [self presentError:error];
		return;
	}
	
	result						= [streamDecoder readPropertiesAndMetadata:&error];
	
	if(NO == result) {
		result					= [self presentError:error];
		return;
	}
	
	propertiesObject			= [NSEntityDescription insertNewObjectForEntityForName:@"AudioProperties" inManagedObjectContext:managedObjectContext];
		
	[streamObject setValue:propertiesObject forKey:@"properties"];

	[propertiesObject setValue:[NSNumber numberWithFloat:[streamDecoder pcmFormat].mSampleRate] forKey:@"sampleRate"];
	[propertiesObject setValue:[NSNumber numberWithUnsignedInt:[streamDecoder pcmFormat].mBitsPerChannel] forKey:@"bitsPerChannel"];
	[propertiesObject setValue:[NSNumber numberWithUnsignedInt:[streamDecoder pcmFormat].mChannelsPerFrame] forKey:@"channelsPerFrame"];
	[propertiesObject setValue:[NSNumber numberWithLongLong:[streamDecoder totalFrames]] forKey:@"totalFrames"];
	
	metadataObject				= [NSEntityDescription insertNewObjectForEntityForName:@"AudioMetadata" inManagedObjectContext:managedObjectContext];
	
	[streamObject setValue:metadataObject forKey:@"metadata"];
	
	[metadataObject setValue:[streamDecoder valueForKeyPath:@"metadata.albumArtist"] forKey:@"albumArtist"];
	[metadataObject setValue:[streamDecoder valueForKeyPath:@"metadata.albumTitle"] forKey:@"albumTitle"];
	[metadataObject setValue:[streamDecoder valueForKeyPath:@"metadata.artist"] forKey:@"artist"];
	[metadataObject setValue:[streamDecoder valueForKeyPath:@"metadata.composer"] forKey:@"composer"];
	[metadataObject setValue:[streamDecoder valueForKeyPath:@"metadata.discNumber"] forKey:@"discNumber"];
	[metadataObject setValue:[streamDecoder valueForKeyPath:@"metadata.discTotal"] forKey:@"discTotal"];
	[metadataObject setValue:[streamDecoder valueForKeyPath:@"metadata.genre"] forKey:@"genre"];
	[metadataObject setValue:[streamDecoder valueForKeyPath:@"metadata.isrc"] forKey:@"isrc"];
	[metadataObject setValue:[streamDecoder valueForKeyPath:@"metadata.mcn"] forKey:@"mcn"];
	[metadataObject setValue:[streamDecoder valueForKeyPath:@"metadata.partOfCompilation"] forKey:@"partOfCompilation"];
	[metadataObject setValue:[streamDecoder valueForKeyPath:@"metadata.title"] forKey:@"title"];
	[metadataObject setValue:[streamDecoder valueForKeyPath:@"metadata.trackNumber"] forKey:@"trackNumber"];
	[metadataObject setValue:[streamDecoder valueForKeyPath:@"metadata.trackTotal"] forKey:@"trackTotal"];
}

#pragma mark Playback Control

- (IBAction) play:(id)sender
{
	NSArray						*streams;
	
	streams						= [_streamArrayController selectedObjects];

	[self playStream:streams];
}

- (IBAction) stop:(id)sender
{
	[[self player] stop];
}

- (void) playStream:(NSArray *)streams
{
	NSManagedObjectContext		*managedObjectContext;
	NSManagedObject				*streamObject;
	NSManagedObject				*propertiesObject;
	NSURL						*url;
	BOOL						result;
	AudioStreamDecoder			*streamDecoder;
	NSError						*error;
	
	if(0 == [streams count]) {
		return;
	}
	
	error						= nil;
	managedObjectContext		= [self managedObjectContext];
	streamObject				= [streams objectAtIndex:0];
	propertiesObject			= [streamObject valueForKey:@"properties"];
	url							= [NSURL URLWithString:[streamObject valueForKey:@"url"]];
	streamDecoder				= [AudioStreamDecoder streamDecoderForURL:url error:&error];

	if(nil == streamDecoder) {
		BOOL					errorRecoveryDone;
		
		errorRecoveryDone		= [self presentError:error];
		return;
	}
	
	// Read properties for this stream if they aren't already known (they should be)
	if(nil == propertiesObject) {		
		
		error					= nil;
		result					= [streamDecoder readProperties:&error];

		if(NO == result) {
			BOOL					errorRecoveryDone;
			
			errorRecoveryDone		= [self presentError:error];
			return;
		}
		
		propertiesObject				= [NSEntityDescription insertNewObjectForEntityForName:@"AudioProperties" inManagedObjectContext:managedObjectContext];

		// Read properties from the raw stream and set them
		
		[propertiesObject setValue:[NSNumber numberWithFloat:[streamDecoder pcmFormat].mSampleRate] forKey:@"sampleRate"];
		[propertiesObject setValue:[NSNumber numberWithUnsignedInt:[streamDecoder pcmFormat].mBitsPerChannel] forKey:@"bitsPerChannel"];
		[propertiesObject setValue:[NSNumber numberWithUnsignedInt:[streamDecoder pcmFormat].mChannelsPerFrame] forKey:@"channelsPerFrame"];
		[propertiesObject setValue:[NSNumber numberWithLongLong:[streamDecoder totalFrames]] forKey:@"totalFrames"];

		[streamObject setValue:propertiesObject forKey:@"properties"];
	}
		
	result						= [[self player] setStreamDecoder:streamDecoder error:&error];
	if(NO == result) {
		
	}
	
	[streamObject setValue:[NSDate date] forKey:@"lastPlayed"];

	[[self player] play];
}

@end

@implementation LibraryDocument (NSTableViewDelegateMethods)

- (void) tableViewSelectionDidChange:(NSNotification *)aNotification
{
	id							bindingTarget;
	NSString					*keyPath;
	NSDictionary				*bindingOptions;

	// When the selected Playlist changes, update the AudioStream Array Controller's bindings
	[_streamArrayController unbind:@"contentSet"];

	if(0 == [[[_playlistArrayController selection] valueForKey:@"@count"] intValue]) {
		bindingTarget			= [self fetchLibraryObject];
		keyPath					= @"streams";
		bindingOptions			= [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:NSDeletesObjectsOnRemoveBindingsOption];
	}
	else {
		bindingTarget			= _playlistArrayController;
		keyPath					= @"selection.streams";
		bindingOptions			= nil;
	}
	
	[_streamArrayController bind:@"contentSet" toObject:bindingTarget withKeyPath:keyPath options:bindingOptions];
}

@end

@implementation LibraryDocument (Private)

- (AudioPlayer *) player
{
	return [[_player retain] autorelease];
}

- (NSManagedObject *) fetchLibraryObject
{
	NSManagedObjectContext		*managedObjectContext;
	NSEntityDescription			*libraryEntityDescription;
	NSManagedObject				*libraryObject;
	NSFetchRequest				*fetchRequest;
	NSError						*error;
	NSArray						*fetchResult;

	// Fetch the Library entity from the store
	managedObjectContext		= [self managedObjectContext];
	libraryEntityDescription	= [NSEntityDescription entityForName:@"Library" inManagedObjectContext:managedObjectContext];
	fetchRequest				= [[[NSFetchRequest alloc] init] autorelease];
	error						= nil;
	
	[fetchRequest setEntity:libraryEntityDescription];
	
	fetchResult					= [managedObjectContext executeFetchRequest:fetchRequest error:&error];
	
	if(nil == fetchResult) {
		BOOL					errorRecoveryDone;
		
		errorRecoveryDone		= [self presentError:error];
		return nil;
	}
	
	// There should always be one (and only one!) Library entity in the store
	NSAssert(1 == [fetchResult count], @"More than one Library entity returned!");
	
	libraryObject				= [fetchResult objectAtIndex:0];

	return [[libraryObject retain] autorelease];
}

- (void) addFilesOpenPanelDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	if(NSOKButton == returnCode) {
		NSArray						*URLs;
		NSURL						*URL;
		unsigned					i;
		
		URLs						= [panel URLs];
		
		for(i = 0; i < [URLs count]; ++i) {
			URL						= [URLs objectAtIndex:i];
			
			[self addURLToLibrary:URL];
		}	
	}	
}

@end