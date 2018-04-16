//
//  DKVideoPlayerManger.h
//  DKShortVideo
//
//  Created by Keer_LGQ on 2018/4/1.
//  Copyright © 2018年 DK. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

// Media states
typedef enum tagMEDIA_STATE {
    REACHED_END,
    PAUSED,
    STOPPED,
    PLAYING,
    READY,
    BUFFERING,
    NOT_READY,
    ERROR,
} MEDIA_STATE;

// Media player type
typedef enum tagPLAYER_TYPE {
    PLAYER_TYPE_ON_PIXELBUFFER,
    PLAYER_TYPE_AVPLAYER
} PLAYER_TYPE;

#define RETAINED_BUFFER_COUNT 6

// Used to specify that playback should start from the current position when
// calling the load and play methods
static const float VIDEO_PLAYBACK_CURRENT_POSITION = -1.0f;

@protocol DKVideoPlayerDelegate;
@interface DKVideoPlayerManger : NSObject

- (instancetype)initWithDelegate:(id<DKVideoPlayerDelegate>)delegate callbackQueue:(dispatch_queue_t)queue;

@property (nonatomic, weak) id <DKVideoPlayerDelegate> delegate;
@property (nonatomic, readonly) AVPlayer* player;

/**
 
 @param urlString an media url locol or network
 @param playImmediately play now?
 @param playType default is PLAYER_TYPE_ON_PIXELBUFFER
 @return bool
 */
- (BOOL)loadMedia:(NSString*)urlString playImmediately:(BOOL)playImmediately playerType:(PLAYER_TYPE)playType;
- (BOOL)unload;

- (BOOL)playPosition:(float)seekPosition;
- (BOOL)pause;
- (BOOL)stop;

- (BOOL)seekTo:(float)position;
- (BOOL)setVolume:(float)volume;

- (CVPixelBufferRef)getLastestSampleBuffer;

- (MEDIA_STATE)getStatus;
- (CGFloat)getVideoHeight;
- (CGFloat)getVideoWidth;

@end

@protocol DKVideoPlayerDelegate <NSObject>
@required

- (void)videoPlaydidPlaybackReadyToPlay:(DKVideoPlayerManger *)player;
- (void)videoPlaydidPlaybackStart:(DKVideoPlayerManger *)player;
- (void)videoPlaydidPlaybackEnd:(DKVideoPlayerManger *)player;

- (void)videoPlayCurrentTime:(NSInteger)currentTime totalTime:(NSInteger)totalTime progressValue:(CGFloat)progress;
// Preview
- (void)videoPlay:(DKVideoPlayerManger *)player previewPixelBufferReadyForDisplay:(CVPixelBufferRef)pixelBuffer;

@end
