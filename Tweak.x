#import <Foundation/Foundation.h>
#import "src/ui/QQFarmOverlay.h"
#import "src/ui/QQFarmFloatingBall.h"
#import "src/utils/QQFarmUtils.h"

%ctor {
    NSLog(@"[QQFarm] 插件已加载，准备拦截 WebSocket 请求...");

    // 在主线程初始化悬浮窗、常驻小球与默认配置
    dispatch_async(dispatch_get_main_queue(), ^{
        [QQFarmUtils ensureDefaultConfig];
        [QQFarmOverlay sharedInstance];
        [QQFarmFloatingBall sharedInstance]; // 常驻悬浮小球，点一下即可呼出面板
        NSLog(@"[QQFarm] 悬浮窗及配置已初始化");
    });
}
