//
//  CTGradient.h
//
//  Created by Chad Weider on 2/14/07.
//  Writtin by Chad Weider.
//
//  Released into public domain on 4/10/08.
//  
//  Version: 1.8

#import <Cocoa/Cocoa.h>

typedef struct _CTGradientElement 
	{
	CGFloat red, green, blue, alpha;
	CGFloat position;
	
	struct _CTGradientElement *nextElement;
	} CTGradientElement;

typedef enum  _CTBlendingMode
	{
	CTLinearBlendingMode,
	CTChromaticBlendingMode,
	CTInverseChromaticBlendingMode
	} CTGradientBlendingMode;


@interface CTGradient : NSObject <NSCopying, NSCoding>
	{
	CTGradientElement* elementList;
	CTGradientBlendingMode blendingMode;
	
	CGFunctionRef gradientFunction;
	}

+ (CTGradient *)gradientWithBeginningColor:(NSColor *)begin endingColor:(NSColor *)end;

+ (CTGradient *)aquaSelectedGradient;
+ (CTGradient *)aquaNormalGradient;
+ (CTGradient *)aquaPressedGradient;

+ (CTGradient *)unifiedSelectedGradient;
+ (CTGradient *)unifiedNormalGradient;
+ (CTGradient *)unifiedPressedGradient;
+ (CTGradient *)unifiedDarkGradient;

+ (CTGradient *)sourceListSelectedGradient;
+ (CTGradient *)sourceListUnselectedGradient;

+ (CTGradient *)rainbowGradient;
+ (CTGradient *)hydrogenSpectrumGradient;

- (CTGradient *)gradientWithAlphaComponent:(CGFloat)alpha;

- (CTGradient *)addColorStop:(NSColor *)color atPosition:(CGFloat)position;	//positions given relative to [0,1]
- (CTGradient *)removeColorStopAtIndex:(NSUInteger)thisIndex;
- (CTGradient *)removeColorStopAtPosition:(CGFloat)position;

- (CTGradientBlendingMode)blendingMode;
- (NSColor *)colorStopAtIndex:(NSUInteger)thisIndex;
- (NSColor *)colorAtPosition:(CGFloat)position;


- (void)drawSwatchInRect:(NSRect)rect;
- (void)fillRect:(NSRect)rect angle:(CGFloat)angle;					// fills rect with axial gradient
																	// angle in degrees
- (void)radialFillRect:(NSRect)rect;								// fills rect with radial gradient
																	// gradient from center outwards
- (void)fillBezierPath:(NSBezierPath *)path angle:(CGFloat)angle;
- (void)radialFillBezierPath:(NSBezierPath *)path;

@end
