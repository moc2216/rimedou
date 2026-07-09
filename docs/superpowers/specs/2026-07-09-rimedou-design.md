# rimedou 重构设计文档

**日期**：2026-07-09  
**分支**：`rimedou-rewrite`  
**状态**：待实现计划评审

---

## 1. 目标

从零重写 rimedou，把它从当前近 1400 行的 `AppDelegate` 上帝类改造成功能边界清晰、可测试、易维护的模块化 macOS 菜单栏工具。

核心能力保持不变：**点按右 Command 唤起豆包语音输入，语音结束后自动把输入法切回 RIME（鼠须管）**。

## 2. 非目标

- 不做通用语音输入法桥接器，只服务「豆包语音 → RIME」这一组输入法。
- 不做开机自启 / KeepAlive 启动代理。
- 不做长按触发模式，只保留点按切换（tap-toggle）。
- 不引入第三方依赖，只用 Swift 标准库和 Apple 系统框架。

## 3. 范围

### 保留
- 菜单栏图标与菜单（图标继续使用「豆」）。
- 权限引导窗口（Accessibility + Input Monitoring）。
- CGEvent tap 事件捕获与自动重启用。
- 触发键点按判定、语音热键合成、输入法切换、焦点弹跳还原。
- 用户配置文件 `~/Library/Application Support/rimedou/config.json`。
- 日志文件 `~/Library/Logs/rimedou/app.log`。

### 移除
- `DoubaoVoiceBridge` 品牌字符串、旧目录名、旧注释。
- LaunchAgent 模块及相关脚本（`install-launch-agent.sh`、`launch-agent-status.sh`、`uninstall-launch-agent.sh`）。
- `DoubaoImeVoiceStrategy`（holdHotkey / tapHotkey 策略判断）。
- `optionWarmupTapDuration`、`optionWarmupToHoldDelay`、`postSwitchSettleDelay` 等废弃配置项。
- 长按/按住相关的防御代码和状态。

### 新增
- 模块化目录结构。
- 更完整的单元测试覆盖。
- Swift 6 严格并发检查。

## 4. 架构

### 目录结构

```
rimedou/
├── Package.swift
├── README.md
├── config.json
├── assets/
│   └── AppIcon.icns
├── scripts/
│   └── build-app.sh
├── support/
│   └── Info.plist
├── Sources/
│   ├── rimedou/                          # 可执行入口
│   │   ├── main.swift
│   │   ├── AppDelegate.swift             # 菜单栏、权限窗口、生命周期
│   │   └── PermissionsWindowController.swift
│   └── RimeDouCore/                      # 核心库，只保留必要模块
│       ├── RimeDouConfig.swift           # 配置模型 + Hotkey 解析
│       ├── VoiceStateMachine.swift       # 状态机
│       ├── KeyboardEngine.swift          # 事件监听 + 触发判定 + 热键合成
│       ├── InputMethodController.swift   # 输入法切换 + 焦点弹跳
│       ├── PermissionReport.swift        # 权限检测
│       └── RimeDouLogger.swift           # 日志
└── Tests/
    └── RimeDouCoreTests/
        ├── ConfigTests.swift
        ├── StateMachineTests.swift
        ├── KeyboardEngineTests.swift
        └── InputMethodControllerTests.swift
```

### 模块职责

> 命名约定：用户可见的产品名、可执行文件名、配置/日志目录统一使用小写 `rimedou`；`RimeDouCore` 作为 Swift 库模块名保留 PascalCase 写法，仅为符合 Swift 命名惯例，不含 `DoubaoVoiceBridge` 等旧品牌。

