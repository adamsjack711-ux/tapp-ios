#import <UIKit/UIKit.h>
#import <TargetConditionals.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "../SharedRenderer/TappGlobalRenderer.h"

#if !TARGET_OS_SIMULATOR
#error TappOverlayProbe is simulator-only research, never a production target.
#endif

// Interface reference: Lessica/TrollSpeed, MIT. This independent probe tests
// registration without its privileged deployment, event routing or root helper.
static NSMutableArray *events;
static void Record(NSString *name, NSDictionary *details) {
    if (!events) events = [NSMutableArray array];
    [events addObject:@{@"event":name, @"time":@([[NSDate date] timeIntervalSince1970]), @"details":details ?: @{}}];
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSJSONSerialization dataWithJSONObject:events options:NSJSONWritingPrettyPrinted error:nil]
        writeToFile:[dir stringByAppendingPathComponent:@"overlay-probe.json"] atomically:YES];
    NSLog(@"TAPP %@ %@", name, details);
}

static NSDictionary *AccessibilityState(void) {
    void *handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW);
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    for (NSString *symbol in @[@"_AXSAssistiveTouchEnabled", @"_AXSPointerControlEnabled", @"_AXSDwellControlEnabled", @"AXRuntimeCheck_AXAction", @"AXRuntimeCheck_AXAction_PointerControl"]) {
        bool (*getter)(void) = handle ? dlsym(handle, symbol.UTF8String) : NULL;
        state[symbol] = getter ? @(getter()) : @"unavailable";
    }
    if (handle) dlclose(handle);
    return state;
}

static NSString *RestoreJournalPath(void) {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"pointer-control-original.json"];
}
static void RestorePointerControl(void) {
    NSData *data = [NSData dataWithContentsOfFile:RestoreJournalPath()];
    NSDictionary *saved = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (!saved) return;
    void *handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW);
    void (*setter)(bool) = handle ? dlsym(handle, "_AXSPointerControlSetEnabled") : NULL;
    bool (*getter)(void) = handle ? dlsym(handle, "_AXSPointerControlEnabled") : NULL;
    if (setter) {
        setter([saved[@"original"] boolValue]);
        if (getter && getter() == [saved[@"original"] boolValue]) {
            [[NSFileManager defaultManager] removeItemAtPath:RestoreJournalPath() error:nil];
            Record(@"pointer-control-readback-restored", AccessibilityState());
        } else Record(@"pointer-control-restore-unverified", AccessibilityState());
    } else Record(@"restore-setter-unavailable", nil);
    if (handle) dlclose(handle);
}

@interface TappOverlayWindow : UIWindow
@end
@implementation TappOverlayWindow
+ (BOOL)_isSystemWindow { return YES; }
- (BOOL)_isWindowServerHostingManaged { return NO; }
- (BOOL)_ignoresHitTest { return YES; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }
@end

@interface TappProbeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIWindow *overlay;
@property(nonatomic,strong) id host;
@property(nonatomic,strong) TappGlobalRenderer *renderer;
@property(nonatomic,strong) id pointerSystemClient;
@property(nonatomic,strong) id displayConfiguration;
@property(nonatomic,strong) id pointerClient;
@property(nonatomic,strong) id pointerVisibility;
@property(nonatomic,strong) id pointerKeepAlive;
@property(nonatomic,strong) id mouseService;
@property(nonatomic) CGPoint originalPointer;
@property(nonatomic) BOOL hasOriginalPointer;
@property(nonatomic) BOOL changedPointerControl;
@property(nonatomic) BOOL originalPointerControl;
@property(nonatomic) UIBackgroundTaskIdentifier backgroundTask;
@end

@interface TappProbeScene : UIResponder <UIWindowSceneDelegate>
@end

