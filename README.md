<div align="center">

<img src="Sources/ClashBar/Resources/Brand/clashbar-icon.png" width="96" alt="ClashBar Logo" />

# ClashBar

原生 macOS 菜单栏代理客户端（SwiftUI + AppKit），以 `mihomo` 为 Core。

<p>
  <img alt="Platform" src="https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&logo=apple" />
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.2-F05138?style=flat-square&logo=swift" />
  <img alt="Build" src="https://img.shields.io/badge/Build-SwiftPM-0A84FF?style=flat-square" />
  <img alt="i18n" src="https://img.shields.io/badge/i18n-zh--Hans%20%7C%20en-34C759?style=flat-square" />
</p>

</div>

---

## 为什么是 ClashBar

ClashBar 的目标是：在 macOS 菜单栏里，给你一个**启动即用、可打包分发、可维护扩展**的 mihomo 客户端。  
它不是 Web 包壳，也不依赖 Xcode 工程文件，项目使用单一 SwiftPM 工程组织。

适用场景：

- 想要一个原生菜单栏代理管理器
- 想在 Swift 代码里直接维护代理客户端
- 想自己控制打包、helper、发布流程

---

## 功能亮点

### 核心运行与状态

- 菜单栏实时显示运行状态与上下行速率
- Core 生命周期控制：启动 / 停止 / 重启
- 模式切换：`Rule` / `Global` / `Direct`

### 配置管理

- 配置文件切换（yml/yaml 自动扫描）
- 导入本地配置 / 导入远程配置
- 批量更新远程配置源
- 新增：重载配置（刷新配置文件列表）
- 在 Finder 中定位当前配置

### 代理与规则运维

- Provider 列表与单项更新
- Proxy Group 节点切换与延迟测试
- Rules / Connections / Logs 面板化查看与操作
- 一键复制终端代理命令

### 系统集成

- 系统代理开关（Privileged Helper + XPC）
- 开机启动（Launch at Login）
- 多语言（简体中文 / English）
- Keychain 存储控制密钥，日志内建敏感信息脱敏

---

## 快速开始

### 环境要求

- macOS 14+
- Xcode Command Line Tools
- Swift 6.2+

### 方式 A：本地调试（开发）

```bash
swift build
swift run ClashBar
```

> `swift run` 适合 UI/业务逻辑开发调试。  
> 系统代理 helper 相关能力请使用 `.app` 产物验证。

### 方式 B：打包运行（推荐）

```bash
./Scripts/build.sh app
```

生成：`dist/ClashBar.app`

如需 DMG：

```bash
./Scripts/build.sh dmg
```

或一键全流程：

```bash
./Scripts/build.sh all
```

### 首次使用建议路径

1. 启动应用并打开菜单栏面板
2. 启动 Core（Start/Restart）
3. 选择或导入配置文件
4. 按需开启系统代理
5. 若提示权限，前往「系统设置 > 通用 > 登录项」批准后台项目

---

## 日常使用地图

- **Proxy**：流量、连接数、内存、配置入口、系统代理开关
- **Rules**：规则与规则集统计、规则/Provider 刷新
- **Activity**：活动连接过滤、关闭单连接/全部连接
- **Logs**：级别过滤、关键词搜索、复制日志
- **System**：语言、状态栏样式、allow-lan/ipv6/log-level、端口设置

---

## 运行目录与文件布局

### 运行目录（自动创建）

- `~/Library/Application Support/clashbar/config`
- `~/Library/Application Support/clashbar/logs`
- `~/Library/Application Support/clashbar/state`

### 配置扫描规则

- 仅识别 `.yaml` / `.yml`
- 按文件名排序
- 未选中配置时默认选中第一个

---

## 安全与隐私

- Secret 默认存储到 Keychain
- 日志会脱敏常见敏感字段（token/secret/password/api_key 等）
- Core 二进制在启动前执行基础安全校验（路径/权限/hash）

---

## 贡献

欢迎提交 Issue / PR（功能改进、文档修正、稳定性优化都欢迎）。
