//
//  PTZColorTempValueTransformer.m
//  PTZ Camera Sim
//
//  Created by Lee Ann Rucker on 1/9/23.
//

#import "PTZColorTempValueTransformer.h"

@implementation PTZColorTempValueTransformer

+ (Class)transformedValueClass
{
   return [NSNumber class];
}

+ (BOOL)allowsReverseTransformation
{
   return YES;
}

- (id)transformedValue:(id)beforeObject
{
    return @(([beforeObject intValue] * 100) + 2500);
}

- (id)reverseTransformedValue:(id)beforeObject
{
    return @(([beforeObject intValue] - 2500) / 100);
}
 

@end // PLScaleByFour
