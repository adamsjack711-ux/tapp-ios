#import "DraftRocketRenderer.h"
#if TARGET_OS_SIMULATOR
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <spawn.h>
#import <sys/wait.h>
#import <sys/stat.h>
static double Smooth(double t);

UIColor *DraftColorFromHex(NSString *hex) {
    if (hex.length != 6) return nil;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    unsigned value = 0;
    if (![scanner scanHexInt:&value] || !scanner.isAtEnd) return nil;
    return [UIColor colorWithRed:((value >> 16) & 255)/255.0
                          green:((value >> 8) & 255)/255.0
                           blue:(value & 255)/255.0 alpha:1];
}
UIImage *DraftTintedImage(UIImage *image, UIColor *color) {
    if (!color) return image;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = image.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:image.size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGRect bounds = (CGRect){CGPointZero, image.size};
        [image drawInRect:bounds];
        CGContextSetBlendMode(context.CGContext, kCGBlendModeColor);
        [color setFill]; UIRectFillUsingBlendMode(bounds, kCGBlendModeColor);
        [image drawInRect:bounds blendMode:kCGBlendModeDestinationIn alpha:1];
    }];
}

int DraftSpawnCompanionRuntime(NSString *directory, NSString *session) {
    // simctl installs nested bundles as resources and strips executable bits.
    // Stage only our built simulator helper in this draft's own data container.
    NSString *source = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"CompanionRuntime.app"];
    NSString *staged = [directory stringByAppendingPathComponent:@"CompanionRuntime.app"];
    NSFileManager *files = NSFileManager.defaultManager;
    [files removeItemAtPath:staged error:nil];
    if (![files copyItemAtPath:source toPath:staged error:nil]) return -2;
    NSString *executable = [staged stringByAppendingPathComponent:@"CompanionRuntime"];
    if (chmod(executable.fileSystemRepresentation,0755)) return -3;
    NSString *artwork = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"Characters.png"];
    char *args[]={(char *)executable.UTF8String,(char *)directory.UTF8String,(char *)session.UTF8String,(char *)artwork.UTF8String,NULL};
    extern char **environ;
    pid_t pid=0;
    int (*spawn)(pid_t *,const char *,const posix_spawn_file_actions_t *,const posix_spawnattr_t *,char *const[],char *const[])=dlsym(RTLD_DEFAULT,"posix_spawn");
    if(!spawn)return -1;
    int result=spawn(&pid,executable.UTF8String,NULL,NULL,args,environ);
    if(result)return -result;
    // Reap only the child we created; its own renderer deadline is 180 seconds.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{ waitpid(pid,NULL,0); });
    return pid;
}

// Samples form one seamless sinusoidal cycle, including matching endpoints.
// Linear time interpolation preserves the smooth envelope without a long dwell.
static CAKeyframeAnimation *BreathingAnimation(NSString *key, double center, double amplitude, double duration) {
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:key];
    NSMutableArray *values = [NSMutableArray array];
    for (NSUInteger i=0; i<=120; i++) [values addObject:@(center + amplitude * sin(2 * M_PI * i / 120.0))];
    animation.values = values;
    animation.calculationMode = kCAAnimationLinear;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.duration = duration;
    return animation;
}

