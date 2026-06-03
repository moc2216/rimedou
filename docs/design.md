# 技术设计

## 结论

第一版采用 Swift 原生 macOS 后台工具，不采用纯脚本或第三方自动化工具。

理由：

- 需要全局监听右 Ctrl，并区分左右 Ctrl。
- 需要调用 macOS 输入源 API 切换鼠须管和豆包。
- 需要检测 Type4Me 是否正在运行。
- 需要尽量减少外部依赖和系统配置改动。

脚本方案适合验证单点能力，但不适合作为最终第一版。

## 本机已确认信息

当前本机只读验证结果：

- Swift 工具链可用：Apple Swift 6.3.2。
- 豆包输入法路径存在：`/Library/Input Methods/DoubaoIme.app`。
- 鼠须管路径存在：`/Library/Input Methods/Squirrel.app`。
- Type4Me 路径存在：`/Applications/Type4Me.app`。

已从 `Info.plist` 确认：

- 豆包 bundle id：`com.bytedance.inputmethod.doubaoime`。
- 豆包输入源 ID：`com.bytedance.inputmethod.doubaoime.pinyin`。
- 鼠须管 bundle id：`im.rime.inputmethod.Squirrel`。
- 鼠须管简体输入源 ID：`im.rime.inputmethod.Squirrel.Hans`。
- 鼠须管繁体输入源 ID：`im.rime.inputmethod.Squirrel.Hant`。
- Type4Me bundle id：`com.type4me.app`。

第一版默认主输入源使用鼠须管简体：`im.rime.inputmethod.Squirrel.Hans`。

阶段 3 验证发现：

- macOS TIS 能在所有已安装输入源中找到豆包输入源。
- 豆包输入源 ID `com.bytedance.inputmethod.doubaoime.pinyin` 可以被 TIS 选择。
- 鼠须管输入源 ID `im.rime.inputmethod.Squirrel.Hans` 可以被 TIS 选择。
- 在 Codex 沙盒内调用 `TISSelectInputSource` 会返回 `-50`，并伴随 HIServices 连接错误。
- 沙盒外运行同一验证命令可以成功切到豆包、切回鼠须管并恢复原输入源。
- 工具应区分“已安装输入源”和“已启用/可选择输入源”。
- 按项目红线，工具不得自动启用输入源或修改系统输入法配置。
- 涉及真实输入源切换的手动验证需要在沙盒外运行。

## 方案比较

### 方案 A：Swift 原生后台工具

做法：

- 使用 Swift Package Manager 管理项目。
- 使用 AppKit / Foundation 管理应用生命周期。
- 使用 `CGEventTap` 或等价事件监听能力监听全局键盘事件。
- 使用 Text Input Source Services 切换输入源。
- 使用 `NSWorkspace` 检测 Type4Me 是否正在运行。

优点：

- 能区分右 Ctrl 和左 Ctrl。
- 能做长期后台运行。
- 能直接调用 macOS API。
- 依赖少，适合后续打包成菜单栏工具。
- 测试可以围绕状态机和服务接口做，不必一开始就把系统 API 写死。

缺点：

- 需要处理 macOS 权限。
- 需要写一层系统 API 适配，测试时要隔离。
- 后续如果要分发，可能要处理签名和权限提示。

判断：

这是第一版最合适方案。

### 方案 B：AppleScript / shell 脚本

做法：

- 用脚本切换输入法。
- 用第三方工具或系统快捷键触发脚本。

优点：

- 验证快。
- 代码少。

缺点：

- 全局监听右 Ctrl 很弱。
- 区分左右 Ctrl 不可靠。
- 长期后台状态管理麻烦。
- 容易依赖用户本机自动化配置。

判断：

只适合探索输入源切换能力，不作为第一版主方案。

### 方案 C：Karabiner-Elements / Hammerspoon 等现成自动化工具

做法：

- 把右 Ctrl 映射给脚本或自动化动作。
- 用现成工具处理按键监听。

优点：

- 按键层能力强。
- 能快速做个人工作流。

缺点：

- 引入新的全局依赖或系统配置。
- 不符合本项目“不默认安装全局依赖或修改系统配置”的约束。
- 后续迁移和复现依赖外部工具。

