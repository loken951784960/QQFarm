# <span style="color:red; font-size:50px;">用智能助手挂机会封号！！！</span>

# QQFarm 助手

这是一个 iOS Tweak 插件，用于辅助管理 QQFarm 账号。它可以自动抓取 QQ 的登录凭证（Code），并与远程服务器进行交互，实现账号的更新和自动化任务的启停控制。


## 功能特性

*   **自动抓取 Code**：Hook QQ 的 WebSocket 通信，自动提取登录凭证。
*   **常驻悬浮小球**：QQ 内常驻一个可拖动/点击的悬浮小球，点一下即展开控制台；摇一摇作为备用呼出方式（无需先抓到 Code）。
*   **非模态悬浮窗**：操作悬浮窗的同时不影响 QQ 的正常使用，支持点击穿透。
*   **账号管理**：
    *   查看服务器上的账号列表（支持下拉刷新）。
    *   **更新账号**：一键将当前抓取的 Code 上传绑定到指定账号。
    *   **启停控制**：远程启动或停止账号的自动化任务。
*   **配置管理**：支持配置服务器地址和 Admin Token，并持久化保存。

## 编译与安装

本项目基于 [Theos](https://github.com/theos/theos) 开发。

### 前置要求

*   macOS / Linux / Windows (WSL)
*   Theos 开发环境
*   配置好的 `THEOS_DEVICE_IP` (如果需要远程安装)

### 编译命令

```bash
# 编译
make

# 打包
make package

# 安装到设备
make install
```

或者使用项目自带的构建脚本：

```bash
./build.sh
```

## 使用说明

1.  **安装插件**：将生成的 `.deb` 包安装到越狱的 iOS 设备上（支持巨魔注入），并注销（Respring）。
2.  **抓取 Code**：
    *   打开手机 QQ。
    *   进行一些操作（进入 动态->QQ经典农场）以触发网络请求。
    *   插件会自动在后台静默抓取 Code。
3.  **唤出控制台**：
    *   QQ 内会常驻一个悬浮小球，直接点击即可展开/收起控制台（小球位置可拖动并自动记忆）。
    *   备用方式：在 QQ 界面**摇一摇手机**也可唤出控制台。
    *   以上两种方式均无需先抓到 Code 即可呼出。
4.  **配置服务器**：
    *   点击悬浮窗顶部的“设置”标签。
    *   输入您的后端服务器地址（例如 `http://192.168.1.100:3000`）。
    *   输入 Admin Token（如果服务器需要）。
    *   点击“保存配置”。
5.  **管理账号**：
    *   切换到“账号”标签。
    *   下拉刷新列表。
    *   点击“更新”：将当前手机 QQ 的 Code 上传到该账号。
    *   点击“启动/停止”：控制该账号在服务器端的运行状态。

## API 接口适配

插件依赖以下后端 API 接口：

*   `GET /api/accounts`：获取账号列表。
*   `POST /api/accounts`：更新账号信息（上传 Code）。
    *   参数：`id`, `name`, `code`, `platform`, `loginType`
*   `POST /api/accounts/:id/start`：启动任务。
*   `POST /api/accounts/:id/stop`：停止任务。

## 目录结构

*   `src/hooks/`：Tweak 钩子代码 (WebSocket Hook, Shake Handler)。
*   `src/ui/`：界面相关代码 (悬浮窗, 列表, 设置页)。
*   `src/utils/`：工具类 (Code 管理)。
*   `Tweak.x`：入口文件。

## 免责声明

本项目仅供学习交流使用，请勿用于非法用途。
