#import <Foundation/Foundation.h>
#import "src/ui/QQFarmOverlay.h"
#import "src/utils/QQFarmUtils.h"

%ctor {
    NSLog(@"[QQFarm] 插件已加载，准备拦截 WebSocket 请求...");

    // 在主线程初始化悬浮窗与默认配置（默认配置会写入设备 config.plist，开箱即用）
    dispatch_async(dispatch_get_main_queue(), ^{
        [QQFarmUtils ensureDefaultConfig];
        [QQFarmOverlay sharedInstance];
        NSLog(@"[QQFarm] 悬浮窗及配置已初始化");
    });
}
