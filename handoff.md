# rimedou 交接文档 — 项目全史与接手指引

> **本文用途**：让一个完全没有上下文的人或 AI，读完这一个文件即可接手二次开发。
> 当前版本 **v2.0.2（202）** · macOS 15+ · Swift 6 · 零第三方依赖 · MIT License
> 最后更新：2026-09-03

---

## 0. 一页速览

**rimedou** 是 macOS 菜单栏工具：日常打字用 RIME / 鼠须管，**点按右 Command 键**唤起豆包输入法的全局语音输入，说完自动切回 RIME。专为「打字用 RIME、语音用豆包」的双输入法工作流设计。

| 事项 | 内容 |
|---|---|
| 构建 | `swift build -c release && ./scripts/build-app.sh` → `build/rimedou.app` |
| 测试 | `swift test`（**64 项全绿是回归底线**） |
| 运行前提 | macOS 15+、豆包输入法 0.9.3+（设置里开「全局唤起语音」、热键设**右 Control**）、主输入法 Squirrel、授予辅助功能 + 输入监控权限 |
| 触发键 | 默认 `RightCommand`（点按判定 ≤0.35s 且无其他键；⌘ 组合使用不误触；左右严格区分）；可选**第二触发键** `triggerHotkey2`（如 `LeftControl+LeftOption+LeftCommand+Z` 供鼠标侧键经 Mac Mouse Fix 触发），与主键并存、任一可触发，见 README「第二触发键（鼠标侧键方案）」 |
| 用户配置 | `~/Library/Application Support/rimedou/config.json`（首启自动生成；菜单 Reload Config 热生效） |
| 日志 | `~/Library/Logs/rimedou/app.log`（菜单 Open Log） |
| 架构 | `Sources/RimeDouCore`（核心库：状态机 / 配置 / 键盘事件 / 输入法控制 / 权限 / 日志）+ `Sources/rimedou`（菜单栏可执行入口） |
| 签名注意 | 无证书时 ad-hoc 签名，**每次构建覆盖安装都会导致权限重授**；可用 `CODE_SIGN_IDENTITY` 指定稳定证书 |

---

## 1. 项目缘起与约束（2026-06 初）

用户日常用鼠须管 86 五笔打字，偶尔需要语音输入，看中豆包输入法 0.9.x 的「全局唤起语音」能力。动手前调研了两个同类项目：

- `Paxxs/Doubao-ime-hammerspoon`：Hammerspoon 配置方案（监听右 Cmd → 切豆包 → 模拟按键 → 延迟恢复）
- `xubihang/Doubao-Voice-Input-Bridge`：独立 macOS app，按住说话模式（v0.1.0 → v1.0.6）

由此确立本项目约束（至今未变）：

1. 只借豆包的**语音**能力，不把豆包当日常键盘输入法；会话结束必须恢复鼠须管（`im.rime.inputmethod.Squirrel.Hans`）。
2. **不安装全局依赖**（Hammerspoon / Karabiner / LaunchAgent 等），只做独立 app。
3. 借鉴了 xubihang 项目的关键洞察「**焦点回弹**」：输入源切换成功 ≠ 当前文本上下文已重新绑定，需要焦点弹跳强制刷新。
4. 豆包「免按模式」热键（右 Control）是事实来源，由工具合成发送。

---

## 2. 开发全史

### 2.1 自研初版（2026-06-03 → 06-25，tag `v0.1-trial` → `v0.2.0`）

用户从零自研：项目最初名 **SwitchOnlyDoubaoVoiceInput**，起步即带全套 SDD 风格文档（design / plan / spec / requirements / review / manual-acceptance / agent 规则），git tag `v0.1-trial` 保留完整快照。

演进：版本管理规则 → README + 打包脚本 → 重命名 **RimeDou** → `v0.2.0`（右 Cmd 触发 + 任意键结束 + 合成右 Ctrl 加 dwell 修「语音唤起方式调整」弹窗 + 豆字图标）。

**已知问题**（早期文档自认）：稳定性不足——「前几次成功，后面无反馈或停留豆包输入法」。

### 2.2 转向 fork：上游与个性化（2026-07-06 → 07-08）

