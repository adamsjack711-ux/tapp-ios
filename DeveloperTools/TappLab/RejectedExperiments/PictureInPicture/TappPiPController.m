#import "TappPiPController.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>

static void DrawTapp(CGContextRef context, double time) {
    CGContextTranslateCTM(context,0,256);
    CGContextScaleCTM(context,1,-1);
    UIGraphicsPushContext(context);
    [[UIColor colorWithRed:0.07 green:0.13 blue:0.16 alpha:1] setFill];
    UIRectFill(CGRectMake(0,0,256,256));
    double bob = 5 * sin(time * M_PI * 2 / 3);
    CGRect body = CGRectMake(48,39+bob,160,160);
    CGContextSetShadowWithColor(context,CGSizeMake(0,6),12,[UIColor colorWithWhite:0 alpha:0.3].CGColor);
    UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:64];
    [[UIColor colorWithRed:0.28 green:0.94 blue:0.76 alpha:1] setFill];
    [shape fill];
    CGContextSetShadowWithColor(context,CGSizeZero,0,NULL);
    [[UIColor colorWithRed:0.04 green:0.24 blue:0.22 alpha:1] setStroke];
    shape.lineWidth = 4;
    [shape stroke];
    BOOL blink = fmod(time,3.0)>2.7 && fmod(time,3.0)<2.85;
    for (NSNumber *x in @[@94,@144]) {
        [[UIColor colorWithRed:0.04 green:0.22 blue:0.21 alpha:1] setFill];
        CGRect eye = CGRectMake(x.doubleValue,91+bob+(blink?13:0),18,blink?5:31);
        [[UIBezierPath bezierPathWithRoundedRect:eye cornerRadius:9] fill];
        if (!blink) {
            [UIColor.whiteColor setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x.doubleValue+3,96+bob,5,8) cornerRadius:2.5] fill];
        }
    }
    [[UIColor colorWithRed:1 green:0.55 blue:0.63 alpha:1] setFill];
    for (NSNumber *x in @[@73,@165]) [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(x.doubleValue,129+bob,21,11)] fill];
    UIBezierPath *mouth = [UIBezierPath bezierPath];
    [mouth moveToPoint:CGPointMake(116,142+bob)];
    [mouth addQuadCurveToPoint:CGPointMake(140,142+bob) controlPoint:CGPointMake(128,156+bob)];
    mouth.lineWidth = 4;
    mouth.lineCapStyle = kCGLineCapRound;
    [[UIColor colorWithRed:0.04 green:0.22 blue:0.21 alpha:1] setStroke];
    [mouth stroke];
    NSDictionary *attributes = @{NSFontAttributeName:[UIFont systemFontOfSize:20 weight:UIFontWeightSemibold], NSForegroundColorAttributeName:UIColor.whiteColor};
    CGSize text = [@"tapp" sizeWithAttributes:attributes];
    [@"tapp" drawAtPoint:CGPointMake((256-text.width)/2,216) withAttributes:attributes];
    UIGraphicsPopContext();
}

static void MakeMovie(NSURL *url, void (^completion)(NSError *)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        @autoreleasepool {
            [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
            NSError *error = nil;
            AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeMPEG4 error:&error];
            AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{AVVideoCodecKey:AVVideoCodecTypeH264, AVVideoWidthKey:@256, AVVideoHeightKey:@256}];
            AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA),(id)kCVPixelBufferWidthKey:@256,(id)kCVPixelBufferHeightKey:@256,(id)kCVPixelBufferCGImageCompatibilityKey:@YES,(id)kCVPixelBufferCGBitmapContextCompatibilityKey:@YES}];
            if (!writer || ![writer canAddInput:input]) { completion(error ?: [NSError errorWithDomain:@"TappMovie" code:1 userInfo:nil]); return; }
            [writer addInput:input];
            if (![writer startWriting]) { completion(writer.error ?: [NSError errorWithDomain:@"TappMovie" code:4 userInfo:nil]); return; }
            [writer startSessionAtSourceTime:kCMTimeZero];
            BOOL success = YES;
            for (int frame=0;frame<120 && success;frame++) {
                CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent()+5;
                while (!input.readyForMoreMediaData && writer.status==AVAssetWriterStatusWriting && CFAbsoluteTimeGetCurrent()<deadline) [NSThread sleepForTimeInterval:0.005];
                if (!input.readyForMoreMediaData || writer.status!=AVAssetWriterStatusWriting) { success=NO; break; }
                CVPixelBufferRef buffer = NULL;
                if (CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault,adaptor.pixelBufferPool,&buffer)!=kCVReturnSuccess) { success=NO; break; }
                CVPixelBufferLockBaseAddress(buffer,0);
                CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
                CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(buffer),256,256,8,CVPixelBufferGetBytesPerRow(buffer),color,kCGBitmapByteOrder32Little|(CGBitmapInfo)kCGImageAlphaPremultipliedFirst);
                if (context) DrawTapp(context,frame/20.0);
                else success=NO;
                if (context) CGContextRelease(context);
                CGColorSpaceRelease(color);
                CVPixelBufferUnlockBaseAddress(buffer,0);
                if (success) success=[adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(frame,20)];
                CVPixelBufferRelease(buffer);
            }
            if (!success) {
                error=writer.error ?: [NSError errorWithDomain:@"TappMovie" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Could not generate the local Tapp animation."}];
                [writer cancelWriting];
                completion(error);
                return;
            }
            [writer endSessionAtSourceTime:CMTimeMake(120,20)];
            [input markAsFinished];
            [writer finishWritingWithCompletionHandler:^{ completion(writer.status==AVAssetWriterStatusCompleted ? nil : writer.error ?: [NSError errorWithDomain:@"TappMovie" code:3 userInfo:nil]); }];
        }
    });
}

