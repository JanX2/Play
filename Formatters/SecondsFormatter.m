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

#import "SecondsFormatter.h"

#define TWO_GIGASECONDS_IS_ENOUGH 1 // 2 Gs is about 68 years.
#if TWO_GIGASECONDS_IS_ENOUGH
typedef int32_t sec_t; // Type used internally for time values (mostly in seconds).
#define PRIsec PRIi32
#define SEC_MAX INT32_MAX
#define scanSec scanInt
#else
typedef NSInteger sec_t;
#define PRIsec "zd"
#define SEC_MAX NSIntegerMax
#define scanSec scanInteger
#endif

@implementation SecondsFormatter

- (NSString *) stringForObjectValue:(id)object
{
	if (nil == object || NO == [object isKindOfClass:[NSNumber class]]) {
		// Docs state: “Returns nil if object is not of the correct class.”
		return nil;
	}
	
	NSTimeInterval timeInterval = [object doubleValue];
	
	return [self stringForTimeInterval:timeInterval];
}

- (NSString * _Nullable)stringForTimeInterval:(NSTimeInterval)timeInterval;
{
	if (isnan(timeInterval)) { return @"NaN"; }
	if (isinf(timeInterval)) { return @"Inf"; }
	
	BOOL isNegative = signbit(timeInterval);
	
	sec_t totalSeconds = (sec_t)(isNegative ? -timeInterval : timeInterval);
	
	sec_t seconds	= totalSeconds % 60;
	sec_t minutes	= totalSeconds / 60;
	sec_t hours = 0;
	sec_t days = 0;
	
	while (60 <= minutes) {
		minutes -= 60;
		++hours;
	}
	
	while (24 <= hours) {
		hours -= 24;
		++days;
	}
	
	NSString *result = nil;
	
	const char *signPrefix = isNegative ? "-" : "";
	
	if (0 < days) {
		result = [NSString stringWithFormat:@"%s" "%" PRIsec ":" "%02" PRIsec ":" "%02" PRIsec ":" "%02" PRIsec "", signPrefix, days, hours, minutes, seconds];
	}
	else if (0 < hours) {
		result = [NSString stringWithFormat:@"%s" "%" PRIsec ":" "%02" PRIsec ":" "%02" PRIsec "", signPrefix, hours, minutes, seconds];
	}
	else if (0 < minutes) {
		result = [NSString stringWithFormat:@"%s" "%" PRIsec ":" "%02" PRIsec "", signPrefix, minutes, seconds];
	}
	else {
		result = [NSString stringWithFormat:@"%s" "0:" "%02" PRIsec "", signPrefix, seconds];
	}
	
	return result;
}

- (BOOL)getObjectValue:(out id  _Nullable __autoreleasing *)object
			 forString:(NSString *)string
	  errorDescription:(out NSString * _Nullable __autoreleasing *)error
{
	// In the previous implementation,
	// all types were incorrectly treated indentically.
	// This made the code much simpler,
	// but the added complexity is needed to support both negative and large values.
	
	NSScanner *scanner = [NSScanner scannerWithString:string];
	
	BOOL malformed = NO;
	
	//const int segmentCount = 4;
	#define segmentCount 4
	const int lastSegment = segmentCount - 1;
	sec_t segments[segmentCount] = {-1, -1, -1, -1};
	int lastScannedSegment = -1;
	
	BOOL isNegative = NO;
	
	if ([scanner isAtEnd] == NO) {
		isNegative = [scanner scanString:@"-" intoString:NULL];
		
		int segmentIndex = 0;
		
		while ([scanner isAtEnd] == NO) {
			// Grab a value
			if ([scanner scanSec:&(segments[segmentIndex])] == NO) {
				segments[segmentIndex] = -1;
				malformed = YES;
				break;
			}
			
			if (segmentIndex == lastSegment) {
				break;
			}
			
			// Grab the separator, if present
			if ([scanner scanString:@":" intoString:NULL] == NO) {
				break;
			}
			
			segmentIndex += 1;
		}
		
		lastScannedSegment = segmentIndex;
	}
	
	if ([scanner isAtEnd] == NO) {
		malformed = YES;
	}
	
	sec_t seconds = 0;
	
	if (malformed == NO) {
		// `segments` entries need to be mapped to the correct unit type.
		// The position of each type depends on the number of scanned segments.
		
		//const int typeCount = segmentCount;
		#define typeCount segmentCount

		typedef enum : int {
			DAYS = 0, HOURS = 1, MINUTES = 2, SECONDS = 3,
		} SegmentType;
		
		const int segmentIndexes[segmentCount][typeCount] = {
			{ -1, -1, -1,  0 },
			{ -1, -1,  0,  1 },
			{ -1,  0,  1,  2 },
			{  0,  1,  2,  3 },
		};
		
#define HAS_SEGMENT(segmentType) \
(segmentIndexes[lastScannedSegment][(segmentType)] >= 0)
		
		typedef struct {
			sec_t max;
			sec_t scaleFactor;
		} SegmentMetadata;
		
		const SegmentMetadata segmentMetadata[segmentCount] = {
			{.max = SEC_MAX,	.scaleFactor = 24},
			{.max = 24,			.scaleFactor = 60},
			{.max = 60,			.scaleFactor = 60},
			{.max = 60,			.scaleFactor =  1},
		};
		
		for (SegmentType segmentType = DAYS; segmentType < segmentCount; segmentType += 1) {
			if (!HAS_SEGMENT(segmentType)) {
				if (segmentType == SECONDS) {
					// Must have SECONDS.
					malformed = YES;
					break;
				}
				else {
					continue;
				}
			}
			
			const int index = segmentIndexes[lastScannedSegment][segmentType];
			
			const SegmentMetadata metadata = segmentMetadata[segmentType];
			
			if ((segments[index] >= 0) && (segments[index] < metadata.max)) {
				seconds += segments[index];
				seconds *= metadata.scaleFactor;
			}
			else {
				malformed = YES;
				break;
			}
		}
		
		seconds *= (isNegative ? -1 : 1);
	}
	
	const BOOL result = (malformed == NO);
	
	if (result && NULL != object) {
		NSTimeInterval timeInterval = (NSTimeInterval)seconds;
		// NOTE: The floating point standard has support for negative zero.
		// We use that to represent the parsing result without information loss.
		if (isNegative && (timeInterval == 0.0)) { timeInterval = -0.0; }
		*object = @(timeInterval);
	}
	else if (NULL != error) {
		*error = @"Couldn't convert value to seconds";
	}
	
	return result;
}

- (NSAttributedString *) attributedStringForObjectValue:(id)object withDefaultAttributes:(NSDictionary *)attributes
{
	NSString *stringValue = [self stringForObjectValue:object];
	if(nil == stringValue)
		return nil;
	
	NSAttributedString *result = [[NSAttributedString alloc] initWithString:stringValue attributes:attributes];
	return result;
}

@end
