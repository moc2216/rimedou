import Foundation

public enum BridgeState: Equatable, Sendable {
    case idle
    case waitingForTriggerHold
    case preparingVoice
    case holdingOption
}

public enum BridgeEvent: Equatable, Sendable {
    case rightCommandDown
    case triggerHoldThresholdPassed
    case optionHoldStarted
    case rightCommandUp
    case reset
}

public enum BridgeAction: Equatable, Sendable {
    case startVoiceSession
    case cancelPendingOptionHold
    case releaseOptionHold
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
        case (.idle, .rightCommandDown):
            state = .waitingForTriggerHold
            return []
        case (.waitingForTriggerHold, .triggerHoldThresholdPassed):
            state = .preparingVoice
            return [.startVoiceSession]
        case (.waitingForTriggerHold, .rightCommandUp):
            state = .idle
            return []
        case (.preparingVoice, .optionHoldStarted):
            state = .holdingOption
            return []
        case (.preparingVoice, .rightCommandUp):
            state = .idle
            return [.cancelPendingOptionHold, .restorePreviousInputMethod]
        case (.holdingOption, .rightCommandUp):
            state = .idle
            return [.releaseOptionHold, .restorePreviousInputMethod]
        case (_, .reset):
            state = .idle
            return []
        default:
            return []
        }
    }
}
