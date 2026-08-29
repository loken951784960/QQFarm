#import <UIKit/UIKit.h>

// 悬浮窗关闭后发出，用于让常驻小球重新显示
#define kQQFarmOverlayDidHideNotification @"kQQFarmOverlayDidHideNotification"

@interface QQFarmOverlay : UIWindow

+ (instancetype)sharedInstance;
- (void)showWithCode:(NSString *)code;
- (void)hide;

@end
