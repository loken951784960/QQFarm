#import "QQFarmUtils.h"
#import <UIKit/UIKit.h>
#import <Security/Security.h>

// 默认服务器与 Token（开箱即用，也会写入设备 config.plist）
// 注意：Token 使用后端 .env 中的 EXTERNAL_SUBMIT_TOKEN（外部提交接口专用静态令牌），
// 而不是后台管理员密码。外部接口 /api/external/submit-code 按 uin 去重，同一设备只会产生一个账号。
static NSString *const kQQFarmDefaultServer = @"http://106.55.41.254:3009";
static NSString *const kQQFarmDefaultToken  = @"qfb_1LnPCVb1e0NiMiV6dG7oaGnr6D2CcSVdfDk1x8tinmYQim";

static NSString *gLastCapturedCode = nil;
static NSString *gLastUploadedCode = nil;

@implementation QQFarmUtils

+ (void)checkAndExtractCode:(NSURL *)url {
    if (!url) return;

    NSString *urlString = url.absoluteString;

    // 调试：先打印所有疑似 WebSocket 的 URL（便于定位实际地址）
    BOOL isWebSocket = [urlString hasPrefix:@"ws://"] || [urlString hasPrefix:@"wss://"] ||
                       [urlString containsString:@"/ws"] || [urlString containsString:@"websocket"];
    BOOL qqRelated = [urlString containsString:@"qq.com"] || [urlString containsString:@"nqf.qq.com"] ||
                     [urlString containsString:@"nq.qq.com"];
    if (isWebSocket && qqRelated) {
        NSLog(@"[QQFarm] 🔍 WS 候选 URL: %@", urlString);
    }

    // 目标地址放宽：旧版 gate-obt.nqf.qq.com/prod/ws 仍优先，同时兼容子域名/路径变化
    // 新增：只要 ws/wss 指向 qq.com 域，也视为目标（覆盖路径不带 /ws 的新地址）
    BOOL isTarget = [urlString containsString:@"nqf.qq.com"] ||
                    [urlString containsString:@"nq.qq.com"] ||
                    ([urlString containsString:@"qq.com"] &&
                     ([urlString containsString:@"/ws"] ||
                      [urlString hasPrefix:@"ws://"] ||
                      [urlString hasPrefix:@"wss://"]));
    if (!isTarget) return;

    NSLog(@"[QQFarm] 🎯 捕获到目标 WebSocket URL: %@", urlString);

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSArray<NSURLQueryItem *> *queryItems = components.queryItems ?: @[];

    // 1) 优先取名为 code 的参数
    NSString *code = nil;
    for (NSURLQueryItem *item in queryItems) {
        if ([item.name isEqualToString:@"code"]) {
            code = item.value;
            break;
        }
    }
    // 2) 兜底：名字里含 code/token 且长度 >= 8 的参数
    if (!code || code.length == 0) {
        for (NSURLQueryItem *item in queryItems) {
            NSString *nameLower = [item.name lowercaseString];
            if (([nameLower containsString:@"code"] || [nameLower containsString:@"token"]) && item.value.length >= 8) {
                code = item.value;
                break;
            }
        }
    }

    if (code && code.length > 0) {
        NSLog(@"[QQFarm] ✅ 成功提取 Code: %@", code);

        // 保存 Code
        gLastCapturedCode = [code copy];

        // 复制到剪贴板 + 发通知（供悬浮窗回显）
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIPasteboard generalPasteboard].string = code;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"kQQFarmCodeCapturedNotification" object:nil userInfo:@{@"code": code}];
        });

        // 零点击自动上传到后端
        [self uploadCodeAutomatically:code];
    } else {
        NSMutableArray *names = [NSMutableArray array];
        for (NSURLQueryItem *item in queryItems) { [names addObject:item.name]; }
        NSLog(@"[QQFarm] ⚠️ 目标 URL 未找到 code 参数，参数名列表: %@", names);
    }
}

+ (NSString *)getLastCapturedCode {
    return gLastCapturedCode;
}

#pragma mark - 默认配置（开箱即用）

+ (NSString *)configFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *dir = [paths.firstObject stringByAppendingPathComponent:@"QQFarm"];
    return [dir stringByAppendingPathComponent:@"config.plist"];
}

