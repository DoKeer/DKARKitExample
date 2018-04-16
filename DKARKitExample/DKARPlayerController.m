//
//  ViewController.m
//  DKARKitExample
//
//  Created by Keer_LGQ on 2018/4/12.
//  Copyright © 2018年 DK. All rights reserved.
//

#import "DKARPlayerController.h"
#import "DKVideoPlayerManger.h"
#import "DKVideoPlane.h"

typedef NS_ENUM(NSInteger,DKARPlayerMaterialType)
{
    DKARPlayerMaterialTypeBackground = 0,
    DKARPlayerMaterialTypeVideo,
    DKARPlayerMaterialTypePlay,
    DKARPlayerMaterialTypeText
};

typedef NS_ENUM(NSInteger, DKARPanDirection){
    DKARPanDirectionHorizontalMoved, // 横向移动
    DKARPanDirectionVerticalMoved    // 纵向移动
};


@interface DKARPlayerController () <ARSCNViewDelegate, DKVideoPlayerDelegate ,SCNSceneRendererDelegate>
{
    dispatch_semaphore_t _frameRenderingSemaphore;
    BOOL _shouldPlay;
}
/* ARKit相关配置 */
@property (nonatomic, strong) ARSCNView *sceneView;
@property (nonatomic, strong) ARWorldTrackingConfiguration *arConfig;
@property (nonatomic, strong) UIImage *deImage;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, SCNNode *> *planes;
@property (nonatomic ,strong) DKVideoPlayerManger *playerManger;
@property (nonatomic, strong) NSMutableArray<SCNMaterial *> *materials;
@property (nonatomic ,strong) SCNNode *videoNode;
@property (nonatomic ,strong) SCNNode *btnPlayNodel;
@property (nonatomic ,strong) SCNNode *textNode;

@property (nonatomic ,copy) NSString *planText;

/* AVplayer相关配置 */
@property (nonatomic, assign) DKARPanDirection panDirection;
@property (nonatomic, assign) CGFloat sumTime;
@end

    
@implementation DKARPlayerController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.view addSubview:self.sceneView];
    // Set the view's delegate
    self.sceneView.delegate = self;
    
    // Show statistics such as fps and timing information
    self.sceneView.showsStatistics = YES;
    
    self.planes = [NSMutableDictionary dictionary];
    _frameRenderingSemaphore = dispatch_semaphore_create(1);

    [self setupRecognizers];
    
    UIButton *btnBack = [UIButton buttonWithType:UIButtonTypeCustom];
    [btnBack addTarget:self action:@selector(onCloseView:) forControlEvents:UIControlEventTouchUpInside];
    [btnBack setBackgroundColor:[UIColor redColor]];
    [btnBack setTitle:@"返回" forState:UIControlStateNormal];
    [btnBack setFrame:CGRectMake(10, 30, 60, 30)];
    [self.view addSubview:btnBack];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    BOOL isNet = YES;
    NSString *netUrl = isNet?@"http://devimages.apple.com.edgekey.net/streaming/examples/bipbop_4x3/gear2/prog_index.m3u8":@"0001.mp4";
    [self.playerManger loadMedia:netUrl playImmediately:NO playerType:PLAYER_TYPE_ON_PIXELBUFFER];
    
    [self resetTracking];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [_playerManger unload];
    [self resetTracking];
    // Pause the view's session
    [self.sceneView.session pause];
}

#pragma mark config session

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


- (void)resetTracking
{
    for (NSUUID *planeId in self.planes) {
        [self.planes[planeId] removeFromParentNode];
    }

    /**
     ARSessionRunOptions 也是一个NS_OPTION。
     ARSessionRunOptionResetTracking 每次调用重新配置识别。
     ARSessionRunOptionRemoveExistingAnchors 重新配置时删除之前存在的Anchors
     
     如果不配置options:默认保留现有的Anchors
     */
    [self.sceneView.session runWithConfiguration:self.arConfig options:ARSessionRunOptionResetTracking | ARSessionRunOptionRemoveExistingAnchors];
}

- (void)resetNodeMaterial
{
    if (!self.videoNode) {
        return;
    }
    
    self.videoNode.geometry.materials = @[self.materials[DKARPlayerMaterialTypeBackground]];
    [self.videoNode addChildNode:self.btnPlayNodel];
}

