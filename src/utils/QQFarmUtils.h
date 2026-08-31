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
 * 规范化服务器地址：缺少 http(s):// 时自动补回 http://
 */
+ (NSString *)normalizeServerURL:(NSString *)server;

/**
 * 从 WebSocket 收到的二进制消息中识别好友 RPC（gamepb.friendpb.FriendService），
 * 命中后将原始 protobuf 字节 base64 上传到后端 submit-friend-blob 接口。
 * @param message 服务器下发的 wss 消息体（protobuf 二进制）
 */
+ (void)handleFriendMessage:(NSData *)message;

@end