// 首次启动时写入默认服务器/Token 配置（已存在则保留用户设置，不覆盖）
+ (void)ensureDefaultConfig {
    NSString *path = [self configFilePath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) return;

    NSString *dir = [path stringByDeletingLastPathComponent];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

    NSDictionary *cfg = @{
        @"QQFarmServer": kQQFarmDefaultServer,
        @"QQFarmToken":  kQQFarmDefaultToken
    };
    BOOL ok = [cfg writeToFile:path atomically:YES];
    NSLog(@"[QQFarm] %@写入默认配置 -> %@", ok ? @"✅" : @"❌", path);
}

#pragma mark - 稳定设备标识（后端据此去重，避免每次识别都新建账号）

// 在 Keychain 持久化一个设备级 UUID：即使重装 deb / App 也不变，
// 后端把它当作同一账号的稳定标识，重复识别时更新而非新建。
+ (NSString *)deviceId {
    static NSString *const kService = @"com.i80k.qqfarm";
    static NSString *const kAccount = @"deviceId";
    NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService: kService,
                            (__bridge id)kSecAttrAccount: kAccount,
                            (__bridge id)kSecReturnData: @YES,
                            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne};
    CFTypeRef dataRef = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)query, &dataRef);
    if (st == errSecSuccess && dataRef) {
        NSData *d = (__bridge_transfer NSData *)dataRef;
        NSString *sid = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (sid.length) return sid;
    }
    NSString *newId = [[NSUUID UUID] UUIDString];
    NSData *nd = [newId dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *add = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                          (__bridge id)kSecAttrService: kService,
                          (__bridge id)kSecAttrAccount: kAccount,
                          (__bridge id)kSecValueData: nd};
    SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    return newId;
}

#pragma mark - 零点击自动上传

+ (NSString *)normalizeServerURL:(NSString *)server {
    if (!server || server.length == 0) return server;
    NSString *trimmed = [server stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    // 补回可能丢失的 scheme，避免 UI/用户输入成 http:1.2.3.4:3007 导致上传失败
    if (![trimmed hasPrefix:@"http://"] && ![trimmed hasPrefix:@"https://"]) {
        trimmed = [NSString stringWithFormat:@"http://%@", trimmed];
    }
    return trimmed;
}

+ (void)uploadCodeAutomatically:(NSString *)code {
    if (!code || code.length == 0) return;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        // 优先读用户配置，缺失则用内置默认值
        NSDictionary *cfg = [NSDictionary dictionaryWithContentsOfFile:[QQFarmUtils configFilePath]];
        NSString *server = cfg[@"QQFarmServer"];
        NSString *token  = cfg[@"QQFarmToken"];
        if (!server || server.length == 0) server = kQQFarmDefaultServer;
        if (!token  || token.length == 0)  token  = kQQFarmDefaultToken;

        // 同一 code 不重复上传（避免重连时反复提交）
        if ([gLastUploadedCode isEqualToString:code]) {
            NSLog(@"[QQFarm] 自动上传跳过：code 与上一次相同");
            return;
        }

        // 使用专为 iOS deb 设计的外部提交接口（静态 token 鉴权，按 uin 去重）：
        //   GET /api/external/submit-code?token=<EXTERNAL_SUBMIT_TOKEN>&code=<code>&uin=<设备ID>&platform=qq
        // 同一台设备重复识别只会更新同一个账号，不会每次都新建。
        NSString *base = [self normalizeServerURL:server];
        if ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
        NSURLComponents *comp = [NSURLComponents componentsWithString:[base stringByAppendingString:@"/api/external/submit-code"]];
        if (!comp) {
            NSLog(@"[QQFarm] 自动上传失败：服务器地址非法 -> %@", base);
            return;
        }
        NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
        [items addObject:[NSURLQueryItem queryItemWithName:@"token" value:token]];
        [items addObject:[NSURLQueryItem queryItemWithName:@"code" value:code]];
        [items addObject:[NSURLQueryItem queryItemWithName:@"uin" value:[QQFarmUtils deviceId]]];
        [items addObject:[NSURLQueryItem queryItemWithName:@"platform" value:@"qq"]];
        comp.queryItems = items;
        NSURL *url = comp.URL;
        if (!url) {
            NSLog(@"[QQFarm] 自动上传失败：无法组装 URL -> %@", base);
            return;
        }

        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = @"GET";
        req.timeoutInterval = 15;

        NSLog(@"[QQFarm] 🚀 自动上传 code 到 %@", url);
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
            completionHandler:^(NSData *respData, NSURLResponse *response, NSError *e) {
                if (e) {
                    NSLog(@"[QQFarm] 自动上传网络错误: %@", e.localizedDescription);
                    return;
                }
                NSInteger status = [(NSHTTPURLResponse *)response statusCode];
                if (status >= 200 && status < 300) {
                    gLastUploadedCode = [code copy];
                    NSLog(@"[QQFarm] ✅ 自动上传成功 (HTTP %ld)，后端已建档并自动上线", (long)status);
                } else {
                    NSString *resp = respData ? [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding] : @"";
                    NSLog(@"[QQFarm] 自动上传失败 HTTP %ld -> %@", (long)status, resp);
                }
            }];
        [task resume];
    });
}

