// Simulator-only native companion event/render process. No host mouse monitor,
// touch injection, system settings changes, or privileged identity is used.
#import "DraftRocketRenderer.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <signal.h>

static DraftRocketRenderer *renderer;
static id inputContext;
static CALayer *inputLayer;
static NSString *directory, *session, *name;
static double deadline, downAt, lastWake=-100;
static BOOL quiet, tracking;
static CGPoint downPoint;
static unsigned wakeCount, eventCount;
static CGFloat displayScale;
static NSString *phase=@"starting";
static void Record(NSString *message) {
    NSString *line=[NSString stringWithFormat:@"%@ %@\n",[[NSISO8601DateFormatter new] stringFromDate:NSDate.date],message];
    NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:[directory stringByAppendingPathComponent:@"events.log"]];
    if(!file) { [NSData.data writeToFile:[directory stringByAppendingPathComponent:@"events.log"] atomically:YES]; file=[NSFileHandle fileHandleForWritingAtPath:[directory stringByAppendingPathComponent:@"events.log"]]; }
    [file seekToEndOfFile]; [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [file closeFile];
}
static void Wake(NSString *source) {
    double now=CACurrentMediaTime();
    if(now>=deadline-2 || now-lastWake<.65)return;
    lastWake=now; wakeCount++; [renderer wake]; phase=[renderer motionPhase];
    Record([NSString stringWithFormat:@"wake %@ source=%@ count=%u",name,source,wakeCount]);
}
static void Event(void *target,void *refcon,void *service,void *hid) {
    // BackBoard routes only events belonging to our small input context.
    Class cls=NSClassFromString(@"AXEventRepresentation");
    if(!cls)return;
    id rep=((id(*)(id,SEL,void*,id))objc_msgSend)(cls,NSSelectorFromString(@"representationWithHIDEvent:hidStreamIdentifier:"),hid,@"TappCompanionPreview");
    if(!rep)return;
    BOOL down=((BOOL(*)(id,SEL))objc_msgSend)(rep,NSSelectorFromString(@"isTouchDown"));
    BOOL lift=((BOOL(*)(id,SEL))objc_msgSend)(rep,NSSelectorFromString(@"isLift"));
    BOOL cancel=((BOOL(*)(id,SEL))objc_msgSend)(rep,NSSelectorFromString(@"isCancel"));
    CGPoint point=((CGPoint(*)(id,SEL))objc_msgSend)(rep,NSSelectorFromString(@"location"));
    eventCount++;
    if(down) { tracking=YES; downAt=CACurrentMediaTime(); downPoint=point; }
    if(cancel || (tracking && hypot(point.x-downPoint.x,point.y-downPoint.y)>36))tracking=NO;
    if(lift) { BOOL tap=tracking && CACurrentMediaTime()-downAt<.7; tracking=NO; if(tap)Wake(@"native-cross-app-tap"); }
}
static NSDictionary *Request(void) {
    NSData *data=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"request.json"]];
    return data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
}
static void Publish(void) {
    CGRect rect=[renderer interactionRect];
    NSDictionary *state=@{@"session":session,@"phase":phase,@"name":name,@"wakeCount":@(wakeCount),@"eventCount":@(eventCount),@"x":@(rect.origin.x),@"y":@(rect.origin.y),@"width":@(rect.size.width),@"height":@(rect.size.height)};
    if(CGRectIsNull(rect))state=@{@"session":session,@"phase":phase,@"name":name,@"wakeCount":@(wakeCount),@"eventCount":@(eventCount)};
    [[NSJSONSerialization dataWithJSONObject:state options:0 error:nil] writeToFile:[directory stringByAppendingPathComponent:@"state.json"] atomically:YES];
}
int main(int argc,char **argv) { @autoreleasepool {
    if(argc!=4 || ![NSProcessInfo.processInfo.environment[@"SIMULATOR_UDID"] isEqualToString:@"8B65F7CB-757A-43EA-BC00-A1A3A195E051"])return 2;
    directory=@(argv[1]); session=@(argv[2]);
    NSDictionary *request=Request(); if(![request[@"session"] isEqual:session])return 3;
    name=request[@"name"]; quiet=[request[@"quiet"] boolValue];
    void *bks=dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices",RTLD_NOW);
    void *gs=dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices",RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities",RTLD_NOW);
    void (*start)(void)=bks?dlsym(bks,"BKSDisplayServicesStart"):NULL;
    void (*initialize)(int)=gs?dlsym(gs,"GSEventInitialize"):NULL;
    void (*registerEvent)(void*)=bks?dlsym(bks,"BKSHIDEventRegisterEventCallback"):NULL;
    if(!start||!initialize||!registerEvent||!NSClassFromString(@"AXEventRepresentation"))return 4;
    start(); initialize(0); registerEvent(Event);
    UIImage *sheet=[UIImage imageWithContentsOfFile:@(argv[3])]; NSInteger style=[request[@"style"] integerValue];
    if(!sheet || style<0 || style>2)return 5;
    size_t side=CGImageGetWidth(sheet.CGImage)/3;
    CGImageRef crop=CGImageCreateWithImageInRect(sheet.CGImage,CGRectMake(side*style,0,side,CGImageGetHeight(sheet.CGImage)));
    UIImage *art=[UIImage imageWithCGImage:crop];CGImageRelease(crop);
    renderer=[DraftRocketRenderer new];NSError *error=nil;
    renderer.accentColor = DraftColorFromHex(request[@"color"] ?: @"");
    renderer.islandHome = [request[@"islandHome"] boolValue];
    art = DraftTintedImage(art, renderer.accentColor);
    if(![renderer startWithImage:art pointSize:[request[@"size"] doubleValue] style:style motion:!quiet error:&error]) { Record(error.localizedDescription);return 6; }
    Class dc=NSClassFromString(@"CADisplay"),cc=NSClassFromString(@"CAContext");
    id display=((id(*)(id,SEL))objc_msgSend)(dc,NSSelectorFromString(@"mainDisplay"));
    unsigned displayID=((unsigned(*)(id,SEL))objc_msgSend)(display,NSSelectorFromString(@"displayId"));
    CGRect bounds=((CGRect(*)(id,SEL))objc_msgSend)(display,NSSelectorFromString(@"bounds"));
    displayScale=bounds.size.width/UIScreen.mainScreen.bounds.size.width;
    void *q=dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore",RTLD_NOW);
    NSMutableDictionary *options=[NSMutableDictionary dictionary];
    for(NSString *s in @[@"kCAContextDisplayId",@"kCAContextDisplayable",@"kCAContextIgnoresHitTest"]) {
      NSString *__unsafe_unretained *key=(NSString *__unsafe_unretained *)dlsym(q,s.UTF8String);if(!key||!*key)return 7;
      options[*key]=[s isEqualToString:@"kCAContextDisplayId"]?@(displayID):@([s isEqualToString:@"kCAContextDisplayable"]);
    }
    inputContext=((id(*)(id,SEL,id))objc_msgSend)(cc,NSSelectorFromString(@"remoteContextWithOptions:"),options);
    if(!inputContext)return 8;
    ((void(*)(id,SEL,float))objc_msgSend)(inputContext,NSSelectorFromString(@"setLevel:"),10000011);
    inputLayer=[CALayer layer];inputLayer.backgroundColor=UIColor.clearColor.CGColor;
    // A transparent visual must still own its small rectangular touch region.
    SEL opaqueHit=NSSelectorFromString(@"setHitTestsAsOpaque:");
    if(![inputLayer respondsToSelector:opaqueHit]) { Record(@"transparent touch regions unavailable");return 9; }
    ((void(*)(id,SEL,BOOL))objc_msgSend)(inputLayer,opaqueHit,YES);
    ((void(*)(id,SEL,id))objc_msgSend)(inputContext,NSSelectorFromString(@"setLayer:"),inputLayer);
    deadline=CACurrentMediaTime()+180;
    [renderer beginTourForDuration:180 motion:!quiet];
    phase=[renderer motionPhase];
    Record([NSString stringWithFormat:@"started %@ pid=%d native-input-context",name,getpid()]);
    NSString *sequence=request[@"sequence"];double nextIO=0;
    while(CACurrentMediaTime()<deadline) { @autoreleasepool {
      double now=CACurrentMediaTime();
      NSString *currentPhase=[renderer motionPhase];
      if(![phase isEqual:currentPhase]) { phase=currentPhase; Record([NSString stringWithFormat:@"phase %@ %@",name,phase]); }
      CGRect rect=[renderer interactionRect];
      [CATransaction begin];[CATransaction setDisableActions:YES];
      if(CGRectIsNull(rect))inputLayer.hidden=YES;
      else { inputLayer.hidden=NO;inputLayer.bounds=CGRectMake(0,0,rect.size.width*displayScale,rect.size.height*displayScale);inputLayer.position=CGPointMake(CGRectGetMidX(rect)*displayScale,CGRectGetMidY(rect)*displayScale); }
      [CATransaction commit];[CATransaction flush];
      if(now>=nextIO) {
        nextIO=now+.1;request=Request();
        if(![request[@"session"] isEqual:session] || [request[@"command"] isEqual:@"stop"])break;
        if(![request[@"sequence"] isEqual:sequence]) {
          sequence=request[@"sequence"];
          if([request[@"command"] isEqual:@"wake"])Wake(@"accessible-companion-tap");
          if([request[@"command"] isEqual:@"rest"]) { [renderer settle];phase=[renderer motionPhase]; }
          if([request[@"command"] isEqual:@"expression"]) {
              [renderer playExpression:request[@"expression"] ?: @"hello"];
              Record([NSString stringWithFormat:@"expression %@ %@", name, request[@"expression"] ?: @"hello"]);
          }
          if([request[@"command"] isEqual:@"island"]) {
              [renderer playIslandAction:request[@"islandAction"] ?: @"peek"];
              Record([NSString stringWithFormat:@"island %@ %@", name, request[@"islandAction"] ?: @"peek"]);
          }
        }
        Publish();
      }
      CFRunLoopRunInMode(kCFRunLoopDefaultMode,1.0/60.0,false);
    }}
    ((void(*)(id,SEL))objc_msgSend)(inputContext,NSSelectorFromString(@"invalidate"));inputContext=nil;
    [renderer invalidate];renderer=nil;phase=@"stopped";Publish();Record([NSString stringWithFormat:@"stopped %@ events=%u wakes=%u",name,eventCount,wakeCount]);
 }return 0; }
