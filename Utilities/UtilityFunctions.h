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

#import <Cocoa/Cocoa.h>

#ifdef __cplusplus
extern "C" {
#endif
	
	// Types of audio contained in an Ogg stream that Play knows about
	enum _OggStreamType {
		kOggStreamTypeInvalid,
		kOggStreamTypeUnknown,
		kOggStreamTypeVorbis,
		kOggStreamTypeFLAC,
		kOggStreamTypeSpeex	
	};
	typedef enum _OggStreamType OggStreamType;
	
	// Determine the type of audio contained in an ogg stream
	OggStreamType oggStreamType(NSURL *url);

	NSArray * getBuiltinExtensions();
	NSArray * getCoreAudioExtensions();
	NSArray	* getAudioExtensions();

	NSData * getPNGDataForImage(NSImage *image);
	NSData * getBitmapDataForImage(NSImage *image, NSBitmapImageFileType type);
	
#if MAC_OS_X_VERSION_MIN_REQUIRED > MAC_OS_X_VERSION_10_4
	NSTreeNode * treeNodeForRepresentedObject(NSTreeNode *root, id representedObject);
#endif

#ifdef __cplusplus
}
#endif
