import Foundation

public enum VoiceState: Equatable, Sendable {
    case idle
    case voiceActive
}

public enum VoiceEvent: Equatable, Sendable {
    case triggerTap
    case externalVoiceEnd
    case reset
}

public enum VoiceAction: Equatable, Sendable {
    case startVoiceSession
    case stopVoice
    case restoreInputMethod
}

public struct VoiceStateMachine: Sendable {
    public private(set) var state: VoiceState

    public init(state: VoiceState = .idle) {
        self.state = state
    }

    @discardableResult
    public mutating func handle(_ event: VoiceEvent) -> [VoiceAction] {
        switch (state, event) {
        case (.idle, .triggerTap):
            state = .voiceActive
            return [.startVoiceSession]
        case (.idle, .externalVoiceEnd):
            return []
        case (.voiceActive, .triggerTap):
            state = .idle
            return [.stopVoice, .restoreInputMethod]
        case (.voiceActive, .externalVoiceEnd):
            state = .idle
            return [.restoreInputMethod]
        case (_, .reset):
            state = .idle
            return []
        }
    }
}
