# 实施计划

## 结论

第一版按 TDD 推进，先实现可测试的纯逻辑状态机，再接入 macOS 系统 API。豆包语音启动和停止是最大不确定点，应放在可替换模块里，最后做手动验收。

## 阶段 0：项目骨架

目标：

- 创建 Swift Package 项目结构。
- 创建本地默认配置。
- 更新 `agent.md` 的验证命令。

拟创建：

- `Package.swift`
- `src/RimeDou/`
- `tests/RimeDouTests/`
- `config/default.json`

验证：

- `env CLANG_MODULE_CACHE_PATH=.build/module-cache XDG_CACHE_HOME=.build/xdg-cache swift run --disable-sandbox --cache-path .build/swiftpm-cache rimedou-tests`

完成标准：

- Swift Package 可以正常测试。
- 配置文件包含 Type4Me、鼠须管、豆包的默认标识。
- `agent.md` 中写明实现阶段验证命令。

## 阶段 1：核心状态机 TDD

目标：

- 不碰真实 macOS API。
- 先用测试锁定右 Ctrl、Type4Me 让渡、豆包语音进入和退出规则。

先写测试：

- `idle` 下收到右 Ctrl，应请求切换豆包并启动语音。
- `idle` 下收到左 Ctrl，不应做任何动作。
- `doubaoVoiceActive` 下收到右 Ctrl，应请求停止语音并恢复鼠须管。
- Type4Me 运行时收到右 Ctrl，不应请求豆包相关动作。
- Type4Me 从运行变为退出后，右 Ctrl 应重新触发豆包流程。
- 切换豆包失败，应进入错误状态或返回明确错误。
- 恢复鼠须管失败，应进入错误状态或返回明确错误。

实现：

- `SwitchCoordinator`
- 状态枚举。
- 事件枚举。
- 可注入的服务协议：
  - `InputSourceControlling`
  - `VoiceControlling`
  - `ExternalVoiceToolMonitoring`
  - `Logging`

验证：

- `env CLANG_MODULE_CACHE_PATH=.build/module-cache XDG_CACHE_HOME=.build/xdg-cache swift run --disable-sandbox --cache-path .build/swiftpm-cache rimedou-tests`

完成标准：

- 状态机测试全部通过。
- 状态机不依赖 AppKit、Carbon、CoreGraphics 等真实系统 API。

## 阶段 2：配置加载 TDD

目标：

- 能读取项目本地配置。
- 配置项清晰表达可替换外部语音工具。

先写测试：

- 能读取 `externalVoiceAppPath`。
- 能读取 `externalVoiceBundleId`。
- 能读取 `primaryInputSourceId`。
- 能读取 `doubaoInputSourceId`。
- 配置缺字段时返回明确错误。

实现：

- `AppConfig`
- `ConfigStore`

验证：

- `env CLANG_MODULE_CACHE_PATH=.build/module-cache XDG_CACHE_HOME=.build/xdg-cache swift run --disable-sandbox --cache-path .build/swiftpm-cache rimedou-tests`

完成标准：

- 配置测试全部通过。
- 默认配置为：
  - `/Applications/Type4Me.app`
  - `com.type4me.app`
  - `im.rime.inputmethod.Squirrel.Hans`
  - `com.bytedance.inputmethod.doubaoime.pinyin`

## 阶段 3：输入源服务

目标：

- 使用 macOS Text Input Source Services 查找和切换输入源。
- 把系统 API 包在 `InputSourceService`，避免污染状态机。

先写测试：

- 对纯解析或错误包装做单元测试。
- 系统 API 本身以手动验证为主。

实现：

- `InputSourceService`
- 查找输入源。
- 切换输入源。
- 查询当前输入源。

验证：

- `env CLANG_MODULE_CACHE_PATH=.build/module-cache XDG_CACHE_HOME=.build/xdg-cache swift run --disable-sandbox --cache-path .build/swiftpm-cache rimedou-tests`
- 手动运行开发命令确认能找到：
  - `im.rime.inputmethod.Squirrel.Hans`
  - `com.bytedance.inputmethod.doubaoime.pinyin`

完成标准：

- 找不到输入源时错误清楚。
- 能在本机切换到鼠须管。
- 能在本机切换到豆包。

## 阶段 4：Type4Me 运行检测

目标：

- 通过 bundle id 检测 Type4Me 是否运行。
- 路径作为配置说明和存在性检查，不作为唯一判断。

先写测试：

- bundle id 匹配时返回运行中。
- bundle id 不匹配时返回未运行。
- 路径不存在时能输出配置警告，但不直接导致状态机不可用。

实现：

- `VoiceToolMonitor`
- 基于 `NSWorkspace.shared.runningApplications` 的运行检测。

验证：

- `env CLANG_MODULE_CACHE_PATH=.build/module-cache XDG_CACHE_HOME=.build/xdg-cache swift run --disable-sandbox --cache-path .build/swiftpm-cache rimedou-tests`
- 手动验证：
  - Type4Me 打开时检测为运行中。
  - Type4Me 退出时检测为未运行。

