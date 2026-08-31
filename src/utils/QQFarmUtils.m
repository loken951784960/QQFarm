#import "QQFarmUtils.h"
#import <UIKit/UIKit.h>
#import <Security/Security.h>

// 默认服务器与 Token（开箱即用，也会写入设备 config.plist）
// 注意：Token 使用后端 .env 中的 EXTERNAL_SUBMIT_TOKEN（外部提交接口专用静态令牌），
// 而不是后台管理员密码。外部接口 /api/external/submit-code 按 uin 去重，同一设备只会产生一个账号。
static NSString *const kQQFarmDefaultServer = @"http://106.55.41.254:3007";
// 3007 后台 API 需要 x-admin-token；插件改为自动用管理员密码(默认 admin)登录 /api/login 换取，
// 因此这里内置空 token（运行时若未填写密码则回退到 "admin"）。
static NSString *const kQQFarmDefaultToken  = @"";

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

// 恢复默认配置：删除本地 config.plist 并重新写入默认服务器/Token
+ (void)restoreDefaultConfig {
    NSString *path = [self configFilePath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) {
        NSError *err = nil;
        [fm removeItemAtPath:path error:&err];
        if (err) {
            NSLog(@"[QQFarm] 删除旧配置失败: %@", err.localizedDescription);
        } else {
            NSLog(@"[QQFarm] ✅ 已删除旧配置: %@", path);
        }
    }
    [self ensureDefaultConfig];
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

    // 同一 code 不重复上传（避免重连时反复提交）
    if ([gLastUploadedCode isEqualToString:code]) {
        NSLog(@"[QQFarm] 自动上传跳过：code 与上一次相同");
        return;
    }

    // 优先读用户配置，缺失则用内置默认值
    NSDictionary *cfg = [NSDictionary dictionaryWithContentsOfFile:[QQFarmUtils configFilePath]];
    NSString *server = cfg[@"QQFarmServer"];
    NSString *token  = cfg[@"QQFarmToken"];
    if (!server || server.length == 0) server = kQQFarmDefaultServer;
    if (!token  || token.length == 0)  token  = kQQFarmDefaultToken;

    [self performSubmitCode:code server:server token:token completion:nil];
}

// 抓包登录核心：GET /api/external/submit-code?token=&code=&uin=<设备ID>&platform=qq
+ (void)performSubmitCode:(NSString *)code
                   server:(NSString *)server
                    token:(NSString *)token
               completion:(void (^)(BOOL ok, NSString *message))completion {
    if (!code || code.length == 0) {
        if (completion) completion(NO, @"无 code 可提交");
        return;
    }

    NSString *base = [self normalizeServerURL:server];
    if ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    NSURLComponents *comp = [NSURLComponents componentsWithString:[base stringByAppendingString:@"/api/external/submit-code"]];
    if (!comp) {
        if (completion) completion(NO, @"服务器地址非法");
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
        if (completion) completion(NO, @"无法组装 URL");
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 15;

    NSLog(@"[QQFarm] 🚀 提交 code 到 %@", url);
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *respData, NSURLResponse *response, NSError *e) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (e) {
                    if (completion) completion(NO, e.localizedDescription);
                    return;
                }
                NSInteger status = [(NSHTTPURLResponse *)response statusCode];
                if (status >= 200 && status < 300) {
                    gLastUploadedCode = [code copy];
                    NSLog(@"[QQFarm] ✅ 提交成功 (HTTP %ld)，后端已建档并自动上线", (long)status);
                    if (completion) completion(YES, [NSString stringWithFormat:@"登录成功 (HTTP %ld)", (long)status]);
                } else {
                    NSString *resp = respData ? [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding] : @"";
                    NSLog(@"[QQFarm] 提交失败 HTTP %ld -> %@", (long)status, resp);
                    if (completion) completion(NO, [NSString stringWithFormat:@"HTTP %ld: %@", (long)status, resp]);
                }
            });
        }];
    [task resume];
}

