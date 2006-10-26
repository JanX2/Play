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

#import <Cocoa/Cocoa.h>

// A simple implementation of a circular (AKA ring) buffer
@interface CircularBuffer : NSObject
{
	uint8_t			*_buffer;
	unsigned		_bufsize;

	uint8_t			*_readPtr;
	uint8_t			*_writePtr;
}

- (id)				initWithBufferSize:(unsigned)size;

- (void)			reset;

- (unsigned)		bufferSize;
- (void)			increaseBufferSize:(unsigned)bufferSize;
- (void)			resizeBuffer:(unsigned)bufferSize;

- (unsigned)		bytesAvailable;
- (unsigned)		freeSpaceAvailable;
- (double)			percentFull;

- (unsigned)		putData:(const void *)data byteCount:(unsigned)byteCount;
- (unsigned)		getData:(void *)buffer byteCount:(unsigned)byteCount;

- (const void *)	exposeBufferForReading;
- (void)			readBytes:(unsigned)byteCount;

- (void *)			exposeBufferForWriting;
- (void)			wroteBytes:(unsigned)byteCount;

@end
