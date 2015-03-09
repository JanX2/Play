//
//  NSPathControl+PasteboardSupport.m
//  Play
//
//  Created by Jan on 09.03.15.
//  Copyright (c) 2015 sbooth.org. All rights reserved.
//

#import "NSPathControl+PasteboardSupport.h"

@implementation NSPathControl (PasteboardSupport)

- (IBAction)copy:(id)sender
{
	NSString *path = self.URL.path;
	NSPasteboard *pasteBoard = [NSPasteboard generalPasteboard];
	[pasteBoard declareTypes:@[NSPasteboardTypeString]
					   owner:nil];
	[pasteBoard setString:path
				  forType:NSPasteboardTypeString];
}

@end
