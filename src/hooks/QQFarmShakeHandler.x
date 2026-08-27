#import <UIKit/UIKit.h>
#import "../ui/QQFarmOverlay.h"
#import "../utils/QQFarmUtils.h"

// Hook UIWindow to detect shake gesture
%hook UIWindow

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake) {
        // 摇一摇作为备用呼出方式：无论是否已截获 Code 都显示面板
        // 在主线程显示悬浮窗
        dispatch_async(dispatch_get_main_queue(), ^{
            QQFarmOverlay *overlay = [QQFarmOverlay sharedInstance];
            // iOS 13+ 要求 UIWindow 必须挂到 UIWindowScene 才能显示，
            // 否则即使 hidden=NO 也不会渲染（悬浮窗在 iOS13+ 不显示的修复）
            if (@available(iOS 13.0, *)) {
                if (!overlay.windowScene) {
                    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                        if ([scene isKindOfClass:[UIWindowScene class]]) {
                            overlay.windowScene = (UIWindowScene *)scene;
                            break;
                        }
                    }
                }
            }
            [overlay showWithCode:[QQFarmUtils getLastCapturedCode]];
        });
    }
    %orig;
}

// 确保视图控制器支持摇一摇
- (BOOL)canBecomeFirstResponder {
    return YES;
}

%end