#pragma mark control
- (void)play
{
    _shouldPlay = YES;
    [self.playerManger playPosition:0];
    [self.btnPlayNodel removeFromParentNode];
    self.videoNode.geometry.materials = @[self.materials[DKARPlayerMaterialTypeVideo]];
    
}

- (void)pause
{
    _shouldPlay = NO;
    [self.playerManger pause];
    [self resetNodeMaterial];
}

- (void)onCloseView:(UIButton *)btnBack
{
    [[DKRouterManger shareInstance] onARVideoView:NO];
}

#pragma mark - UIPanGestureRecognizer
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

- (void)onPlayerVideo:(UITapGestureRecognizer *)sender {
    
    
    if (sender.state == UIGestureRecognizerStateEnded) {
        
        if ([self.playerManger getStatus] == PLAYING) {
            [self pause];
        }else{
            [self play];
        }
    }
    
    return;
    /**
     // Take the screen space tap coordinates and pass them to the hitTest method on the ARSCNView instance
     CGPoint tapPoint = [sender locationInView:self.sceneView];
     
     NSLog(@"tapPoint ==== x %f, y %f",tapPoint.x,tapPoint.y);
     
     NSArray<ARHitTestResult *> *result = [self.sceneView hitTest:tapPoint types:ARHitTestResultTypeEstimatedHorizontalPlane |ARHitTestResultTypeEstimatedVerticalPlane|ARHitTestResultTypeExistingPlane];
     
     // If the intersection ray passes through any plane geometry they will be returned, with the planes
     // ordered by distance from the camera
     if (result.count == 0) {
     NSLog(@"没点中我....... ");
     return;
     }
     
     // If there are multiple hits, just pick the closest plane
     [result enumerateObjectsUsingBlock:^(ARHitTestResult * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
     
     NSLog(@"obj.anchor.identifier = %@ \nself.planes = %@",obj.anchor.identifier,self.planes);
     
     
     if ([self.planes objectForKey:obj.anchor.identifier] != nil) {
     if ([self.playerManger getStatus] == PLAYING) {
     [self pause];
     }else{
     [self play];
     }
     }
     }];
     
     */

}

#pragma mark config lazy
- (ARSCNView *)sceneView
{
    if (!_sceneView) {
        _sceneView = [[ARSCNView alloc] initWithFrame:self.view.bounds];
        // 显示fps等信息
        _sceneView.showsStatistics = YES;
        // set up delegate
        _sceneView.delegate = self;
        
        // config camera
        _sceneView.pointOfView.camera.wantsHDR = YES;
        _sceneView.pointOfView.camera.exposureOffset = -1;
        _sceneView.pointOfView.camera.minimumExposure = -1;
        _sceneView.pointOfView.camera.maximumExposure = 3;
        _sceneView.automaticallyUpdatesLighting = NO;
        
        // 添加播放进度node
        SCNText *text = [SCNText textWithString:@"等待播放" extrusionDepth:5];
        text.firstMaterial.diffuse.contents = [UIColor blueColor];
        text.containerFrame = CGRectMake(10, 10, 100, 100);
        text.font = [UIFont systemFontOfSize:120];
        _textNode = [SCNNode nodeWithGeometry:text];
        _textNode.position = SCNVector3Make(0, 0.1, -1);
        _textNode.scale = SCNVector3Make(0.5, 0.5, 0.5);
        [_sceneView.scene.rootNode addChildNode:_textNode];
    }
    return _sceneView;
}

- (ARWorldTrackingConfiguration *)arConfig
{
    if (!_arConfig) {
        _arConfig = [[ARWorldTrackingConfiguration alloc] init];

        //iOS 11.3 新特性之一: ARPlaneDetectionVertical API_AVAILABLE(ios(11.3)) = (1 << 1)
        /** Plane detection determines vertical planes in the scene. */

        if (@available(iOS 11.3, *)) {
//            _arConfig.planeDetection = ARPlaneDetectionHorizontal | ARPlaneDetectionVertical;

            NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
            NSString *filePath = [resourcePath stringByAppendingPathComponent:TrackImage];
            _deImage = [UIImage imageWithContentsOfFile:filePath];
            
            //iOS 11.3 新特性之二: ARReferenceImage API_AVAILABLE(ios(11.3))

            ARReferenceImage *referenceDetectedImg = [[ARReferenceImage alloc] initWithCGImage:_deImage.CGImage orientation:1 physicalWidth:0.1];
            [_arConfig setDetectionImages:[NSSet setWithObject:referenceDetectedImg]];
        }
    }
    return _arConfig;
}

