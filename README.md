AR系列的开篇。本系列打算由上而下的学习AR的各种实现方式和原理。会涉及到音视频、视频照片滤镜和OpenGLES相关的知识。

让我们来定义一个需求，AR识别固定标记，识别后根据识别标记的位置计算旋转、平移和缩放矩阵确定播放器视口位置和大小，支持播放网络视频。当然实现的方式有多种：

![效果图](https://upload-images.jianshu.io/upload_images/80684-40ef63ccd2348cd3.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

- 通过第三方 Vuforia可以实现AR识别功能，官方demo介绍了本地视频播放的方法，但是不支持流媒体播放。流媒体播放视频可以用AVPlayer加载URL，并添加AVPlayerItemOutput 为AVPlayerItem的output。调用下面的API获取视频帧缓存。

```
/*!
@abstract检索适合在指定的项目时间显示的图像，并将图像标记为已获取。
@discussion
完成后，客户端负责在返回的CVPixelBuffer上调用CVBufferRelease。
通常，您将调用此方法来响应CVDisplayLink回调或CADisplayLink委托调用，并且hasNewPixelBufferForItemTime：也返回YES。
从copyPixelBufferForItemTime：itemTimeForDisplay：中检索的缓冲区引用本身可能为NULL。 为NULL时表明该CMTime没有像素缓冲区需要显示。
 */
- (nullable CVPixelBufferRef)copyPixelBufferForItemTime:(CMTime)itemTime itemTimeForDisplay:(nullable CMTime *)outItemTimeForDisplay CF_RETURNS_RETAINED;
```

Vuforia 类似的详细实现之后专门开篇讨论。

- ARKit实现识别图片。这是iOS 11.3推出的新功能。具体API如下


```
/**
AR场景中要检测的图片
@discussion 如果设置detectionImages，ARKit将尝试检测指定的图像。当检测到图像时，
 会回调 - (nullable SCNNode *)renderer:(id <SCNSceneRenderer>)renderer nodeForAnchor:(ARAnchor *)anchor方法。anchor  是ARImageAnchor。
 */
@property (nonatomic, copy, nullable, readwrite) NSSet<ARReferenceImage *> *detectionImages API_AVAILABLE(ios(11.3));
```

本篇主要讨论ARKit实现方案。

#### 先看几个11.3 新特性
- iOS 11.3 新特性之一 ARPlaneDetectionVertical 这是一个NS_OPTIONS位移枚举。用于检测场景中的垂直平面。

- iOS 11.3 新特性之二: ARReferenceImage API_AVAILABLE(ios(11.3))
ARReferenceImage 是识别图像的模型类，提供了三个创建方法。init和new都设置为不可用。

```
// CGImageRef生成ARReferenceImage识别模型，注意physicalWidth的单位是：米 （meters）
- (instancetype)initWithCGImage:(CGImageRef)image orientation:(CGImagePropertyOrientation)orientation physicalWidth:(CGFloat)physicalWidth NS_SWIFT_NAME(init(_:orientation:physicalWidth:));
// 从CVPixelBufferRef生成ARReferenceImage识别模型
- (instancetype)initWithPixelBuffer:(CVPixelBufferRef)pixelBuffer orientation:(CGImagePropertyOrientation)orientation physicalWidth:(CGFloat)physicalWidth NS_SWIFT_NAME(init(_:orientation:physicalWidth:));

// 从指定的图片包里加载一套识别图，返回一个ARReferenceImage识别模型 的NSSet。
+ (nullable NSSet<ARReferenceImage *> *)referenceImagesInGroupNamed:(NSString *)name bundle:(nullable NSBundle *)bundle;

/** Unavailable */ 
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
```

- iOS 11.3 新特性之三: ARWorldTrackingConfiguration的新属性detectionImages 。把我们上面创建的ARReferenceImage识别模型组赋值给detectionImages。

```
@property (nonatomic, copy, nullable, readwrite) NSSet<ARReferenceImage *> *detectionImages API_AVAILABLE(ios(11.3));

- iOS 11.3 新特性之四: SCNMaterial对象的contents可以直接添加AVPlayer对象作为纹理源。（iOS 11.3之前可以添加SpriteKit scene add child SKVideoNode  (SKVideoNode may creat with AVPlayer)）
@property(nonatomic, retain, nullable) id contents;

   SCNMaterial *materialVideoFrame = [SCNMaterial material];
   materialVideoFrame.diffuse.contents = self.playerManger.player;
``` 

#### 根据上诉四条新功能，可以实现AR视频播放。下面上代码：

- 配置 ARWorldTrackingConfiguration 添加识别图， 并runWithConfiguration。


```
- (void)resetTracking
{
    /**
     ARSessionRunOptions 也是一个NS_OPTION。
     ARSessionRunOptionResetTracking 每次调用重新配置识别。
     ARSessionRunOptionRemoveExistingAnchors 重新配置时删除之前存在的Anchors
     
     如果不配置options:默认保留现有的Anchors
     */
    [self.sceneView.session runWithConfiguration:self.arConfig options:ARSessionRunOptionResetTracking | ARSessionRunOptionRemoveExistingAnchors];
}
```

```
- (ARWorldTrackingConfiguration *)arConfig
{
    if (!_arConfig) {
        _arConfig = [[ARWorldTrackingConfiguration alloc] init];

        //iOS 11.3 新特性之一: ARPlaneDetectionVertical API_AVAILABLE(ios(11.3)) = (1 << 1)
        /** Plane detection determines vertical planes in the scene. */

        if (@available(iOS 11.3, *)) {
// 由于我们识别的是图像平面，这里不设置其他平面的识别。
//            _arConfig.planeDetection = ARPlaneDetectionHorizontal | ARPlaneDetectionVertical;

            NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
            NSString *filePath = [resourcePath stringByAppendingPathComponent:@"L3DWY888_800x600@2x.jpg"];
            _deImage = [UIImage imageWithContentsOfFile:filePath];
            
            //iOS 11.3 新特性之二: ARReferenceImage API_AVAILABLE(ios(11.3))

            ARReferenceImage *referenceDetectedImg = [[ARReferenceImage alloc] initWithCGImage:_deImage.CGImage orientation:1 physicalWidth:0.1];
//  iOS 11.3 新特性之三: ARWorldTrackingConfiguration的新属性
            [_arConfig setDetectionImages:[NSSet setWithObject:referenceDetectedImg]];
        }
    }
    return _arConfig;
}
```

- 识别成功返回锚点，添加node，矩阵变换。

```
#pragma mark - ARSCNViewDelegate
// 重写以根据anchor创建添加到当前session中的node。识别水平垂直平面或图像返回的锚点。
- (SCNNode *)renderer:(id<SCNSceneRenderer>)renderer nodeForAnchor:(ARAnchor *)anchor {
    // 当返回ARImageAnchor时，说明识别到图片了。
    if (![anchor isMemberOfClass:[ARImageAnchor class]]) {
        return [SCNNode node];
    }
// 这里配置我们播放视频相关的node。
// 自定义SCNGeometry（SCNGeometrySource， SCNGeometryElement） 设置视频node
    DKVideoPlane *videoGeometry = [DKVideoPlane planeWithType:DKVideoPlaneHorizontal width:0.1 length:0.07];
    videoGeometry.materials = @[self.materials[DKARPlayerMaterialTypeVideo]];

    _videoNode = [SCNNode nodeWithGeometry:videoGeometry];
    //worldTransform 和 transform 的区别：worldTransform相对于根节点的旋转平移缩放矩阵，transform和position同时设置，共同作用与node的变换。
    SCNMatrix4 transM = SCNMatrix4FromMat4(anchor.transform);
    _videoNode.worldTransform = transM;
}

- (NSMutableArray<SCNMaterial *> *)materials
{
    if (!_materials) {
        _materials = [NSMutableArray array];
      
        SCNMaterial *materialVideoFrame = [SCNMaterial material];
        /**
         SKScene *ss = [SKScene sceneWithSize:CGSizeMake(100, 100)];
         SKVideoNode *vn = [SKVideoNode videoNodeWithAVPlayer:self.playerManger.player];
         [ss addChild:vn];
         materialVideoFrame.diffuse.contents = ss;
         */
        
        // iOS 11.3 新特性之四: SCNMaterial对象的contents可以直接添加AVPlayer对象作为纹理源。
        materialVideoFrame.diffuse.contents = self.playerManger.player;
        [_materials insertObject:materialVideoFrame atIndex:DKARPlayerMaterialTypeVideo];
    }
    return _materials;
}

```

- 加上简单的播放逻辑，点击播放暂停，快进快退seek

```
- (void)setupRecognizers {
    // Single tap will insert a new piece of geometry into the scene
    UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onPlayerVideo:)];
    tapGestureRecognizer.numberOfTapsRequired = 1;
    [self.sceneView addGestureRecognizer:tapGestureRecognizer];
    
    UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(panDirection:)];
    [panRecognizer setMaximumNumberOfTouches:1];
    [panRecognizer setDelaysTouchesBegan:YES];
    [panRecognizer setDelaysTouchesEnded:YES];
    [panRecognizer setCancelsTouchesInView:YES];
    [self.sceneView addGestureRecognizer:panRecognizer];
}

// 添加手势控制播放暂停
- (void)onPlayerVideo:(UITapGestureRecognizer *)sender {
    
    if (sender.state == UIGestureRecognizerStateEnded) {
        
        if ([self.playerManger getStatus] == PLAYING) {
            [self pause];
        }else{
            [self play];
        }
    }
}
// 添加手势控制播放进度
- (void)panDirection:(UIPanGestureRecognizer *)pan {
    CGPoint veloctyPoint = [pan velocityInView:self.sceneView];
    
    // 判断是垂直移动还是水平移动
    switch (pan.state) {
        case UIGestureRecognizerStateBegan: { // 开始移动
            // 使用绝对值来判断移动的方向
            CGFloat x = fabs(veloctyPoint.x);
            CGFloat y = fabs(veloctyPoint.y);
            if (x > y) { // 水平移动
                self.panDirection = DKARPanDirectionHorizontalMoved;
                CMTime time       = self.playerManger.player.currentTime;
                self.sumTime      = time.value/time.timescale;
            }
            break;
        }
        case UIGestureRecognizerStateChanged: {
            switch (self.panDirection) {
                case DKARPanDirectionHorizontalMoved:{
                    [self horizontalMoved:veloctyPoint.x];
                    break;
                }
                default:
                    break;
            }
            break;
        }
        case UIGestureRecognizerStateEnded: {
            switch (self.panDirection) {
                case DKARPanDirectionHorizontalMoved:{
                    [self.playerManger seekTo:self.sumTime];
                    self.sumTime = 0;
                    break;
                }
                default:
                    break;
            }
            break;
        }
        default:
            break;
    }
}
```
识别标记图：
```
// 要识别的图片name。也可以定义图片包。
#define TrackImage @"aaa.jpg"
```

- 基本完成开篇提出的需求。
#### 开发过程中需要注意的点：
- 需要对纹理坐标系和顶点坐标系有清晰的理解。
- 注意node的SCNGeometry绘制方向。
#### 待完善的地方：
- hitTest: 不能击中已添加的ARImageAnchor，识别平面添加的anchor可以正确击中。接下来打算自定义点击区域计算方法。

- SCNText没有正确显示到scene中

有不明白的欢迎讨论。[博客地址](https://www.jianshu.com/u/0b058f2513f1)


