# 审查记录

## 阶段 7 审查

日期：2026-06-02

## 当前结论

开发版应用入口已经串起：

- 配置加载。
- 输入源存在性和可选择性检查。
- Type4Me 运行状态检测。
- 输入监听权限检查。
- 辅助功能权限检查。
- 右 Ctrl 监听入口。
- 状态机。
- 鼠须管和豆包输入源切换服务。
- 豆包语音控制接口。

当前运行环境缺少必要权限：

- `inputMonitoringPermission=false`
- `accessibilityPermission=false`

因此开发版 `--run` 会明确失败并提示输入监听权限缺失。这是预期行为，不是代码绕过。

## 已验证

自动测试通过：

```bash
env CLANG_MODULE_CACHE_PATH=.build/module-cache XDG_CACHE_HOME=.build/xdg-cache swift run --disable-sandbox --cache-path .build/swiftpm-cache rimedou-tests
```

输出：

```text
All tests passed
```

开发版运行检查输出：

```text
configLoaded=true
primaryInputSourceSelectable=true
doubaoInputSourceSelectable=true
inputMonitoringPermission=false
accessibilityPermission=false
externalVoiceToolRunning=false
rimedou error: Input monitoring permission is missing
```

输入源切换在沙盒外验证通过：

```text
selectedDoubaoInputSourceId=com.bytedance.inputmethod.doubaoime.pinyin
selectedPrimaryInputSourceId=im.rime.inputmethod.Squirrel.Hans
restoredInputSourceId=im.rime.inputmethod.Squirrel.Hans
```

## 剩余手动验收

需要给运行程序授予 macOS 权限后再验收：

- 输入监听权限：用于全局监听右 Ctrl。
- 辅助功能权限：用于模拟右 Ctrl 触发豆包语音。

权限到位后需要验证：

- 左 Ctrl 不触发。
- Type4Me 运行时右 Ctrl 不触发豆包流程。
- Type4Me 退出后右 Ctrl 触发豆包流程。
- 第一次右 Ctrl 切到豆包并尝试触发语音。
- 第二次右 Ctrl 尝试结束豆包语音并恢复鼠须管。

## 风险

- 豆包语音是否接受外部模拟右 Ctrl 仍需真实权限环境下验证。
- 当前开发版是命令行程序，macOS 权限授权对象可能是 Terminal、Codex、swift 产物或最终打包 App；后续正式使用应考虑打包成稳定 App。
- Codex 沙盒内真实输入源切换会失败；需要沙盒外或正式 App 环境验证。

## 阶段 8 审查

日期：2026-06-02

## 第一阶段自查

需求、spec、设计、实现已对齐：

- 右 Ctrl 作为主触发键。
- 左 Ctrl 不触发。
- Type4Me 运行时暂停豆包流程。
- Type4Me 退出后恢复接管右 Ctrl。
- 第一次右 Ctrl：切豆包并尝试触发豆包语音。
- 第二次右 Ctrl：尝试停止豆包语音并恢复鼠须管。
- 权限不足时明确失败，不伪装成正常运行。
- 不修改系统配置，不自动授予权限，不安装全局依赖。

审查中发现并修复：

- `AppRunner` 原先只在启动时检查 Type4Me，不能处理 Type4Me 后续打开/退出。已新增 `ExternalVoiceToolStateTracker` 并在运行时每秒轮询。
- `AppRunner.stop()` 原先没有在 `doubaoVoiceActive` 状态下尽力恢复鼠须管。已补充退出恢复逻辑。

## 第二阶段行为审查

自动验证已覆盖：

- 状态机进入和退出豆包语音流程。
- Type4Me started/stopped 事件。
- 输入源配置加载。
- 输入源存在性和可选择性。
- 右 Ctrl / 左 Ctrl 解析。
- 合成右 Ctrl 事件不被监听器再次处理。
- 豆包语音控制模块会模拟右 Ctrl tap。

开发版 `--run` 当前行为：

```text
configLoaded=true
primaryInputSourceSelectable=true
doubaoInputSourceSelectable=true
inputMonitoringPermission=false
accessibilityPermission=false
externalVoiceToolRunning=false
rimedou error: Input monitoring permission is missing
```

这是符合预期的失败：当前运行程序没有输入监听权限和辅助功能权限。

## 最终剩余风险

- 真实右 Ctrl 全局监听需要授予输入监听权限后验收。
- 真实豆包语音触发需要授予辅助功能权限后验收。
- 豆包是否接受外部模拟右 Ctrl 启动/停止语音，仍需真实权限环境验证。
- 开发版命令行程序的权限授权对象不够稳定；后续正式使用应打包成固定 macOS App。

## 打包方案

为避免 `swift run` 产物导致权限授权对象不稳定，项目新增本地打包脚本：

