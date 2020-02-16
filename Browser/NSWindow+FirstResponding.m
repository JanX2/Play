//
//  NSWindow+FirstResponding.m
//  Play
//
//  Created by Jan on 16.02.20.
//  Copyright © 2020 sbooth.org. All rights reserved.
//

#import "NSWindow+FirstResponding.h"

@implementation NSDrawerWindow (FirstResponding)

- (void)_setFirstResponder:(NSResponder *)responder
{
	if (![responder isKindOfClass:NSView.class] || [(NSView *)responder window] == self) {
		[super _setFirstResponder:responder];
	}
}

@end
