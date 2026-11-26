#import <UIKit/UIKit.h>

@interface TouchWindow : UIWindow
@property(nonatomic,copy) void (^recordEvent)(NSDictionary *);
@end
@implementation TouchWindow
- (void)sendEvent:(UIEvent *)event {
    for (UITouch *touch in event.allTouches) {
        if (touch.phase==UITouchPhaseStationary || touch.phase==UITouchPhaseMoved) continue;
        CGPoint point=[touch locationInView:self];
        if (self.recordEvent) self.recordEvent(@{@"event":@"window-touch",@"phase":@(touch.phase),
            @"x":@(point.x/self.bounds.size.width),@"y":@(point.y/self.bounds.size.height),
            @"time":@([NSDate.date timeIntervalSince1970])});
    }
    [super sendEvent:event];
}
@end

@interface ClickScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIButton *button;
@property(nonatomic,copy) NSString *sessionID;
@property(nonatomic) NSUInteger clicks;
@property(nonatomic) BOOL foreground;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *corners;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *events;
@end
@implementation ClickScene
- (void)save {
    NSString *dir=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSDictionary *result=@{@"session":self.sessionID ?: @"",@"clicks":@(self.clicks),
        @"foreground":@(self.foreground),@"time":@([NSDate.date timeIntervalSince1970]),
        @"target":@{@"x":@0.5,@"y":@0.55},@"corners":self.corners ?: @{},@"events":self.events ?: @[]};
    [[NSJSONSerialization dataWithJSONObject:result options:0 error:nil]
        writeToFile:[dir stringByAppendingPathComponent:@"tapp-click-result.json"] atomically:YES];
}
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    NSArray *args=NSProcessInfo.processInfo.arguments;
    NSUInteger i=[args indexOfObject:@"--test-session"];
    self.sessionID=i!=NSNotFound && i+1<args.count ? args[i+1] : @"manual";
    self.events=[NSMutableArray array];
    TouchWindow *window=[[TouchWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window=window;
    __weak ClickScene *weakSelf=self;
    window.recordEvent=^(NSDictionary *event) {
        ClickScene *owner=weakSelf;
        [owner.events addObject:event]; [owner save];
    };
    UIViewController *root=[UIViewController new];
    root.view.backgroundColor=UIColor.systemBackgroundColor;
    UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(30,280,350,150)];
    label.text=@"Tapp click test\nSeparate app.\nThe button only increments a counter.";
    label.numberOfLines=0;
    [root.view addSubview:label];
    self.button=[UIButton buttonWithType:UIButtonTypeSystem];
    CGSize size=self.window.bounds.size;
    self.button.frame=CGRectMake(size.width*0.5-100,size.height*0.55-45,200,90);
    self.button.backgroundColor=UIColor.secondarySystemBackgroundColor;
    self.button.layer.cornerRadius=18;
    [self.button setTitle:@"Centre ready" forState:UIControlStateNormal];
    self.button.titleLabel.font=[UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
    self.button.accessibilityIdentifier=@"tapp.click.counter";
    [self.button addTarget:self action:@selector(clicked) forControlEvents:UIControlEventTouchUpInside];
    [root.view addSubview:self.button];
    self.corners=[NSMutableDictionary dictionary];
    NSArray *names=@[@"Top left",@"Top right",@"Bottom left",@"Bottom right"];
    for (NSUInteger i=0;i<names.count;i++) {
        NSString *name=names[i];
        self.corners[name]=@0;
        UIButton *corner=[UIButton buttonWithType:UIButtonTypeSystem];
        CGFloat x=(i%2==0 ? 0.17 : 0.83)*size.width;
        CGFloat y=(i<2 ? 0.19 : 0.84)*size.height;
        corner.frame=CGRectMake(x-65,y-40,130,80);
        corner.backgroundColor=UIColor.secondarySystemBackgroundColor;
        corner.layer.cornerRadius=16;
        corner.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        corner.accessibilityIdentifier=name;
        [corner setTitle:name forState:UIControlStateNormal];
        [corner addTarget:self action:@selector(cornerClicked:) forControlEvents:UIControlEventTouchUpInside];
        [corner addTarget:self action:@selector(cornerDown:) forControlEvents:UIControlEventTouchDown];
        [corner addTarget:self action:@selector(cornerOutside:) forControlEvents:UIControlEventTouchUpOutside];
        [corner addTarget:self action:@selector(cornerCancelled:) forControlEvents:UIControlEventTouchCancel];
        [root.view addSubview:corner];
    }
    self.window.rootViewController=root;
    [self.window makeKeyAndVisible];
    [self save];
}
- (void)clicked {
    self.clicks++;
    [self.button setTitle:self.clicks==1 ? @"Centre clicked" : [NSString stringWithFormat:@"Centre %lu",(unsigned long)self.clicks] forState:UIControlStateNormal];
    [self save];
}
- (void)cornerClicked:(UIButton *)button {
    NSString *name=button.accessibilityIdentifier;
    self.corners[name]=@([self.corners[name] unsignedIntegerValue]+1);
    NSUInteger count=[self.corners[name] unsignedIntegerValue];
    NSArray *words=@[@"zero",@"done",@"two",@"three",@"four",@"five",@"six",@"seven",@"eight",@"nine",@"ten"];
    NSString *value=count<words.count ? words[count] : [NSString stringWithFormat:@"%lu",(unsigned long)count];
    NSString *title=[NSString stringWithFormat:@"%@ %@",name,value];
    [button setTitle:title forState:UIControlStateNormal];
    [self.events addObject:@{@"event":@"click",@"corner":name,@"count":@(count),
        @"foreground":@(self.foreground),@"time":@([NSDate.date timeIntervalSince1970])}];
    [self save];
}
- (void)recordTouch:(NSString *)event button:(UIButton *)button {
    [self.events addObject:@{@"event":event,@"corner":button.accessibilityIdentifier,
        @"foreground":@(self.foreground),@"time":@([NSDate.date timeIntervalSince1970])}];
    [self save];
}
- (void)cornerDown:(UIButton *)button { [self recordTouch:@"touch-down" button:button]; }
- (void)cornerOutside:(UIButton *)button { [self recordTouch:@"touch-up-outside" button:button]; }
- (void)cornerCancelled:(UIButton *)button { [self recordTouch:@"touch-cancelled" button:button]; }
- (void)sceneDidBecomeActive:(UIScene *)scene {
    self.foreground=YES;
    [self.events addObject:@{@"event":@"active",@"time":@([NSDate.date timeIntervalSince1970])}];
    [self save];
}
- (void)sceneWillResignActive:(UIScene *)scene {
    self.foreground=NO;
    [self.events addObject:@{@"event":@"inactive",@"time":@([NSDate.date timeIntervalSince1970])}];
    [self save];
}
@end
@interface ClickApp : UIResponder <UIApplicationDelegate>
@end
@implementation ClickApp
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration=[[UISceneConfiguration alloc] initWithName:@"ClickTarget" sessionRole:session.role];
    configuration.delegateClass=ClickScene.class;
    return configuration;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(ClickApp.class)); } }
