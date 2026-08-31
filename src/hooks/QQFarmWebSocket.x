#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../utils/QQFarmUtils.h"

// 声明 SRWebSocket 接口以避免编译警告
@interface SRWebSocket : NSObject
- (id)initWithURLRequest:(NSURLRequest *)request;
- (id)initWithURL:(NSURL *)url;
- (void)setDelegate:(id)delegate;
@end

#pragma mark - 运行时 swizzle 助手

// 记录已 swizzle 的 (类, 方法)，避免重复
static NSMutableDictionary *gOrigImp() {
    static NSMutableDictionary *d = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [NSMutableDictionary dictionary]; });
    return d;
}

static NSString *swizzleKeyFor(Class cls, SEL sel) {
    return [NSString stringWithFormat:@"%@_%s", NSStringFromClass(cls), sel_getName(sel)];
}

// 把 cls 的 sel 原实现存到桥接 selector __qqfarm_orig_<sel>，并将 sel 替换为 newImp。
// 一个 (cls,sel) 只做一次。
static void swizzleInstanceMethodOnce(Class cls, SEL sel, IMP newImp) {
    if (!cls || !sel || !newImp) return;
    NSMutableDictionary *imp = gOrigImp();
    NSString *k = swizzleKeyFor(cls, sel);
    @synchronized(imp) {
        if (imp[k] != nil) return;
        if (![cls instancesRespondToSelector:sel]) return;
        Method m = class_getInstanceMethod(cls, sel);
        IMP orig = method_getImplementation(m);
        imp[k] = [NSValue valueWithPointer:(orig ?: (IMP)1)];
        SEL bridge = NSSelectorFromString([NSString stringWithFormat:@"__qqfarm_orig_%s", sel_getName(sel)]);
        class_addMethod(cls, bridge, orig, method_getTypeEncoding(m));
        method_setImplementation(m, newImp);
    }
}

// NSURLSession WebSocket 接收（iOS 13+）：- (void)URLSession:webSocketTask:didReceiveMessageWith:
static void QQFarm_NSURLSessionWebSocketReceive(id self, SEL _cmd,
    NSURLSession *session, NSURLSessionWebSocketTask *task, NSURLSessionWebSocketMessage *message) {
    NSData *data = nil;
    if ([message respondsToSelector:@selector(data)]) data = message.data;
    else if ([message respondsToSelector:@selector(string)]) {
        NSString *str = message.string;
        data = [str dataUsingEncoding:NSUTF8StringEncoding];
    }
    if (data) [QQFarmUtils handleFriendMessage:data];
    SEL bridge = NSSelectorFromString([NSString stringWithFormat:@"__qqfarm_orig_%s", sel_getName(_cmd)]);
    if ([self respondsToSelector:bridge]) {
        ((void(*)(id,SEL,NSURLSession*,NSURLSessionWebSocketTask*,NSURLSessionWebSocketMessage*))objc_msgSend)
            (self, bridge, session, task, message);
    }
}

// SRWebSocket 老 API：- (void)webSocket:didReceiveMessage:(id)
static void QQFarm_SRWebSocketReceive(id self, SEL _cmd, SRWebSocket *ws, id message) {
    NSData *data = nil;
    if ([message isKindOfClass:[NSData class]]) data = message;
    else if ([message isKindOfClass:[NSString class]]) data = [message dataUsingEncoding:NSUTF8StringEncoding];
    if (data) [QQFarmUtils handleFriendMessage:data];
    SEL bridge = NSSelectorFromString([NSString stringWithFormat:@"__qqfarm_orig_%s", sel_getName(_cmd)]);
    if ([self respondsToSelector:bridge]) {
        ((void(*)(id,SEL,SRWebSocket*,id))objc_msgSend)(self, bridge, ws, message);
    }
}

// SRWebSocket 新 API：- (void)webSocket:didReceiveMessageWithData:(NSData *)
static void QQFarm_SRWebSocketReceiveData(id self, SEL _cmd, SRWebSocket *ws, NSData *data) {
    if (data) [QQFarmUtils handleFriendMessage:data];
    SEL bridge = NSSelectorFromString([NSString stringWithFormat:@"__qqfarm_orig_%s", sel_getName(_cmd)]);
    if ([self respondsToSelector:bridge]) {
        ((void(*)(id,SEL,SRWebSocket*,NSData*))objc_msgSend)(self, bridge, ws, data);
    }
}

// SRWebSocket 新 API：- (void)webSocket:didReceiveMessageWithString:(NSString *)
static void QQFarm_SRWebSocketReceiveString(id self, SEL _cmd, SRWebSocket *ws, NSString *str) {
    NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
    if (data) [QQFarmUtils handleFriendMessage:data];
    SEL bridge = NSSelectorFromString([NSString stringWithFormat:@"__qqfarm_orig_%s", sel_getName(_cmd)]);
    if ([self respondsToSelector:bridge]) {
        ((void(*)(id,SEL,SRWebSocket*,NSString*))objc_msgSend)(self, bridge, ws, str);
    }
}

