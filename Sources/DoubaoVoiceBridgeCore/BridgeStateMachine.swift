/**
 * [INPUT]: 依赖 Foundation 的 Sendable 基础类型
 * [OUTPUT]: 对外提供 BridgeState、BridgeEvent、BridgeAction、BridgeStateMachine
 * [POS]: DoubaoVoiceBridgeCore 的会话状态核心（全局唤起 toggle 版）：点按切换语音开关
 * [PROTOCOL]: 变更时更新此头部，然后检查 codex.md
 */
import Foundation

public enum BridgeState: Equatable, Sendable {
    case idle
    case voiceActive
}

public enum BridgeEvent: Equatable, Sendable {
    /// 干净的点按：触发键从按下到松开期间没有按其他键、且时长 ≤ tapMaxDuration
    case triggerTap
    /// 语音激活期间，用户按了非触发键（豆包原生"任意键停止"），语音已被豆包结束
    case externalVoiceEnd
    case reset
}

public enum BridgeAction: Equatable, Sendable {
    case startVoiceSession
    case stopVoice
    case restorePreviousInputMethod
}

public struct BridgeStateMachine: Sendable {
    public private(set) var state: BridgeState

    public init(state: BridgeState = .idle) {
        self.state = state
    }

    @discardableResult
    public mutating func handle(_ event: BridgeEvent) -> [BridgeAction] {
        switch (state, event) {
        case (.idle, .triggerTap):
            // 点按开始：豆包全局唤起自己切到自己 + 开语音，DVB 无需切输入法
            state = .voiceActive
            return [.startVoiceSession]
        case (.idle, .externalVoiceEnd):
            // idle 状态下没有语音在跑，忽略
            return []
        case (.voiceActive, .triggerTap):
            // 用右 Cmd 停止：发停止键（兼容）+ 还原
            state = .idle
            return [.stopVoice, .restorePreviousInputMethod]
        case (.voiceActive, .externalVoiceEnd):
            // 用任意键（空格/字母/其他修饰键）停止：豆包已自己结束，DVB 只需还原
            state = .idle
            return [.restorePreviousInputMethod]
        case (_, .reset):
            state = .idle
            return []
        }
    }
}