判断：

不作为第一版方案。除非 Swift 方案验证失败，再作为备选。

## 模块设计

第一版按可测试边界拆成以下模块：

- `AppRunner`：应用入口和生命周期。
- `ConfigStore`：加载配置。
- `VoiceToolMonitor`：判断外部语音工具是否正在运行。
- `HotkeyMonitor`：监听右 Ctrl。
- `InputSourceService`：查找和切换输入源。
- `DoubaoVoiceController`：触发或结束豆包语音输入。
- `SwitchCoordinator`：核心状态机，协调上述模块。
- `Logger`：开发阶段日志输出。
- `MenuBarPresentation`：菜单栏状态文案和控制项文案的纯逻辑表示。

核心逻辑放在 `SwitchCoordinator`，系统 API 放到服务模块中，便于测试。

## 菜单栏设计

正式试用版使用 `NSStatusBar` 创建菜单栏图标，标题暂用 `豆`，避免 Dock 图标或终端命令成为主要控制方式。

菜单项：

- 状态文本：来自 `MenuBarPresentation`。
- `暂停` / `启用`：调用 `AppRunner.togglePause()`。
- `恢复鼠须管`：调用 `AppRunner.restorePrimaryInputNow()`。
- `退出`：调用 `NSApplication.shared.terminate(nil)`，退出前由 `AppRunner.stop()` 尽力恢复鼠须管。

`AppRunner` 负责运行态控制：

- `pause()` 停止右 Ctrl 监听、Type4Me 轮询和空闲鼠须管守护，并尽力恢复鼠须管。
- `resume()` 重新启动右 Ctrl 监听、Type4Me 轮询和空闲鼠须管守护。
- `menuPresentation()` 返回菜单栏所需的当前状态。

菜单栏只负责展示和调用，不直接操作输入法状态机。

## 状态机设计

状态：

- `idle`
- `suspended`
- `doubaoVoiceActive`
- `error`

事件：

- `externalVoiceToolStarted`
- `externalVoiceToolStopped`
- `rightControlPressed`
- `leftControlPressed`
- `inputSourceMissing`
- `permissionMissing`
- `switchFailed`

主要规则：

- `idle + rightControlPressed`：进入豆包语音流程。
- `doubaoVoiceActive + rightControlPressed`：退出豆包语音流程并恢复鼠须管。
- 任意非错误状态 + `externalVoiceToolStarted`：进入 `suspended`。
- `suspended + rightControlPressed`：不做任何豆包相关动作。
- `suspended + externalVoiceToolStopped`：回到 `idle`。
- 任意状态 + 严重错误：进入 `error`。

## 配置设计

第一版配置建议放在项目内的本地配置文件，便于开发和测试：

- 路径：`config/default.json`
- 内容：

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

- `externalVoiceAppPath` 用于用户理解和路径存在性检查。
- `externalVoiceBundleId` 用于运行中检测，优先级高于路径。
- 输入源 ID 来自本机验证，但仍应在启动时确认存在。
- `doubaoVoiceHotkey` 必须与豆包输入法“语音输入 -> 免按模式”的快捷键一致。第一版只支持 `rightControl`，因为用户当前豆包设置就是右 Ctrl。

后续如果做成正式 App，再迁移到用户配置目录。

## 权限设计

第一版可能需要：

- 输入监听权限：全局监听右 Ctrl。
- 辅助功能权限：如果需要模拟按键触发豆包语音。

设计约束：

- 程序只检测和提示权限，不自动修改系统设置。
- 权限不足时进入明确错误状态。
- 权限提示写入日志。

## 豆包语音触发设计

这里是最大不确定点。

第一阶段实现一个可替换接口：

- `startVoiceInput()`
- `stopVoiceInputIfPossible()`

第一版按两个层级尝试：

1. 切换到豆包输入源。
2. 按 `doubaoVoiceHotkey` 模拟豆包现有语音快捷键。

设计上不把豆包语音启动方式写死在状态机里，而是封装到 `DoubaoVoiceController`。这样后续验证出真实可行方式后，只改这个模块。