static void trySwizzleSessionDelegate(id delegate) {
    if (!delegate) return;
    swizzleInstanceMethodOnce([delegate class],
        @selector(URLSession:webSocketTask:didReceiveMessageWith:),
        (IMP)QQFarm_NSURLSessionWebSocketReceive);
}

static void trySwizzleSRDelegate(id delegate) {
    if (!delegate) return;
    Class cls = [delegate class];
    swizzleInstanceMethodOnce(cls, @selector(webSocket:didReceiveMessage:), (IMP)QQFarm_SRWebSocketReceive);
    swizzleInstanceMethodOnce(cls, @selector(webSocket:didReceiveMessageWithData:), (IMP)QQFarm_SRWebSocketReceiveData);
    swizzleInstanceMethodOnce(cls, @selector(webSocket:didReceiveMessageWithString:), (IMP)QQFarm_SRWebSocketReceiveString);
}

#pragma mark - 钩子：SRWebSocket (第三方库/小程序容器)
%hook SRWebSocket

- (id)initWithURLRequest:(NSURLRequest *)request {
    if (request && request.URL) [QQFarmUtils checkAndExtractCode:request.URL];
    return %orig;
}

- (id)initWithURL:(NSURL *)url {
    [QQFarmUtils checkAndExtractCode:url];
    return %orig;
}

// 在 delegate 被设置时，动态 swizzle 其接收方法，从而拿到好友 RPC 回复
- (void)setDelegate:(id)delegate {
    trySwizzleSRDelegate(delegate);
    %orig;
}

%end

#pragma mark - 钩子：NSURLSession (iOS 原生 WebSocket)
%hook NSURLSession

- (NSURLSessionWebSocketTask *)webSocketTaskWithURL:(NSURL *)url {
    NSURLSessionWebSocketTask *task = %orig;
    [QQFarmUtils checkAndExtractCode:url];
    trySwizzleSessionDelegate(self.delegate);
    return task;
}

- (NSURLSessionWebSocketTask *)webSocketTaskWithURL:(NSURL *)url protocols:(NSArray<NSString *> *)protocols {
    NSURLSessionWebSocketTask *task = %orig;
    [QQFarmUtils checkAndExtractCode:url];
    trySwizzleSessionDelegate(self.delegate);
    return task;
}

- (NSURLSessionWebSocketTask *)webSocketTaskWithRequest:(NSURLRequest *)request {
    if (request && request.URL) [QQFarmUtils checkAndExtractCode:request.URL];
    NSURLSessionWebSocketTask *task = %orig;
    trySwizzleSessionDelegate(self.delegate);
    return task;
}

%end

#pragma mark - 兜底：URL 创建时检查（保持原有逻辑）
%hook NSURL

+ (instancetype)URLWithString:(NSString *)URLString {
    NSURL *url = %orig;
    if (url) [QQFarmUtils checkAndExtractCode:url];
    return url;
}

%end

%hook NSURLRequest

+ (NSURLRequest *)requestWithURL:(NSURL *)url {
    if (url) [QQFarmUtils checkAndExtractCode:url];
    return %orig;
}

- (instancetype)initWithURL:(NSURL *)url {
    if (url) [QQFarmUtils checkAndExtractCode:url];
    return %orig;
}

%end

%hook NSMutableURLRequest

+ (NSMutableURLRequest *)requestWithURL:(NSURL *)url {
    if (url) [QQFarmUtils checkAndExtractCode:url];
    return %orig;
}

- (instancetype)initWithURL:(NSURL *)url {
    if (url) [QQFarmUtils checkAndExtractCode:url];
    return %orig;
}

%end

#pragma mark - 兼容 Starscream / PocketSocket
%hook WebSocket

- (id)initWithURL:(NSURL *)url {
    if (url) [QQFarmUtils checkAndExtractCode:url];
    return %orig;
}

- (id)initWithURL:(NSURL *)url protocols:(NSArray<NSString *> *)protocols {
    if (url) [QQFarmUtils checkAndExtractCode:url];
    return %orig;
}

%end

%hook PSWebSocket

- (id)initWithURL:(NSURL *)url {
    if (url) [QQFarmUtils checkAndExtractCode:url];
    return %orig;
}

- (id)initWithURL:(NSURL *)url protocols:(NSArray<NSString *> *)protocols {
    if (url) [QQFarmUtils checkAndExtractCode:url];
    return %orig;
}

%end
