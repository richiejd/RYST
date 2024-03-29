//
//  RYSTAPIResult.h
//  RYST
//
//  Created by Richie Davis on 4/15/15.
//  Copyright (c) 2015 Vissix. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <RestKit/RestKit.h>

@class RKObjectMapping;

@protocol RYSTAPIResult <NSObject>

+ (RKObjectMapping *)mapping;

@end
