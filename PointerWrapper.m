//
//  PointerWrapper.m
//  Play
//
//  Created by Jan on 16.04.10.
//  Copyright 2010 sbooth.org. All rights reserved.
//

#import "PointerWrapper.h"


@implementation PointerWrapper

+ (PointerWrapper *) pointerWrapperWithPointer: (sqlite3_stmt *) pointer
{
    return [[[PointerWrapper alloc] initWithPointer:pointer] autorelease];
}

- (PointerWrapper *) initWithPointer: (sqlite3_stmt *) pointer
{	
	if ( (self = [super init]) ) {
		statementPointer = pointer;
	}
	return self;
}

@synthesize statementPointer;

@end
