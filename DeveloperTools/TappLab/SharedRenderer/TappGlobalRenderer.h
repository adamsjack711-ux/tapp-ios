#import <UIKit/UIKit.h>

/// Private-API research renderer. A valid context is not proof of visibility.
/// Does not dispatch input, change accessibility settings or request entitlements.
@interface TappGlobalRenderer : NSObject
@property(nonatomic,readonly) unsigned contextIdentifier;
@property(nonatomic,readonly) CGRect displayBounds;
@property(nonatomic,readonly) BOOL contextValid;
/// Readback only; even a matching ID still requires independent visual evidence.
@property(nonatomic,readonly) unsigned attachedDisplayIdentifier;
@property(nonatomic,readonly) NSDictionary *diagnostics;
- (BOOL)start:(NSError **)error;
- (void)moveToNormalizedPoint:(CGPoint)point;
- (void)park;
- (void)invalidate;
@end
