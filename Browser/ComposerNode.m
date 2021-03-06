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

#import "ComposerNode.h"
#import "AudioLibrary.h"
#import "CollectionManager.h"
#import "AudioStreamManager.h"
#import "AudioStream.h"

@interface AudioStreamCollectionNode (Private)
- (NSMutableArray *) streamsArray;
@end

@implementation ComposerNode

- (void) loadStreams
{
	[self willChangeValueForKey:@"streams"];
	[[self streamsArray] addObjectsFromArray:[[[CollectionManager manager] streamManager] streamsForComposer:[self name]]];
	[self didChangeValueForKey:@"streams"];
}

- (void) refreshStreams
{
	[self willChangeValueForKey:@"streams"];
	[[self streamsArray] removeAllObjects];
	[[self streamsArray] addObjectsFromArray:[[[CollectionManager manager] streamManager] streamsForComposer:[self name]]];
	[self didChangeValueForKey:@"streams"];
}

#pragma mark KVC Mutator Overrides

- (void) insertObject:(AudioStream *)stream inStreamsAtIndex:(NSUInteger)thisIndex
{
	NSAssert([self canInsertStream], @"Attempt to insert a stream in an immutable ComposerNode");
	
	// Only add streams that match our composer
	if([[stream valueForKey:MetadataComposerKey] isEqualToString:[self name]]) {
		[[self streamsArray] insertObject:stream atIndex:thisIndex];
	}
}

- (void) removeObjectFromStreamsAtIndex:(NSUInteger)thisIndex
{
	NSAssert([self canRemoveStream], @"Attempt to remove a stream from an immutable ComposerNode");	
	
	AudioStream *stream = [[self streamsArray] objectAtIndex:thisIndex];
	
	if([stream isPlaying]) {
		[[AudioLibrary library] stop:self];
	}
	
	[stream delete];	
	[[self streamsArray] removeObjectAtIndex:thisIndex];
}

@end
