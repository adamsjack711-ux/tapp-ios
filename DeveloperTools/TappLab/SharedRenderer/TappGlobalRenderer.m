#import "TappGlobalRenderer.h"
#import <objc/message.h>
#import <dlfcn.h>

@interface TappGlobalRenderer ()
@property(nonatomic,strong) id context;
@property(nonatomic,strong) CALayer *root;
@property(nonatomic,strong) CALayer *character;
@property(nonatomic,strong) NSArray<CALayer *> *eyes;
@property(nonatomic,readwrite) unsigned contextIdentifier;
@property(nonatomic,readwrite) CGRect displayBounds;
@property(nonatomic,readwrite) NSDictionary *diagnostics;
@end

@implementation TappGlobalRenderer
- (BOOL)start:(NSError **)error {
    [self invalidate];
    void *quartz = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_NOW);
    Class displayClass = NSClassFromString(@"CADisplay");
    Class contextClass = NSClassFromString(@"CAContext");
    if (![displayClass respondsToSelector:NSSelectorFromString(@"mainDisplay")] || ![contextClass respondsToSelector:NSSelectorFromString(@"remoteContextWithOptions:")]) {
        if (error) *error = [NSError errorWithDomain:@"TappRenderer" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Global renderer interfaces unavailable"}];
        return NO;
    }
    id display = ((id (*)(id,SEL))objc_msgSend)(displayClass, NSSelectorFromString(@"mainDisplay"));
    unsigned displayID = ((unsigned (*)(id,SEL))objc_msgSend)(display, NSSelectorFromString(@"displayId"));
    self.displayBounds = ((CGRect (*)(id,SEL))objc_msgSend)(display, NSSelectorFromString(@"bounds"));
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    for (NSString *symbol in @[@"kCAContextDisplayId", @"kCAContextDisplayable", @"kCAContextIgnoresHitTest"]) {
        NSString *__unsafe_unretained *key = quartz ? (NSString *__unsafe_unretained *)dlsym(quartz, symbol.UTF8String) : NULL;
        if (!key || !*key) {
            if (error) *error = [NSError errorWithDomain:@"TappRenderer" code:2 userInfo:@{NSLocalizedDescriptionKey:[@"Missing context option: " stringByAppendingString:symbol]}];
            return NO;
        }
        options[*key] = [symbol isEqualToString:@"kCAContextDisplayId"] ? @(displayID) : @YES;
    }
    @try {
        BOOL local = [NSProcessInfo.processInfo.arguments containsObject:@"--local-context"];
        SEL creator = NSSelectorFromString(local ? @"localContextWithOptions:" : @"remoteContextWithOptions:");
        self.context = ((id (*)(id,SEL,id))objc_msgSend)(contextClass, creator, options);
        if (!self.context) {
            if (error) *error = [NSError errorWithDomain:@"TappRenderer" code:3 userInfo:@{NSLocalizedDescriptionKey:@"System returned no displayable context"}];
            return NO;
        }
        ((void (*)(id,SEL,float))objc_msgSend)(self.context, NSSelectorFromString(@"setLevel:"), 10000010.0f);
        self.root = [CALayer layer];
        self.root.frame = self.displayBounds;
        self.character = [self makeCharacter];
        [self.root addSublayer:self.character];
        [self park];
        ((void (*)(id,SEL,id))objc_msgSend)(self.context, NSSelectorFromString(@"setLayer:"), self.root);
        [CATransaction flush];
        self.contextIdentifier = ((unsigned (*)(id,SEL))objc_msgSend)(self.context, NSSelectorFromString(@"contextId"));
        NSDictionary *actualOptions = ((id (*)(id,SEL))objc_msgSend)(self.context, NSSelectorFromString(@"options"));
        unsigned actualDisplay = ((unsigned (*)(id,SEL))objc_msgSend)(self.context, NSSelectorFromString(@"displayId"));
        float actualLevel = ((float (*)(id,SEL))objc_msgSend)(self.context, NSSelectorFromString(@"level"));
        self.diagnostics = @{@"actualOptions":actualOptions ?: @{}, @"actualDisplayID":@(actualDisplay),@"actualLevel":@(actualLevel),@"contextID":@(self.contextIdentifier),@"contextValid":@(self.contextValid),@"displayID":@(displayID),@"bounds":NSStringFromCGRect(self.displayBounds),@"options":options,@"visualVisibilityRequiresExternalVerification":@YES};
        return self.contextValid;
    } @catch (NSException *exception) {
        if (error) *error = [NSError errorWithDomain:@"TappRenderer" code:4 userInfo:@{NSLocalizedDescriptionKey:exception.reason ?: exception.name}];
        [self invalidate];
        return NO;
    }
}
- (CALayer *)makeCharacter {
    CALayer *body = [CALayer layer];
    body.bounds = CGRectMake(0,0,90,90);
    body.cornerRadius = 38;
    body.backgroundColor = [UIColor colorWithRed:0.28 green:0.94 blue:0.76 alpha:1].CGColor;
    body.borderColor = [UIColor colorWithRed:0.04 green:0.24 blue:0.22 alpha:1].CGColor;
    body.borderWidth = 3;
    body.shadowColor = UIColor.blackColor.CGColor;
    body.shadowOpacity = 0.24;
    body.shadowRadius = 9;
    body.shadowOffset = CGSizeMake(0,4);
    NSMutableArray *eyes = [NSMutableArray array];
    for (NSNumber *x in @[@28,@55]) {
        CALayer *eye = [CALayer layer];
        eye.frame = CGRectMake(x.doubleValue,29,11,19);
        eye.cornerRadius = 5.5;
        eye.backgroundColor = [UIColor colorWithRed:0.04 green:0.22 blue:0.21 alpha:1].CGColor;
        [body addSublayer:eye];
        CALayer *sparkle = [CALayer layer];
        sparkle.frame = CGRectMake(2,3,3,5);
        sparkle.cornerRadius = 1.5;
        sparkle.backgroundColor = UIColor.whiteColor.CGColor;
        [eye addSublayer:sparkle];
        CAKeyframeAnimation *blink = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale.y"];
        blink.values = @[@1,@1,@0.12,@1,@1];
        blink.keyTimes = @[@0,@0.79,@0.82,@0.85,@1];
        blink.duration = 4.6;
        blink.repeatCount = HUGE_VALF;
        [eye addAnimation:blink forKey:@"blink"];
        [eyes addObject:eye];
    }
    self.eyes = eyes;
    CAShapeLayer *smile = [CAShapeLayer layer];
    UIBezierPath *mouth = [UIBezierPath bezierPath];
    [mouth moveToPoint:CGPointMake(39,56)];
    [mouth addQuadCurveToPoint:CGPointMake(51,56) controlPoint:CGPointMake(45,63)];
    smile.path = mouth.CGPath;
    smile.strokeColor = [UIColor colorWithRed:0.04 green:0.22 blue:0.21 alpha:1].CGColor;
    smile.fillColor = nil;
    smile.lineWidth = 3;
    smile.lineCap = kCALineCapRound;
    [body addSublayer:smile];
    for (NSNumber *x in @[@14,@65]) {
        CALayer *cheek = [CALayer layer];
        cheek.frame = CGRectMake(x.doubleValue,49,12,7);
        cheek.cornerRadius = 3.5;
        cheek.backgroundColor = [UIColor colorWithRed:1 green:0.55 blue:0.63 alpha:0.70].CGColor;
        [body addSublayer:cheek];
    }
    return body;
}
- (BOOL)contextValid {
    return self.context && ((BOOL (*)(id,SEL))objc_msgSend)(self.context, NSSelectorFromString(@"valid"));
}
- (unsigned)attachedDisplayIdentifier {
    return self.context ? ((unsigned (*)(id,SEL))objc_msgSend)(self.context, NSSelectorFromString(@"displayId")) : 0;
}
- (void)moveToNormalizedPoint:(CGPoint)point {
    if (!isfinite(point.x) || !isfinite(point.y) || !self.character) return;
    CGRect bounds = self.displayBounds;
    double x = MAX(48, MIN(CGRectGetWidth(bounds)-48, point.x*CGRectGetWidth(bounds)));
    double y = MAX(48, MIN(CGRectGetHeight(bounds)-48, point.y*CGRectGetHeight(bounds)));
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.55];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    self.character.position = CGPointMake(x,y);
    [CATransaction commit];
    [CATransaction flush];
}
- (void)park { [self moveToNormalizedPoint:CGPointMake(0.5,0.5)]; }
- (void)invalidate {
    if (self.context) ((void (*)(id,SEL))objc_msgSend)(self.context, NSSelectorFromString(@"invalidate"));
    self.context = nil;
    self.root = nil;
    self.character = nil;
    self.eyes = nil;
    self.contextIdentifier = 0;
}
- (void)dealloc { [self invalidate]; }
@end
