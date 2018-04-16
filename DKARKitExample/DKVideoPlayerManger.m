//
//  DKVideoPlayerManger.m
//  DKShortVideo
//
//  Created by Keer_LGQ on 2018/4/1.
//  Copyright © 2018年 DK. All rights reserved.
//

#import "DKVideoPlayerManger.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AudioToolbox/AudioServices.h>


// Constants
static const int TIMESCALE = 1000;  // 1 millisecond granularity for time
static const float PLAYER_CURSOR_POSITION_MEDIA_START = 0.0f;
//static const float PLAYER_VOLUME_DEFAULT = 1.0f;
// Key-value observation contexts
static void* AVPlayerItemStatusObservationContext = &AVPlayerItemStatusObservationContext;
static void* AVPlayerRateObservationContext = &AVPlayerRateObservationContext;

// String constants
static NSString* const kStatusKey = @"status";
static NSString* const kTracksKey = @"tracks";
static NSString* const kRateKey = @"rate";
static NSString* const kloadedTimeRangesKey = @"loadedTimeRanges";
static NSString* const kplaybackBufferEmptyKey = @"playbackBufferEmpty";
static NSString* const kplaybackLikelyToKeepUpKey = @"playbackLikelyToKeepUp";

@interface DKVideoPlayerManger ()
{
    // Playback status
    MEDIA_STATE mediaState;
    PLAYER_TYPE playerType;
    // Asset
    BOOL playVideoImmediately;
    
    // AVPlayer
    CMTime playerCursorStartPosition;
    // Timing
    CFTimeInterval mediaStartTime;
    CFTimeInterval playerCursorPosition;
    
    // Video properties
    CGSize videoSize;
    Float64 videoLengthSeconds;
    float videoFrameRate;
    BOOL playVideo;
    
    // Audio properties
    float currentVolume;
    BOOL playAudio;
    
    BOOL stopFrameLoop;
    dispatch_queue_t _delegateCallbackQueue;
    
    BOOL _addedObservers;
    BOOL _allowedToUseGPU;
    
}
@property (nonatomic, strong, readwrite) AVPlayer* player;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, strong) NSURL* mediaURL;
@property (nonatomic, strong) AVPlayerItemVideoOutput *videoOutput;
@property (nonatomic, strong) AVURLAsset* asset;
@property (nonatomic, strong) NSLock* dataLock;
@property (nonatomic, strong) id timeObserve;

@end

@implementation DKVideoPlayerManger
static DKVideoPlayerManger *_shareInstance = nil;

//------------------------------------------------------------------------------
#pragma mark - Lifecycle
- (instancetype)initWithDelegate:(id<DKVideoPlayerDelegate>)delegate callbackQueue:(dispatch_queue_t)queue
{
    self = [super init];
    
    if (nil != self) {
        // Initialise data
        [self resetData];
        // Class data lock
        _dataLock = [[NSLock alloc] init];
        // Video sample buffer lock
        _delegate = delegate;
        _delegateCallbackQueue = queue;
        
        [self configNotification];
    }
    
    return self;
}

- (void)dealloc
{
    // Stop playback
    (void)[self stop];
    [self resetData];
    NSLog(@"*******************************%@: dealloc", [self class]);
    
    if ( _addedObservers ) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:[UIApplication sharedApplication]];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:[UIApplication sharedApplication]];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:[UIDevice currentDevice]];
        [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    }
}

#pragma mark - Public methods
- (BOOL)loadMedia:(NSString *)urlString playImmediately:(BOOL)playImmediately
       playerType:(PLAYER_TYPE)playType
{
    BOOL ret = NO;
    
    // Load only if there is no media currently loaded
    if (NOT_READY != mediaState && ERROR != mediaState) {
        NSLog(@"Media already loaded.  Unload current media first.");
    }
    else {
        playerType = playType;
        
        if (YES == playImmediately) {
            playVideoImmediately = playImmediately;
        }
        if (NSNotFound != [urlString rangeOfString:@"://"].location) {
            _mediaURL = [NSURL URLWithString:urlString];
            ret = [self loadMediaURL:_mediaURL];
        }else {
            NSString* fullPath = nil;
            
            if (0 == [urlString rangeOfString:@"/"].location) {
                fullPath = [NSString stringWithString:urlString];
            }
            else {
                fullPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:urlString];
            }
            _mediaURL = [[NSURL alloc] initFileURLWithPath:fullPath];
            ret = [self loadMediaURL:_mediaURL];
        }
    }
    return ret;
}

