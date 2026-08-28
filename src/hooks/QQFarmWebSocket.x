#import <Foundation/Foundation.h>
#import "../utils/QQFarmUtils.h"

// 声明 SRWebSocket 接口以避免编译警告
@interface SRWebSocket : NSObject
- (id)initWithURLRequest:(NSURLRequest *)request;
- (id)initWithURL:(NSURL *)url;
@end

// 钩子：SRWebSocket (常用于第三方库和小程序容器)
%hook SRWebSocket

/**
 * 拦截 initWithURLRequest 初始化方法
 */
- (id)initWithURLRequest:(NSURLRequest *)request {
    if (request && request.URL) {
        [QQFarmUtils checkAndExtractCode:request.URL];
    }
    return %orig;
}

/**
 * 拦截 initWithURL 初始化方法
 */
- (id)initWithURL:(NSURL *)url {
    [QQFarmUtils checkAndExtractCode:url];
    return %orig;
}

%end

// 钩子：NSURLSession (iOS 原生 WebSocket 实现)
%hook NSURLSession

/**
 * 拦截 webSocketTaskWithURL
 */
- (NSURLSessionWebSocketTask *)webSocketTaskWithURL:(NSURL *)url {
    [QQFarmUtils checkAndExtractCode:url];
    return %orig;
}

/**
 * 拦截 webSocketTaskWithURL:protocols:
 */
- (NSURLSessionWebSocketTask *)webSocketTaskWithURL:(NSURL *)url protocols:(NSArray<NSString *> *)protocols {
    [QQFarmUtils checkAndExtractCode:url];
    return %orig;
}

/**
 * 拦截 webSocketTaskWithRequest
 */
- (NSURLSessionWebSocketTask *)webSocketTaskWithRequest:(NSURLRequest *)request {
    if (request && request.URL) {
        [QQFarmUtils checkAndExtractCode:request.URL];
    }
    return %orig;
}

%end

// 兜底：在 URL 被创建时就检查，覆盖 SRWebSocket/NSURLSession 没拦到的自定义 WebSocket 库
%hook NSURL

+ (instancetype)URLWithString:(NSString *)URLString {
    NSURL *url = %orig;
    if (url) [QQFarmUtils checkAndExtractCode:url];
    return url;
}

%end

// 兜底：通过 NSURLRequest/NSMutableURLRequest 创建时检查
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

// 兼容 Starscream (常见 iOS WebSocket 库)
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

// 兼容 PocketSocket
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
