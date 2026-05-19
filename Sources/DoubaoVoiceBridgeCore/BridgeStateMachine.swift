import Foundation

public enum BridgeState: Equatable, Sendable {
    case idle
    case preparingVoice
    case holdingOption
}

public enum BridgeEvent: Equatable, Sendable {
    case rightCommandDown
    case optionHoldStarted
    case rightCommandUp
    case reset
}

public enum BridgeAction: Equatable, Sendable {
    case startVoiceSession
    case cancelPendingOptionHold
    case releaseOptionHold
    case restoreUserInputMethod
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
            state = .preparingVoice
            return [.startVoiceSession]
        case (.preparingVoice, .optionHoldStarted):
            state = .holdingOption
            return []
        case (.preparingVoice, .rightCommandUp):
            state = .idle
            return [.cancelPendingOptionHold, .restoreUserInputMethod]
        case (.holdingOption, .rightCommandUp):
            state = .idle
            return [.releaseOptionHold, .restoreUserInputMethod]
        case (_, .reset):
            state = .idle
            return []
        default:
            return []
        }
    }
}