// Play the asset
- (BOOL)playPosition:(float)seekPosition
{
    BOOL ret = NO;
    if (PLAYING != mediaState  && NOT_READY > mediaState) {
        
        if (0.0f <= seekPosition) {
            [self updatePlayerCursorPosition:seekPosition];
        }
        mediaState = PLAYING;
        [_player play];
        if ([self.delegate respondsToSelector:@selector(videoPlaydidPlaybackStart:)]) {
            [self.delegate videoPlaydidPlaybackStart:self];
        }
        
        ret = YES;
    }
    return ret;
}

- (BOOL)pause
{
    BOOL ret = NO;
    if (PLAYING == mediaState) {
        [_dataLock lock];
        mediaState = PAUSED;
        [_player pause];
        ret = YES;
        [_dataLock unlock];
    }
    return ret;
}

- (BOOL)unload
{
    [self stop];
    [self resetData];
    
    return YES;
}

- (MEDIA_STATE)getStatus
{
    return mediaState;
}

- (CGFloat)getVideoHeight
{
    int ret = -1;
    
    if (NOT_READY > mediaState) {
        ret = videoSize.height;
    }
    else {
        NSLog(@"Video height not available in current state");
    }
    
    return ret;
}

- (CGFloat)getVideoWidth
{
    CGFloat ret = -1;
    if (NOT_READY > mediaState) {
        ret = videoSize.width;
    }
    else {
        NSLog(@"Video width not available in current state");
    }
    return ret;
}

// Get the length of the media
- (float)getLength
{
    float ret = -1.0f;
    
    if (NOT_READY > mediaState) {
        ret = (float)videoLengthSeconds;
    }
    else {
        NSLog(@"Video length not available in current state");
    }
    
    return ret;
}

- (BOOL)stop
{
    BOOL ret = NO;
    
    if (PLAYING == mediaState) {
        [_dataLock lock];
        mediaState = STOPPED;
        
        [_player pause];
        
        // Reset the playback cursor position
        [self updatePlayerCursorPosition:PLAYER_CURSOR_POSITION_MEDIA_START];
        
        [_dataLock unlock];
        ret = YES;
    }
    return ret;
}

#pragma mark - Private methods
// Create a Loop to drive the video frame pump
- (void)createFrameTimer
{
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(frameTimerFired)];
    [_link addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [_link setPaused:NO];
}

- (void)updatePlayerCursorPosition:(float)position
{
    playerCursorPosition = position;
}

- (void)configNotification
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:[UIApplication sharedApplication]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:[UIApplication sharedApplication]];
    _addedObservers = YES;
    
    _allowedToUseGPU = ( [UIApplication sharedApplication].applicationState != UIApplicationStateBackground );
    
}


- (void)applicationDidEnterBackground
{
    _allowedToUseGPU = NO;
    [self pause];
}

- (void)applicationWillEnterForeground
{
    [self playPosition:[self getCurrentPosition]];
    _allowedToUseGPU = YES;
}

#pragma mark config player
- (BOOL)loadMediaURL:(NSURL*)url
{
    BOOL ret = YES;
    self.asset = [AVURLAsset assetWithURL:url];
    
    [self prepareAVPlayer];
    
    return ret;
}