完成标准：

- Type4Me 运行时，本工具进入 `suspended`。
- Type4Me 退出后，本工具可回到 `idle`。

## 阶段 5：右 Ctrl 监听

目标：

- 全局监听右 Ctrl。
- 区分右 Ctrl 和左 Ctrl。
- 权限不足时给出明确提示。

先写测试：

- 对事件解析逻辑做单元测试，例如按键侧别映射到 `rightControlPressed` / `leftControlPressed`。

实现：

- `HotkeyMonitor`
- 使用 `CGEventTap` 或设计阶段验证出的等价 API。
- 只把解析后的事件交给 `SwitchCoordinator`。

验证：

- `env CLANG_MODULE_CACHE_PATH=.build/module-cache XDG_CACHE_HOME=.build/xdg-cache swift run --disable-sandbox --cache-path .build/swiftpm-cache rimedou-tests`
- 手动运行开发版工具：
  - 左 Ctrl 不触发。
  - 右 Ctrl 触发。
  - Type4Me 运行时右 Ctrl 不触发豆包流程。

完成标准：

- 能稳定识别右 Ctrl。
- 权限不足时日志明确说明。
- 不影响普通键盘输入。

## 阶段 6：豆包语音控制

目标：

- 把豆包语音启动和停止封装在 `DoubaoVoiceController`。
- 先保证切换输入源，再验证是否需要模拟快捷键。

先写测试：

- 状态机调用 `startVoiceInput()`。
- 状态机调用 `stopVoiceInputIfPossible()`。
- 启动或停止失败时错误能向上返回。

实现：

- `DoubaoVoiceController`
- 初始版本可以先只记录调用和保留系统触发接口。
- 如果验证需要模拟快捷键，再接入辅助功能相关实现。

验证：

- `env CLANG_MODULE_CACHE_PATH=.build/module-cache XDG_CACHE_HOME=.build/xdg-cache swift run --disable-sandbox --cache-path .build/swiftpm-cache rimedou-tests`
- 手动验证：
  - 右 Ctrl 后豆包语音是否启动。
  - 第二次右 Ctrl 后鼠须管是否恢复。
  - 如果豆包语音未被停止，确认恢复鼠须管是否足够满足第一版。

完成标准：

- 第一版至少做到右 Ctrl 后进入豆包可语音状态。
- 第二次右 Ctrl 后必须恢复鼠须管。

## 阶段 7：应用入口和开发运行

目标：

- 串起配置、监听、状态机、系统服务。
- 提供开发阶段可运行命令。

实现：

- `AppRunner`
- 标准输出日志。
- 启动检查：
  - 配置加载。
  - 输入源存在。
  - Type4Me 状态。
  - 权限状态。

验证：

- `env CLANG_MODULE_CACHE_PATH=.build/module-cache XDG_CACHE_HOME=.build/xdg-cache swift run --disable-sandbox --cache-path .build/swiftpm-cache rimedou-tests`
- `swift run`

完成标准：

- 工具能保持运行。
- 日志能说明当前状态。
- 手动退出时尽力恢复鼠须管。

## 阶段 8：两阶段审查

第一阶段自查：

- 需求、spec、设计、实现是否一致。
- 是否违反 `agent.md` 的红线。
- 是否有未说明的系统权限或配置修改。
- 是否有硬编码但应配置的内容。

第二阶段行为审查：

- Type4Me 运行时是否完全让渡右 Ctrl。
- Type4Me 退出后是否恢复接管。
- 左 Ctrl 是否无影响。
- 右 Ctrl 第一次是否进入豆包语音。
- 右 Ctrl 第二次是否恢复鼠须管。
- 权限不足时是否明确失败。

验证：

- `env CLANG_MODULE_CACHE_PATH=.build/module-cache XDG_CACHE_HOME=.build/xdg-cache swift run --disable-sandbox --cache-path .build/swiftpm-cache rimedou-tests`
- 手动验收记录写入 `docs/review.md`

完成标准：

- 自动测试通过。
- 手动验收结果有记录。
- 剩余风险明确写出。

## 实施顺序

1. 阶段 0：创建 Swift Package 骨架。
2. 阶段 1：状态机 TDD。
3. 阶段 2：配置加载 TDD。
4. 阶段 3：输入源服务。
5. 阶段 4：Type4Me 运行检测。
6. 阶段 5：右 Ctrl 监听。
7. 阶段 6：豆包语音控制。
8. 阶段 7：应用入口。
9. 阶段 8：两阶段审查。

## 需要确认后才能开始的事项

进入实现前需要确认：

- 按本计划创建 Swift Package 项目骨架。
- 创建 `config/default.json`。
- 更新 `agent.md` 的验证命令为项目自带测试 runner。

这些操作只会在项目目录内创建或修改文件，不会安装全局依赖，不会修改系统配置。
