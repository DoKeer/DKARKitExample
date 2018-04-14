//
//  DKVideoPlane.m
//  DKARKitExample
//
//  Created by Keer_LGQ on 2018/4/13.
//  Copyright © 2018年 DK. All rights reserved.
//

#import "DKVideoPlane.h"

@implementation DKVideoPlane
+ (instancetype)planeWithType:(DKVideoPlaneOrientation)orientation width:(CGFloat)width length:(CGFloat)length
{
    int uvCount ;
    
    SCNGeometrySource *vertexSource;
    SCNGeometrySource *normalSource;
    SCNGeometrySource *uvSource;
    SCNGeometryElement *element;
    
    if (orientation == DKVideoPlaneVertical) {
        uvCount = 4;
        SCNVector3 vertices[] = {
            
            SCNVector3Make(-1 * width,-1 * length, 0),
            SCNVector3Make(1 * width, -1 * length, 0),
            SCNVector3Make(-1* width, 1 * length, 0),
            SCNVector3Make(1 * width, 1 * length, 0)
        };
        
        SCNVector3 normals[] = {

            SCNVector3Make(0, 0, 1),
            SCNVector3Make(0, 0, 1),
            SCNVector3Make(0, 0, 1),
            SCNVector3Make(0, 0, 1),
        };
        
        CGPoint textureCoordinates[] = {
            CGPointMake(0, 0),
            CGPointMake(1, 0),
            CGPointMake(0, 1),
            CGPointMake(1, 1),
        };
        
        
        vertexSource = [SCNGeometrySource geometrySourceWithVertices:vertices count:uvCount];
        
        normalSource = [SCNGeometrySource geometrySourceWithNormals:normals count:uvCount];
        
        uvSource = [SCNGeometrySource geometrySourceWithTextureCoordinates:textureCoordinates count:uvCount];
        
        uint8_t indices[] = {
            1,2,0,3
        };
        
        NSData *indicesData = [NSData dataWithBytes:indices length:sizeof(indices)];
        element = [SCNGeometryElement geometryElementWithData:indicesData primitiveType:SCNGeometryPrimitiveTypeTriangleStrip primitiveCount:uvCount bytesPerIndex:sizeof(uint8_t)];

    }
    else {
        uvCount = 6;
        SCNVector3 vertices[] = {

            SCNVector3Make( -0.5 * width, 0, 0.5 * length),
            SCNVector3Make( -0.5 * width, 0, -0.5 * length),
            SCNVector3Make( 0.5 * width, 0, -0.5 * length),
            SCNVector3Make( -0.5 * width, 0, 0.5 * length),
            SCNVector3Make( 0.5 * width, 0, -0.5 * length),
            SCNVector3Make( 0.5 * width, 0, 0.5 * length),
        };
        
        SCNVector3 normals[] = {
            SCNVector3Make(0, 1, 0),
            SCNVector3Make(0, 1, 0),
            SCNVector3Make(0, 1, 0),
            SCNVector3Make(0, 1, 0),
            SCNVector3Make(0, 1, 0),
            SCNVector3Make(0, 1, 0),
        };
        
        CGPoint textureCoordinates[] = {
            CGPointMake(0, 1),
            CGPointMake(0, 0),
            CGPointMake(1, 0),
            CGPointMake(0, 1),
            CGPointMake(1, 0),
            CGPointMake(1, 1),
        };
        
        NSInteger indices[] = {
            0,1,2,3,4,5
        };

        vertexSource = [SCNGeometrySource geometrySourceWithVertices:vertices count:uvCount];
        
        normalSource = [SCNGeometrySource geometrySourceWithNormals:normals count:uvCount];
        
        uvSource = [SCNGeometrySource geometrySourceWithTextureCoordinates:textureCoordinates count:uvCount];
        
        NSData *indicesData = [NSData dataWithBytes:indices length:sizeof(indices)];
        element = [SCNGeometryElement geometryElementWithData:indicesData primitiveType:SCNGeometryPrimitiveTypeTriangleStrip primitiveCount:uvCount bytesPerIndex:sizeof(NSInteger)];

    }

    //
    DKVideoPlane *videoGeometry = [DKVideoPlane geometryWithSources:@[vertexSource, uvSource, normalSource] elements:@[element]];
    
    
    return videoGeometry;
}

@end