- (void)prepareAVPlayer
{
    // Create a player item
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:_asset];
    
    // use videoOutput
    NSDictionary *settings = @{(id) kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
    self.videoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:settings];
    [playerItem addOutput:self.videoOutput];
    
    // Add player item status KVO observer
    NSKeyValueObservingOptions opts = NSKeyValueObservingOptionNew;
    [playerItem addObserver:self forKeyPath:kStatusKey options:opts context:AVPlayerItemStatusObservationContext];
    
    [playerItem addObserver:self forKeyPath:kloadedTimeRangesKey options:NSKeyValueObservingOptionNew context:nil];
    // 缓冲区空了，需要等待数据
    [playerItem addObserver:self forKeyPath:kplaybackBufferEmptyKey options:NSKeyValueObservingOptionNew context:nil];
    // 缓冲区有足够数据可以播放了
    [playerItem addObserver:self forKeyPath:kplaybackLikelyToKeepUpKey options:NSKeyValueObservingOptionNew context:nil];
    
    // Create an AV player
    _player = [AVPlayer playerWithPlayerItem:playerItem];
    
    if([[UIDevice currentDevice] systemVersion].intValue>=10){
        if (@available(iOS 10.0, *)) {
            _player.automaticallyWaitsToMinimizeStalling = NO;
        } else {
            // Fallback on earlier versions
        }
    }
    
    // Add player rate KVO observer
    [_player addObserver:self forKeyPath:kRateKey options:opts context:AVPlayerRateObservationContext];
    playVideo = YES;
    if (playerType == PLAYER_TYPE_ON_PIXELBUFFER) {
        [self createFrameTimer];
    }
    [self createPlayLengthTimer];
}

//播放时长计时器
- (void)createPlayLengthTimer {
    __weak typeof(self) weakSelf = self;
    self.timeObserve = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(1, 1) queue:nil usingBlock:^(CMTime time){
        AVPlayerItem *currentItem = [weakSelf.player currentItem];
        NSArray *loadedRanges = currentItem.seekableTimeRanges;
        
        // 加载成功后会回调 这里可以获取视频码率，长宽等数据。
        [weakSelf bufferInfoWithTracks:currentItem.tracks];

        if (loadedRanges.count > 0 && currentItem.duration.timescale != 0) {
            NSInteger currentTime = (NSInteger)CMTimeGetSeconds([currentItem currentTime]);
            CGFloat totalTime     = (CGFloat)currentItem.duration.value / currentItem.duration.timescale;
            CGFloat value         = CMTimeGetSeconds([currentItem currentTime]) / totalTime;
            
            if ([weakSelf.delegate respondsToSelector:@selector(videoPlayCurrentTime:totalTime:progressValue:)]) {
                [weakSelf.delegate videoPlayCurrentTime:currentTime totalTime:totalTime progressValue:value];
            }
        }
    }];
}

- (void)bufferInfoWithTracks:(NSArray <AVPlayerItemTrack *> *)tracks
{
    if (tracks.count > 0) {
        [tracks enumerateObjectsUsingBlock:^(AVPlayerItemTrack * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([obj.assetTrack.mediaType isEqualToString:AVMediaTypeVideo]) {
                if (self->mediaState == NOT_READY) {
                    self->mediaState = READY;
                }
                // 解析视频尺寸
                self->videoSize = [obj.assetTrack naturalSize];
                self->videoLengthSeconds = CMTimeGetSeconds([obj.assetTrack.asset duration]);
                self->videoFrameRate = [obj.assetTrack nominalFrameRate];
            }
            [self descriptVideoTrackInfo:obj.assetTrack];
        }];
    }
    
}

