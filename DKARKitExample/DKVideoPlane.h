//
//  DKVideoPlane.h
//  DKARKitExample
//
//  Created by Keer_LGQ on 2018/4/13.
//  Copyright © 2018年 DK. All rights reserved.
//

#import <SceneKit/SceneKit.h>
typedef NS_ENUM(NSInteger,DKVideoPlaneOrientation)
{
    DKVideoPlaneVertical = 0,
    DKVideoPlaneHorizontal
};

@interface DKVideoPlane : SCNGeometry
+ (instancetype)planeWithType:(DKVideoPlaneOrientation)orientation width:(CGFloat)width length:(CGFloat)length;
@end
