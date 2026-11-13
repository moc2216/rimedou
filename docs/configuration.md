# 配置说明

从 RimeDou 菜单选择“打开配置”。文件位于 `~/Library/Application Support/rimedou/config.json`，保存后选择“重新加载配置”。

## 入口与语音键

| 字段 | 默认值 | 用途 |
|---|---|---|
| `triggerHotkey` | `RightCommand` | RimeDou 主入口 |
| `triggerHotkey2` | 未设置 | RimeDou 第二入口，常用于鼠标侧键映射 |
| `doubao_VoiceHotkey` | `RightControl` | RimeDou 转发给豆包的语音键，应与豆包设置一致 |
| `qianwen_VoiceHotkey` | 未设置 | RimeDou 转发给千问的语音键，应与千问设置一致 |

来源由菜单选择。只启用豆包时可以省略千问字段。只启用千问时，填写其真实语音键即可。首次无历史选择时会使用检测到的来源，保留的历史选择仍由用户明确切换。

当前启用的来源参与快捷键冲突校验。两家同时启用时，两个语音键及其前缀关系须满足冲突检查。输入法列表发生变化后，RimeDou 会在安全空闲时重新校验。若提示松开按键，请松键后重新加载配置。

旧字段 `voiceHotkey`、`qianwenVoiceHotkey` 分别对应豆包和千问。新旧并存时以新名称为准。新字段显式为 `null` 时也覆盖旧字段，豆包采用默认语音键，千问保持未配置状态。

## 按键英文

| 按键 | 左侧 | 右侧 | 任意侧 |
|---|---|---|---|
| Shift `⇧` | `LeftShift` | `RightShift` | `Shift` |
| Control `⌃` | `LeftControl` | `RightControl` | `Control` |
| Option `⌥` | `LeftOption` | `RightOption` | `Option` |
| Command `⌘` | `LeftCommand` | `RightCommand` | `Command` |

用 `+` 连接组合键，例如 `LeftShift+LeftControl`。入口支持单键，或修饰键加一个普通键，例如 `LeftShift+LeftOption+Z`。普通键支持字母、数字、部分英文标点、`Space` 和 `Tab`。

千问语音键支持一个或两个修饰键，左右侧应与千问自身设置对应。千问设置中还需开启短按唤起。字段无效或存在冲突时，日志会给出提示。

## 两家输入法示例

```json
{
  "triggerHotkey": "RightCommand",
  "triggerHotkey2": "LeftShift+LeftOption+Z",
  "doubao_VoiceHotkey": "RightControl",
  "qianwen_VoiceHotkey": "LeftShift+LeftControl"
}
```

使用此示例时，将豆包设置成右 Control，将千问设置成左 Shift＋左 Control，将鼠标侧键映射为左 Shift＋左 Option＋Z。也可以选择其他满足校验的组合，并同步修改对应设置。

## 在配置末尾保存参考

配置采用标准 JSON。可以加入普通说明字段来保存按键参考，如下面的 `_快捷键参考`。加载时会记录未知字段提示，说明字段的内容供人阅读，实际行为由上方有效字段决定。

```json
{
  "triggerHotkey": "RightCommand",
  "triggerHotkey2": "LeftShift+LeftOption+Z",
  "doubao_VoiceHotkey": "RightControl",
  "qianwen_VoiceHotkey": "LeftShift+LeftControl",
  "_快捷键参考": {
    "英文名称": ["LeftShift", "RightShift", "LeftControl", "RightControl", "LeftOption", "RightOption", "LeftCommand", "RightCommand"],
    "豆包示例": ["RightControl", "RightOption"],
    "千问示例": ["LeftShift+LeftControl", "LeftShift+LeftOption"],
    "说明": "示例须与输入法自身设置一致，修改上方生效字段后重新加载配置"
  }
}
```

JSON 中字符串使用英文双引号，最后一项后省略逗号。说明文字请放在字符串字段中。

## 时序参数

日常使用可以保留默认值。

| 字段 | 默认值 | 含义 |
|---|---|---|
| `tapMaxDuration` | `0.35` | 用户短按最长秒数 |
| `tapDuration` | `0.15` | 合成语音键持续秒数 |
| `restoreDelay` | `0.5` | 豆包未确认窗口完成时的恢复延迟秒数 |
| `switchPollInterval` | `0.05` | 输入源恢复轮询间隔秒数 |
| `switchWaitTimeout` | `2.0` | 输入源恢复最长等待秒数 |
| `focusBounceBackDelay` | `0.1` | 必要的焦点刷新等待秒数 |
| `focusBounceSettleDelay` | `0.1` | 焦点刷新稳定等待秒数 |
| `qianwenCompletionTimeout` | `60` | 千问停止后最长等待秒数，可设 1–300 |
| `qianwenGoneStabilityDelay` | `0.15` | 千问窗口消失稳定观察秒数，可设 0.1–1 |

[返回使用说明](../README.md)