- (void)descriptVideoTrackInfo:(AVAssetTrack *)track
{
    NSLog(@" -------------------------------------------- ");
    
    NSLog(@"trackVideo = %@",track);
    NSLog(@"trackVideoSize = %f--%f",videoSize.width,videoSize.height);
    NSLog(@"trackVideoSec = %f",videoLengthSeconds);
    NSLog(@"trackVideoFrameRate = %f",videoFrameRate);
    NSLog(@"trackVideo mediaType = %@",track.mediaType);
    NSLog(@"trackVideo formatDescriptions = %@",track.formatDescriptions);
    NSLog(@"trackVideo playable = %d",track.playable);
    NSLog(@"trackVideo decodable = %d",track.decodable);
    NSLog(@"trackVideo totalSampleDataLength = %lld",track.totalSampleDataLength);
    NSLog(@"trackVideo languageCode = %@",track.languageCode);
    NSLog(@"trackVideo mediaType = %f  -- %f",CMTimeGetSeconds(track.timeRange.start),CMTimeGetSeconds(track.timeRange.duration));
    
    NSLog(@"trackVideo segments = %@",track.segments);
    NSLog(@"trackVideo commonMetadata = %@",track.commonMetadata);
    NSLog(@"trackVideo metadata = %@",track.metadata);
    NSLog(@"trackVideo availableMetadataFormats = %@",track.availableMetadataFormats);
    NSLog(@"trackVideo availableTrackAssociationTypes = %@",track.availableTrackAssociationTypes);
    
    NSLog(@" -------------------------------------------- ");
    
}

// Video frame pump timer callback
- (void)frameTimerFired
{
    if (NO == stopFrameLoop) {
        [self invokeDelegateCallbackAsync:^{
            
            [self.delegate videoPlay:self previewPixelBufferReadyForDisplay:[self getLastestSampleBuffer]];
        }];
    }
    else {
        [_link invalidate];
    }
}

- (CVPixelBufferRef)getLastestSampleBuffer
{
    // We must not use the GPU while running in the background.
    // setRenderingEnabled: takes the same lock so the caller can guarantee no GPU usage once the setter returns.
    
    CVPixelBufferRef pixelBuffer = NULL;
    if (PLAYING == mediaState && PLAYER_TYPE_ON_PIXELBUFFER == playerType) {
        
        if ([_videoOutput hasNewPixelBufferForItemTime:_player.currentItem.currentTime]) {
            
            pixelBuffer = [self.videoOutput copyPixelBufferForItemTime:_player.currentItem.currentTime itemTimeForDisplay:nil];
        }
        
    }
    return pixelBuffer;
}

#pragma mark seek
// Seek to a particular playback cursor position (on-texture player only)
- (BOOL)seekTo:(float)position
{
    BOOL ret = NO;
    
    if (NOT_READY > mediaState) {
        if (position < videoLengthSeconds) {
            [_dataLock lock];
            [self updatePlayerCursorPosition:position];
            [_player seekToTime:CMTimeMake(position, 1)];
            [_dataLock unlock];
            ret = YES;
        }
        else {
            NSLog(@"Requested seek position greater than video length");
        }
    }
    else {
        NSLog(@"Seek control not available in current state");
    }
    
    return ret;
}


- (float)getCurrentPosition
{
    float ret = -1.0f;
    
    if (PLAYER_TYPE_ON_PIXELBUFFER == playerType) {
    }
    else {
        NSLog(@"Current playback position available only when playing video on texture");
    }
    
    return ret;
}

- (BOOL)setVolume:(float)volume
{
    BOOL ret = NO;
    
    if (PLAYER_TYPE_ON_PIXELBUFFER == playerType) {
        if (NOT_READY > mediaState) {
            [_dataLock lock];
            ret = [self setVolumeLevel:volume];
            [_dataLock unlock];
        }
        else {
            NSLog(@"Volume control not available in current state");
        }
    }
    else {
        NSLog(@"Volume control available only when playing video on texture");
    }
    
    return ret;
}

