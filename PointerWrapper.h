//
//  PointerWrapper.h
//  Play
//
//  Created by Jan on 16.04.10.
//  Copyright 2010 sbooth.org. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#include "sqlite3.h"

@interface PointerWrapper : NSObject {
	sqlite3_stmt *	statementPointer;
}

+ (PointerWrapper *) pointerWrapperWithPointer: (sqlite3_stmt *) pointer;

- (PointerWrapper *) initWithPointer: (sqlite3_stmt *) pointer;

@property sqlite3_stmt *statementPointer;

@end
