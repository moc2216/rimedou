import Foundation

public enum VoiceState: Equatable, Sendable {
    case idle
    case voiceActive
    case restoringInputMethod
}

public enum VoiceEvent: Equatable, Sendable {
    case triggerTap
    case externalVoiceEnd
    case forcedStop
    case restoreCompleted
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
        case (.idle, .forcedStop):
            return []
        case (.voiceActive, .triggerTap):
            state = .restoringInputMethod
            return [.restoreInputMethod]
        case (.voiceActive, .externalVoiceEnd):
            state = .restoringInputMethod
            return [.restoreInputMethod]
        case (.voiceActive, .forcedStop):
            state = .restoringInputMethod
            return [.stopVoice, .restoreInputMethod]
        case (.restoringInputMethod, .restoreCompleted):
            state = .idle
            return []
        case (_, .restoreCompleted), (.restoringInputMethod, .triggerTap),
             (.restoringInputMethod, .externalVoiceEnd), (.restoringInputMethod, .forcedStop):
            return []
        }
    }
}