@implementation TappProbeDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    Record(@"launch", AccessibilityState());
    return YES;
}
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Probe" sessionRole:session.role];
    configuration.delegateClass = TappProbeScene.class;
    return configuration;
}
- (void)startInScene:(UIWindowScene *)scene {
    self.backgroundTask = UIBackgroundTaskInvalid;
    Record(@"scene-connected", AccessibilityState());
    self.window = [[UIWindow alloc] initWithWindowScene:scene];
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(30, 120, 330, 160)];
    label.numberOfLines = 0;
    label.text = [NSProcessInfo.processInfo.arguments containsObject:@"--native-pointer"]
        ? @"Tapp system pointer probe\nSimulator only · 45 second limit\nNo app-drawn cursor.\nSwitch to Settings to inspect."
        : @"Tapp global renderer probe\nSimulator only · 45 second limit\nSwitch to Settings to inspect.\nGlobal visibility is unproven.";
    [root.view addSubview:label];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self registerOverlay]; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, ([NSProcessInfo.processInfo.arguments containsObject:@"--idle-persistence"] ? 180 : 45) * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self finishProbe:@"deadline-cleanup"];
    });
}
- (void)finishProbe:(NSString *)reason {
    if (self.hasOriginalPointer) ((void (*)(id,SEL,CGPoint))objc_msgSend)(self.mouseService, NSSelectorFromString(@"setGlobalPointerPosition:"), self.originalPointer);
    // Explicit invalidation is required before releasing BSSimpleAssertion.
    for (id assertion in @[self.pointerVisibility ?: NSNull.null, self.pointerKeepAlive ?: NSNull.null]) {
        if ([assertion respondsToSelector:NSSelectorFromString(@"invalidate")]) ((void (*)(id,SEL))objc_msgSend)(assertion,NSSelectorFromString(@"invalidate"));
    }
    self.pointerVisibility = nil;
    self.pointerKeepAlive = nil;
    if ([self.pointerClient respondsToSelector:NSSelectorFromString(@"invalidate")]) ((void (*)(id,SEL))objc_msgSend)(self.pointerClient, NSSelectorFromString(@"invalidate"));
    [self.renderer invalidate];
    self.renderer = nil;
    if (self.pointerSystemClient && self.displayConfiguration) ((void (*)(id,SEL,id))objc_msgSend)(self.pointerSystemClient, NSSelectorFromString(@"invalidateScenesForPointerForDisplayConfiguration:"), self.displayConfiguration);
    self.pointerSystemClient = nil;
    self.overlay.hidden = YES;
    self.overlay = nil;
    self.host = nil;
    if (self.changedPointerControl) RestorePointerControl();
    Record(reason, AccessibilityState());
    if (self.backgroundTask != UIBackgroundTaskInvalid) {
        [UIApplication.sharedApplication endBackgroundTask:self.backgroundTask];
        self.backgroundTask = UIBackgroundTaskInvalid;
    }
    exit(0); // Dedicated finite simulator probe; also releases system assertions.
}
- (void)registerOverlay {
    for (NSString *framework in @[@"SpringBoardServices", @"AccessibilityUIUtilities", @"AccessibilityUtilities", @"FrontBoardServices", @"PointerUIServices", @"PointerUISystemServices"]) {
        NSString *path = [NSString stringWithFormat:@"/System/Library/PrivateFrameworks/%@.framework/%@", framework, framework];
        void *handle = dlopen(path.UTF8String, RTLD_NOW);
        const char *error = handle ? NULL : dlerror();
        Record(@"framework", @{@"name":framework, @"loaded":@(handle != NULL), @"error":error ? @(error) : @""});
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--native-pointer"]) { [self probeNativePointer]; return; }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--global-layer"]) { [self probeGlobalLayer]; return; }
    unsigned count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableDictionary *interfaces = [NSMutableDictionary dictionary];
    for (unsigned i=0; i<count; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        const char *imageName = class_getImageName(classes[i]);
        NSString *imagePath = imageName ? @(imageName) : @"";
        if ([name containsString:@"WindowHost"] || [name hasPrefix:@"AXUIDaemon"] || [name hasPrefix:@"BKSMousePointer"] || [imagePath containsString:@"/PointerUI"] || [name containsString:@"SystemUIService"] || [name isEqualToString:@"UIScreen"] || [name isEqualToString:@"FBSDisplayConfiguration"] || [name isEqualToString:@"CAContext"] || [name isEqualToString:@"CADisplay"]) {
            unsigned methodCount = 0;
            Method *methods = class_copyMethodList(classes[i], &methodCount);
            NSMutableArray *names = [NSMutableArray array];
            for (unsigned m=0; m<methodCount; m++) [names addObject:[NSString stringWithFormat:@"%s %s", sel_getName(method_getName(methods[m])), method_getTypeEncoding(methods[m])]];
            free(methods);
            methods = class_copyMethodList(object_getClass(classes[i]), &methodCount);
            for (unsigned m=0; m<methodCount; m++) [names addObject:[NSString stringWithFormat:@"+ %s %s", sel_getName(method_getName(methods[m])), method_getTypeEncoding(methods[m])]];
            free(methods);
            interfaces[name] = names;
        }
    }
    free(classes);
    Record(@"available-interfaces", interfaces);
    Class hostClass = NSClassFromString(@"SBSAccessibilityWindowHostingController");
    SEL registerSelector = NSSelectorFromString(@"registerWindowWithContextID:atLevel:");
    Method registration = class_getInstanceMethod(hostClass, registerSelector);
    Record(@"host-interface", @{@"classFound":@(hostClass != Nil), @"encoding": registration ? @(method_getTypeEncoding(registration)) : @"missing"});
    if (!registration) return;
    self.host = [hostClass new];
    self.overlay = [[TappOverlayWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.overlay.backgroundColor = UIColor.clearColor;
    self.overlay.userInteractionEnabled = NO;
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    self.overlay.rootViewController = root;
    self.overlay.windowLevel = 10000010;
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(CGRectGetMidX(self.overlay.bounds)-16, CGRectGetMidY(self.overlay.bounds)-16, 32, 32)];
    dot.backgroundColor = UIColor.systemMintColor;
    dot.layer.cornerRadius = 16;
    dot.layer.borderWidth = 3;
    dot.layer.borderColor = UIColor.blackColor.CGColor;
    [root.view addSubview:dot];
    self.overlay.hidden = NO;
    SEL contextSelector = NSSelectorFromString(@"_contextId");
    if (![self.overlay respondsToSelector:contextSelector]) { Record(@"context-unavailable", nil); return; }
    unsigned context = ((unsigned (*)(id, SEL))objc_msgSend)(self.overlay, contextSelector);
    NSMethodSignature *signature = [self.host methodSignatureForSelector:registerSelector];
    if (signature.numberOfArguments != 4 || strcmp([signature getArgumentTypeAtIndex:2], @encode(unsigned)) || strcmp([signature getArgumentTypeAtIndex:3], @encode(double))) {
        Record(@"unsupported-signature", nil); return;
    }
    @try {
        ((void (*)(id,SEL,unsigned,double))objc_msgSend)(self.host, registerSelector, context, (double)self.overlay.windowLevel);
        Record(@"registration-call-returned", @{@"contextID":@(context), @"level":@(self.overlay.windowLevel), @"successNotYetProven":@YES});
    } @catch (NSException *exception) {
        Record(@"registration-exception", @{@"name":exception.name, @"reason":exception.reason ?: @""});
    }
}
- (void)probeGlobalLayer {
    self.renderer = [TappGlobalRenderer new];
    NSError *error;
    if (![self.renderer start:&error]) { Record(@"global-context-missing", @{@"error":error.localizedDescription ?: @"invalid context"}); return; }
    Record(@"global-layer-request", self.renderer.diagnostics);
    for (int step=1; step<=5; step++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, step*3*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            CGPoint point = CGPointMake(step == 5 ? 0.5 : (step%2 ? 0.6 : 0.4), 0.5);
            [self.renderer moveToNormalizedPoint:point];
            Record(@"global-layer-motion-request", @{@"step":@(step),@"normalizedPosition":NSStringFromCGPoint(point),@"accessibility":AccessibilityState()});
        });
    }
}
- (void)probeNativePointer {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--pointer-control"]) {
        void *handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW);
        bool (*getter)(void) = handle ? dlsym(handle, "_AXSPointerControlEnabled") : NULL;
        void (*setter)(bool) = handle ? dlsym(handle, "_AXSPointerControlSetEnabled") : NULL;
        if (getter && setter) {
            self.originalPointerControl = getter();
            self.changedPointerControl = YES;
            Record(@"pointer-control-before", AccessibilityState());
            [[NSJSONSerialization dataWithJSONObject:@{@"original":@(self.originalPointerControl)} options:0 error:nil] writeToFile:RestoreJournalPath() atomically:YES];
            setter(true);
            Record(@"pointer-control-after", AccessibilityState());
        } else { Record(@"pointer-control-setter-unavailable", nil); }
        if (handle) dlclose(handle);
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--prepare-pointer-scene"]) {
        self.displayConfiguration = ((id (*)(id,SEL))objc_msgSend)(self.window.screen, NSSelectorFromString(@"displayConfiguration"));
        Class systemClass = NSClassFromString(@"PSPointerSystemClientController");
        self.pointerSystemClient = [systemClass new];
        @try {
            ((void (*)(id,SEL,id))objc_msgSend)(self.pointerSystemClient, NSSelectorFromString(@"prepareScenesForPointerForDisplayConfiguration:"), self.displayConfiguration);
            Record(@"system-pointer-scene-requested", @{@"configuration":[self.displayConfiguration description] ?: @"nil"});
        } @catch (NSException *exception) {
            Record(@"system-pointer-scene-exception", @{@"name":exception.name,@"reason":exception.reason ?: @""});
        }
    }
    Class clientClass = NSClassFromString(@"PSPointerClientController");
    Class serviceClass = NSClassFromString(@"BKSMousePointerService");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    SEL show = NSSelectorFromString(@"persistentlyShowPointerAssertionForReason:");
    SEL keep = NSSelectorFromString(@"acquireServiceKeepAliveAssertion");
    SEL position = NSSelectorFromString(@"globalPointerPosition");
    SEL setPosition = NSSelectorFromString(@"setGlobalPointerPosition:");
    if (![clientClass instancesRespondToSelector:show] || ![serviceClass respondsToSelector:shared]) { Record(@"native-interface-missing", nil); return; }
    self.pointerClient = [clientClass new];
    self.mouseService = ((id (*)(id,SEL))objc_msgSend)(serviceClass, shared);
    if (![self.mouseService respondsToSelector:position] || ![self.mouseService respondsToSelector:setPosition]) { Record(@"position-interface-missing", nil); return; }
    self.originalPointer = ((CGPoint (*)(id,SEL))objc_msgSend)(self.mouseService, position);
    self.hasOriginalPointer = YES;
    self.pointerKeepAlive = ((id (*)(id,SEL))objc_msgSend)(self.pointerClient, keep);
    self.pointerVisibility = ((id (*)(id,SEL,NSUInteger))objc_msgSend)(self.pointerClient, show, 0);
    CGPoint target = CGPointMake(CGRectGetMidX(self.window.bounds), CGRectGetMidY(self.window.bounds));
    ((void (*)(id,SEL,CGPoint))objc_msgSend)(self.mouseService, setPosition, target);
    Record(@"native-request", @{@"original":NSStringFromCGPoint(self.originalPointer), @"requested":NSStringFromCGPoint(target), @"showAssertion":@(self.pointerVisibility != nil), @"keepAlive":@(self.pointerKeepAlive != nil), @"noAppDrawnCursor":@YES});
    for (int second=1; second<=20; second+=3) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, second*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            CGPoint actual = ((CGPoint (*)(id,SEL))objc_msgSend)(self.mouseService, position);
            NSInteger visibility = ((NSInteger (*)(id,SEL))objc_msgSend)(self.pointerClient, NSSelectorFromString(@"pointerVisibilityState"));
            BOOL enabled = ((BOOL (*)(id,SEL))objc_msgSend)(self.pointerClient, NSSelectorFromString(@"isClientInteractionEnabled"));
            Record(@"native-observation", @{@"seconds":@(second), @"position":NSStringFromCGPoint(actual), @"visibilityState":@(visibility), @"interactionEnabled":@(enabled), @"accessibility":AccessibilityState()});
        });
    }
}
- (void)applicationDidEnterBackground:(UIApplication *)app {
    Record(@"entered-background", AccessibilityState());
    self.backgroundTask = [app beginBackgroundTaskWithExpirationHandler:^{
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--idle-persistence"]) {
            Record(@"background-time-expired-keep-renderer", AccessibilityState());
            [UIApplication.sharedApplication endBackgroundTask:self.backgroundTask];
            self.backgroundTask = UIBackgroundTaskInvalid;
        } else [self finishProbe:@"background-expiration-cleanup"];
    }];
}
- (void)applicationDidBecomeActive:(UIApplication *)app { Record(@"active", AccessibilityState()); }
@end