// 导入好友 GID：先自动登录换 token，再 POST /api/friend-known-gids/batch-add?accountId=<id>  body {"gids":[...]}
+ (void)uploadFriendGids:(NSArray<NSString *> *)gids
              forAccount:(NSString *)accountId
              completion:(void (^)(BOOL ok, NSString *message))completion {
    if (!accountId || accountId.length == 0) {
        if (completion) completion(NO, @"缺少 accountId");
        return;
    }

    // 清洗：去非数字、过滤长度、去重、转为数字
    NSMutableArray<NSNumber *> *valid = [NSMutableArray array];
    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    for (NSString *raw in gids) {
        NSString *s = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (s.length == 0) continue;
        NSMutableString *num = [NSMutableString string];
        for (NSUInteger i = 0; i < s.length; i++) {
            unichar c = [s characterAtIndex:i];
            if ([digits characterIsMember:c]) [num appendFormat:@"%C", c];
        }
        if (num.length < 5 || num.length > 12) continue; // GID 大致 9~11 位，放宽容错
        long long v = [num longLongValue];
        if (v <= 0) continue;
        NSNumber *n = @(v);
        if ([seen containsObject:n]) continue;
        [seen addObject:n];
        [valid addObject:n];
    }
    if (valid.count == 0) {
        if (completion) completion(NO, @"没有有效的 GID（每行一个，或逗号/空格分隔）");
        return;
    }

    NSDictionary *cfg = [NSDictionary dictionaryWithContentsOfFile:[QQFarmUtils configFilePath]];
    NSString *server = cfg[@"QQFarmServer"];
    NSString *password = cfg[@"QQFarmToken"];
    if (!server || server.length == 0) server = kQQFarmDefaultServer;
    if (!password || password.length == 0) password = @"admin";

    NSString *base = [self normalizeServerURL:server];
    if ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];

    NSError *jsonErr;
    NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"gids": valid} options:0 error:&jsonErr];
    if (!body) {
        if (completion) completion(NO, @"构建请求失败");
        return;
    }

    // 1) 登录换 token
    NSURL *loginUrl = [NSURL URLWithString:[base stringByAppendingString:@"/api/login"]];
    NSMutableURLRequest *loginReq = [NSMutableURLRequest requestWithURL:loginUrl];
    loginReq.HTTPMethod = @"POST";
    [loginReq setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    loginReq.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"username":@"admin", @"password":password} options:0 error:nil];
    loginReq.timeoutInterval = 15;

    [[[NSURLSession sharedSession] dataTaskWithRequest:loginReq completionHandler:^(NSData *lData, NSURLResponse *lResp, NSError *lErr){
        if (lErr) { dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, lErr.localizedDescription); }); return; }
        NSInteger lStatus = [(NSHTTPURLResponse *)lResp statusCode];
        if (lStatus != 200) {
            NSString *raw = lData ? [[NSString alloc] initWithData:lData encoding:NSUTF8StringEncoding] : @"";
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, [NSString stringWithFormat:@"登录失败(HTTP %ld): %@", (long)lStatus, raw]); });
            return;
        }
        NSError *je;
        NSDictionary *lj = [NSJSONSerialization JSONObjectWithData:lData options:0 error:&je];
        NSString *token = lj[@"data"][@"token"];
        if (!token) { dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, @"登录成功但未返回 token"); }); return; }

        // 2) 真正导入 GID
        NSURLComponents *comp = [NSURLComponents componentsWithString:[base stringByAppendingString:@"/api/friend-known-gids/batch-add"]];
        if (!comp) { dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, @"服务器地址非法"); }); return; }
        comp.queryItems = @[[NSURLQueryItem queryItemWithName:@"accountId" value:accountId]];
        NSURL *url = comp.URL;
        if (!url) { dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, @"无法组装 URL"); }); return; }

        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = @"POST";
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [req setValue:token forHTTPHeaderField:@"x-admin-token"];
        req.HTTPBody = body;
        req.timeoutInterval = 15;

        NSLog(@"[QQFarm] 🚀 导入 %lu 个好友 GID (accountId=%@)", (unsigned long)valid.count, accountId);
        [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *respData, NSURLResponse *response, NSError *e) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (e) { if (completion) completion(NO, e.localizedDescription); return; }
                NSInteger status = [(NSHTTPURLResponse *)response statusCode];
                NSString *resp = respData ? [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding] : @"";
                if (status >= 200 && status < 300) {
                    if (completion) completion(YES, [NSString stringWithFormat:@"已导入 %lu 个 GID", (unsigned long)valid.count]);
                } else {
                    if (completion) completion(NO, [NSString stringWithFormat:@"HTTP %ld: %@", (long)status, resp]);
                }
            });
        }] resume];
    }] resume];
}