// [Always called with dataLock locked]
- (BOOL)setVolumeLevel:(float)volume
{
    BOOL ret = NO;
    NSArray* arrayTracks = [_asset tracksWithMediaType:AVMediaTypeAudio];
    
    if (0 < [arrayTracks count]) {
        // Get the asset's audio track
        AVAssetTrack* assetTrackAudio = [arrayTracks objectAtIndex:0];
        
        if (nil != assetTrackAudio) {
            // Set up the audio mix
            AVMutableAudioMixInputParameters* audioInputParams = [AVMutableAudioMixInputParameters audioMixInputParameters];
            [audioInputParams setVolume:currentVolume -= volume atTime:playerCursorStartPosition];
            [audioInputParams setTrackID:[assetTrackAudio trackID]];
            NSArray* audioParams = [NSArray arrayWithObject:audioInputParams];
            AVMutableAudioMix* audioMix = [AVMutableAudioMix audioMix];
            [audioMix setInputParameters:audioParams];
            
            // Apply the audio mix the the AVPlayer's current item
            [[_player currentItem] setAudioMix:audioMix];
            
            // Store the current volume level
            currentVolume = volume;
            ret = YES;
        }
    }else {
        UISlider *slider = [self getSystemVolumeSlider];
        slider.value += volume / 10000;
    }
    
    return ret;
}

- (void)resetData
{
    // ----- Info: additional player threads not running at this point -----
    
    // Reset media state and information
    mediaState = NOT_READY;
    playerType = PLAYER_TYPE_ON_PIXELBUFFER;
    playerCursorPosition = PLAYER_CURSOR_POSITION_MEDIA_START;
    playVideoImmediately = NO;
    videoSize.width = 0.0f;
    videoSize.height = 0.0f;
    videoLengthSeconds = 0.0f;
    videoFrameRate = 0.0f;
    playAudio = NO;
    playVideo = NO;
    
    // Remove KVO observers
    [[_player currentItem] removeObserver:self forKeyPath:kStatusKey];
    [_player removeObserver:self forKeyPath:kRateKey];
    // 移除time观察者
    if (self.timeObserve) {
        [self.player removeTimeObserver:self.timeObserve];
        self.timeObserve = nil;
    }
    
    // Release AVPlayer, AVAsset, etc.
    _player = nil;
    _asset = nil;
    _mediaURL = nil;
    
    [_link setPaused:YES];
    [_link invalidate];
    
}


#pragma mark Utilities
- (void)invokeDelegateCallbackAsync:(dispatch_block_t)callbackBlock
{
    dispatch_async( _delegateCallbackQueue, ^{
        @autoreleasepool {
            callbackBlock();
        }
    } );
}

/**
 *  获取系统音量
 */
- (UISlider *)getSystemVolumeSlider {
    MPVolumeView *volumeView = [[MPVolumeView alloc] init];
    UISlider *volumeViewSlider;
    for (UIView *view in [volumeView subviews]){
        if ([view.class.description isEqualToString:@"MPVolumeSlider"]){
            volumeViewSlider = (UISlider *)view;
            break;
        }
    }
    
    // 使用这个category的应用不会随着手机静音键打开而静音，可在手机静音下播放声音
    NSError *setCategoryError = nil;
    BOOL success = [[AVAudioSession sharedInstance]
                    setCategory: AVAudioSessionCategoryPlayback
                    error: &setCategoryError];
    
    if (!success) { /* handle the error in setCategoryError */ }
    
    return volumeViewSlider;
}
#pragma mark - 计算缓冲进度

/**
 *  计算缓冲进度
 *
 *  @return 缓冲进度
 */
- (NSTimeInterval)availableDuration {
    NSArray *loadedTimeRanges = [[_player currentItem] loadedTimeRanges];
    CMTimeRange timeRange     = [loadedTimeRanges.firstObject CMTimeRangeValue];// 获取缓冲区域
    float startSeconds        = CMTimeGetSeconds(timeRange.start);
    float durationSeconds     = CMTimeGetSeconds(timeRange.duration);
    NSTimeInterval result     = startSeconds + durationSeconds;// 计算缓冲总进度
    return result;
}

/**
 *  缓冲较差时候回调这里
 */
- (void)bufferingSomeSecond {
    
    // playbackBufferEmpty会反复进入，因此在bufferingOneSecond延时播放执行完之前再调用bufferingSomeSecond都忽略
    __block BOOL isBuffering = NO;
    if (isBuffering) return;
    isBuffering = YES;
    
    // 需要先暂停一小会之后再播放，否则网络状况不好的时候时间在走，声音播放不出来
    [_dataLock lock];
    [self.player pause];
    mediaState = BUFFERING;
    [_dataLock unlock];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        if (self->mediaState == PAUSED || self->mediaState == READY) {
            isBuffering = NO;
            return;
        }
        self->mediaState = READY;
        [self playPosition:0];
        
    });
}