| 模块 | 职责 |
|---|---|
| `rimedou` | 可执行入口。创建 `NSApplication`、安装菜单栏、显示权限窗口、处理应用生命周期。 |
| `RimeDouConfig` | 配置模型、默认值、JSON 解析、用户配置模板生成；包含 `Hotkey`/`Key` 解析与键码映射。 |
| `VoiceStateMachine` | 管理 `idle` ↔ `voiceActive`，输出动作指令。 |
| `KeyboardEngine` | 安装 CGEvent tap、判定触发键点按、合成并发送语音热键。 |
| `InputMethodController` | 读取当前输入法、选择目标输入法、通过 Finder 焦点弹跳强制刷新输入上下文。 |
| `PermissionReport` | 检测 Accessibility 与 Input Monitoring 授权状态。 |
| `PermissionsWindowController` | 权限引导窗口 UI（位于 app 目标）。 |
| `RimeDouLogger` | 文件日志。 |

## 5. 核心数据流

1. **用户点按右 Cmd**：`KeyboardEngine` 通过 CGEvent tap 捕获 `keyDown` / `keyUp` / `flagsChanged`。
2. **触发判定**：`KeyboardEngine` 在 `keyUp` 时判断是否满足：
   - 期间未按其他键；
   - 按下到松开时长 ≤ `tapMaxDuration`。
   满足则输出 `triggerTap`。
3. **状态机响应**：`VoiceStateMachine` 从 `idle` 收到 `triggerTap`，输出 `startVoiceSession`。
4. **开始语音会话**：
   - 生成新的 sessionID，记录原输入法、原应用/窗口、开始时间。
   - 若当前输入法不是豆包，记录原输入法作为还原目标；若已是豆包，则还原目标固定为 `Squirrel`。
   - `KeyboardEngine` 向系统发送一次 `voiceHotkey`（默认 RightControl）点按，持续 `tapDuration`。
5. **豆包响应**：自切到豆包输入法并打开语音弹窗。
6. **停止信号**：
   - 用户再点按右 Cmd → `triggerTap` → 状态机输出 `[stopVoice, restoreInputMethod]`。
   - 用户按空格/字母/其他修饰键 → `externalVoiceEnd`（仅在语音开始 0.5s 后生效，过滤合成键噪声）→ 状态机输出 `[restoreInputMethod]`。
7. **输入法还原**：
   - 若 `triggerTap`，`KeyboardEngine` 再发一次 `voiceHotkey` 让豆包停止。
   - `InputMethodController` 选择目标输入法，并激活 Finder 再切回原应用/窗口，强制刷新输入上下文。
   - 最多轮询 8 次，每次间隔 0.25s，覆盖豆包上屏期间的反复重抢。
8. **状态回到 `idle`**，等待下一次点按。

## 6. 关键接口

### 状态机

```swift
public enum VoiceState { case idle; case voiceActive }
public enum VoiceEvent { case triggerTap; case externalVoiceEnd; case reset }
public enum VoiceAction { case startVoiceSession; case stopVoice; case restoreInputMethod }

public struct VoiceStateMachine {
    public private(set) var state: VoiceState
    public mutating func handle(_ event: VoiceEvent) -> [VoiceAction]
}
```

### 键盘引擎

```swift
public final class KeyboardEngine: @unchecked Sendable {
    public init(config: RimeDouConfig, logger: RimeDouLogger)

    /// 安装事件监听，开始捕获按键事件
    public func start() -> Bool

    /// 卸载事件监听
    public func stop()

    /// 发送一次语音热键点按（用于开始或停止语音）
    public func sendVoiceHotkey()
}
```

`KeyboardEngine` 内部封装事件 tap、触发判定和热键合成，对外只暴露开始/停止/发送语音键三个动作。

## 7. 配置

默认 `config.json`：

```json
{
  "restoreDelay": 0.5,
  "switchPollInterval": 0.05,
  "switchWaitTimeout": 2.0,
  "focusBounceBackDelay": 0.1,
  "focusBounceSettleDelay": 0.1,
  "tapMaxDuration": 0.35,
  "tapDuration": 0.15,
  "triggerHotkey": "RightCommand",
  "voiceHotkey": "RightControl"
}
```

说明：
- `launchAtLogin`、`optionWarmupTapDuration`、`optionWarmupToHoldDelay`、`postSwitchSettleDelay` 从配置模型中移除。
- 为兼容旧版用户配置，JSON 解析时忽略未知键；旧配置中的 `launchAtLogin` 等字段会被静默丢弃。
- `voiceHotkey` 默认统一为 `RightControl`，与豆包「全局唤起语音」默认设置一致。