这里的优先级规则是：豆包输入法自己的快捷键设置是事实来源，本工具必须匹配它，而不是要求豆包迁就本工具。当前豆包设置为“免按模式：右 Ctrl”，所以本工具旁听右 Ctrl，并延迟处理事件。第一次右 Ctrl 先被当前鼠须管状态消化，随后工具切到豆包并合成一次右 Ctrl。第二次右 Ctrl 不再向豆包额外合成停止快捷键，只尽快恢复鼠须管，避免触发“语音唤起方式调整”。

豆包输入源切换后不能立刻发送语音快捷键。手动验收发现，如果刚切到豆包就立即发送右 Ctrl，豆包可能只完成输入源切换，没有进入语音输入；第二次右 Ctrl 又可能弹出“语音唤起方式调整”。因此第一版先把用户物理右 Ctrl 事件延迟 0.08 秒处理，再切换到豆包；切换后不只相信 `TISSelectInputSource` 的返回值，而是轮询当前输入源，直到系统实际报告已经是豆包；随后再等待 0.18 秒发送右 Ctrl。进入语音态后，第二次右 Ctrl 改为 0 秒延迟处理，尽快恢复鼠须管，降低豆包处理物理右 Ctrl 并弹出设置提示的机会。

曾测试过用可拦截 event tap 吞掉手抖造成的快速重复右 Ctrl，但手动验收显示它会破坏正常短按主路径。因此当前版本恢复为旁听 event tap，不吞物理右 Ctrl。也曾测试过退出时发送 `Esc` 清理豆包弹窗，但手动验收显示它可能取消豆包尚未提交的识别结果。当前版本在退出时等待 1.2 秒再恢复鼠须管，优先保证文字上屏；如果第一次恢复后系统仍报告停在豆包，会等待 0.25 秒后重试一次鼠须管切换。

为处理偶发停留在豆包输入源的问题，`AppRunner` 增加空闲输入法守护定时器。工具处于 `idle` 且外部语音工具未运行时，每秒检查一次当前输入源；如果不是鼠须管，则调用 `restorePrimaryInputSourceIfNeeded()` 拉回鼠须管。这样即使退出流程中的一次恢复没有生效，后续空闲轮询也会纠正。

## 测试设计

TDD 第一层不碰真实 macOS API，先测纯逻辑：

- Type4Me 运行时，右 Ctrl 不触发豆包逻辑。
- Type4Me 退出后，右 Ctrl 可触发豆包逻辑。
- `idle` 下右 Ctrl 会请求切换豆包并启动语音。
- `doubaoVoiceActive` 下右 Ctrl 会请求停止语音并恢复鼠须管。
- 左 Ctrl 不触发流程。
- 切换失败会进入错误或输出失败结果。

第二层再加系统服务的小验证：

- 能读取配置。
- 能找到输入源 ID。
- 能判断输入源是否可选择。
- 能判断 Type4Me 是否运行。
- 能调用输入源切换接口。

真实语音触发属于手动验收，不能只靠自动化测试证明。

## 目录设计

根据 `agent.md`，第一版目录为：

- `docs/`：需求、规格、设计、计划。
- `src/`：Swift 源码。
- `tests/`：Swift 测试。
- `config/`：项目本地默认配置。
- `scripts/`：只读验证或开发辅助脚本。

创建 `config/` 前应在计划阶段列明用途。

## 验证策略

文档阶段：

- 检查需求、规格、设计是否一致。

实现阶段：

- `env CLANG_MODULE_CACHE_PATH=.build/module-cache XDG_CACHE_HOME=.build/xdg-cache swift run --disable-sandbox --cache-path .build/swiftpm-cache switch-only-doubao-voice-input-tests`：跑状态机和配置测试。
- `swift run`：手动运行开发版工具。
- 手动验收：在普通输入框中验证右 Ctrl、Type4Me 让渡、鼠须管恢复。

## 剩余风险

- 豆包语音启动和停止方式尚未验证。
- 真实输入源切换在 Codex 沙盒内会失败；需要沙盒外运行或打包后的正常应用环境验证。
- macOS 权限提示和事件监听在开发运行、打包运行时可能表现不同。
- Type4Me 是否运行应优先用 bundle id 检测，单靠路径不足。
- 如果豆包拦截右 Ctrl 的时机和本工具冲突，可能需要调整事件监听策略。