@interface TappPiPController () <AVPictureInPictureControllerDelegate>
@property(nonatomic,copy) void (^recorder)(NSString *,NSDictionary *);
@property(nonatomic,strong) AVQueuePlayer *player;
@property(nonatomic,strong) AVPlayerItem *lastItem;
@property(nonatomic,strong) id endObserver;
@property(nonatomic,strong) AVPlayerLayer *video;
@property(nonatomic,strong) AVPictureInPictureController *pip;
@property(nonatomic,strong) UIView *preview;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIButton *startButton;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) NSTimeInterval startedAt;
@property(nonatomic) NSInteger observation;
@property(nonatomic) BOOL stopped;
@property(nonatomic) BOOL starting;
@end

@implementation TappPiPController
- (instancetype)initWithRecorder:(void (^)(NSString *,NSDictionary *))recorder {
    if ((self=[super init])) self.recorder=recorder;
    return self;
}
- (void)record:(NSString *)event details:(NSDictionary *)details {
    if (self.recorder) self.recorder(event,details ?: @{});
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[UIColor colorWithRed:0.04 green:0.08 blue:0.10 alpha:1];
    UILabel *title=[UILabel new];
    title.text=@"Tapp · floating companion";
    title.font=[UIFont systemFontOfSize:25 weight:UIFontWeightBold];
    title.textColor=UIColor.whiteColor;
    title.numberOfLines=0;
    self.preview=[UIView new];
    self.preview.layer.cornerRadius=28;
    self.preview.clipsToBounds=YES;
    self.status=[UILabel new];
    self.status.textColor=UIColor.lightGrayColor;
    self.status.font=[UIFont systemFontOfSize:16];
    self.status.numberOfLines=0;
    self.status.text=@"Preparing Tapp’s animation…\nAssistiveTouch stays off.\nPicture in Picture controls the window.\nThis experiment does not tap other apps.";
    self.startButton=[UIButton buttonWithType:UIButtonTypeSystem];
    self.startButton.configuration=[UIButtonConfiguration filledButtonConfiguration];
    [self.startButton setTitle:@"Float Tapp" forState:UIControlStateNormal];
    self.startButton.enabled=NO;
    [self.startButton addTarget:self action:@selector(startFloating) forControlEvents:UIControlEventTouchUpInside];
    UIButton *stop=[UIButton buttonWithType:UIButtonTypeSystem];
    [stop setTitle:@"Stop Tapp" forState:UIControlStateNormal];
    [stop addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[title,self.preview,self.status,self.startButton,stop]];
    stack.axis=UILayoutConstraintAxisVertical;
    stack.spacing=22;
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24],[stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24],[stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:28],[self.preview.heightAnchor constraintEqualToConstant:230]]];
    [self record:@"pip-launch" details:@{@"supported":@([AVPictureInPictureController isPictureInPictureSupported]),@"inputDispatched":@NO,@"maximumActiveSeconds":@300}];
    NSURL *url=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"tapp-animation.mp4"]];
    __weak typeof(self) weakSelf=self;
    MakeMovie(url,^(NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            TappPiPController *self=weakSelf;
            if (!self || self.stopped) return;
            if (error) { [self record:@"pip-video-error" details:@{@"message":error.localizedDescription}]; self.status.text=error.localizedDescription; return; }
            [self preparePlayback:url];
        });
    });
}
- (void)preparePlayback:(NSURL *)url {
    NSError *error=nil;
    AVAudioSession *audio=AVAudioSession.sharedInstance;
    if (![audio setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeMoviePlayback options:AVAudioSessionCategoryOptionMixWithOthers error:&error] || ![audio setActive:YES error:&error]) {
        [self record:@"pip-audio-session-error" details:@{@"message":error.localizedDescription ?: @"Session unavailable"}];
        self.status.text=@"Could not prepare video playback.";
        return;
    }
    // A finite queue keeps the five-minute ceiling even if iOS suspends our timer.
    NSMutableArray<AVPlayerItem *> *items=[NSMutableArray array];
    for (int i=0;i<50;i++) [items addObject:[AVPlayerItem playerItemWithURL:url]];
    self.lastItem=items.lastObject;
    self.player=[AVQueuePlayer queuePlayerWithItems:items];
    self.player.muted=YES;
    __weak typeof(self) weakSelf=self;
    self.endObserver=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:self.lastItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){ [weakSelf stop]; }];
    self.video=[AVPlayerLayer playerLayerWithPlayer:self.player];
    self.video.videoGravity=AVLayerVideoGravityResizeAspect;
    self.video.frame=self.preview.bounds;
    [self.preview.layer addSublayer:self.video];
    self.pip=[[AVPictureInPictureController alloc] initWithPlayerLayer:self.video];
    self.pip.delegate=self;
    self.pip.canStartPictureInPictureAutomaticallyFromInline=NO;
    self.pip.requiresLinearPlayback=YES;
    [self.player play];
    self.status.text=@"Tapp is ready. Tap Float Tapp, then open another app.\nFive-minute research session.\nDrag the floating video to a corner. It does not control other apps.";
    if (![AVPictureInPictureController isPictureInPictureSupported]) self.status.text=@"This device does not support Picture in Picture.\nThe animation preview works here; cross-app display requires a supported device.";
    [self record:@"pip-video-ready" details:@{@"localAnimation":@YES,@"networkUsed":@NO}];
    self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){ [weakSelf tick]; }];
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; self.video.frame=self.preview.bounds; }
- (void)tick {
    if (self.stopped) return;
    self.startButton.enabled=self.pip.pictureInPicturePossible && !self.pip.pictureInPictureActive && !self.starting;
    if (++self.observation%5==0) [self record:@"pip-observation" details:@{@"possible":@(self.pip.pictureInPicturePossible),@"active":@(self.pip.pictureInPictureActive),@"suspended":@(self.pip.pictureInPictureSuspended),@"playerRate":@(self.player.rate),@"itemStatus":@(self.player.currentItem.status),@"itemError":self.player.currentItem.error.localizedDescription ?: @"",@"videoReadyForDisplay":@(self.video.readyForDisplay),@"background":@(UIApplication.sharedApplication.applicationState==UIApplicationStateBackground)}];
    if (self.startedAt && NSProcessInfo.processInfo.systemUptime-self.startedAt>=300) [self stop];
}
- (void)startFloating {
    if (self.stopped || self.starting || !self.pip.pictureInPicturePossible) return;
    self.starting=YES;
    self.startButton.enabled=NO;
    self.startedAt=NSProcessInfo.processInfo.systemUptime;
    [self record:@"pip-start-request" details:nil];
    [self.pip startPictureInPicture];
}
- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)controller {
    self.starting=NO;
    [self record:@"pip-started" details:@{@"active":@(controller.pictureInPictureActive),@"visualProofStillRequired":@YES}];
    self.status.text=@"Tapp is floating. Open another app to inspect it.\nPicture in Picture owns the window; this is not a free-position cursor.";
}
- (void)pictureInPictureController:(AVPictureInPictureController *)controller failedToStartPictureInPictureWithError:(NSError *)error {
    self.starting=NO;
    [self record:@"pip-start-failed" details:@{@"domain":error.domain,@"code":@(error.code),@"message":error.localizedDescription}];
    self.status.text=error.localizedDescription;
}
- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)controller {
    [self record:@"pip-stopped" details:nil];
    [self stop];
}
- (void)pictureInPictureController:(AVPictureInPictureController *)controller restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL))completionHandler {
    completionHandler(self.view.window!=nil && UIApplication.sharedApplication.applicationState==UIApplicationStateActive);
}
- (void)stop {
    if (self.stopped) return;
    self.stopped=YES;
    [self.timer invalidate]; self.timer=nil;
    [self.pip stopPictureInPicture];
    [self.player pause];
    if (self.endObserver) [NSNotificationCenter.defaultCenter removeObserver:self.endObserver];
    self.endObserver=nil;
    [self.player removeAllItems];
    NSError *error=nil;
    BOOL inactive=[AVAudioSession.sharedInstance setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
    self.startButton.enabled=NO;
    self.status.text=@"Tapp stopped. Reopen this research mode to start another session.";
    [self record:@"pip-cleanup" details:@{@"playerPaused":@(self.player.rate==0),@"audioSessionDeactivated":@(inactive),@"audioError":error.localizedDescription ?: @""}];
}
@end