## 8. 用户界面

### 菜单栏

菜单栏图标使用纯文字「豆」，不需要额外图标资源。点击后菜单项：

- Enable Key Capture（勾选状态）
- 分隔线
- Open Log
- Open Config
- Reload Config
- Check Permissions
- 分隔线
- Quit

### 权限窗口

窗口标题：`Enable rimedou`

内容：
- 顶部：应用图标 + 标题 + 说明文案。
- 两行权限卡片：Accessibility、Input Monitoring。
- 每行显示当前授权状态 + 「Open System Settings」按钮。
- 全部授权后显示「Enable rimedou」按钮，点击后窗口关闭，应用进入后台菜单栏模式。

所有文案统一使用 `rimedou`，不再出现 `DoubaoVoiceBridge`、`RimeDou`、`豆` 等品牌字样（菜单栏图标除外）。

## 9. 错误处理

| 场景 | 处理 |
|---|---|
| 权限未授权 | 启动时弹出权限窗口，授权检测通过后再安装事件监听。 |
| 事件 tap 被系统禁用 | 自动重新启用。 |
| 合成语音热键失败 | 记录日志，不影响下一次触发。 |
| 输入法切换失败 | 最多重试 8 次，失败后记录日志，状态回到 idle。 |
| 焦点弹跳失败 | 记录日志，输入法切换仍会继续重试。 |
| 程序退出时仍在语音中 | 尝试还原输入法，释放事件监听，记录日志。 |

核心原则：任何单点失败都不应崩溃程序，也不应阻塞下一次点按。

## 10. 测试策略

### 单元测试（必须）

- `ConfigTests`：配置解析、默认值、部分 JSON 覆盖、用户模板生成。
- `StateMachineTests`：点按开始、再点按停止、任意键停止、reset。
- `KeyboardEngineTests`：触发判定（干净点按、组合键取消、长按不触发）、热键事件序列生成。
- `InputMethodControllerTests`：输入法名称匹配逻辑（mock TIS 输入源列表）。

### 手动测试（必须）

- 真实 macOS 环境下的点按触发、语音唤起、输入法回切。
- 权限窗口首次引导流程。
- 菜单栏启用/禁用、重载配置、打开日志/配置。
- 事件 tap 被系统禁用后自动恢复。

### 不测试

- 真实的 CGEvent post 行为。
- 真实的 TIS 输入法切换。
- 真实的 Accessibility 焦点操作。

这些依赖系统环境和用户授权，单元测试成本过高，靠手动运行验证。

## 11. 平台与工具链

- Swift tools 6.0
- macOS 15.0+
- 开启 Swift 6 严格并发检查
- 不使用第三方依赖

## 12. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 模块化拆分后引入新的并发问题 | 使用 Swift 6 严格并发检查；事件相关对象限定在主线程。 |
| 重写过程中丢失已有的 bugfix（如 0.5s 静默、焦点弹跳） | 设计文档明确列出关键行为；实现时逐项对照原代码验证。 |
| 配置文件路径变化导致老用户配置丢失 | 保留 `~/Library/Application Support/rimedou/config.json` 路径不变；如旧路径是 `RimeDou`，首次启动迁移。 |
| 菜单栏图标「豆」在新系统上显示异常 | 使用 `NSStatusBar` 标准文字按钮，无需额外资源。 |

## 13. 验收标准

- [ ] `swift build` 成功，无警告。
- [ ] `swift test` 全部通过。
- [ ] 项目内不再出现 `DoubaoVoiceBridge` 字符串。
- [ ] 菜单栏点按右 Cmd 可稳定唤起豆包语音。
- [ ] 语音结束后自动切回 RIME。
- [ ] 权限窗口首次引导正常。
- [ ] 菜单栏「Quit」可彻底退出，无残留启动代理。

## 14. 待实现计划确认后决定

- 具体文件命名是否需要调整。
- 测试覆盖率阈值。