- (DKVideoPlayerManger *)playerManger
{
    if (!_playerManger) {
        _playerManger = [[DKVideoPlayerManger alloc] initWithDelegate:self callbackQueue:dispatch_get_global_queue(0, 0)];

    }
    return _playerManger;
}

- (NSMutableArray<SCNMaterial *> *)materials
{
    if (!_materials) {
        _materials = [NSMutableArray array];
        
        SCNMaterial *materialBackground = [SCNMaterial material];
        materialBackground.diffuse.contents = _deImage;
        SCNMaterial *materialVideoFrame = [SCNMaterial material];
        
        /**
         SKScene *ss = [SKScene sceneWithSize:CGSizeMake(100, 100)];
         SKVideoNode *vn = [SKVideoNode videoNodeWithAVPlayer:self.playerManger.player];
         [ss addChild:vn];
         materialVideoFrame.diffuse.contents = ss;
         */
        
        // iOS 11.3 新特性之四: SCNMaterial对象的contents可以直接添加AVPlayer对象作为纹理源。
        materialVideoFrame.diffuse.contents = self.playerManger.player;
        SCNMaterial *materialPlay = [SCNMaterial material];
        materialPlay.diffuse.contents = [UIImage imageNamed:@"icon_play"];
        SCNMaterial *materialText = [SCNMaterial material];
        materialText.diffuse.contents = @"等待播放";
        
        [_materials insertObject:materialBackground atIndex:DKARPlayerMaterialTypeBackground];
        [_materials insertObject:materialVideoFrame atIndex:DKARPlayerMaterialTypeVideo];
        [_materials insertObject:materialPlay atIndex:DKARPlayerMaterialTypePlay];
        [_materials insertObject:materialText atIndex:DKARPlayerMaterialTypeText];

    }
    return _materials;
}

#pragma mark - ARSCNViewDelegate
// 重写以根据anchor创建添加到当前session中的node。识别平面或图像返回的锚点。
- (SCNNode *)renderer:(id<SCNSceneRenderer>)renderer nodeForAnchor:(ARAnchor *)anchor {
    // 当返回ARImageAnchor时，说明识别到图片了。
    if (![anchor isMemberOfClass:[ARImageAnchor class]]) {
        return [SCNNode node];
    }
    if (_videoNode) {
        return _videoNode;
    }
    CGFloat videoScale = [_playerManger getVideoWidth]/[_playerManger getVideoHeight];
    if (videoScale == 0 || videoScale == 1) {
        videoScale = 16.0/9.0;
    }
    // DKVideoPlaneHorizontal
    DKVideoPlane *videoGeometry = [DKVideoPlane planeWithType:DKVideoPlaneHorizontal width:0.1 length:0.1/videoScale];
    videoGeometry.materials = @[self.materials[DKARPlayerMaterialTypeBackground]];

    _videoNode = [SCNNode nodeWithGeometry:videoGeometry];
    //worldTransform 和 transform 的区别：worldTransform相对于根节点的旋转平移缩放矩阵，transform和position同时设置，共同作用与node的变换。
    SCNMatrix4 transM = SCNMatrix4FromMat4(anchor.transform);
    _videoNode.worldTransform = transM;
    printMatrix(&transM.m11);
    if (!_shouldPlay) {
        // Player play Button Node
        DKVideoPlane *btnPlan = [DKVideoPlane planeWithType:DKVideoPlaneHorizontal width:0.03 length:0.03];
        btnPlan.materials = @[self.materials[DKARPlayerMaterialTypePlay]];
        self.btnPlayNodel = [SCNNode nodeWithGeometry:btnPlan];
        [_videoNode addChildNode:_btnPlayNodel];
    }
   
    return _videoNode;
}

