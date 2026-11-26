#import <Foundation/Foundation.h>
#import <objc/message.h>

// Observe lifecycle before XCTest's early-background path. Never replace or
// dismiss a system prompt, and never authorize automation.
@interface PocketRunnerStatusBootstrap : NSObject
@end
@implementation PocketRunnerStatusBootstrap
+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class bridge = NSClassFromString(@"PocketRunnerActivityBridge");
        SEL install = NSSelectorFromString(@"install");
        if ([bridge respondsToSelector:install]) {
            ((void (*)(id, SEL))objc_msgSend)(bridge, install);
        }
    });
}
@end
