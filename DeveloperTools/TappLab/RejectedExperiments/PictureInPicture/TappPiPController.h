#import <UIKit/UIKit.h>

/// Public-API video companion experiment. This is not a touch-injecting cursor.
@interface TappPiPController : UIViewController
- (instancetype)initWithRecorder:(void (^)(NSString *, NSDictionary *))recorder;
- (void)stop;
@end