#pragma mark - 好友 RPC 原始字节上传（与内置抓包等价）

+ (void)handleFriendMessage:(NSData *)message {
    if (!message || message.length == 0) return;

    // 好友列表 RPC 回复是 gatepb.Message(protobuf)，其中 meta.service_name 字段为明文
    // ASCII 字符串 "gamepb.friendpb.FriendService"，在 protobuf 字节中原样出现。
    // 直接按字节搜索该串即可识别好友 RPC 回复，无需完整 protobuf 解析。
    NSData *needle = [@"gamepb.friendpb.FriendService" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange r = [message rangeOfData:needle options:0 range:NSMakeRange(0, message.length)];
    if (r.location == NSNotFound) return;

    NSLog(@"[QQFarm] 🎯 命中好友 RPC 回复，上传原始字节 (%lu bytes)", (unsigned long)message.length);
    [self uploadFriendBlobAutomatically:message];
}

+ (void)uploadFriendBlobAutomatically:(NSData *)blob {
    if (!blob || blob.length == 0) return;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSDictionary *cfg = [NSDictionary dictionaryWithContentsOfFile:[QQFarmUtils configFilePath]];
        NSString *server = cfg[@"QQFarmServer"];
        NSString *token  = cfg[@"QQFarmToken"];
        if (!server || server.length == 0) server = kQQFarmDefaultServer;
        if (!token  || token.length == 0)  token  = kQQFarmDefaultToken;

        NSString *base = [self normalizeServerURL:server];
        if ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
        NSURL *url = [NSURL URLWithString:[base stringByAppendingString:@"/api/external/submit-friend-blob"]];
        if (!url) {
            NSLog(@"[QQFarm] blob 上传失败：服务器地址非法 -> %@", base);
            return;
        }

        NSString *b64 = [blob base64EncodedStringWithOptions:0];
        NSDictionary *body = @{@"token": token, @"uin": [QQFarmUtils deviceId], @"blob": b64};
        NSError *err = nil;
        NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&err];
        if (!bodyData) {
            NSLog(@"[QQFarm] blob 序列化失败: %@", err);
            return;
        }

        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = @"POST";
        req.timeoutInterval = 15;
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        req.HTTPBody = bodyData;

        NSLog(@"[QQFarm] 🚀 上传好友 RPC blob (base64 %lu chars)", (unsigned long)b64.length);
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
            completionHandler:^(NSData *respData, NSURLResponse *response, NSError *e) {
                if (e) {
                    NSLog(@"[QQFarm] blob 上传网络错误: %@", e.localizedDescription);
                    return;
                }
                NSInteger status = [(NSHTTPURLResponse *)response statusCode];
                if (status >= 200 && status < 300) {
                    NSLog(@"[QQFarm] ✅ blob 上传成功 (HTTP %ld)，后端已解析并写入好友 gid", (long)status);
                } else {
                    NSString *resp = respData ? [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding] : @"";
                    NSLog(@"[QQFarm] blob 上传失败 HTTP %ld -> %@", (long)status, resp);
                }
            }];
        [task resume];
    });
}

@end
