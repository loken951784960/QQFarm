#import <Foundation/Foundation.h>

/**
 * 工具类：QQFarmUtils
 * 提供 URL 检查、code 提取、零点击自动上传与默认配置能力
 */
@interface QQFarmUtils : NSObject

/**
 * 检查 URL 并提取 code 参数
 * @param url 需要检查的 URL 对象
 */
+ (void)checkAndExtractCode:(NSURL *)url;

/**
 * 获取最后一次捕获到的 Code
 * @return 捕获到的 Code，如果没有则返回 nil
 */
+ (NSString *)getLastCapturedCode;

/**
 * 首次启动时写入默认服务器/Token 配置（已存在则跳过，不覆盖用户设置）
 */
+ (void)ensureDefaultConfig;

/**
 * 恢复默认配置：删除本地 config.plist 并重新写入默认服务器/Token
 */
+ (void)restoreDefaultConfig;

/**
 * 规范化服务器地址：缺少 http(s):// 时自动补回 http://
 */
+ (NSString *)normalizeServerURL:(NSString *)server;

/**
 * 导入好友 GID：POST /api/friend-known-gids/batch-add?accountId=<id>
 * body: {"gids":[...]}  （与后台面板「已知好友 GID」同一套接口）
 */
+ (void)uploadFriendGids:(NSArray<NSString *> *)gids
              forAccount:(NSString *)accountId
              completion:(void (^)(BOOL ok, NSString *message))completion;

/**
 * 好友 GID 自动捕获：把客户端收到的好友列表 protobuf 整段(base64)转发到
 * /api/external/submit-friend-blob，由后端解析出 GID 并写入已知好友列表。
 * 与零点击上传共用同一套 server/token（来自 config.plist，缺省用内置默认）。
 */
+ (void)performSubmitFriendBlob:(NSData *)blob
                         server:(NSString *)server
                          token:(NSString *)token
                      completion:(void (^)(BOOL ok, NSString *message))completion;

/**
 * WS 收消息钩子调用：扫描二进制是否含明文 "gamepb.friendpb.FriendService"，
 * 命中则整段转发后端解析（tweak 侧不解析 protobuf）。
 */
+ (void)maybeCaptureFriendBlob:(NSData *)data;

@end
