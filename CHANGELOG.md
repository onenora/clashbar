## v0.1.7

![macOS](https://img.shields.io/badge/macOS-Supported-000000?style=flat-square&logo=apple) ![Version](https://img.shields.io/badge/Release-v0.1.7-10B981?style=flat-square) ![Core](https://img.shields.io/badge/Core-Mihomo-6366f1?style=flat-square)

> 本次更新重点补上了 **系统代理状态恢复** 这块一直该做但没做干净的事情：重启应用后不再莫名掉代理；同时顺手把 `System` 页快捷键和启动后的分组延迟探测补齐，让常用操作更顺手。

### 📝 更新日志 (Changelog)

**✨ 新增功能 (New Features)**
- ![Feature](https://img.shields.io/badge/Feature-10B981?style=flat-square) **系统页快捷键**：新增 `Command + ,` 快捷键，支持从菜单命令快速切换到 `System` 页面，更符合 macOS 用户习惯。

**🚀 优化改进 (Improvements)**
- ![Optimize](https://img.shields.io/badge/Optimize-3B82F6?style=flat-square) **启动延迟探测**：内核启动完成后会自动触发 Proxy Group 延迟测试，用户打开面板时能更快看到各组节点状态。
- ![Optimize](https://img.shields.io/badge/Optimize-3B82F6?style=flat-square) **退出清理流程**：应用退出时会主动清理系统代理，减少异常退出后系统仍残留无效代理状态的情况。

**🐞 修复问题 (Bug Fixes)**
- ![Fix](https://img.shields.io/badge/Fix-EF4444?style=flat-square) **系统代理恢复**：修复 ClashBar 重新启动后系统代理状态丢失的问题；如果退出前已开启代理，应用恢复运行后会自动按上次状态恢复。

## v0.1.6

![macOS](https://img.shields.io/badge/macOS-Supported-000000?style=flat-square&logo=apple) ![Version](https://img.shields.io/badge/Release-v0.1.6-10B981?style=flat-square) ![Core](https://img.shields.io/badge/Core-Mihomo-6366f1?style=flat-square)

> 本次更新重点把 **Mihomo 内核升级** 直接做进了菜单栏底部，运行中的用户无需再手动折腾；同时补齐了升级结果反馈、版本刷新与新版检测时机，减少“点了没反应”和版本信息滞后的问题。

### 📝 更新日志 (Changelog)

**✨ 新增功能 (New Features)**

- ![Feature](https://img.shields.io/badge/Feature-10B981?style=flat-square) **内核一键升级**：在菜单栏底部新增 Mihomo 内核升级入口，支持在运行中直接检查并执行升级操作。

**🚀 优化改进 (Improvements)**

- ![Optimize](https://img.shields.io/badge/Optimize-3B82F6?style=flat-square) **升级反馈**：为内核升级补充进行中、成功、已是最新版、失败等明确状态提示，并同步写入日志，减少黑盒体验。
- ![Optimize](https://img.shields.io/badge/Optimize-3B82F6?style=flat-square) **版本同步**：升级完成后自动刷新内核版本号，底部显示的 Mihomo 版本会尽快与实际运行版本保持一致。
- ![Optimize](https://img.shields.io/badge/Optimize-3B82F6?style=flat-square) **版本检查时机**：应用新版检测改为在面板展开时刷新，避免后台无效轮询，同时保证用户打开菜单时能看到最新版本提示。

**🐞 修复问题 (Bug Fixes)**

- ![Fix](https://img.shields.io/badge/Fix-EF4444?style=flat-square) **升级响应兼容性**：兼容 Mihomo `/upgrade` 接口的多种响应与错误文案，正确识别“已是最新版”场景，避免把正常结果误判为失败。

## v0.1.5

### 🐞 修复问题

- 修复 macOS 13 Intel 平台下的兼容性问题，提升应用在旧版 Intel 设备上的启动与界面稳定性

<details>
<summary><strong> ✨ 新增功能 </strong></summary>

- 新增无内核版本的 ClashBar 安装包，支持按需分发不内置 Mihomo 内核的应用版本
- 支持在未内置核心组件时提供首次启动引导，方便用户手动安装和配置 Mihomo 内核

</details>

<details>
<summary><strong> 🚀 优化改进 </strong></summary>

- 优化未内置内核场景下的启动流程，缺少托管内核时将延后自动启动并提供更清晰的提示信息
- 调整启动失败与 TUN 相关错误提示文案，帮助用户更快定位和处理手动安装内核后的运行问题
- 优化打包与发布流程，适配新的安装包结构并同步更新相关资源与文档

</details>