```bash
zsh scripts/build-app.sh
```

脚本会在项目内生成：

```text
dist/RimeDou.app
```

该目录属于生成产物，已加入 `.gitignore`。打包脚本不安装全局依赖，不修改系统配置。

## 试用基线记录

日期：2026-06-03

## 当前安装与运行状态

正式试用 App 路径：

```text
/Applications/RimeDou.app
```

当前已启动并常驻：

```text
27958 /Applications/RimeDou.app/Contents/MacOS/RimeDou
```

当前输入源检查：

```text
primaryInputSourceId=im.rime.inputmethod.Squirrel.Hans exists=true selectable=true
doubaoInputSourceId=com.bytedance.inputmethod.doubaoime.pinyin exists=true selectable=true
currentInputSourceId=im.rime.inputmethod.Squirrel.Hans
```

Type4Me 当前未运行：

```text
externalVoiceToolRunning=false
```

## 当前版本行为

当前试用版本采用以下策略：

- 豆包输入法自己的“语音输入 -> 免按模式 -> 右 Ctrl”是事实来源，本工具只匹配该快捷键。
- 使用旁听式 event tap，不吞掉物理右 Ctrl。之前测试过短窗口吞键，但会破坏正常短按主路径，已撤销。
- 第一次右 Ctrl：
  - 延迟 `0.08s` 处理物理右 Ctrl。
  - 切换输入源到豆包。
  - 轮询确认系统实际切到豆包。
  - 等待 `0.18s` 后合成一次右 Ctrl，触发豆包语音。
- 第二次右 Ctrl：
  - 不额外合成豆包停止快捷键。
  - 不自动发送 `Esc`，避免取消豆包尚未提交的识别结果。
  - 等待 `1.2s` 让识别文字提交到输入框。
  - 切回鼠须管；如果第一次确认失败，`0.25s` 后重试一次。
- 空闲守护：
  - 工具处于 `idle` 且 Type4Me 未运行时，每秒检查当前输入源。
  - 如果当前输入源不是鼠须管，自动拉回鼠须管。

## 最新验证

自动测试通过：

```bash
env CLANG_MODULE_CACHE_PATH=.build/module-cache XDG_CACHE_HOME=.build/xdg-cache swift run --disable-sandbox --cache-path .build/swiftpm-cache rimedou-tests
```

输出：

```text
All tests passed
```

手动试用反馈：

- 默认输入法是 RIME 时，大概率语音输入正常。
- 正常短按右 Ctrl 多数情况下可以识别语音并在输入框上屏。
- 曾出现少部分情况下文字上屏后输入源停留在豆包，因此已新增空闲守护兜底。
- 曾测试过自动 `Esc` 清理弹窗，但可能导致识别结果不上屏，已撤销。
- 曾测试过可拦截 event tap 吞掉手抖快按，但会破坏短按主路径，已撤销。

## 下次继续入口

下次继续时优先验证：

1. 正常短按右 Ctrl 后，豆包语音启动速度是否可接受。
2. 语音文字上屏后，输入源是否能稳定回到鼠须管。
3. 如果偶尔停在豆包，等待约 1 秒后空闲守护是否自动拉回鼠须管。
4. Type4Me 打开时，本工具是否暂停接管右 Ctrl。

## 菜单栏控制基线

日期：2026-06-03

已新增菜单栏控制版：

- 菜单栏标题：`豆`
- 状态项：显示运行中、已暂停、Type4Me 让渡、豆包语音中或错误。
- `暂停` / `启用`：暂停或恢复右 Ctrl 监听。
- `恢复鼠须管`：立即尝试切回鼠须管。
- `退出`：关闭后台 App。

实现文件：

- `src/RimeDou/main.swift`
- `src/RimeDouCore/AppRunner.swift`
- `src/RimeDouCore/MenuBarPresentation.swift`
- `tests/RimeDouTests/MenuBarPresentationTests.swift`

验证：

```text
All tests passed
```

当前菜单栏版已覆盖到 `/Applications/RimeDou.app`。由于二进制变化且当前为 adhoc 签名，启动后 macOS 再次返回：

```text
inputMonitoringPermission=false
accessibilityPermission=false
rimedou error: Input monitoring permission is missing
```

需要重新添加 `输入监控` 和 `辅助功能` 授权后再启动菜单栏版。

如果需要重新打包并覆盖 `/Applications`：

1. 运行 `scripts/build-app.sh`。
2. 停止当前 `RimeDou` 旧进程。用户已授权为了覆盖新版而停止旧进程，不需要重复询问同一问题。
3. 用 `ditto dist/RimeDou.app /Applications/RimeDou.app` 覆盖。
4. 因当前 App 是 adhoc 签名，覆盖二进制后 macOS 可能要求重新添加 `输入监控` 和 `辅助功能` 授权。
