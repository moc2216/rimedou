# 手动验收

## 结论

当前代码和 App 包已经准备好。下一步必须由用户手动授予 macOS 权限，然后再验证右 Ctrl 行为。

需要授权的 App：

```text
dist/SwitchOnlyDoubaoVoiceInput.app
```

需要授予的权限：

- 输入监听：用于全局监听右 Ctrl。
- 辅助功能：用于模拟右 Ctrl，触发或结束豆包语音。

## 授权前检查

在项目根目录运行：

```bash
zsh scripts/build-app.sh
```

确认生成：

```text
dist/SwitchOnlyDoubaoVoiceInput.app
```

## 授权步骤

打开 macOS 系统设置：

1. 进入“隐私与安全性”。
2. 进入“输入监听”。
3. 添加并启用 `dist/SwitchOnlyDoubaoVoiceInput.app`。
4. 回到“隐私与安全性”。
5. 进入“辅助功能”。
6. 添加并启用 `dist/SwitchOnlyDoubaoVoiceInput.app`。

如果系统不允许选择项目内的 App，可以先在 Finder 中定位 `dist/SwitchOnlyDoubaoVoiceInput.app`，再拖到对应权限列表里。

## 权限检查

授权后运行：

```bash
dist/SwitchOnlyDoubaoVoiceInput.app/Contents/MacOS/SwitchOnlyDoubaoVoiceInput --check-hotkey-permission
```

期望输出：

```text
inputMonitoringPermission=true
```

再运行：

```bash
dist/SwitchOnlyDoubaoVoiceInput.app/Contents/MacOS/SwitchOnlyDoubaoVoiceInput --check-voice-control-permission
```

期望输出：

```text
accessibilityPermission=true
```

## 输入源检查

运行：

```bash
dist/SwitchOnlyDoubaoVoiceInput.app/Contents/MacOS/SwitchOnlyDoubaoVoiceInput --check-input-sources
```

期望至少包含：

```text
primaryInputSourceId=im.rime.inputmethod.Squirrel.Hans exists=true selectable=true
doubaoInputSourceId=com.bytedance.inputmethod.doubaoime.pinyin exists=true selectable=true
```

## Type4Me 检查

Type4Me 未运行时：

```bash
dist/SwitchOnlyDoubaoVoiceInput.app/Contents/MacOS/SwitchOnlyDoubaoVoiceInput --check-external-voice-tool
```

期望：

```text
externalVoiceToolRunning=false
```

Type4Me 运行时再次检查，期望：

```text
externalVoiceToolRunning=true
```

## 右 Ctrl 监听检查

运行：

```bash
dist/SwitchOnlyDoubaoVoiceInput.app/Contents/MacOS/SwitchOnlyDoubaoVoiceInput --listen-hotkeys-once
```

按左 Ctrl：

- 期望不输出 `rightControlPressed`。

再次运行同一命令，按右 Ctrl：

- 期望输出：

```text
hotkeyEvent=rightControlPressed
```

## 完整流程验收

运行：

```bash
dist/SwitchOnlyDoubaoVoiceInput.app/Contents/MacOS/SwitchOnlyDoubaoVoiceInput --run
```

Type4Me 未运行时：

1. 在普通输入框中确认当前输入法是鼠须管。
2. 按右 Ctrl。
3. 期望切到豆包，并尝试触发豆包语音。
4. 再按右 Ctrl。
5. 期望恢复鼠须管。

Type4Me 运行时：

1. 启动 Type4Me。
2. 运行本工具。
3. 按右 Ctrl。
4. 期望本工具不切豆包，不恢复鼠须管，不干扰 Type4Me。

## 失败记录

如果失败，记录以下内容：

- 当前 Type4Me 是否运行。
- `--check-hotkey-permission` 输出。
- `--check-voice-control-permission` 输出。
- `--check-input-sources` 输出。
- `--run` 中出现的最后 20 行日志。

## 恢复鼠须管

如果验收过程中当前输入法停在豆包，可以运行：

```bash
dist/SwitchOnlyDoubaoVoiceInput.app/Contents/MacOS/SwitchOnlyDoubaoVoiceInput --set-input-source im.rime.inputmethod.Squirrel.Hans
```
