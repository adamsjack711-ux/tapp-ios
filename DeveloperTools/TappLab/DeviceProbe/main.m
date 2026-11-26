#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>
#import "../SharedRenderer/TappGlobalRenderer.h"

static NSMutableArray *history;
static void Save(NSString *event, NSDictionary *details) {
    if (!history) history = [NSMutableArray array];
    [history addObject:@{@"event":event,@"time":@([NSDate.date timeIntervalSince1970]),@"details":details ?: @{}}];
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSJSONSerialization dataWithJSONObject:history options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[dir stringByAppendingPathComponent:@"tapp-device-probe.json"] atomically:YES];
    NSLog(@"Tapp device probe: %@ %@",event,details);
}
static NSDictionary *States(void) {
    void *library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW);
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *symbol in @[@"_AXSAssistiveTouchEnabled",@"_AXSPointerControlEnabled",@"_AXSDwellControlEnabled",@"AXRuntimeCheck_AXAction",@"AXRuntimeCheck_AXAction_PointerControl"]) {
        bool (*getter)(void) = library ? dlsym(library,symbol.UTF8String) : NULL;
        result[symbol] = getter ? @(getter()) : @"unavailable";
    }
    if (library) dlclose(library);
    return result;
}
@interface TappDeviceScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIWindow *accessibilityWindow;
@property(nonatomic,strong) TappGlobalRenderer *renderer;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) id pointerClient;
@property(nonatomic,strong) id pointerVisibility;
@property(nonatomic,strong) id pointerKeepAlive;
@property(nonatomic,strong) id mouseService;
@property(nonatomic,strong) id pointerSystemClient;
@property(nonatomic,strong) id displayConfiguration;
@property(nonatomic) UIBackgroundTaskIdentifier task;
@property(nonatomic) BOOL stopped;
@end
@implementation TappDeviceScene
- (NSDictionary *)pointerState {
    NSMutableDictionary *details = [NSMutableDictionary dictionaryWithDictionary:@{@"accessibility":States()}];
    SEL position = NSSelectorFromString(@"globalPointerPosition");
    SEL visibility = NSSelectorFromString(@"pointerVisibilityState");
    SEL interaction = NSSelectorFromString(@"isClientInteractionEnabled");
    SEL state = NSSelectorFromString(@"clientInteractionState");
    if ([self.mouseService respondsToSelector:position]) details[@"position"] = NSStringFromCGPoint(((CGPoint (*)(id,SEL))objc_msgSend)(self.mouseService,position));
    if ([self.pointerClient respondsToSelector:visibility]) details[@"visibilityState"] = @(((NSInteger (*)(id,SEL))objc_msgSend)(self.pointerClient,visibility));
    if ([self.pointerClient respondsToSelector:interaction]) details[@"interactionEnabled"] = @(((BOOL (*)(id,SEL))objc_msgSend)(self.pointerClient,interaction));
    if ([self.pointerClient respondsToSelector:state]) details[@"interactionState"] = @(((NSInteger (*)(id,SEL))objc_msgSend)(self.pointerClient,state));
    return details;
}
- (void)recordPointerChange:(NSString *)event client:(id)client {
    // Delegate callbacks supplement polling so brief state changes are retained.
    // These are readbacks, never evidence of visible movement by themselves.
    dispatch_async(dispatch_get_main_queue(),^{
        if (!self.stopped && client == self.pointerClient) Save(event,[self pointerState]);
    });
}
- (void)pointerClientControllerClientInteractionEnabledDidChange:(id)client {
    [self recordPointerChange:@"pointer-interaction-enabled-changed" client:client];
}
- (void)pointerClientControllerClientInteractionStateDidChange:(id)client {
    [self recordPointerChange:@"pointer-interaction-state-changed" client:client];
}
- (void)pointerClientControllerPointerVisibilityStateDidChange:(id)client {
    [self recordPointerChange:@"pointer-visibility-changed" client:client];
}
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.task = UIBackgroundTaskInvalid;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.systemBackgroundColor;
    self.status = [[UILabel alloc] initWithFrame:CGRectMake(24,120,350,230)];
    self.status.numberOfLines = 0;
    self.status.text = @"Tapp device research\nChecking global rendering permission…\nNo input or accessibility changes.\n45 second limit.";
    [root.view addSubview:self.status];
    UIButton *stop = [UIButton buttonWithType:UIButtonTypeSystem];
    stop.frame = CGRectMake(24,370,220,60);
    [stop setTitle:@"Stop Tapp probe" forState:UIControlStateNormal];
    [stop addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
    [root.view addSubview:stop];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    Save(@"launch",States());
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{ [self begin]; });
}
- (void)begin {
    if (self.stopped) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [self stop]; });
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--pointer-service"]) {
        [self beginPointerService];
        return;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--ax-window"]) {
        [self beginAccessibilityWindow];
        return;
    }
    self.renderer = [TappGlobalRenderer new];
    NSError *error = nil;
    BOOL started = [self.renderer start:&error];
    Save(@"renderer-result",@{@"contextCreated":@(started),@"error":error.localizedDescription ?: @"",@"diagnostics":self.renderer.diagnostics ?: @{},@"accessibility":States()});
    self.status.text = !started ? [@"Tapp rendering failed:\n" stringByAppendingString:error.localizedDescription ?: @"System rejected the context."] :
        self.renderer.attachedDisplayIdentifier == 0 ? @"Tapp device research\nContext exists but is NOT attached to a display.\nGlobal rendering has not succeeded.\n45 second diagnostic limit; no input or settings changes." :
        @"Tapp device research\nDisplay ID assigned. Visibility still needs visual verification.\n45 second limit; no input or settings changes.";
    for (int step=1;step<=5;step++) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,step*3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if (self.stopped) return;
        CGPoint p = CGPointMake(step==5 ? 0.5 : (step%2 ? 0.6 : 0.4),0.5);
        [self.renderer moveToNormalizedPoint:p];
        Save(@"motion-request",@{@"normalizedPosition":NSStringFromCGPoint(p),@"actualDisplayID":@(self.renderer.attachedDisplayIdentifier),@"contextValid":@(self.renderer.contextValid),@"accessibility":States()});
    });
}
- (NSDictionary *)accessibilityWindowState {
    UIWindow *window = self.accessibilityWindow;
    NSMutableDictionary *state = [@{@"exists":@(window != nil), @"hidden":@(window.hidden),
        @"sceneState":@(window.windowScene.activationState), @"level":@(window.windowLevel),
        @"frame":NSStringFromCGRect(window.frame), @"accessibility":States(),
        @"visualVisibilityRequiresExternalVerification":@YES} mutableCopy];
    SEL context = NSSelectorFromString(@"_contextId");
    if ([window respondsToSelector:context]) state[@"contextID"] = @(((unsigned (*)(id,SEL))objc_msgSend)(window,context));
    return state;
}
- (void)beginAccessibilityWindow {
    // Owned by this app: no system identity, entitlement or accessibility changes.
    void *handle = dlopen("/System/Library/PrivateFrameworks/AccessibilityUIUtilities.framework/AccessibilityUIUtilities", RTLD_NOW);
    Class candidate = NSClassFromString(@"AXUIDaemonNonInteractiveWindow");
    Save(@"ax-window-interface",@{@"frameworkLoaded":@(handle != NULL),@"classFound":@(candidate != Nil)});
    if (!candidate || ![candidate isSubclassOfClass:UIWindow.class]) { [self stop]; return; }
    @try {
        self.accessibilityWindow = [[candidate alloc] initWithWindowScene:self.window.windowScene];
        self.accessibilityWindow.frame = self.window.bounds;
        self.accessibilityWindow.windowLevel = 10000010;
        self.accessibilityWindow.backgroundColor = UIColor.clearColor;
        self.accessibilityWindow.userInteractionEnabled = NO;
        UIViewController *controller = [UIViewController new];
        controller.view.backgroundColor = UIColor.clearColor;
        self.accessibilityWindow.rootViewController = controller;
        UIView *buddy = [[UIView alloc] initWithFrame:CGRectMake(34,530,42,42)];
        buddy.backgroundColor = UIColor.systemMintColor;
        buddy.layer.cornerRadius = 18;
        buddy.layer.borderWidth = 1.5;
        buddy.layer.borderColor = UIColor.blackColor.CGColor;
        UILabel *face = [[UILabel alloc] initWithFrame:buddy.bounds];
        face.text = @"•ᴗ•"; face.textColor = UIColor.blackColor;
        face.textAlignment = NSTextAlignmentCenter;
        face.font = [UIFont systemFontOfSize:22 weight:UIFontWeightMedium];
        [buddy addSubview:face];
        [controller.view addSubview:buddy];
        UILabel *bubble = [[UILabel alloc] initWithFrame:CGRectMake(86,516,232,66)];
        bubble.numberOfLines = 0;
        bubble.text = @"  tapp\n  Window hosting test";
        bubble.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        bubble.textColor = UIColor.labelColor;
        bubble.backgroundColor = UIColor.secondarySystemBackgroundColor;
        bubble.layer.cornerRadius = 16; bubble.clipsToBounds = YES;
        [controller.view addSubview:bubble];
        self.accessibilityWindow.hidden = NO;
        [CATransaction flush];
        Save(@"ax-window-created",[self accessibilityWindowState]);
        self.status.text = @"Tapp accessibility-window research\nCompact buddy + adjacent bubble.\nSwitch apps to test actual visibility.\n45 second / background-expiration limit.";
        for (int second=1;second<=40;second+=3) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,second*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if (!self.stopped) Save(@"ax-window-observation",[self accessibilityWindowState]);
        });
    } @catch (NSException *exception) {
        Save(@"ax-window-exception",@{@"name":exception.name,@"reason":exception.reason ?: @""});
        [self stop];
    }
}
- (void)beginPointerService {
    // Visibility/keep-alive assertions only. Native mouse motion, if tested,
    // belongs to hitapp's separately bounded, foreground-only experiment.
    for (NSString *name in @[@"BackBoardServices", @"PointerUIServices", @"PointerUISystemServices"]) {
        NSString *path = [NSString stringWithFormat:@"/System/Library/PrivateFrameworks/%@.framework/%@",name,name];
        dlopen(path.UTF8String, RTLD_NOW);
    }
    @try {
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--prepare-pointer-scene"]) {
            SEL configuration = NSSelectorFromString(@"displayConfiguration");
            SEL prepare = NSSelectorFromString(@"prepareScenesForPointerForDisplayConfiguration:");
            SEL invalidate = NSSelectorFromString(@"invalidateScenesForPointerForDisplayConfiguration:");
            Class system = NSClassFromString(@"PSPointerSystemClientController");
            if ([self.window.screen respondsToSelector:configuration] && [system instancesRespondToSelector:prepare] && [system instancesRespondToSelector:invalidate]) {
                self.displayConfiguration = ((id (*)(id,SEL))objc_msgSend)(self.window.screen,configuration);
                if (self.displayConfiguration) {
                    self.pointerSystemClient = [system new];
                    ((void (*)(id,SEL,id))objc_msgSend)(self.pointerSystemClient,prepare,self.displayConfiguration);
                    Save(@"pointer-scene-requested",@{@"clientCreated":@(self.pointerSystemClient != nil),@"visibilityVerified":@NO});
                } else Save(@"pointer-scene-configuration-unavailable",nil);
            } else Save(@"pointer-scene-interface-unavailable",nil);
        }
        Class client = NSClassFromString(@"PSPointerClientController");
        Class service = NSClassFromString(@"BKSMousePointerService");
        SEL show = NSSelectorFromString(@"persistentlyShowPointerAssertionForReason:");
        SEL keep = NSSelectorFromString(@"acquireServiceKeepAliveAssertion");
        SEL shared = NSSelectorFromString(@"sharedInstance");
        if (![client instancesRespondToSelector:show] || ![client instancesRespondToSelector:keep] || ![service respondsToSelector:shared]) {
            Save(@"pointer-interface-unavailable",States());
            [self stop];
            return;
        }
        self.pointerClient = [client new];
        self.mouseService = ((id (*)(id,SEL))objc_msgSend)(service,shared);
        SEL delegate = NSSelectorFromString(@"setDelegate:");
        BOOL observesChanges = [self.pointerClient respondsToSelector:delegate];
        if (observesChanges) ((void (*)(id,SEL,id))objc_msgSend)(self.pointerClient,delegate,self);
        self.pointerKeepAlive = ((id (*)(id,SEL))objc_msgSend)(self.pointerClient,keep);
        self.pointerVisibility = ((id (*)(id,SEL,NSUInteger))objc_msgSend)(self.pointerClient,show,0);
        Save(@"pointer-service-request",@{@"showAssertion":@(self.pointerVisibility != nil),@"keepAlive":@(self.pointerKeepAlive != nil),@"observesStateChanges":@(observesChanges),@"accessibility":States(),@"inputDispatched":@NO});
        self.status.text = @"Tapp pointer-service research\nAssertions requested; visibility NOT verified.\nNo drawn cursor, input or settings changes.\n45 second / background-expiration limit.";
        for (int second=1;second<=40;second+=3) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,second*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if (self.stopped) return;
            NSMutableDictionary *details = [[self pointerState] mutableCopy];
            details[@"seconds"] = @(second);
            Save(@"pointer-service-observation",details);
        });
    } @catch (NSException *exception) {
        Save(@"pointer-service-exception",@{@"name":exception.name,@"reason":exception.reason ?: @""});
        [self stop];
    }
}
- (void)stop {
    if (self.stopped) return;
    self.stopped = YES;
    Save(@"cleanup-start",States());
    if (self.accessibilityWindow) {
        self.accessibilityWindow.hidden = YES;
        self.accessibilityWindow.rootViewController = nil;
        self.accessibilityWindow.windowScene = nil;
        self.accessibilityWindow = nil;
        Save(@"ax-window-released",States());
    }
    if ([self.pointerClient respondsToSelector:NSSelectorFromString(@"setDelegate:")]) ((void (*)(id,SEL,id))objc_msgSend)(self.pointerClient,NSSelectorFromString(@"setDelegate:"),nil);
    // BSSimpleAssertion traps in dealloc if it has not been invalidated.
    for (id assertion in @[self.pointerVisibility ?: NSNull.null, self.pointerKeepAlive ?: NSNull.null]) {
        if ([assertion respondsToSelector:NSSelectorFromString(@"invalidate")]) ((void (*)(id,SEL))objc_msgSend)(assertion,NSSelectorFromString(@"invalidate"));
    }
    self.pointerVisibility = nil;
    Save(@"visibility-assertion-released",nil);
    self.pointerKeepAlive = nil;
    Save(@"keepalive-assertion-released",nil);
    if ([self.pointerClient respondsToSelector:NSSelectorFromString(@"invalidate")]) ((void (*)(id,SEL))objc_msgSend)(self.pointerClient,NSSelectorFromString(@"invalidate"));
    Save(@"pointer-client-invalidated",nil);
    self.pointerClient = nil;
    self.mouseService = nil;
    if (self.pointerSystemClient && self.displayConfiguration) {
        @try {
            ((void (*)(id,SEL,id))objc_msgSend)(self.pointerSystemClient,NSSelectorFromString(@"invalidateScenesForPointerForDisplayConfiguration:"),self.displayConfiguration);
            Save(@"pointer-scene-invalidation-requested",nil);
        } @catch (NSException *exception) {
            Save(@"pointer-scene-cleanup-exception",@{@"name":exception.name,@"reason":exception.reason ?: @""});
        }
    }
    self.pointerSystemClient = nil;
    self.displayConfiguration = nil;
    [self.renderer invalidate];
    Save(@"cleanup",States());
    self.status.text = @"Tapp probe stopped.\nRenderer and pointer assertions released. Results saved.\nA created context or assertion alone does not prove visibility.";
    if (self.task != UIBackgroundTaskInvalid) {
        [UIApplication.sharedApplication endBackgroundTask:self.task];
        self.task = UIBackgroundTaskInvalid;
    }
}
- (void)sceneDidEnterBackground:(UIScene *)scene {
    Save(@"background",States());
    if (!self.stopped && self.task == UIBackgroundTaskInvalid) self.task = [UIApplication.sharedApplication beginBackgroundTaskWithExpirationHandler:^{ [self stop]; }];
}
- (void)sceneWillEnterForeground:(UIScene *)scene {
    if (self.task != UIBackgroundTaskInvalid) {
        [UIApplication.sharedApplication endBackgroundTask:self.task];
        self.task = UIBackgroundTaskInvalid;
    }
}
- (void)sceneDidDisconnect:(UIScene *)scene { [self stop]; }
@end
@interface TappDeviceApp : UIResponder <UIApplicationDelegate>
@end
@implementation TappDeviceApp
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"DeviceProbe" sessionRole:session.role];
    configuration.delegateClass = TappDeviceScene.class;
    return configuration;
}
@end
// A bounded request for a system-UI hosting role under our own bundle identity.
// A role declaration cannot grant an entitlement or prove a hosted scene exists.
@interface TappHostingApplication : UIApplication
@end
@implementation TappHostingApplication
+ (BOOL)_isSystemUIService { return YES; }
+ (NSString *)_systemUIServiceIdentifier { return @"com.jackadamslovell.TappDeviceProbe"; }
@end
int main(int argc,char **argv) {
    @autoreleasepool {
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--state-only"]) {
            Save(@"state-only", States());
            return 0;
        }
        BOOL hosting = [NSProcessInfo.processInfo.arguments containsObject:@"--system-ui-host"];
        if (hosting) {
            Save(@"system-ui-host-request",@{@"identifier":@"com.jackadamslovell.TappDeviceProbe",@"accessibility":States(),@"visibilityVerified":@NO});
            // Also bounds startup failures that never connect a scene.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                Save(@"system-ui-host-deadline",States());
                exit(0);
            });
        }
        return UIApplicationMain(argc,argv,hosting ? NSStringFromClass(TappHostingApplication.class) : nil,NSStringFromClass(TappDeviceApp.class));
    }
}
