# rimedou

macOS 菜单栏工具：**通过可配置快捷键启动豆包输入法的语音输入，说完自动切回主输入法（RIME / 鼠须管）**。

专为「打字用 RIME、语音用豆包」的双输入法工作流设计。利用豆包输入法 0.9.3 的「全局唤起语音」，无需手动切换输入法。默认**点按右 Command 键**触发（严格区分左右，左 Command 与 ⌘ 组合键使用不受影响）；想用鼠标侧键触发的用户可配置**第二触发键**组合键，见下方「第二触发键（鼠标侧键方案）」。

启动时会短暂激活一次豆包输入法并切回原输入法，让冷启动后的豆包语音快捷键完成初始化。语音结束后的输入法恢复期间，键盘事件会被短暂保存，并在 RIME 恢复后按原顺序补发，避免第一个字符落入豆包输入法。

## 用法

| 操作 | 结果 |
|---|---|
| 点按右 Command（或已配置的鼠标侧键） | 豆包语音弹窗出现，开始识别 |
| 说完后再点按同一快捷键 | 文字上屏，输入法自动切回 RIME |
| 说完后按空格 / 任意键 | 文字上屏，自动切回 RIME（豆包原生「任意键停止」，工具也会还原） |

> 点按 = 快捷键从按下到松开的时长 ≤ `tapMaxDuration`（默认 0.35s），且中间没按其他键。右 Command 与其他键的组合使用（如 ⌘+C）不会触发。

## 前置条件

- macOS 15.0+
- Swift 6.0 工具链（Xcode 或 Command Line Tools）
- 豆包输入法 0.9.3 及以上
- 豆包设置里：打开「全局唤起语音」开关，全局热键设为**右 Control**
- 主输入法为 Squirrel（鼠须管 / RIME）
- 首次使用授予：辅助功能、输入监控

## 构建

```bash
git clone https://github.com/moc2216/rimedou.git
cd rimedou
swift build
./scripts/build-app.sh
open build/rimedou.app
```

- `swift build` 编译可执行文件与 `RimeDouCore` 库。
- `./scripts/build-app.sh` 生成 `build/rimedou.app` 并完成代码签名；默认使用本地可用的签名身份，未找到则 ad-hoc 签名（`-`）。可用 `CODE_SIGN_IDENTITY="证书名"` 指定稳定签名身份。

## 配置

用户配置位于 `~/Library/Application Support/rimedou/config.json`，首次启动会自动生成。常用项：

| 字段 | 默认 | 说明 |
|---|---|---|
| `triggerHotkey` | `RightCommand` | 主触发键，支持单键或“修饰键 + 一个普通键”组合 |
| `triggerHotkey2` | （不设置） | 可选第二触发键，与主触发键并存、任一可触发；见下方「第二触发键」 |
| `voiceHotkey` | `RightControl` | 发给豆包的全局语音热键，需与豆包设置一致 |
| `tapMaxDuration` | `0.35` | 点按最长时长（秒），超过算修饰键使用 |
| `tapDuration` | `0.15` | 合成语音键的点按时长 |
| `restoreDelay` | `0.5` | 停止后多久开始切回主输入法 |
| `switchPollInterval` | `0.05` | 切回主输入法时的轮询间隔 |
| `switchWaitTimeout` | `2.0` | 切回主输入法的最长等待时间 |
| `focusBounceBackDelay` | `0.1` | 焦点回弹等待 |
| `focusBounceSettleDelay` | `0.1` | 焦点稳定等待 |

改完后在菜单栏图标点 `Reload Config` 即时生效（或重启）。无法解析或不合法的字段会自动回退默认值，并在日志中记录一条警告（例如写成只有修饰键的组合时，日志会提示 `invalid triggerHotkey`），方便排查误配。

## 第二触发键（鼠标侧键方案）

想让**鼠标侧键**也能触发语音时，配置可选的第二触发键。在 `config.json` 加入下面这行（复制粘贴后 `Reload Config` 生效）：

```json
"triggerHotkey2": "LeftControl+LeftOption+LeftCommand+Z"
```

再到鼠标工具里把侧键映射为该组合键。以 Logitech MX Master 3S 的 Button 6 + Mac Mouse Fix 为例：MMF → Buttons → Button 6 → 添加「Keyboard Shortcut」→ 录制 **⌃⌥⌘Z**。

几点说明：

- **为什么用组合键而不是右 Command 单键**：Mac Mouse Fix 的键盘快捷键不支持录制单独修饰键（官方 [issue #1679](https://github.com/noah-nuebling/mac-mouse-fix/issues/1679)，截至 3.0.8 仍为 open 的功能请求），侧键只能发组合键。
- **为什么普通键选 Z**：组合键的普通键在语音中单独按下时不算“结束信号”，选一个输入中几乎不用的键（五笔 Z 为万能学习键、英文 Z 频率最低）可避免误触；可换成任意其他普通键。
- **与设备无关**：第二触发键只是“监听 ⌃⌥⌘Z 这个键盘模式”，换用没有侧键的鼠标时它会自然休眠（不触发、不报错），右 Command 主触发不受影响。
- 第二触发键配置错误（无效组合、与主触发键相同、与语音键自触发冲突）只会在日志告警并忽略该键，主触发键和语音键不受影响。
- 组合键必须包含一个普通键；只有修饰键的组合无效。触发键（含主键）不能与 `voiceHotkey`（右 Control）产生自我触发冲突，此类配置会告警并回退。

**已知小边界**：语音进行中若恰好**单独按下**组合键里的普通键（如裸 Z）来结束语音，rimedou 会等下一个按键才恢复输入法（该字符可能落入豆包）。用空格、回车或其他键结束则无此问题。

## 运行机制

1. 启动时短暂切到豆包再切回，完成豆包语音快捷键初始化
2. 点按任一触发键（右 Command / 第二触发键 ⌃⌥⌘Z / 映射了该组合键的鼠标侧键）→ rimedou 合成右 Control → 豆包全局唤起，自切到豆包 + 开语音
3. 用户说话（实时上屏）
4. 停止信号（再点快捷键 / 任意键）→ 豆包停止 + 上屏
5. rimedou 暂存恢复期间的键盘事件，确认切回 RIME 后再补发

结束语音的实体按键本身已经会通知豆包停止，因此 rimedou 不会在普通结束流程中再次发送右 Control，避免语音弹窗被意外重新唤醒。

键盘事件在会话层监听，因此既能识别实体键盘，也能识别 Mac Mouse Fix 等工具生成的模拟快捷键。事件 tap 被系统超时禁用时会自动重新启用，避免「按了没反应」。

## 目录

- `Sources/rimedou` — 菜单栏可执行入口
- `Sources/RimeDouCore` — 状态机、配置、键盘事件、输入法控制
- `Tests/RimeDouCoreTests` — 单元测试
- `assets/AppIcon.icns` — 应用图标
- `support/Info.plist` — 应用 bundle 信息
- `scripts/build-app.sh` — 编译打包

默认配置硬编码在 `RimeDouConfig.default`（上表即其取值），首次启动自动写入用户配置文件，无需模板文件。

## 许可

MIT License，见 [LICENSE](LICENSE)。