// Gentle character effects live on the render server, not a repeating app timer.
static CALayer *CursorLayer(UIImage *image, CGFloat size, NSInteger style, BOOL motion) {
    CALayer *body = [CALayer layer];
    body.bounds = CGRectMake(0, 0, size, size);
    body.contents = (__bridge id)image.CGImage;
    body.contentsScale = UIScreen.mainScreen.scale;
    if (!motion || UIAccessibilityIsReduceMotionEnabled()) return body;

    CAKeyframeAnimation *wiggle = BreathingAnimation(@"transform.rotation.z", 0, .022, 4.2);
    wiggle.repeatCount = HUGE_VALF;
    [body addAnimation:wiggle forKey:@"gentleWiggle"];
    if (style == 0 || style == 2) {
        // A separate container lets the engine dim when the pet is resting.
        CALayer *tail = [CALayer layer]; tail.name = @"tailEffects";
        tail.frame = body.bounds; [body addSublayer:tail];
        // Artwork faces upper-left; exhaust/sparkles follow its lower-right tail.
        for (NSInteger index=0; index<2; index++) {
            CAShapeLayer *effect = [CAShapeLayer layer];
            CGFloat unit = size * (style == 0 ? .13 : .14);
            effect.bounds = CGRectMake(0, 0, unit, unit);
            effect.position = CGPointMake(size * (.77 + index*.075), size * (.78 + index*.065));
            UIBezierPath *path = [UIBezierPath bezierPath];
            if (style == 0) {
                [path moveToPoint:CGPointMake(unit*.12, 0)];
                [path addQuadCurveToPoint:CGPointMake(unit, unit) controlPoint:CGPointMake(unit*.85, unit*.25)];
                [path addQuadCurveToPoint:CGPointMake(0, unit*.12) controlPoint:CGPointMake(unit*.25, unit*.85)];
            } else {
                [path moveToPoint:CGPointMake(unit*.5, 0)];
                [path addLineToPoint:CGPointMake(unit*.62, unit*.38)];
                [path addLineToPoint:CGPointMake(unit, unit*.5)];
                [path addLineToPoint:CGPointMake(unit*.62, unit*.62)];
                [path addLineToPoint:CGPointMake(unit*.5, unit)];
                [path addLineToPoint:CGPointMake(unit*.38, unit*.62)];
                [path addLineToPoint:CGPointMake(0, unit*.5)];
                [path addLineToPoint:CGPointMake(unit*.38, unit*.38)];
            }
            [path closePath]; effect.path = path.CGPath;
            effect.fillColor = [UIColor colorWithRed:1 green:.70 blue:.30 alpha:1].CGColor;
            effect.opacity = 0;
            [tail addSublayer:effect];
            CAKeyframeAnimation *pulse;
            CAKeyframeAnimation *scale;
            if (style == 0) {
                // Keep a softly breathing engine lit instead of blinking on/off.
                pulse = BreathingAnimation(@"opacity", .55, .20, 1.8);
                scale = BreathingAnimation(@"transform.scale", .9, .18, 1.8);
            } else {
                pulse = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
                pulse.values = @[@0, @.72, @0, @0]; pulse.keyTimes = @[@0,@.3,@.65,@1]; pulse.duration = 3.4;
                scale = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
                scale.values = @[@.6,@1,@.6,@.6]; scale.keyTimes = pulse.keyTimes; scale.duration = pulse.duration;
                NSArray *easing = @[[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
                                    [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
                                    [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
                pulse.timingFunctions = easing; scale.timingFunctions = easing;
            }
            CAAnimationGroup *animation = [CAAnimationGroup animation];
            animation.animations = @[pulse,scale]; animation.duration = pulse.duration;
            if (style == 2) {
                CAKeyframeAnimation *driftX = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
                driftX.values = @[@0,@(size*.13)]; driftX.duration = pulse.duration;
                CAKeyframeAnimation *driftY = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
                driftY.values = driftX.values; driftY.duration = pulse.duration;
                animation.animations = @[pulse,scale,driftX,driftY];
            }
            animation.timeOffset = index*.48; animation.repeatCount = HUGE_VALF;
            [effect addAnimation:animation forKey:@"tailPulse"];
        }
    }
    return body;
}

// Finite expressions share the same implementation in the home, studio and floating cursor.
// They affect the artwork, leaving the movement carrier and its route intact.
static void PlayExpression(CALayer *body, NSString *expression, BOOL motion, UIColor *accent) {
    if (!body) return;
    [body removeAnimationForKey:@"expression"];
    for (CALayer *effect in [body.sublayers copy]) {
        if ([effect.name isEqualToString:@"expressionEffect"]) [effect removeFromSuperlayer];
    }
    BOOL allowed = motion && !UIAccessibilityIsReduceMotionEnabled();
    double duration = 1.4;
    NSMutableArray *animations = [NSMutableArray array];
    void (^add)(NSString *, NSArray *) = ^(NSString *key, NSArray *values) {
        CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:key];
        a.values = values; a.calculationMode = kCAAnimationLinear;
        NSMutableArray *easing = [NSMutableArray array];
        for (NSUInteger i=1;i<values.count;i++) [easing addObject:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
        a.timingFunctions = easing;
        [animations addObject:a];
    };
    if (!allowed) {
        add(@"opacity", @[@1,@.70,@1]); duration = .8;
    } else if ([expression isEqualToString:@"thinking"]) {
        duration = 2.4;
        add(@"transform.rotation.z", @[@0,@-.16,@-.16,@.10,@0]);
        add(@"transform.translation.y", @[@0,@(-body.bounds.size.height*.06),@(-body.bounds.size.height*.06),@0,@0]);
    } else if ([expression isEqualToString:@"listening"]) {
        duration = 2.7;
        add(@"transform.scale", @[@1,@1.06,@1,@1.06,@1,@1.06,@1]);
        CALayer *ring = [CALayer layer]; ring.name = @"expressionEffect";
        ring.frame = CGRectInset(body.bounds, body.bounds.size.width*.08, body.bounds.size.height*.08);
        ring.cornerRadius = ring.bounds.size.width/2;
        ring.borderWidth = MAX(1,body.bounds.size.width*.012);
        ring.borderColor = (accent ?: [UIColor colorWithRed:.43 green:.65 blue:.51 alpha:1]).CGColor;
        ring.opacity = 0; [body addSublayer:ring];
        CABasicAnimation *expand = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        expand.fromValue = @.85; expand.toValue = @1.55;
        CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        fade.values = @[@0,@.55,@0];
        CAAnimationGroup *pulse = [CAAnimationGroup animation];
        pulse.animations = @[expand,fade]; pulse.duration = .9; pulse.repeatCount = 3;
        [ring addAnimation:pulse forKey:@"listeningPulse"];
    } else if ([expression isEqualToString:@"celebrate"]) {
        duration = 1.8;
        add(@"transform.translation.y", @[@0,@(-body.bounds.size.height*.24),@0,@(-body.bounds.size.height*.09),@0]);
        add(@"transform.scale.x", @[@1,@.94,@1.12,@.98,@1]);
        add(@"transform.scale.y", @[@1,@1.08,@.90,@1.03,@1]);
        add(@"transform.rotation.z", @[@0,@-.12,@.10,@-.04,@0]);
        for (NSUInteger i=0;i<5;i++) {
            CALayer *spark = [CALayer layer]; spark.name = @"expressionEffect";
            CGFloat d = MAX(2,body.bounds.size.width*.045);
            spark.bounds = CGRectMake(0,0,d,d); spark.cornerRadius = d/2;
            spark.position = CGPointMake(body.bounds.size.width/2,body.bounds.size.height/2);
            spark.backgroundColor = (accent ?: [UIColor colorWithRed:.86 green:.67 blue:.35 alpha:1]).CGColor;
            spark.opacity = 0; [body addSublayer:spark];
            double angle = -M_PI + i*M_PI/4;
            CABasicAnimation *travel = [CABasicAnimation animationWithKeyPath:@"position"];
            travel.fromValue = [NSValue valueWithCGPoint:spark.position];
            travel.toValue = [NSValue valueWithCGPoint:CGPointMake(spark.position.x+cos(angle)*body.bounds.size.width*.70,spark.position.y+sin(angle)*body.bounds.size.height*.70)];
            CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
            fade.values = @[@0,@.8,@0];
            CAAnimationGroup *burst = [CAAnimationGroup animation];
            burst.animations = @[travel,fade]; burst.duration = 1.1;
            [spark addAnimation:burst forKey:@"celebration"];
        }
    } else {
        add(@"transform.rotation.z", @[@0,@-.15,@.16,@-.09,@.04,@0]);
        add(@"transform.scale.y", @[@1,@.91,@1.08,@.97,@1]);
    }
    for (CAAnimation *a in animations) a.duration = duration;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = animations; group.duration = duration;
    [body addAnimation:group forKey:@"expression"];
}

@interface DraftCursorView ()
@property(nonatomic) double configuredSize;
@property(nonatomic) NSInteger configuredStyle;
@property(nonatomic) BOOL configuredMotion;
@property(nonatomic,strong) CALayer *character;
@property(nonatomic,strong) UIImage *configuredImage;
@end
@implementation DraftCursorView
- (void)playExpression:(NSString *)expression {
    PlayExpression(self.character, expression, self.configuredMotion, self.accentColor);
}
- (void)configureWithImage:(UIImage *)image size:(double)size style:(NSInteger)style motion:(BOOL)motion {
    BOOL allowed = motion && !UIAccessibilityIsReduceMotionEnabled();
    if (self.character && self.configuredImage == image && self.configuredSize == size && self.configuredStyle == style && self.configuredMotion == allowed) return;
    [self.character removeFromSuperlayer];
    self.configuredSize = size; self.configuredStyle = style; self.configuredMotion = allowed;
    self.configuredImage = image;
    self.character = CursorLayer(image, size, style, allowed);
    self.character.position = CGPointMake(size/2, size/2);
    [self.layer addSublayer:self.character]; self.userInteractionEnabled = NO;
}
@end

// Adapted from this repository's visually verified TappLab SharedRenderer.
// Compile out of phone builds: these private developer APIs are NOT a phone
// overlay implementation and do not acquire restricted entitlements.
@interface DraftRocketRenderer ()
@property(nonatomic,strong) id context;
@property(nonatomic,strong) CALayer *root;
@property(nonatomic,strong) CALayer *character;
@property(nonatomic,strong) CALayer *expressionBody;
@property(nonatomic) BOOL followsHeading;
@property(nonatomic) BOOL motionEnabled;
@property(nonatomic,strong) CALayer *tail;
@property(nonatomic,strong) CALayer *greeting;
@property(nonatomic,strong) NSArray<CALayer *> *trail;
@property(nonatomic) NSInteger style;
@property(nonatomic) CFTimeInterval motionStart;
@property(nonatomic) double motionDuration;
@property(nonatomic) BOOL flight;
@property(nonatomic) CFTimeInterval previewEnd;
@property(nonatomic,copy) NSString *islandAction;
@property(nonatomic,strong) CAShapeLayer *islandRipple;
@end

@implementation DraftRocketRenderer
- (BOOL)startWithImage:(UIImage *)image pointSize:(double)pointSize style:(NSInteger)style motion:(BOOL)motion error:(NSError **)error {
    if (self.context) return YES;
    NSString *failure = nil;
    if (![NSProcessInfo.processInfo.environment[@"SIMULATOR_UDID"] isEqualToString:@"8B65F7CB-757A-43EA-BC00-A1A3A195E051"]) {
        failure = @"Tapp's developer renderer is restricted to the dedicated iPhone Air simulator.";
    } else {
        void *quartz = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_NOW);
        Class displayClass = NSClassFromString(@"CADisplay"), contextClass = NSClassFromString(@"CAContext");
        if ([displayClass respondsToSelector:NSSelectorFromString(@"mainDisplay")] &&
            [contextClass respondsToSelector:NSSelectorFromString(@"remoteContextWithOptions:")]) {
            @try {
                id display = ((id (*)(id,SEL))objc_msgSend)(displayClass,NSSelectorFromString(@"mainDisplay"));
                unsigned displayID = ((unsigned (*)(id,SEL))objc_msgSend)(display,NSSelectorFromString(@"displayId"));
                CGRect bounds = ((CGRect (*)(id,SEL))objc_msgSend)(display,NSSelectorFromString(@"bounds"));
                NSMutableDictionary *options = [NSMutableDictionary dictionary];
                for (NSString *symbol in @[@"kCAContextDisplayId",@"kCAContextDisplayable",@"kCAContextIgnoresHitTest"]) {
                    NSString *__unsafe_unretained *key = quartz ? (NSString *__unsafe_unretained *)dlsym(quartz,symbol.UTF8String) : NULL;
                    if (!key || !*key) { failure = @"Simulator display options unavailable."; break; }
                    options[*key] = [symbol isEqualToString:@"kCAContextDisplayId"] ? @(displayID) : @YES;
                }
                if (!failure && displayID && bounds.size.width > 0 && bounds.size.height > 0) {
                    self.context = ((id (*)(id,SEL,id))objc_msgSend)(contextClass,NSSelectorFromString(@"remoteContextWithOptions:"),options);
                    if (!self.context) failure = @"Simulator returned no displayable context.";
                    else {
                        ((void (*)(id,SEL,float))objc_msgSend)(self.context,NSSelectorFromString(@"setLevel:"),10000010.0f);
                        self.root = [CALayer layer]; self.root.frame = bounds;
                        CGFloat points = isfinite(pointSize) ? MAX(28, MIN(56, pointSize)) : 32;
                        CGFloat pixelsPerPoint = bounds.size.width / UIScreen.mainScreen.bounds.size.width;
                        CGFloat side = points * pixelsPerPoint;
                        self.motionEnabled = motion && !UIAccessibilityIsReduceMotionEnabled();
                        self.followsHeading = (style == 0 || style == 2) && self.motionEnabled;
                        self.style = style;
                        // Travel rotates a carrier, while the child retains its tiny
                        // independent wiggle. Rotate the original upper-left nose
                        // onto +X first, so path-tangent rotation points it forwards.
                        self.character = [CALayer layer];
                        self.character.bounds = CGRectMake(0, 0, side, side);
                        CALayer *alignment = [CALayer layer];
                        alignment.bounds = self.character.bounds;
                        alignment.position = CGPointMake(side/2, side/2);
                        alignment.transform = CATransform3DMakeRotation(self.followsHeading ? 3*M_PI/4 : 0, 0, 0, 1);
                        CALayer *artwork = CursorLayer(image, side, style, motion);
                        self.expressionBody = artwork;
                        // The tour owns the complete expression envelope. Rest is still.
                        [artwork removeAnimationForKey:@"gentleWiggle"];
                        artwork.position = CGPointMake(side/2, side/2);
                        for (CALayer *child in artwork.sublayers) if ([child.name isEqualToString:@"tailEffects"]) self.tail = child;
                        [alignment addSublayer:artwork];
                        [self.character addSublayer:alignment];
                        self.greeting = [CALayer layer];
                        self.greeting.frame = self.character.bounds;
                        self.greeting.opacity = 0;
                        for (NSInteger i=0; i<2; i++) {
                            CAShapeLayer *spark = [CAShapeLayer layer];
                            CGFloat r = side*.075;
                            UIBezierPath *star = [UIBezierPath bezierPath];
                            [star moveToPoint:CGPointMake(0,-r)];
                            [star addLineToPoint:CGPointMake(r*.28,-r*.28)];
                            [star addLineToPoint:CGPointMake(r,0)];
                            [star addLineToPoint:CGPointMake(r*.28,r*.28)];
                            [star addLineToPoint:CGPointMake(0,r)];
                            [star addLineToPoint:CGPointMake(-r*.28,r*.28)];
                            [star addLineToPoint:CGPointMake(-r,0)];
                            [star addLineToPoint:CGPointMake(-r*.28,-r*.28)];
                            [star closePath];
                            spark.path = star.CGPath;
                            spark.position = CGPointMake(side*(i ? .87 : .12),side*(i ? .16 : .30));
                            spark.fillColor = (self.accentColor ?: [UIColor colorWithRed:.60 green:.70 blue:.44 alpha:1]).CGColor;
                            [self.greeting addSublayer:spark];
                        }
                        [self.character addSublayer:self.greeting];
                        self.character.position = [self dockPoint];
                        self.character.transform = CATransform3DMakeRotation(self.followsHeading ? -3*M_PI/4 : 0,0,0,1);
                        self.character.opacity = 0; // A finite explicit tour owns visibility.
                        NSMutableArray *bubbles = [NSMutableArray array];
                        for (NSUInteger i=0;i<3;i++) {
                            CALayer *bubble = [CALayer layer];
                            CGFloat diameter = side*(.14-i*.032);
                            bubble.bounds = CGRectMake(0,0,diameter,diameter);
                            bubble.cornerRadius = diameter/2;
                            bubble.backgroundColor = (self.accentColor ?: [UIColor colorWithRed:.67 green:.76 blue:.54 alpha:1]).CGColor;
                            bubble.opacity = 0;
                            [self.root addSublayer:bubble];
                            [bubbles addObject:bubble];
                        }
                        self.trail = bubbles;
                        if (self.islandHome) {
                            CGFloat uiScale = bounds.size.width / UIScreen.mainScreen.bounds.size.width;
                            self.islandRipple = [CAShapeLayer layer];
                            CGRect capsule = CGRectMake(0,0,128*uiScale,38*uiScale);
                            self.islandRipple.bounds = capsule;
                            self.islandRipple.position = [self islandPoint];
                            self.islandRipple.path = [UIBezierPath bezierPathWithRoundedRect:capsule cornerRadius:19*uiScale].CGPath;
                            self.islandRipple.fillColor = UIColor.clearColor.CGColor;
                            self.islandRipple.strokeColor = (self.accentColor ?: [UIColor colorWithRed:.54 green:.72 blue:.61 alpha:1]).CGColor;
                            self.islandRipple.lineWidth = 1.3*uiScale;
                            self.islandRipple.opacity = 0;
                            [self.root addSublayer:self.islandRipple];
                        }
                        [self.root addSublayer:self.character];
                        ((void (*)(id,SEL,id))objc_msgSend)(self.context,NSSelectorFromString(@"setLayer:"),self.root);
                        [CATransaction flush];
                        // The display association is established by the first
                        // layer commit, not merely by constructing the context.
                        unsigned attached = ((unsigned (*)(id,SEL))objc_msgSend)(self.context,NSSelectorFromString(@"displayId"));
                        BOOL valid = ((BOOL (*)(id,SEL))objc_msgSend)(self.context,NSSelectorFromString(@"valid"));
                        if (valid && attached == displayID) return YES;
                        failure = @"Simulator refused to attach Tapp's display layer.";
                    }
                }
            } @catch (NSException *exception) { failure = exception.reason; }
        }
    }
    [self invalidate];
    if (error) *error = [NSError errorWithDomain:@"SimulatorTapp" code:1 userInfo:@{NSLocalizedDescriptionKey:failure ?: @"Simulator display renderer unavailable."}];
    return NO;
}
static CGPoint CubicPoint(CGPoint a, CGPoint b, CGPoint c, CGPoint d, double t) {
    double u=1-t;
    return CGPointMake(u*u*u*a.x+3*u*u*t*b.x+3*u*t*t*c.x+t*t*t*d.x,
                       u*u*u*a.y+3*u*u*t*b.y+3*u*t*t*c.y+t*t*t*d.y);
}
static double NearestAngle(double angle, double reference) {
    return reference + atan2(sin(angle-reference), cos(angle-reference));
}
- (CGPoint)islandPoint {
    CGFloat scale = self.root.bounds.size.width / UIScreen.mainScreen.bounds.size.width;
    return CGPointMake(self.root.bounds.size.width*.5, 36*scale);
}
- (CGPoint)dockPoint {
    if (self.islandHome) {
        CGFloat scale = self.root.bounds.size.width / UIScreen.mainScreen.bounds.size.width;
        CGPoint island = [self islandPoint];
        return CGPointMake(island.x+20*scale,island.y+32*scale);
    }
    return CGPointMake(self.root.bounds.size.width*.94, self.root.bounds.size.height*.32);
}
- (void)beginTourForDuration:(double)duration motion:(BOOL)motion {
    if (!self.character) return;
    self.previewEnd = CACurrentMediaTime() + duration;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.root.opacity = 0;
    self.character.position = [self dockPoint]; self.character.opacity = .65;
    self.character.transform = CATransform3DMakeRotation(self.followsHeading ? -3*M_PI/4 : 0,0,0,1);
    [CATransaction commit];
    // Visibility belongs to the whole preview, independently of wake/rest.
    // Repeated wake requests cannot extend the three-minute draft lifetime.
    CAKeyframeAnimation *lifetime = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    lifetime.values = @[@1,@1,@0]; lifetime.keyTimes = @[@0,@((duration-2)/duration),@1]; lifetime.duration = duration;
    [self.root addAnimation:lifetime forKey:@"previewLifetime"];
    [self wake];
}
- (void)wake { [self animateToRestAfterFlight:YES]; }
- (void)playExpression:(NSString *)expression {
    if (!self.character || CACurrentMediaTime() >= self.previewEnd-2) return;
    CALayer *shown = self.character.presentationLayer ?: self.character;
    if (self.islandHome && shown.opacity < .05) {
        [self playIslandAction:@"pop"];
        __weak DraftRocketRenderer *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.05*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DraftRocketRenderer *strongSelf = weakSelf;
            if (strongSelf.context && CACurrentMediaTime()<strongSelf.previewEnd-2)
                PlayExpression(strongSelf.expressionBody, expression, strongSelf.motionEnabled, strongSelf.accentColor);
        });
        return;
    }
    PlayExpression(self.expressionBody, expression, self.motionEnabled, self.accentColor);
}
- (void)playIslandAction:(NSString *)action {
    if (!self.character || CACurrentMediaTime() >= self.previewEnd-2) return;
    if ([action isEqualToString:@"arrive"]) {
        [self animateToRestAfterFlight:NO];
        return;
    }
    CALayer *shown = self.character.presentationLayer ?: self.character;
    CGPoint from = shown.position, home = [self islandPoint];
    CGFloat scale = self.root.bounds.size.width / UIScreen.mainScreen.bounds.size.width;
    CGPoint peek = CGPointMake(home.x+24*scale, home.y+48*scale);
    BOOL hide = [action isEqualToString:@"hide"], pop = [action isEqualToString:@"pop"];
    BOOL animated = self.motionEnabled && !UIAccessibilityIsReduceMotionEnabled();
    double duration = animated ? (hide ? .85 : pop ? 1.0 : 2.8) : .3;
    CGFloat alpha = shown.opacity;
    if (alpha < .05 && !hide) from = home;
    CGPoint final = pop ? peek : home;
    self.motionStart = CACurrentMediaTime(); self.motionDuration = duration; self.flight = NO;
    self.islandAction = hide ? @"hiding" : pop ? @"popping" : @"peeking";
    NSMutableArray *positions = [NSMutableArray array], *opacity = [NSMutableArray array], *sizes = [NSMutableArray array], *angles = [NSMutableArray array];
    double rest = self.followsHeading ? -3*M_PI/4 : 0;
    for (NSUInteger i=0;i<=168;i++) {
        double t = i/168.0, mix;
        CGPoint p;
        CGFloat a, s;
        if (hide) {
            mix = Smooth(t); p = CGPointMake(from.x+(home.x-from.x)*mix, from.y+(home.y-from.y)*mix);
            a = alpha*(1-Smooth((t-.42)/.58)); s = 1-.65*mix;
        } else if (pop) {
            mix = Smooth(MIN(1,t/.85)); p = CGPointMake(from.x+(peek.x-from.x)*mix, from.y+(peek.y-from.y)*mix);
            p.y -= sin(M_PI*t)*5*scale;
            a = alpha+(1-alpha)*Smooth(t/.45); s = .4+.6*mix+.07*sin(M_PI*t);
        } else {
            double out = Smooth(t/.24), back = Smooth((t-.72)/.28);
            p = CGPointMake(from.x+(peek.x-from.x)*out, from.y+(peek.y-from.y)*out);
            p = CGPointMake(p.x+(home.x-p.x)*back,p.y+(home.y-p.y)*back);
            a = (alpha+(1-alpha)*Smooth(t/.20))*(1-back); s = .45+.55*out-.65*back;
        }
        if (!animated) { p = final; s = 1; a = pop ? Smooth(t) : alpha*(1-Smooth(t)); }
        [positions addObject:[NSValue valueWithCGPoint:p]]; [opacity addObject:@(a)]; [sizes addObject:@(s)];
        double curiosity = !hide && !pop && animated ? .14*sin(4*M_PI*t)*sin(M_PI*t) : 0;
        [angles addObject:@(rest+curiosity)];
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    [self.character removeAllAnimations]; [self.expressionBody removeAnimationForKey:@"expression"];
    [self.tail removeAnimationForKey:@"engineState"]; self.tail.opacity = 0;
    for (CALayer *bubble in self.trail) { [bubble removeAllAnimations]; bubble.opacity=0; }
    self.character.position = final; self.character.opacity = pop ? 1 : 0;
    self.character.transform = CATransform3DMakeRotation(rest,0,0,1);
    NSMutableArray *animations = [NSMutableArray array];
    NSArray *keys = @[@"position",@"opacity",@"transform.scale",@"transform.rotation.z"];
    NSArray *values = @[positions,opacity,sizes,angles];
    for (NSUInteger i=0;i<keys.count;i++) {
        CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:keys[i]];
        a.values = values[i]; a.duration = duration; a.calculationMode=kCAAnimationLinear;
        [animations addObject:a];
    }
    CAAnimationGroup *animation=[CAAnimationGroup animation]; animation.animations=animations; animation.duration=duration;
    [self.character addAnimation:animation forKey:@"islandVisit"];
    [CATransaction commit]; [CATransaction flush];
}
- (void)settle { [self animateToRestAfterFlight:NO]; }
- (CGRect)interactionRect {
    // UIKit receives touches only in Tapp's own active scene. The external
    // CAContext deliberately remains noninteractive over other applications.
    if (!self.character || CACurrentMediaTime() >= self.previewEnd-2) return CGRectNull;
    CALayer *shown = self.character.presentationLayer ?: self.character;
    CGFloat scale = self.root.bounds.size.width / UIScreen.mainScreen.bounds.size.width;
    CGPoint point = CGPointMake(shown.position.x/scale, shown.position.y/scale);
    CGFloat side = MAX(44, self.character.bounds.size.width/scale);
    return CGRectIntersection(CGRectMake(point.x-side/2, point.y-side/2, side, side), UIScreen.mainScreen.bounds);
}
static double Smooth(double t) { t=MAX(0,MIN(1,t)); return t*t*t*(t*(t*6-15)+10); }
- (NSString *)motionPhase {
    if (!self.motionEnabled) return @"quiet";
    double elapsed=CACurrentMediaTime()-self.motionStart;
    if (self.islandAction && elapsed<self.motionDuration) return self.islandAction;
    if (elapsed>=self.motionDuration) return self.character.opacity < .05 ? @"hidden" : @"resting";
    if (!self.flight) return @"landing";
    if (elapsed<.65) return @"waking";
    return elapsed>=self.motionDuration-2.45 ? @"landing" : @"flying";
}
- (void)animateToRestAfterFlight:(BOOL)flight {
    if (!self.character || CACurrentMediaTime() >= self.previewEnd) return;
    self.islandAction = nil;
    BOOL animated = self.motionEnabled && !UIAccessibilityIsReduceMotionEnabled();
    CALayer *shown = self.character.presentationLayer ?: self.character;
    CGPoint start = shown.position, dock = [self dockPoint];
    BOOL alreadyDocked = !flight && hypot(dock.x-start.x,dock.y-start.y)<1;
    double startOpacity=shown.opacity;
    CATransform3D transform=shown.transform;
    double heading=atan2(transform.m12,transform.m11);
    double initialScaleX=hypot(transform.m11,transform.m12);
    double initialScaleY=hypot(transform.m21,transform.m22);
    double restHeading=self.followsHeading ? -3*M_PI/4 : 0;
    double tailOpacity=(self.tail.presentationLayer ?: self.tail).opacity;
    CGSize screen=self.root.bounds.size;
    double greetingTime=animated && flight ? .65 : 0;
    double travelTime=animated ? (flight ? 8.8 : 2.2) : .3;
    double landingTime=animated && !alreadyDocked ? (self.islandHome ? 1.5 : .75) : 0;
    double duration=greetingTime+travelTime+landingTime;
    duration=MIN(duration,self.previewEnd-CACurrentMediaTime());
    self.motionStart=CACurrentMediaTime(); self.motionDuration=duration; self.flight=flight;

    CGFloat reach=flight ? screen.width*.12 : MIN(screen.width*.10,MAX(12,hypot(dock.x-start.x,dock.y-start.y)*.35));
    // Classic stays upright, so its visual bank is not a flight heading.
    double departureHeading=self.followsHeading ? heading : -3*M_PI/4;
    CGPoint first=CGPointMake(start.x+cos(departureHeading)*reach,start.y+sin(departureHeading)*reach);
    first.x=MAX(screen.width*(self.islandHome ? .44 : .76),MIN(screen.width*.96,first.x));
    first.y=MAX(screen.height*(self.islandHome ? .025 : .23),MIN(screen.height*.73,first.y));
    CGPoint away=CGPointMake(screen.width*.83,screen.height*.60);
    CGPoint control=CGPointMake(screen.width*.75,screen.height*.51);
    // Mirrored control points keep the two curves tangent at their join.
    CGPoint outbound=CGPointMake(2*away.x-control.x,2*away.y-control.y);
    CGPoint inbound=CGPointMake(dock.x,dock.y+screen.height*.09);
    NSMutableArray<NSValue *> *raw=[NSMutableArray array];
    double distances[401]; distances[0]=0;
    for (NSUInteger i=0;i<=400;i++) {
        double u=i/400.0; CGPoint point;
        if (!animated || alreadyDocked) point=dock;
        else if (flight && u<.5) point=CubicPoint(start,first,control,away,u*2);
        else if (flight) point=CubicPoint(away,outbound,inbound,dock,(u-.5)*2);
        else point=CubicPoint(start,first,inbound,dock,u);
        [raw addObject:[NSValue valueWithCGPoint:point]];
        if(i) { CGPoint a=raw[i-1].CGPointValue; distances[i]=distances[i-1]+hypot(point.x-a.x,point.y-a.y); }
    }
    NSUInteger samples=MAX(2,(NSUInteger)ceil(duration*60));
    NSMutableArray *positions=[NSMutableArray array], *headings=[NSMutableArray array];
    NSMutableArray *scaleX=[NSMutableArray array], *scaleY=[NSMutableArray array];
    NSMutableArray *opacity=[NSMutableArray array], *engineValues=[NSMutableArray array];
    double previous=heading;
    for (NSUInteger i=0;i<=samples;i++) {
        double seconds=duration*i/samples;
        double t=MAX(0,MIN(1,(seconds-greetingTime)/travelTime));
        double target=Smooth(t)*distances[400];
        NSUInteger j=1; while(j<400 && distances[j]<target)j++;
        CGPoint a=raw[j-1].CGPointValue,b=raw[j].CGPointValue;
        double span=distances[j]-distances[j-1],mix=span>0?(target-distances[j-1])/span:0;
        CGPoint point=CGPointMake(a.x+(b.x-a.x)*mix,a.y+(b.y-a.y)*mix);
        double angle=restHeading,sx=1,sy=1;
        if(animated && !alreadyDocked) {
            double tangent=atan2(b.y-a.y,b.x-a.x);
            double desired=self.followsHeading ? NearestAngle(tangent,previous) : -.10*cos(tangent);
            // Low-pass the turn and capture the current presentation pose on interruption.
            angle=previous+(NearestAngle(desired,previous)-previous)*.11;
            double arrival=Smooth((t-.80)/.20);
            angle+=(NearestAngle(restHeading,angle)-angle)*arrival;
            if(seconds<greetingTime) {
                double g=seconds/greetingTime;
                point=start;
                // A small compress / release and two damped happy turns.
                double expression=sin(2*M_PI*g)*sin(M_PI*g);
                sx=1+.10*expression; sy=1-.12*expression;
                angle=heading+.14*sin(4*M_PI*g)*sin(M_PI*g);
            } else if(seconds>greetingTime+travelTime && landingTime>0) {
                double land=MIN(1,(seconds-greetingTime-travelTime)/landingTime);
                double bounce=sin(M_PI*land)*pow(1-land,2);
                point=dock; point.y-=self.character.bounds.size.height*.22*bounce;
                sx=1+.065*sin(2*M_PI*land)*pow(1-land,2);
                sy=1-.085*sin(2*M_PI*land)*pow(1-land,2);
                angle=NearestAngle(restHeading,previous);
                if (self.islandHome) {
                    // Arrive visibly below the Island, compress, bounce, then tuck inside.
                    double impact = sin(M_PI*MIN(1,land/.42))*pow(1-MIN(1,land/.42),.5);
                    sx = 1+.18*impact; sy = 1-.22*impact;
                    double tuck = Smooth((land-.50)/.50);
                    CGPoint island = [self islandPoint];
                    point.x += (island.x-point.x)*tuck; point.y += (island.y-point.y)*tuck;
                    sx *= 1-.65*tuck; sy *= 1-.65*tuck;
                }
            }
            double blend=Smooth(seconds/.18);
            sx=initialScaleX+(sx-initialScaleX)*blend;
            sy=initialScaleY+(sy-initialScaleY)*blend;
        }
        double visible=flight ? startOpacity+(1-startOpacity)*Smooth(seconds/.35) : startOpacity;
        double fade=Smooth((seconds-(greetingTime+travelTime-.9))/(.9+landingTime));
        visible+=((self.islandHome ? 0 : .65)-visible)*fade;
        if (self.islandHome && animated && landingTime>0) {
            visible = startOpacity+(1-startOpacity)*Smooth(seconds/.35);
            visible *= 1-Smooth((seconds-(greetingTime+travelTime+landingTime*.55))/(landingTime*.45));
        }
        double engine=animated && flight ? (tailOpacity+(1-tailOpacity)*Smooth(seconds/.8))*(1-Smooth((t-.72)/.28)) : tailOpacity*(1-Smooth(seconds/.4));
        if(!animated) { point=dock; angle=restHeading; sx=1; sy=1; engine=0; visible=.65+.16*sin(M_PI*seconds/duration); }
        [positions addObject:[NSValue valueWithCGPoint:point]]; [headings addObject:@(angle)];
        [scaleX addObject:@(sx)]; [scaleY addObject:@(sy)]; [opacity addObject:@(visible)]; [engineValues addObject:@(engine)];
        previous=angle;
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    [self.character removeAllAnimations]; [self.tail removeAnimationForKey:@"engineState"];
    [self.greeting removeAllAnimations];
    self.character.position=self.islandHome ? [self islandPoint] : dock; self.character.transform=CATransform3DMakeRotation(restHeading,0,0,1);
    self.character.opacity=self.islandHome ? 0 : .65; self.tail.opacity=0; self.greeting.opacity=0;
    NSMutableArray *animations=[NSMutableArray array];
    NSArray *keys=@[@"position",@"transform.rotation.z",@"transform.scale.x",@"transform.scale.y",@"opacity"];
    NSArray *values=@[positions,headings,scaleX,scaleY,opacity];
    for(NSUInteger i=0;i<keys.count;i++) {
        CAKeyframeAnimation *animation=[CAKeyframeAnimation animationWithKeyPath:keys[i]];
        animation.values=values[i]; animation.duration=duration; animation.calculationMode=kCAAnimationLinear;
        [animations addObject:animation];
    }
    CAAnimationGroup *trip=[CAAnimationGroup animation]; trip.animations=animations; trip.duration=duration;
    [self.character addAnimation:trip forKey:@"petTrip"];
    [self.islandRipple removeAllAnimations];
    if (animated && self.islandHome && !alreadyDocked) {
        CAKeyframeAnimation *glow = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        glow.values = @[@0,@.55,@0];
        CAKeyframeAnimation *stretch = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
        stretch.values = @[@1,@1.06,@1];
        CAAnimationGroup *welcome = [CAAnimationGroup animation];
        welcome.animations = @[glow,stretch]; welcome.duration = 1.3;
        welcome.beginTime = [self.root convertTime:CACurrentMediaTime() fromLayer:nil]+greetingTime+travelTime;
        [self.islandRipple addAnimation:welcome forKey:@"islandWelcome"];
    }
    CAKeyframeAnimation *engine=[CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    engine.values=engineValues; engine.duration=duration; [self.tail addAnimation:engine forKey:@"engineState"];
    // Three delayed samples of the actual flight path form a short bubble tail.
    // They have no hit regions, and dissolve as speed drops approaching the perch.
    for (NSUInteger bubbleIndex=0;bubbleIndex<self.trail.count;bubbleIndex++) {
        CALayer *bubble=self.trail[bubbleIndex];
        [bubble removeAllAnimations]; bubble.opacity=0;
        NSMutableArray *trailPositions=[NSMutableArray array], *trailOpacity=[NSMutableArray array];
        NSUInteger lag=(NSUInteger)round((.12+bubbleIndex*.12)*samples/duration);
        for(NSUInteger i=0;i<positions.count;i++) {
            NSUInteger delayed=i>lag?i-lag:0;
            CGPoint point=[positions[delayed] CGPointValue];
            CGPoint current=[positions[i] CGPointValue];
            // Hide bubbles inside the artwork; fade in only as they fall behind.
            double separation=hypot(current.x-point.x,current.y-point.y)/self.character.bounds.size.width;
            double reveal=Smooth((separation-.22)/.35);
            double seconds=duration*i/samples;
            double fade=1-Smooth((seconds-(greetingTime+travelTime-1.1))/1.1);
            double alpha=animated ? (.42-bubbleIndex*.09)*reveal*fade : 0;
            [trailPositions addObject:[NSValue valueWithCGPoint:point]];
            [trailOpacity addObject:@(alpha)];
        }
        CAKeyframeAnimation *follow=[CAKeyframeAnimation animationWithKeyPath:@"position"];
        follow.values=trailPositions; follow.duration=duration;
        CAKeyframeAnimation *dissolve=[CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        dissolve.values=trailOpacity; dissolve.duration=duration;
        CAAnimationGroup *trailAnimation=[CAAnimationGroup animation];
        trailAnimation.animations=@[follow,dissolve]; trailAnimation.duration=duration;
        [bubble addAnimation:trailAnimation forKey:@"flightBubbles"];
    }
    if(animated && flight) {
        CAKeyframeAnimation *spark=[CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        spark.values=@[@0,@.8,@0]; spark.keyTimes=@[@0,@.35,@1]; spark.duration=.8;
        [self.greeting addAnimation:spark forKey:@"helloTwinkle"];
    }
    [CATransaction commit]; [CATransaction flush];
}
- (void)invalidate {
    if (self.context) ((void (*)(id,SEL))objc_msgSend)(self.context,NSSelectorFromString(@"invalidate"));
    self.context = nil; self.root = nil; self.character = nil; self.expressionBody = nil; self.islandRipple = nil; self.tail = nil; self.greeting = nil; self.trail = nil; self.previewEnd = 0;
}
- (void)dealloc { [self invalidate]; }
@end
#endif