- (void)renderer:(id <SCNSceneRenderer>)renderer didAddNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor
{
    [self.planes setObject:node forKey:anchor.identifier];
}

- (void)renderer:(id <SCNSceneRenderer>)renderer didUpdateNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor {
    
    __block SCNMatrix4 transM = SCNMatrix4FromMat4(anchor.transform);

    if (![anchor isMemberOfClass:[ARImageAnchor class]]) {
        node.worldTransform = transM;
        return ;
    }
    printMatrix(&transM.m11);
    node.worldTransform = transM;
    [node.childNodes enumerateObjectsUsingBlock:^(SCNNode * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        transM = SCNMatrix4Translate(transM, 0, 0.01, 0);
        obj.worldTransform = transM;
    }];
}

- (void)renderer:(id <SCNSceneRenderer>)renderer didRemoveNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor {
    // Nodes will be removed if planes multiple individual planes that are detected to all be
    // part of a larger plane are merged.
    [self.planes removeObjectForKey:anchor.identifier];
}

#pragma mark SCNSceneRendererDelegate

#pragma mark ARSessionDelegate
- (void)session:(ARSession *)session didFailWithError:(NSError *)error {
    // Present an error message to the user
}

// 是不是需要持续定位之前的识别锚点
- (BOOL)sessionShouldAttemptRelocalization:(ARSession *)session
{
    return YES;
}

- (void)sessionWasInterrupted:(ARSession *)session {
    // Inform the user that the session has been interrupted, for example, by presenting an overlay, or being put in to the background
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Interruption" message:@"The tracking session has been interrupted. The session will be reset once the interruption has completed" preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
    }];
    
    [alert addAction:ok];
    [self presentViewController:alert animated:YES completion:nil];
    
}

- (void)sessionInterruptionEnded:(ARSession *)session {
    [self resetTracking];
}

#pragma mark DKVideoPlayerDelegate
- (void)videoPlay:(DKVideoPlayerManger *)player previewPixelBufferReadyForDisplay:(CVPixelBufferRef)pixelBuffer {
    
}

- (void)videoPlayCurrentTime:(NSInteger)currentTime totalTime:(NSInteger)totalTime progressValue:(CGFloat)progress {
    
    // 当前时长进度progress
    NSInteger proMin = currentTime / 60;//当前秒
    NSInteger proSec = currentTime % 60;//当前分钟
    // duration 总时长
    NSInteger durMin = totalTime / 60;//总秒
    NSInteger durSec = totalTime % 60;//总分钟
    
    NSString *string = [NSString stringWithFormat:@"%f----%zd:%zd/%zd:%zd",progress,proSec,proMin,durMin,durSec];
    SCNMaterial *materialText = [SCNMaterial material];
    materialText.diffuse.contents = string;
    _textNode.geometry.materials = @[materialText];
}

- (void)videoPlaydidPlaybackEnd:(DKVideoPlayerManger *)player {
    
}

- (void)videoPlaydidPlaybackReadyToPlay:(DKVideoPlayerManger *)player {
    
}

- (void)videoPlaydidPlaybackStart:(DKVideoPlayerManger *)player {
    
}
#pragma mark utils
// Print a 4x4 matrix
void printMatrix(const float* mat)
{
    printf("============\n");
    
    for (int r = 0; r < 4; r++, mat += 4) {
        printf("%7.3f ,%7.3f ,%7.3f ,%7.3f,\n", mat[0], mat[1], mat[2], mat[3]);
    }
    printf("============\n");
    
}

/**
 *  pan水平移动的方法
 *
 *  @param value void
 */
- (void)horizontalMoved:(CGFloat)value {
    // 每次滑动需要叠加时间
    self.sumTime += value / 200;
    // 需要限定sumTime的范围
    CMTime totalTime           = [self.playerManger.player currentItem].duration;
    CGFloat totalMovieDuration = (CGFloat)totalTime.value/totalTime.timescale;
    if (self.sumTime > totalMovieDuration) { self.sumTime = totalMovieDuration;}
    if (self.sumTime < 0) { self.sumTime = 0; }
    NSLog(@"seekTo == %f",self.sumTime);

    BOOL style = false;
    if (value > 0) { style = YES; }
    if (value < 0) { style = NO; }
    if (value == 0) { return; }
}




@end