同期（05-19 → 06-25）上游 `xubihang/Doubao-Voice-Input-Bridge`（DoubaoVoiceBridge）持续演进到 v1.0.6，解决了 TIS API 线程安全（macOS 15+ 崩溃）和 HotkeySender 事件保真度等可靠性问题——恰是自研版的痛点。于是放弃自研线（保留为本地 tag），**fork 上游 v1.0.6** 重新出发：

- `toggle 版 fork`：从上游「按住说话」改为**点按切换 + 任意键停止**的 tap-toggle 模式
- 启动后 0.5s 静默 externalVoiceEnd，修复合成键噪声导致的弹窗闪退
- **RimeDou 品牌化**：清除上游品牌痕迹（DoubaoVoiceBridge / xubihang 文案）、语音键定右 Control、焦点弹跳还原修复「TIS 已切但 NSTextInputContext 不同步」、菜单「豆」、bundle id `com.moc2216.rimedou`

> 上游 v1.0.6 为按住说话模式，与本项目 tap-toggle + 任意键停止的行为不同；上游无 LICENSE。本仓库的 MIT License 覆盖重写后的全部代码，历史渊源如实记录于此。

### 2.3 全面重写（2026-07-09 → 07-16，`v2.0.1` 上线 GitHub）

fork 来的代码是近 **1400 行的 AppDelegate 上帝类**，难维护。遂用 SDD（spec → plan → 十任务逐一实现 + 审查）流程**从零重写**为当前架构：

- 设计目标：功能边界清晰、可测试、Swift 6 严格并发、零第三方依赖
- 非目标（至今有效）：不做通用输入法桥接器、不做开机自启、不做长按模式、不引入依赖
- 十任务：骨架 → Logger → Config/Hotkey 解析 → VoiceStateMachine → PermissionReport → KeyboardEngine → InputMethodController → App UI → 文档构建 → 手动集成
- 配置精简：删除上游遗留的 `launchAtLogin` / `optionWarmupTapDuration` / `optionWarmupToHoldDelay` / `postSwitchSettleDelay`（旧用户配置文件中的残留键在 2026-09 才被清理，见 2.5）
- 结果：19 项测试，`v2.0.1`（commit `e0a1a69`）推送 GitHub 作为 main

### 2.4 本地演进（2026-07 → 09-02，未发布的中间态）

围绕「Mac Mouse Fix + MX Master 3S 侧键触发」打磨：

- 触发键支持**组合键**（多个修饰键 + 恰好一个普通键），默认一度改为 `LeftControl+LeftOption+LeftCommand+V`（MMF Button 6 生成该组合）
- 键盘监听从 `.cghidEventTap` 改为 **`.cgSessionEventTap`**：HID 层收不到 MMF 的 session 级注入（实测证伪），session 层可同时收实体键盘与模拟键
- 启动**预热**：短暂切豆包再切回，完成豆包快捷键冷启动初始化
- **事件暂存重放**：恢复 RIME 期间吞下的键盘事件按序补发，防首字符落入豆包
- **forcedStop 分离**：普通结束不再补发右 Control（实体结束键已通知豆包），修语音后逗号重开声波窗口
- 测试 43 项；期间本地版本号一度标 2.0.4（未发布）

### 2.5 三轮审阅与定稿（2026-09-03，`v2.0.2`）

两个 AI 对未提交工作区做了独立交叉审阅（一份只读报告 + 一份边审边修），用户综合双方意见定稿：

