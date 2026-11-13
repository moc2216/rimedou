# RimeDou 项目约定

macOS菜单栏工具，通过豆包或千问语音输入，结束后恢复日常输入法。Swift 6、AppKit、macOS 15+，运行时无网络和第三方依赖。

## 入口与目录

- 先读[交接](handoff.md)了解当前状态，使用与配置以[README](README.md)和[配置说明](docs/configuration.md)为准。
- `Sources/RimeDouCore`包含配置、键盘事件、会话与恢复，`Sources/rimedou`包含菜单与权限界面。
- `Tests/RimeDouCoreTests`保存逻辑和模拟依赖回归，`assets`、`support`和`scripts`保存图标、元数据与打包。
- `docs`中的链接应可在独立检出仓库后访问。个人日志、实际配置与回退副本保存在仓库外。

## 验证

按变更运行`swift test`、`swift build -c release`和`./scripts/build-app.sh`。文档变更检查链接与示例JSON即可。发布状态以远端实际记录为准。

## 修改边界

- 保留已有未提交改动。`.build`和`build`为构建产物，清理前确认来源及用途。
- 整理文件时保持用户正在使用的应用、配置与权限可用。实际语音测试遵循用户授权。
- 保护暂存输入及厂商状态未知分支，日志只记录必要状态元数据。
- 当前版本、安装与验收状态以[验证记录](docs/validation.md)和[交接](handoff.md)为准。

## 安装后授权

用户明确要求，安装后的辅助功能与输入监控重新授权由用户手动完成。Agent通过应用日志核对监听启动，再继续功能验证。
