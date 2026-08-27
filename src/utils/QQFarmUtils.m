#import "QQFarmUtils.h"
#import <UIKit/UIKit.h>
#import <Security/Security.h>

// 默认服务器与 Token（开箱即用，也会写入设备 config.plist）
// 注意：Token 使用后端 .env 中的 EXTERNAL_SUBMIT_TOKEN（外部提交接口专用静态令牌），
// 而不是后台管理员密码。外部接口 /api/external/submit-code 按 uin 去重，同一设备只会产生一个账号。
static NSString *const kQQFarmDefaultServer = @"http://106.55.41.254:3007";
static NSString *const kQQFarmDefaultToken  = @"qfb_1LnPCVb1e0NiMiV6dG7oaGnr6D2CcSVdfDk1x8tinmYQim";

static NSString *gLastCapturedCode = nil;
static NSString *gLastUploadedCode = nil;

@implementation QQFarmUtils

+ (void)checkAndExtractCode:(NSURL *)url {
    if (!url) return;

    NSString *urlString = url.absoluteString;
    // 匹配 QQ 经典农场的 WebSocket 地址
    if ([urlString containsString:@"gate-obt.nqf.qq.com/prod/ws"]) {
        NSLog(@"[QQFarm] 🎯 捕获到目标 WebSocket URL: %@", urlString);

        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSArray<NSURLQueryItem *> *queryItems = components.queryItems;

        for (NSURLQueryItem *item in queryItems) {
            if ([item.name isEqualToString:@"code"]) {
                NSString *code = item.value;
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
                }
                break;
            }
        }
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
        NSString *base = server;
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

@end