@implementation TappProbeScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    [(TappProbeDelegate *)UIApplication.sharedApplication.delegate startInScene:(UIWindowScene *)scene];
}
- (void)sceneDidEnterBackground:(UIScene *)scene {
    [(TappProbeDelegate *)UIApplication.sharedApplication.delegate applicationDidEnterBackground:UIApplication.sharedApplication];
}
- (void)sceneDidBecomeActive:(UIScene *)scene { Record(@"scene-active", AccessibilityState()); }
@end

static id TappServiceIdentifier(id self, SEL cmd) { return @"com.hitapp.research.TappOverlayProbe"; }
int main(int argc, char **argv) {
    @autoreleasepool {
        RestorePointerControl();
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--restore-state"]) {
            Record(@"recovery-finished", @{@"journalRemaining":@([[NSFileManager defaultManager] fileExistsAtPath:RestoreJournalPath()]), @"accessibility":AccessibilityState()});
            return 0;
        }
        NSString *principal = nil;
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--system-service"]) {
            dlopen("/System/Library/PrivateFrameworks/AccessibilityUIUtilities.framework/AccessibilityUIUtilities", RTLD_NOW);
            Class base = NSClassFromString(@"AXUIDaemonApplication");
            if (!base) { Record(@"missing-daemon-base", nil); return 2; }
            Class subclass = objc_allocateClassPair(base, "TappSystemServiceApplication", 0);
            class_addMethod(object_getClass(subclass), NSSelectorFromString(@"_systemUIServiceIdentifier"), (IMP)TappServiceIdentifier, "@16@0:8");
            objc_registerClassPair(subclass);
            principal = NSStringFromClass(subclass);
            Record(@"system-service-attempt", @{@"identifier":TappServiceIdentifier(nil, nil), @"privateEntitlementsAdded":@NO});
        }
        return UIApplicationMain(argc, argv, principal, NSStringFromClass(TappProbeDelegate.class));
    }
}