1. **自触发振荡防护**（最重要）：`RimeDouConfig.load` 拒绝可被 voice 快捷键合成事件「重武装」的触发键（纯修饰键触发与 voice 共享任意键码、或组合键触发与 voice 共享普通键 → 回退默认并告警）。规则精确：组合键仅由普通键 keyDown 武装，共享修饰键安全。
2. **权限窗口红 X 泄漏**：清理挂 `windowWillClose`（原实现红 X 关闭会致 Timer 空转 + Dock 图标残留），`enableTapped` 加 `withExtendedLifetime`。
3. **配置告警体系**：未知键 / 无效值 / 解析失败 / 自触发冲突全部记日志（原为静默回退，开发期曾因此误判）；用户配置清理 4 个死键。
4. 退出时强制停止语音（豆包麦克风不再悬空）；`voiceStartedUptime` 对称清理；`findInputSource` 精确匹配优先；`CFMachPortCreateRunLoopSource` 判空；权限探针对齐 session 层。
5. **死代码清理**：`VoiceEvent.reset`、`Key`/`Hotkey` 的 `Encodable`、`CaseIterable`、死参数、`.gitkeep`。
6. **定稿**：默认触发键回归**右 Command**，并新增**可选第二触发键** `triggerHotkey2`（`TriggerDetectorGroup` 聚合多触发键：任一命中即触发、命中后全组 reset 防连环触发；第二键的任何配置问题只丢弃自身并告警，绝不影响主键与语音键）。组合键普通键选 **Z**（五笔万能学习键几乎不用，规避「裸激活键结束语音」边界的触发面）。动因：Mac Mouse Fix 键盘快捷键**不支持录制单独修饰键**（官方 issue #1679，open），鼠标侧键只能发组合键。版本定为 **2.0.2**（首次发布后发现 MMF 限制而撤回重发，历史只有一个 v2.0.2 提交）；MIT License；测试 43 → **64**。

### 版本谱系

| 版本 | tag | 说明 |
|---|---|---|
| v0.1-trial / v0.2.0 | 本仓库 tag | 自研初版线（SwitchOnlyDoubaoVoiceInput → RimeDou），止于 v0.2.0 |
| （上游 v0.1.0 – v1.0.6） | 本仓库 tag | xubihang/Doubao-Voice-Input-Bridge 发布线，fork 源 |
| **v2.0.1** | `e0a1a69` | 全面重写后首发 GitHub |
| **v2.0.2** | 当前 | 演进 + 三轮审阅定稿 |

---

## 3. 架构与设计决策

```
Sources/RimeDouCore/          核心库（全部可单测）
├── VoiceStateMachine.swift   纯函数状态机：idle → voiceActive → restoringInputMethod
├── TriggerDetector           触发检测：单修饰键（flagsChanged 武装）/ 组合键（普通键 keyDown 武装）两套时序
├── TriggerDetectorGroup      多触发键聚合：主键 + 可选第二键，任一命中即触发、命中后全组 reset
├── KeyboardEngine.swift      CGEvent tap 生命周期、合成热键、事件暂存重放、external-end 检测
├── InputMethodController.swift  TIS 输入法切换、启动预热、恢复轮询、焦点回弹（AX API）
├── RimeDouConfig.swift       配置解析 / 校验 / 告警（Hotkey DSL：单键或 修饰键+1 普通键）
├── PermissionReport.swift    权限状态模型
└── RimeDouLogger.swift       文件日志（上限截断保最新）
Sources/rimedou/              菜单栏可执行：AppDelegate（编排）、权限引导窗口、入口
```

**关键决策及原因**（改动前先理解）：

1. **MMF 边界**：Mac Mouse Fix 会独占并吞掉 Button 6 原始鼠标事件，rimedou **不监听鼠标**；边界是 MMF 把按键映射成键盘事件、rimedou 在 session 层接收。
2. **session 事件 tap**（`.cgSessionEventTap` + headInsert + defaultTap）：同时收实体键盘与 MMF 注入，且保留拦截（吞键）能力；tap 被系统超时禁用时自动重启用。
3. **tap-toggle 而非按住**：点按触发（≤`tapMaxDuration` 且无其他键），与上游按住模式根本不同。
4. **普通结束不发右 Control**：实体结束键在更早事件层已通知豆包；补发会重开声波窗口。仅强制停止路径合成右 Control。
5. **Swift 6 严格并发**：tap 回调经 `MainActor.assumeIsolated` 进主 actor（源只挂在主 run loop，**不可**再 `main.sync`，会死锁）。
6. **吞键对称性**：组合键只吞普通键、放行修饰键（修饰键单用无害且他途常用）；取消路径 keyDown/keyUp 成对吞掉。

---

## 4. 验证基线

