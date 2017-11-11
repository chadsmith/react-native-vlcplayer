#import <React/RCTConvert.h>
#import "RCTVLCPlayer.h"
#import <React/RCTBridgeModule.h>
#import <React/RCTEventDispatcher.h>
#import <React/UIView+React.h>
#import <MobileVLCKit/MobileVLCKit.h>
static NSString *const statusKeyPath = @"status";
static NSString *const playbackLikelyToKeepUpKeyPath = @"playbackLikelyToKeepUp";
static NSString *const playbackBufferEmptyKeyPath = @"playbackBufferEmpty";
static NSString *const readyForDisplayKeyPath = @"readyForDisplay";
static NSString *const playbackRate = @"rate";

@implementation RCTVLCPlayer
{
    
    /* Required to publish events */
    RCTEventDispatcher *_eventDispatcher;
    VLCMediaPlayer *_player;
    
    BOOL _paused;
    BOOL _started;
    
}

- (instancetype)initWithEventDispatcher:(RCTEventDispatcher *)eventDispatcher
{
    if ((self = [super init])) {
        _eventDispatcher = eventDispatcher;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillResignActive:)
                                                     name:UIApplicationWillResignActiveNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillEnterForeground:)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        
    }
    
    return self;
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    if (!_paused) {
        [self setPaused:_paused];
    }
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    [self applyModifiers];
}

- (void)applyModifiers
{
    if(!_paused)
        [self play];
}

- (void)setPaused:(BOOL)paused
{
    //NSLog(@">>>>paused %i",paused);
    if(_player){
        if(!_started)
            [self play];
        else {
            [_player pause];
            _paused = paused;
        }
    }
}

-(void)play
{
    if(_player){
        [_player play];
        _paused = NO;
        _started = YES;
    }
}

-(void)setSource:(NSDictionary *)source
{
    if(_player){
        [self _release];
    }
    NSArray* options = [source objectForKey:@"initOptions"];
    NSString* uri    = [source objectForKey:@"uri"];
    BOOL    autoplay = [RCTConvert BOOL:[source objectForKey:@"autoplay"]];
    NSURL* _uri    = [NSURL URLWithString:uri];
    
    //init player && play
    _player = [[VLCMediaPlayer alloc] initWithOptions:options];
    [_player setDrawable:self];
    _player.delegate = self;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mediaPlayerStateChanged:) name:VLCMediaPlayerStateChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mediaPlayerTimeChanged:) name:VLCMediaPlayerTimeChanged object:nil];
    _player.media = [VLCMedia mediaWithURL:_uri];
    if(autoplay)
        [self play];
}

- (void)mediaPlayerTimeChanged:(NSNotification *)aNotification
{
    [self updateVideoProgress];
}

- (void)mediaPlayerStateChanged:(NSNotification *)aNotification
{
    VLCMediaPlayerState state = _player.state;
    switch (state) {
        case VLCMediaPlayerStatePaused:
            _paused = YES;
            if(self.onVideoPaused) {
                self.onVideoPaused(@{
                    @"target": self.reactTag
                });
            }
            break;
        case VLCMediaPlayerStateStopped:
            //NSLog(@"VLCMediaPlayerStateStopped %i",VLCMediaPlayerStateStopped);
            if(self.onVideoStopped) {
                self.onVideoStopped(@{
                    @"target": self.reactTag
                });
            }
            break;
        case VLCMediaPlayerStateBuffering:
            if(self.onVideoBuffering) {
                self.onVideoBuffering(@{
                    @"target": self.reactTag
                });
                break;
            case VLCMediaPlayerStatePlaying:
                _paused = NO;
                //NSLog(@"VLCMediaPlayerStatePlaying %i",VLCMediaPlayerStatePlaying);
                if(self.onVideoPlaying) {
                    self.onVideoPlaying(@{
                        @"target": self.reactTag,
                        @"seekable": [NSNumber numberWithBool:[_player isSeekable]],
                        @"duration":[NSNumber numberWithInt:[_player.media.length intValue]]
                    });
                }
                break;
            case VLCMediaPlayerStateEnded:
                //NSLog(@"VLCMediaPlayerStateEnded %i",VLCMediaPlayerStateEnded);
                if(self.onVideoEnded) {
                    self.onVideoEnded(@{
                        @"target": self.reactTag
                    });
                }
                break;
            case VLCMediaPlayerStateError:
                //NSLog(@"VLCMediaPlayerStateError %i",VLCMediaPlayerStateError);
                if(self.onVideoError) {
                    self.onVideoError(@{ @"target": self.reactTag });
                }
                [self _release];
                break;
            default:
                //NSLog(@"state %i",state);
                break;
            }
    }
}

-(void)updateVideoProgress
{
    
    int currentTime   = [[_player time] intValue];
    int remainingTime = [[_player remainingTime] intValue];
    int duration      = [_player.media.length intValue];
    
    if( currentTime >= 0 && currentTime < duration && self.onVideoProgress) {
        self.onVideoProgress(@{
                               @"target": self.reactTag,
                               @"currentTime": [NSNumber numberWithInt:currentTime],
                               @"remainingTime": [NSNumber numberWithInt:remainingTime],
                               @"duration":[NSNumber numberWithInt:duration],
                               @"position":[NSNumber numberWithFloat:_player.position]
                               });
    }
}

- (void)jumpBackward:(int)interval
{
    if(interval>=0 && interval <= [_player.media.length intValue])
        [_player jumpBackward:interval];
}

- (void)jumpForward:(int)interval
{
    if(interval>=0 && interval <= [_player.media.length intValue])
        [_player jumpForward:interval];
}

-(void)setSeek:(float)pos
{
    if([_player isSeekable]){
        if(pos>=0 && pos <= 1){
            [_player setPosition:pos];
        }
    }
}

-(void)setSnapshotPath:(NSString*)path
{
    if(_player)
        [_player saveVideoSnapshotAt:path withWidth:0 andHeight:0];
}

-(void)setRate:(float)rate
{
    [_player setRate:rate];
}

- (void)_release
{
    [_player pause];
    [_player stop];
    _player = nil;
    _eventDispatcher = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Lifecycle
- (void)removeFromSuperview
{
    [self _release];
    [super removeFromSuperview];
}

@end

