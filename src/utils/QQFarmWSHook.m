#import "QQFarmWSHook.h"
#import "QQFarmUtils.h"
#import <objc/runtime.h>

// 给 NSURLSessionWebSocketTask 加一个"接收消息"的包装方法，用于截获 QQ 农场下发的
// 好友列表 protobuf（其中包含明文 service_name = gamepb.friendpb.FriendService）。
@implementation NSURLSessionWebSocketTask (QQFarmHook)

- (void)qqfarm_receiveMessageWithCompletionHandler:(void (^)(NSURLSessionWebSocketMessage * _Nullable))completionHandler {
    void (^wrapped)(NSURLSessionWebSocketMessage * _Nullable) = ^(NSURLSessionWebSocketMessage * _Nullable msg) {
        if (msg) {
            NSData *data = nil;
            if ([msg isKindOfClass:[NSData class]]) {
                data = (NSData *)msg;
            } else if ([msg respondsToSelector:@selector(data)]) {
                data = [msg data]; // NSURLSessionWebSocketMessage.data
            }
            if (data) [QQFarmUtils maybeCaptureFriendBlob:data];
        }
        if (completionHandler) completionHandler(msg);
    };
    // 经过 method_exchangeImplementations 后，下面这行实际调用的是原始实现
    [self qqfarm_receiveMessageWithCompletionHandler:wrapped];
}

@end

@implementation QQFarmWSHook

+ (void)install {
    Class cls = NSClassFromString(@"NSURLSessionWebSocketTask");
    if (!cls) {
        NSLog(@"[QQFarm] 未找到 NSURLSessionWebSocketTask，跳过 WS 钩子");
        return;
    }
    SEL sel = @selector(receiveMessageWithCompletionHandler:);
    if (![cls instancesRespondToSelector:sel]) {
        NSLog(@"[QQFarm] NSURLSessionWebSocketTask 不响应 receiveMessageWithCompletionHandler:，跳过");
        return;
    }
    Method orig = class_getInstanceMethod(cls, sel);
    Method repl = class_getInstanceMethod(cls, @selector(qqfarm_receiveMessageWithCompletionHandler:));
    if (orig && repl) {
        method_exchangeImplementations(orig, repl);
        NSLog(@"[QQFarm] ✅ 已 hook NSURLSessionWebSocketTask 收消息，用于自动捕获好友 GID");
    }
}

@end
