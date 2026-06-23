# RimeDou

只借用豆包输入法的语音输入能力，日常键盘输入仍回到鼠须管。

这是一个 macOS 菜单栏小工具。它适合这样的使用方式：

- 平时使用鼠须管（Rime / Squirrel）输入中文，例如 86 五笔。
- 偶尔按右 Ctrl 唤醒豆包输入法的语音输入。
- 语音结束后再次按右 Ctrl，工具会尽力把输入法恢复到鼠须管。
- 如果另一个语音输入工具 Type4Me 正在运行，本工具会让渡右 Ctrl，不触发豆包语音。

当前版本：`v0.1-trial`

## 当前状态

这是第一版试用工具，不是正式稳定版。

已实现：

- macOS 菜单栏 app。
- 右 Ctrl 监听。
- 切换到豆包输入法并触发豆包语音。
- 语音结束后恢复鼠须管。
- Type4Me 运行时自动让渡。
- 菜单栏暂停、启用、恢复鼠须管、退出。

仍在观察：

- 连续多次语音后，豆包输入法偶尔可能停留为当前输入法。
- 豆包自身可能弹出“语音唤起方式调整”提示。
- 本地构建版使用 ad-hoc 签名，替换新版 app 后 macOS 可能要求重新授权。

## 使用前提

需要：

- macOS 14 或更新版本。
- 已安装豆包输入法。
- 已安装鼠须管（Rime / Squirrel）。
- 豆包输入法的语音输入设置中，免按模式快捷键设置为右 Ctrl。

当前默认输入源：

```text
豆包输入源：com.bytedance.inputmethod.doubaoime.pinyin
鼠须管输入源：im.rime.inputmethod.Squirrel.Hans
Type4Me：/Applications/Type4Me.app
```

如果你的主输入法不是鼠须管简体，或外部语音工具不是 Type4Me，需要修改 `config/default.json` 后重新构建。

## 普通用户使用方式

普通用户不应该自己编译源码。

最理想的方式是从 GitHub Release 下载已经打包好的 zip：

1. 下载 `RimeDou-v0.1.0.zip`。
2. 解压后得到 `RimeDou.app`。
3. 把 app 拖到 `/Applications`。
4. 双击打开。
5. 按系统提示授予权限。

需要授权：

- 系统设置 -> 隐私与安全性 -> 输入监控
- 系统设置 -> 隐私与安全性 -> 辅助功能

如果 macOS 提示“无法打开，因为无法验证开发者”，可以在 Finder 中右键 app，选择“打开”。这是本地未公证应用的正常限制。

真正接近“一键安装、双击即用”的体验，需要 Apple Developer ID 签名和 notarization 公证。本项目目前还没有做这一步。

## 开发者构建

克隆仓库：

```bash
git clone https://github.com/moc2216/rimedou.git
cd rimedou
```

运行测试：

```bash
env CLANG_MODULE_CACHE_PATH=.build/module-cache \
  XDG_CACHE_HOME=.build/xdg-cache \
  swift run \
  --disable-sandbox \
  --cache-path .build/swiftpm-cache \
  rimedou-tests
```

构建 app：

```bash
./scripts/build-app.sh
```

生成结果：

```text
dist/RimeDou.app
```

打开开发构建：

```bash
open dist/RimeDou.app
```

复制到 `/Applications`：

```bash
ditto dist/RimeDou.app /Applications/RimeDou.app
open /Applications/RimeDou.app
```

## 打包给普通用户

开发者可以生成发布 zip：

```bash
./scripts/package-release.sh
```

生成结果：

```text
dist/RimeDou-v0.1.0.zip
```

这个 zip 可以上传到 GitHub Release，供普通用户下载。

发布 GitHub Release 前，建议确认：

- README 已说明当前是试用版。
- zip 内 app 能打开。
- app 首次运行时能出现在权限列表中。
- 授权后右 Ctrl 主路径能工作。
- 没有 `.env`、token、密钥或私人信息进入仓库。

## 配置

默认配置文件：

```text
config/default.json
```

当前内容：

```json
{
  "externalVoiceAppPath": "/Applications/Type4Me.app",
  "externalVoiceBundleId": "com.type4me.app",
  "primaryInputSourceId": "im.rime.inputmethod.Squirrel.Hans",
  "doubaoInputSourceId": "com.bytedance.inputmethod.doubaoime.pinyin",
  "doubaoVoiceHotkey": "rightControl"
}
```

说明：

- `externalVoiceAppPath`：外部语音工具路径，用于存在性检查和用户理解。
- `externalVoiceBundleId`：外部语音工具 bundle id，用于判断是否正在运行。
- `primaryInputSourceId`：语音结束后要恢复的主输入法。
- `doubaoInputSourceId`：豆包输入法的输入源 ID。
- `doubaoVoiceHotkey`：必须与豆包语音输入的免按模式快捷键一致。

## 菜单栏操作

运行后菜单栏会出现 `豆`。

菜单项：

- `暂停`：停止监听右 Ctrl，并尽力恢复鼠须管。
- `启用`：重新启用监听。
- `恢复鼠须管`：手动拉回鼠须管。
- `退出`：关闭本工具。

## 版本

- `v0.1-trial`：第一版可试用基线。

后续计划：

- `v0.2-focus-bounce`：加入可配置焦点回弹，改善连续触发稳定性。
- `v0.3-usage-polish`：改善日志、配置入口、权限提示和日常启动/退出体验。

更多记录见 `docs/versioning.md`。

## 已知限制

- 当前只支持右 Ctrl 作为豆包语音快捷键。
- 当前默认恢复鼠须管简体输入源。
- 当前没有 Apple Developer ID 签名和 notarization 公证。
- 当前没有自动安装 LaunchAgent；退出后不会自动重启。
- 真实语音输入表现依赖豆包输入法自身行为。

## 许可证

当前还没有选择许可证。

如果希望其他开发者可以正式复用、修改、分发，需要后续补充开源许可证，例如 MIT。
