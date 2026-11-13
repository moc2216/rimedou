import Foundation

public enum VoiceState: Equatable, Sendable {
    case idle
    case voiceActive
    case waitingForProviderCompletion
    case restoringInputMethod
    case blocked
}

public enum VoiceEvent: Equatable, Sendable {
    /// Starts a session; the legacy immediate-stop transition remains available.
    case triggerTap
    case externalVoiceEnd

    /// Explicit RimeDou stop: send the selected provider's transport hotkey once,
    /// then wait for an observable commit-completion signal before restoring.
    case explicitStopRequested
    /// The user pressed the provider's own transport hotkey, so it already received
    /// the toggle and RimeDou must not synthesize a second toggle.
    case explicitStopObserved
    case providerCompletion

    case forcedStop
    case restoreCompleted
    case recoveryRequested
    case failed
    case recovered
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
        if event == .failed, state != .idle {
            state = .blocked
            return []
        }
        switch (state, event) {
        case (.idle, .triggerTap):
            state = .voiceActive
            return [.startVoiceSession]

        case (.voiceActive, .triggerTap):
            state = .restoringInputMethod
            return [.restoreInputMethod]

        case (.voiceActive, .externalVoiceEnd):
            state = .restoringInputMethod
            return [.restoreInputMethod]

        case (.voiceActive, .explicitStopRequested):
            state = .waitingForProviderCompletion
            return [.stopVoice]

        case (.voiceActive, .explicitStopObserved):
            state = .waitingForProviderCompletion
            return []

        case (.voiceActive, .forcedStop):
            state = .restoringInputMethod
            return [.stopVoice, .restoreInputMethod]

        case (.waitingForProviderCompletion, .providerCompletion):
            state = .restoringInputMethod
            return [.restoreInputMethod]

        case (.restoringInputMethod, .restoreCompleted):
            state = .idle
            return []

        case (.blocked, .recovered):
            state = .idle
            return []

        case (.blocked, .recoveryRequested), (.restoringInputMethod, .recoveryRequested):
            state = .restoringInputMethod
            return [.restoreInputMethod]

        case (.idle, _),
             (.voiceActive, _),
             (.waitingForProviderCompletion, _),
             (.restoringInputMethod, _),
             (.blocked, _):
            return []
        }
    }
}
