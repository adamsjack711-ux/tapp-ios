#import <TargetConditionals.h>
#if !TARGET_OS_SIMULATOR
#error This draft renderer must never be compiled for a physical phone.
#endif
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
int DraftSpawnCompanionRuntime(NSString *directory, NSString *session);
UIColor * _Nullable DraftColorFromHex(NSString *hex);
UIImage *DraftTintedImage(UIImage *image, UIColor * _Nullable color);
@interface DraftRocketRenderer : NSObject
@property(nonatomic,strong,nullable) UIColor *accentColor;
@property(nonatomic) BOOL islandHome;
- (BOOL)startWithImage:(UIImage *)image pointSize:(double)pointSize style:(NSInteger)style motion:(BOOL)motion error:(NSError **)error;
- (void)beginTourForDuration:(double)duration motion:(BOOL)motion;
- (void)wake;
- (void)settle;
- (void)playExpression:(NSString *)expression;
- (void)playIslandAction:(NSString *)action;
- (CGRect)interactionRect;
- (NSString *)motionPhase;
- (void)invalidate;
@end
// The same compositor animations are used inside Tapp and on the simulator display.
@interface DraftCursorView : UIView
@property(nonatomic,strong,nullable) UIColor *accentColor;
- (void)configureWithImage:(UIImage *)image size:(double)size style:(NSInteger)style motion:(BOOL)motion;
- (void)playExpression:(NSString *)expression;
@end
NS_ASSUME_NONNULL_END
