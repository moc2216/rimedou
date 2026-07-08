# RimeDou

macOS 菜单栏工具：**点按右 Command 用豆包输入法的语音输入，说完自动切回主输入法（RIME / 鼠须管）**。

专为「打字用 RIME、语音用豆包」的双输入法工作流设计。利用豆包输入法 0.9.3 的「全局唤起语音」，无需手动切换输入法——点按一下右 Cmd 就能语音输入，结束（再点右 Cmd 或按任意键）后自动还原到 RIME。

## 用法

| 操作 | 结果 |
|---|---|
| 点按右 Command（快速按一下松开） | 豆包语音弹窗出现，开始识别 |
| 说完后再点按右 Command | 文字上屏，输入法自动切回 RIME |
| 说完后按空格 / 任意键 | 文字上屏，自动切回 RIME（豆包原生「任意键停止」，工具也会还原） |

> 点按 = 按下到松开期间不按其他键、时长 ≤ `tapMaxDuration`（默认 0.35s）。正常用右 Cmd 作修饰键（Cmd+X 等）不受影响。

## 前置条件

- macOS 13+
- 豆包输入法 0.9.3 及以上
- 豆包设置里：打开「全局唤起语音」开关，全局热键设为**右 Control**
- 主输入法为 Squirrel（鼠须管 / RIME）
- 首次使用授予：辅助功能、输入监控

## 构建

```bash
git clone https://github.com/moc2216/rimedou.git
cd rimedou
./scripts/build-app.sh
open build/rimedou.app
```

需要 Swift 工具链（Xcode 或 Command Line Tools）。代码签名：默认 ad-hoc；可用 `CODE_SIGN_IDENTITY="证书名"` 指定稳定签名身份。

## 配置

用户配置在 `~/Library/Application Support/RimeDou/config.json`，首次启动自动生成。常用项：

| 字段 | 默认 | 说明 |
|---|---|---|
| `triggerHotkey` | `RightCommand` | 触发键，支持组合（如 `RightCommand+Space`） |
| `voiceHotkey` | `RightControl` | 发给豆包的全局语音热键，需与豆包设置一致 |
| `tapMaxDuration` | `0.35` | 点按最长时长（秒），超过算修饰键使用 |
| `restoreDelay` | `0.5` | 停止后多久开始切回主输入法 |
| `tapDuration` | `0.15` | 合成语音键的点按时长 |

改完在菜单栏图标点 `Reload Config` 即时生效。

## 运行机制

1. 点按右 Cmd → RimeDou 合成右 Control → 豆包全局唤起，自切到豆包 + 开语音
2. 用户说话（实时上屏）
3. 停止信号（右 Cmd 点按 / 任意键）→ 豆包停止 + 上屏
4. RimeDou 轮询切回 RIME（覆盖豆包上屏期间的反复重抢）

事件 tap 被系统超时禁用时会自动重新启用，避免「按了没反应」。

## 目录

- `src/RimeDou` — 菜单栏可执行入口
- `src/RimeDouCore` — 状态机、配置、输入法控制、版本检测
- `tests/RimeDouTests` — 单元测试
- `assets/AppIcon.icns` — 应用图标
- `scripts/build-app.sh` — 编译打包

## 许可

个人自用。