- `swift test`：**64 项，0 失败**（v2.0.1 为 19，重写期 43，首轮定稿 55，第二触发键 +9）
- `swift build` / `-c release`：零警告；`bash -n scripts/build-app.sh` 通过
- 真机（macOS 15 + 豆包 0.9.3 + MMF 3.0.8 + MX Master 3S）：组合键时代 Button 6 → 语音 → 上屏 → 切回 RIME 全链路通过；右 Command 单键路径有完整回归测试（左右区分 / 点按判定 / 组合不误触 / 超时取消）
- 已知测试缺口：`handleKeyboardEvent` 的 external-end 检测依赖真实 `systemUptime` 与事件 tap，无单测；补齐需注入时钟（未做，收益比不高）

---

## 5. 踩坑全书（按主题）

**触发与事件**
- MMF 独占 Button 6：别监听鼠标，走键盘事件边界（见决策 1）
- **MMF 键盘快捷键不能录制单独修饰键**（官方 issue #1679，截至 3.0.8 open）：鼠标侧键触发只能发组合键——第二触发键方案的由来
- 组合键必须含一个普通键；只有修饰键无效（告警回退）
- 触发键（含第二触发键）与 voiceHotkey 不能自触发冲突（校验拒绝 + 告警；第二键冲突只丢弃第二键自身）
- **裸激活键边界**：语音中单独按下组合键的普通键（如裸 Z）不算结束信号，恢复要等下一个按键——普通键因此选五笔中几乎不用的 Z
- 组合键改动必须回归「普通按键不被吞」（有测试钉死；初版实现曾吞）
- HID tap 收不到 MMF 注入；必须 session 层

**语音与输入法**
- 语音结束后别再发右 Control（重开声波窗口）
- 输入源切换 ≠ 文本上下文绑定：焦点回弹必要（AX 设 main/focused）
- 恢复期吞下的按键必须重放（否则用户丢字）
- 切输入法查找先精确（name/id）后子串，防命中同级错误源

**macOS 权限与签名**
- ad-hoc 签名每次构建都变：覆盖 `/Applications` → 辅助功能/输入监控权限失效需重授；根治用稳定证书（`CODE_SIGN_IDENTITY`）
- 权限探针要与引擎同层（session），否则探过引擎仍失败
- NSWindowController 关闭清理挂 `windowWillClose`：红 X 不走 controller 的 `close()`

**工程与协作**
- 改配置校验先跑全量测试：曾有一版校验过严被既有测试打回
- 项目目录整体拷贝后 `.build/` 残留旧绝对路径：「module cache path」报错 → 删 `.build/` 重建
- 静默回退配置 = 调试黑洞：所有回退必须告警（曾因「只有修饰键的组合」静默回退误判）
- `KeyboardEngine` 回调已在主循环：不要 `DispatchQueue.main.sync`

---

## 6. 接手指引（给下一个 AI / 开发者）

**优先阅读顺序**：README（用法与备选方案）→ 本文档 → `Sources/RimeDouCore/KeyboardEngine.swift`（含 TriggerDetector）→ `VoiceStateMachine.swift` → `RimeDouConfig.swift` → `AppDelegate.swift`（编排层）。

**二次开发流程**：
1. `swift test` 确认 55 全绿起步
2. 改动 → 全量测试 → `./scripts/build-app.sh` → 换装实测（注意权限重授）
3. 配置 / 触发检测类改动，先补测试再动实现
4. 用户配置与日志在 `~/Library/`，与仓库无关；改配置 schema 时注意向后兼容（未知键忽略 + 告警）

**未采纳的改进建议**（有触发条件再做，勿盲目实施）：60s 语音看门狗超时、合成事件打标 `eventSourceUniqID`、配置自愈写回、`SMAppService` 登录自启、GitHub Actions CI、`VoiceSessionCoordinator` 编排层提取、注入时钟使 external-end 可测。

**安全红线**：零网络、零第三方依赖、日志不记录按键内容——任何改动不得突破。

**发布**：改版本需同时更新 `support/Info.plist` 的两个键（ShortVersionString / BundleVersion）；GitHub 版本线当前为 2.0.2；历史 tag（含自研初版与上游线）已全部推至远端，`git log --all --oneline --graph` 可见全貌。
