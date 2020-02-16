//
//  NSWindow+FirstResponding.h
//  Play
//
//  Created by Jan on 16.02.20.
//  Copyright © 2020 sbooth.org. All rights reserved.
//  Based on https://forums.developer.apple.com/thread/49052#146429
//

#import <Cocoa/Cocoa.h>

@interface NSWindow (FirstResponding)
- (void)_setFirstResponder:(NSResponder *)responder;
@end

@interface NSDrawerWindow : NSWindow
@end
