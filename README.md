# rimedou

macOS 菜单栏工具：**点按右 Command 用豆包输入法的语音输入，说完自动切回主输入法（RIME / 鼠须管）**。

专为「打字用 RIME、语音用豆包」的双输入法工作流设计。利用豆包输入法 0.9.3 的「全局唤起语音」，无需手动切换输入法——点按一下右 Cmd 就能语音输入，结束（再点右 Cmd 或按任意键）后自动还原到 RIME。

启动时会短暂激活一次豆包输入法并切回原输入法，让冷启动后的豆包语音快捷键完成初始化。语音结束后的输入法恢复期间，键盘事件会被短暂保存，并在 RIME 恢复后按原顺序补发，避免第一个字符落入豆包输入法。

## 用法

| 操作 | 结果 |
|---|---|
| 点按右 Command（快速按一下松开） | 豆包语音弹窗出现，开始识别 |
| 说完后再点按右 Command | 文字上屏，输入法自动切回 RIME |
| 说完后按空格 / 任意键 | 文字上屏，自动切回 RIME（豆包原生「任意键停止」，工具也会还原） |

> 点按 = 按下到松开期间不按其他键、时长 ≤ `tapMaxDuration`（默认 0.35s）。正常用右 Cmd 作修饰键（Cmd+X 等）不受影响。

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
| `triggerHotkey` | `RightCommand` | 触发键，当前仅支持单键（如 `RightCommand`） |
| `voiceHotkey` | `RightControl` | 发给豆包的全局语音热键，需与豆包设置一致 |
| `tapMaxDuration` | `0.35` | 点按最长时长（秒），超过算修饰键使用 |
| `tapDuration` | `0.15` | 合成语音键的点按时长 |
| `restoreDelay` | `0.5` | 停止后多久开始切回主输入法 |
| `switchPollInterval` | `0.05` | 切回主输入法时的轮询间隔 |
| `switchWaitTimeout` | `2.0` | 切回主输入法的最长等待时间 |
| `focusBounceBackDelay` | `0.1` | 焦点回弹等待 |
| `focusBounceSettleDelay` | `0.1` | 焦点稳定等待 |

改完后在菜单栏图标点 `Reload Config` 即时生效（或重启）。

## 运行机制

1. 启动时短暂切到豆包再切回，完成豆包语音快捷键初始化
2. 点按右 Cmd → rimedou 合成右 Control → 豆包全局唤起，自切到豆包 + 开语音
3. 用户说话（实时上屏）
4. 停止信号（右 Cmd 点按 / 任意键）→ 豆包停止 + 上屏
5. rimedou 暂存恢复期间的键盘事件，确认切回 RIME 后再补发

事件 tap 被系统超时禁用时会自动重新启用，避免「按了没反应」。

## 目录

- `Sources/rimedou` — 菜单栏可执行入口
- `Sources/RimeDouCore` — 状态机、配置、键盘事件、输入法控制
- `Tests/RimeDouCoreTests` — 单元测试
- `assets/AppIcon.icns` — 应用图标
- `support/Info.plist` — 应用 bundle 信息
- `scripts/build-app.sh` — 编译打包
- `config.json` — 默认配置模板

## 许可

个人自用。
