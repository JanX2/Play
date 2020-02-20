/*
 *  $Id$
 *
 *  Copyright (C) 2005 - 2009 Stephen F. Booth <me@sbooth.org>
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

#import "HotKeyPreferencesController.h"
#import "PlayApplicationDelegate.h"


@implementation HotKeyPreferencesController {
	SRShortcutValidator *_validator;
}


#pragma mark SRRecorderControlDelegate

- (BOOL)shortcutRecorder:(SRRecorderControl *)aRecorder
	   canRecordShortcut:(NSDictionary *)aShortcut
{
	__autoreleasing NSError *error = nil;
	
	BOOL isTaken =
	[_validator isKeyCode:[aShortcut[SRShortcutKeyKeyCode] unsignedShortValue]
			andFlagsTaken:[aShortcut[SRShortcutKeyModifierFlags] unsignedIntegerValue]
					error:&error];
	
	if (isTaken) {
		NSBeep();
		
		NSWindow *window = aRecorder.window;
		[window presentError:error
			  modalForWindow:window
					delegate:nil
		  didPresentSelector:NULL
				 contextInfo:NULL];
	}
	
	return !isTaken;
}

- (BOOL)shortcutRecorder:(SRRecorderControl *)aRecorder shouldUnconditionallyAllowModifierFlags:(NSEventModifierFlags)aModifierFlags forKeyCode:(unsigned short)aKeyCode
{
	if ((aModifierFlags & aRecorder.requiredModifierFlags) != aRecorder.requiredModifierFlags) {
		return NO;
	}
	
	if ((aModifierFlags & aRecorder.allowedModifierFlags) != aModifierFlags) {
		return NO;
	}
	
	switch (aKeyCode) {
		case kVK_F1:
		case kVK_F2:
		case kVK_F3:
		case kVK_F4:
		case kVK_F5:
		case kVK_F6:
		case kVK_F7:
		case kVK_F8:
		case kVK_F9:
		case kVK_F10:
		case kVK_F11:
		case kVK_F12:
		case kVK_F13:
		case kVK_F14:
		case kVK_F15:
		case kVK_F16:
		case kVK_F17:
		case kVK_F18:
		case kVK_F19:
		case kVK_F20:
			return YES;
		default:
			return NO;
	}
}


#pragma mark SRShortcutValidatorDelegate

- (BOOL)shortcutValidator:(SRShortcutValidator *)aValidator
				isKeyCode:(unsigned short)aKeyCode
			andFlagsTaken:(NSEventModifierFlags)aFlags
				   reason:(NSString **)outReason
{
#define IS_TAKEN(aRecorder) (recorder != (aRecorder) && SRShortcutEqualToShortcut(shortcut, [(aRecorder) objectValue]))
	
	SRRecorderControl *recorder = (SRRecorderControl *)self.window.firstResponder;
	
	if (![recorder isKindOfClass:[SRRecorderControl class]]) {
		return NO;
	}
	
	NSDictionary *shortcut = SRShortcutWithCocoaModifierFlagsAndKeyCode(aFlags, aKeyCode);
	
	if (IS_TAKEN(_playPauseShortcutRecorder) ||
		IS_TAKEN(_previousStreamShortcutRecorder) ||
		IS_TAKEN(_nextStreamShortcutRecorder)
		) {
		*outReason = NSLocalizedString(@"The shortcut is already used. To use your shortcut, first remove or change the other shortcut.", @"shortcut already in use error message");
		return YES;
	}
	else {
		return NO;
	}
	
#undef IS_TAKEN
}


- (BOOL)shortcutValidatorShouldCheckSystemShortcuts:(SRShortcutValidator *)aValidator
{
	return YES;
}

- (BOOL)shortcutValidatorShouldCheckMenu:(SRShortcutValidator *)aValidator
{
	return YES;
}


#pragma mark NSObject

- (id) init
{
	if((self = [super initWithWindowNibName:@"HotKeyPreferences"])) {
	}
	
	return self;
}

- (void)awakeFromNib
{
	[super awakeFromNib];
	
	[self initKeyBindingsController];
}

- (void)initKeyBindingsController
{
	[self prepareShortcutRecorder:_playPauseShortcutRecorder
						   forKey:@"playPauseHotKey"];
	
	[self prepareShortcutRecorder:_previousStreamShortcutRecorder
						   forKey:@"playNextStreamHotKey"];
	
	[self prepareShortcutRecorder:_nextStreamShortcutRecorder
						   forKey:@"playPreviousStreamHotKey"];
	
	_validator = [[SRShortcutValidator alloc] initWithDelegate:self];
}

- (void)prepareShortcutRecorder:(SRRecorderControl *)shortcutRecorder
						 forKey:(NSString *)key;
{
	NSUserDefaultsController *defaults = [NSUserDefaultsController sharedUserDefaultsController];
	
	NSString *keyPath = [NSString stringWithFormat:@"values.%@", key];
	
	[shortcutRecorder bind:NSValueBinding
				  toObject:defaults
			   withKeyPath:keyPath
				   options:nil];
}

@end