//------------------------------------------------------------------------------
#pragma mark - AVPlayer observation
// Called when the value at the specified key path relative to the given object
// has changed.  Note, this method is invoked on the main queue
- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context
{
    if ([keyPath isEqualToString:kloadedTimeRangesKey]) {
        if (mediaState == NOT_READY) {
            mediaState = READY;
        }

        // 计算缓冲进度
        NSTimeInterval timeInterval = [self availableDuration];
        CMTime duration             = [_player currentItem].duration;
        CGFloat totalDuration       = CMTimeGetSeconds(duration);
        NSLog(@"缓存进度%f",timeInterval / totalDuration);
        
    } else if ([keyPath isEqualToString:kplaybackBufferEmptyKey]) {
        
        // 当缓冲是空的时候
        if ([_player currentItem].playbackBufferEmpty) {
            //            [self bufferingSomeSecond];
        }
        
    } else if ([keyPath isEqualToString:kplaybackLikelyToKeepUpKey]) {
        
        // 当缓冲好的时候
        if ([_player currentItem].playbackLikelyToKeepUp && mediaState == BUFFERING){
            
        }
    }
    if (AVPlayerItemStatusObservationContext == context) {
        AVPlayerItemStatus status = [[change objectForKey:NSKeyValueChangeNewKey] integerValue];
        
        switch (status) {
            case AVPlayerItemStatusUnknown:
                NSLog(@"AVPlayerItemStatusObservationContext -> AVPlayerItemStatusUnknown");
                if (mediaState != PLAYING) {
                    mediaState = NOT_READY;
                }
                break;
            case AVPlayerItemStatusReadyToPlay:
                NSLog(@"AVPlayerItemStatusObservationContext -> AVPlayerItemStatusReadyToPlay");
                if (mediaState != PLAYING) {
                    mediaState = READY;
                }
                
                // If immediate on-texture playback has been requested, start
                // playback
                if (YES == playVideoImmediately) {
                    [self playPosition:0];
                }
                if ([self.delegate respondsToSelector:@selector(videoPlaydidPlaybackReadyToPlay:)]) {
                    [self.delegate videoPlaydidPlaybackReadyToPlay:self];
                }
                
                break;
            case AVPlayerItemStatusFailed:
                NSLog(@"AVPlayerItemStatusObservationContext -> AVPlayerItemStatusFailed");
                NSLog(@"Error - AVPlayer unable to play media: %@", [[[_player currentItem] error] localizedDescription]);
                mediaState = ERROR;
                break;
            default:
                NSLog(@"AVPlayerItemStatusObservationContext -> Unknown");
                mediaState = NOT_READY;
                break;
        }
    }
    else if (AVPlayerRateObservationContext == context && PLAYING == mediaState) {
        // We must detect the end of playback here when playing audio-only
        // media, because the video frame pump is not running (end of playback
        // is detected by the frame pump when playing video-only and audio/video
        // media).  We detect the difference between reaching the end of the
        // media and the user pausing/stopping playback by testing the value of
        // mediaState
        NSLog(@"AVPlayerRateObservationContext");
        float rate = [[change objectForKey:NSKeyValueChangeNewKey] floatValue];
        
        if (0.0f == rate) {
            // Playback has reached end of media
            mediaState = REACHED_END;
            
            if ([self.delegate respondsToSelector:@selector(videoPlaydidPlaybackEnd:)]) {
                [self.delegate videoPlaydidPlaybackEnd:self];
            }
            // Reset AVPlayer cursor position (audio)
            CMTime startTime = CMTimeMake(PLAYER_CURSOR_POSITION_MEDIA_START * TIMESCALE, TIMESCALE);
            [_player seekToTime:startTime];
        }
    }
}


@end