#pragma mark - 好友 GID 自动捕获（转发客户端 protobuf 给后端解析）

// 把客户端收到的好友列表 protobuf blob 转发到后端解析
+ (void)performSubmitFriendBlob:(NSData *)blob
                         server:(NSString *)server
                          token:(NSString *)token
                      completion:(void (^)(BOOL ok, NSString *message))completion {
    if (!blob || blob.length == 0) { if (completion) completion(NO, @"空 blob"); return; }

    NSDictionary *cfg = [NSDictionary dictionaryWithContentsOfFile:[QQFarmUtils configFilePath]];
    NSString *srv = server ?: cfg[@"QQFarmServer"];
    NSString *tok = token ?: cfg[@"QQFarmToken"];
    if (!srv || srv.length == 0) srv = kQQFarmDefaultServer;
    if (!tok || tok.length == 0) tok = kQQFarmDefaultToken;

    NSString *base = [self normalizeServerURL:srv];
    if ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];

    NSString *blobB64 = [blob base64EncodedStringWithOptions:0];
    NSURLComponents *comp = [NSURLComponents componentsWithString:[base stringByAppendingString:@"/api/external/submit-friend-blob"]];
    if (!comp) { if (completion) completion(NO, @"服务器地址非法"); return; }
    comp.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"token" value:tok],
        [NSURLQueryItem queryItemWithName:@"uin" value:[QQFarmUtils deviceId]],
        [NSURLQueryItem queryItemWithName:@"platform" value:@"qq"],
    ];
    NSURL *url = comp.URL;
    if (!url) { if (completion) completion(NO, @"无法组装 URL"); return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSError *je;
    NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"blob": blobB64} options:0 error:&je];
    if (!body) { if (completion) completion(NO, @"构建请求失败"); return; }
    req.HTTPBody = body;
    req.timeoutInterval = 15;

    NSLog(@"[QQFarm] 🚀 转发好友 protobuf 到 %@/api/external/submit-friend-blob", base);
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *respData, NSURLResponse *response, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (e) { if (completion) completion(NO, e.localizedDescription); return; }
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            NSString *resp = respData ? [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding] : @"";
            if (status >= 200 && status < 300) {
                if (completion) completion(YES, resp);
            } else {
                if (completion) completion(NO, [NSString stringWithFormat:@"HTTP %ld: %@", (long)status, resp]);
            }
        });
    }] resume];
}

// WS 收消息时调用：扫描明文服务名，命中好友服务则转发整段 blob
+ (void)maybeCaptureFriendBlob:(NSData *)data {
    if (!data || data.length < 16) return;

    static NSData *marker = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        marker = [@"gamepb.friendpb.FriendService" dataUsingEncoding:NSUTF8StringEncoding];
    });
    if (marker && [data rangeOfData:marker options:0 range:NSMakeRange(0, data.length)].location == NSNotFound) return;

    // 节流：同一设备每 8 秒最多转发一次，避免刷屏
    static NSTimeInterval lastForward = 0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - lastForward < 8.0) return;
    lastForward = now;

    NSLog(@"[QQFarm] 🔍 命中好友服务 protobuf，转发后端解析");
    [self performSubmitFriendBlob:data server:nil token:nil completion:nil];
}

@end
