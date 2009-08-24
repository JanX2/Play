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

/*
 * This is a port of the BlockingClient client class from 
 * the Last.fm ScrobSub library by sharevari
 */

#import "AudioScrobblerClient.h"

#include <arpa/inet.h>

#define kBufferSize		1024
#define	kPortsToStep	5

static in_addr_t 
addressForHost(NSString *hostname)
{
	NSCParameterAssert(nil != hostname);
	
	in_addr_t			address;
	struct hostent		*hostinfo;
	
	address = inet_addr([hostname cStringUsingEncoding:NSASCIIStringEncoding]);
	
    if(INADDR_NONE == address) {
        hostinfo = gethostbyname([hostname cStringUsingEncoding:NSASCIIStringEncoding]);
        if(NULL == hostinfo) {
			NSLog(@"AudioScrobblerClient error: Unable to resolve address for \"%@\".", hostname);
			return INADDR_NONE;
        }
		
        address = *((in_addr_t *)hostinfo->h_addr_list[0]);
    }

	return address;
}

@interface AudioScrobblerClient (Private)
- (BOOL) connectToSocket:(in_addr_t)remoteAddress port:(in_port_t)port;
@end

@implementation AudioScrobblerClient

- (id) init
{
	if((self = [super init])) {
		_socket				= -1;
		_doPortStepping		= YES;
	}
	return self;
}

- (BOOL) connectToHost:(NSString *)hostname port:(in_port_t)port
{
	NSParameterAssert(nil != hostname);
	
	in_addr_t remoteAddress = addressForHost(hostname);
	
	if(INADDR_NONE != remoteAddress)
		return [self connectToSocket:remoteAddress port:port];
	
	return NO;
}

- (BOOL) isConnected
{
	return (-1 != _socket);
}

- (in_port_t) connectedPort
{
	return _port;
}

- (void) send:(NSString *)data
{	
	const char		*utf8data		= [data UTF8String];
	unsigned		len				= strlen(utf8data);	
	unsigned		bytesToSend		= len;
	unsigned		totalBytesSent	= 0;
	ssize_t			bytesSent		= 0;

	if(NO == [self isConnected]) {
		NSLog(@"AudioScrobblerClient error: Can't send data, client not connected");
		return;
	}
	
	while(totalBytesSent < bytesToSend && -1 != bytesSent) {
		bytesSent = send(_socket, utf8data + totalBytesSent, bytesToSend - totalBytesSent, 0);
		
		if(-1 == bytesSent || 0 == bytesSent)
			NSLog(@"AudioScrobblerClient error: Unable to send data through socket: %s", strerror(errno));
		
		totalBytesSent += bytesSent;
	}
}

- (NSString *) receive
{
	char		buffer			[ kBufferSize ];
	int			readSize		= kBufferSize - 1;
	ssize_t		bytesRead		= 0;
	BOOL		keepGoing		= YES;
	NSString	*result			= nil;

	if(NO == [self isConnected]) {
		NSLog(@"AudioScrobblerClient error: Can't receive data, client not connected");
		return nil;
	}
	
	do {
		bytesRead = recv(_socket, buffer, readSize, 0);
		if(-1 == bytesRead || 0 == bytesRead) {
			NSLog(@"AudioScrobblerClient error: Unable to receive data through socket: %s", strerror(errno));
			break;
		}
			
		if('\n' == buffer[bytesRead - 1]) {			
			--bytesRead;
			keepGoing = NO;
		}

		buffer[bytesRead]	= '\0';
		result				= [[NSString alloc] initWithUTF8String:buffer];
		
	} while(keepGoing);
	
	return [result autorelease];
}

- (void) shutdown
{
	int			result;
	char		buffer [ kBufferSize ];
	ssize_t		bytesRead;
	
	if(NO == [self isConnected]) {
		return;
	}
	
	result = shutdown(_socket, SHUT_WR);
	if(-1 == result)
		NSLog(@"AudioScrobblerClient error: Socket shutdown failed: %s", strerror(errno));

	for(;;) {
		bytesRead = recv(_socket, buffer, kBufferSize, 0);
		if(-1 == bytesRead)
			NSLog(@"AudioScrobblerClient error: Waiting for shutdown confirmation failed: %s", strerror(errno));
		
		if(0 != bytesRead) {
			NSString *received = [[NSString alloc] initWithBytes:buffer length:bytesRead encoding:NSUTF8StringEncoding];
			NSLog(@"Received unexpected bytes during shutdown: %@", received);
			[received release];
		}
		else
			break;
	}

	result = close(_socket);
	if(-1 == result)
		NSLog(@"Couldn't close socket (%s)", strerror(errno));
	
	_socket		= -1;
	_port		= 0;
}

@end

@implementation AudioScrobblerClient (Private)

- (BOOL) connectToSocket:(in_addr_t)remoteAddress port:(in_port_t)port
{
	NSParameterAssert(INADDR_NONE != remoteAddress);
	
	struct sockaddr_in		socketAddress;
	int						result;

	_socket = socket(AF_INET, SOCK_STREAM, 0);
	if(-1 == _socket) {
		NSLog(@"Unable to create socket (%s)", strerror(errno));
		return NO;
	}

	_port							= port;
	socketAddress.sin_family		= AF_INET;
	socketAddress.sin_addr.s_addr	= remoteAddress;
	socketAddress.sin_port			= htons(_port);

	result = connect(_socket, (const struct sockaddr *)&socketAddress, sizeof(struct sockaddr_in));

	// Don't check result yet
	if(_doPortStepping) {
		while(-1 == result && _port <= (port + kPortsToStep)) {
			socketAddress.sin_port = htons(++_port);
			result = connect(_socket, (const struct sockaddr *)&socketAddress, sizeof(struct sockaddr_in));
		}
	}

	// Don't log failures, because the client may not be running
	if(-1 == result) {
		close(_socket);
		
		_socket				= -1;
		_port				= 0;
		_doPortStepping		= NO;
		
		return NO;
	}
	
	return YES;
}

@end
