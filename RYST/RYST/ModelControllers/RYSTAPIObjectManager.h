//
//  RYSTAPIObjectManager.h
//  RYST
//
//  Created by Richie Davis on 4/15/15.
//  Copyright (c) 2015 Vissix. All rights reserved.
//

#import <RestKit/RestKit.h>

@interface RYSTAPIObjectManager : RKObjectManager

+ (instancetype)objectManager;

- (BOOL)isReachable;

@end

