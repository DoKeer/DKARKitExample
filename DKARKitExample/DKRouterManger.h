//
//  DKRouterManger.h
//  DKShortVideo
//
//  Created by Keer_LGQ on 2018/3/30.
//  Copyright © 2018年 DK. All rights reserved.
//

#import <Foundation/Foundation.h>

@class DKRootViewController;

@interface DKRouterManger : NSObject
@property (nonatomic, strong) DKRootViewController * rootViewController;

+ (instancetype)shareInstance;

- (void)onARVideoView:(BOOL)isShow;

@end
