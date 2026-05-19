# DoubaoVoiceBridge

DoubaoVoiceBridge 是一个本地 macOS 菜单栏工具。它把物理右 `Command` 键做成按住说话的开关：平时保留你习惯的输入法，按住右 `Command` 时切到豆包输入法进行语音输入，松开后自动恢复回日常输入法。

## 前置条件

- macOS
- 需要使用豆包输入法
- 默认日常输入法建议是 `Squirrel - Simplified`
- 首次使用要授予两个系统权限：
  - Accessibility
  - Input Monitoring

## 快速开始

### 1. 下载 Release 版

如果你只是想直接用，优先去 GitHub Release 下载打包好的应用：

[`Releases`](https://github.com/xubihang/Doubao-Voice-Input-Bridge/releases)

下载后把 `DoubaoVoiceBridge.app` 放到 `Applications` 或任意常用目录，直接打开即可。

### 2. 首次打开后授权

第一次启动后，系统会提示或需要你手动到系统设置里授权：

- 系统设置 -> 隐私与安全性 -> 辅助功能
- 系统设置 -> 隐私与安全性 -> 输入监控

授权完成后，退出并重新打开应用。

### 3. 开始使用

1. 确认你的正常输入法是 `Squirrel - Simplified`
2. 确认豆包输入法已安装，并且配置中的名称能匹配到它
3. 在任意可输入文本的地方，按住右 `Command`
4. 说话结束后松开右 `Command`
5. 应用会自动切回你的日常输入法

菜单栏里可以：

- `Disable` / `Enable`：临时停用或启用桥接
- `Open Log`：打开日志
- `Check Permissions`：重新检查权限
- `Quit`：退出应用

## 配置说明

配置文件放在项目根目录 `config.json`，不存在就使用默认值。

路径：

```text
./config.json
```

支持部分覆盖，没写的项会自动沿用默认值。

示例：

```json
{
  "targetInputMethod": "豆包输入法",
  "userInputMethod": "Squirrel - Simplified",
  "launchAtLogin": true,
  "restoreDelay": 0.2,
  "postSwitchSettleDelay": 1.2,
  "recentRestoreSettleDelay": 1.5,
  "switchWaitTimeout": 2.0,
  "switchPollInterval": 0.05,
  "focusBounceBackDelay": 0.16,
  "focusBounceSettleDelay": 0.16,
  "optionWarmupTapDuration": 0.05,
  "optionWarmupToHoldDelay": 0.22
}
```

各项含义：

- `targetInputMethod`：按住右 `Command` 时切换到的输入法名称，默认 `豆包输入法`
- `userInputMethod`：松开后恢复的日常输入法，默认 `Squirrel - Simplified`
- `launchAtLogin`：是否开机/登录后自动启动，默认 `true`
- `restoreDelay`：松开右 `Command` 后，延迟多久恢复输入法，默认 `0.2`
- `postSwitchSettleDelay`：切到豆包后，等待系统稳定的时间，默认 `1.2`
- `recentRestoreSettleDelay`：刚恢复过输入法后的额外稳定等待，默认 `1.5`
- `switchWaitTimeout`：等待目标输入法确认成功的超时，默认 `2.0`
- `switchPollInterval`：轮询当前输入法的间隔，默认 `0.05`
- `focusBounceBackDelay`：做焦点回弹时，切走后多久切回原应用，默认 `0.16`
- `focusBounceSettleDelay`：切回原应用后，再等多久再触发语音，默认 `0.16`
- `optionWarmupTapDuration`：左 `Option` 预热按下的持续时间，默认 `0.05`
- `optionWarmupToHoldDelay`：预热结束到正式按住之间的等待时间，默认 `0.22`

## 构建

如果你想自己编译：

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open build/DoubaoVoiceBridge.app
```

打包时，`scripts/build-app.sh` 会把同一份 `config.json` 复制进应用包里，所以本地开发和导出的 app 会共用同一个配置。

## 下载版注意事项

- Release 版和本地编译版都需要重新授权权限
- 第一次打开如果被 macOS 拦截，去系统设置里允许，或者从 Finder 右键打开一次
- 如果你的豆包输入法名称和默认值不一致，把 `targetInputMethod` 改成你机器上实际显示的名称
- 如果你平时的输入法不是 `Squirrel - Simplified`，把 `userInputMethod` 改成你的默认输入法名称
- 日志在：

```text
~/Library/Logs/DoubaoVoiceBridge/app.log
```

## 发布内容

Release 中建议同时提供：

- `DoubaoVoiceBridge.app`
- 对应的源码或构建说明
- 版本变更说明

本次 release 的重点：

- 新增 `launchAtLogin` 配置，默认开启
- App 启动时会自动同步 macOS 登录项状态

这样下载用户可以直接用，开发者也可以自行复现构建结果。
