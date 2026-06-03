public enum SwitchState: Equatable {
    case idle
    case suspended
    case doubaoVoiceActive
    case error
}

public enum SwitchEvent: Sendable {
    case rightControlPressed
    case leftControlPressed
    case externalVoiceToolStarted
    case externalVoiceToolStopped
}

public enum SwitchAction: Equatable {
    case switchToDoubao
    case startDoubaoVoice
    case stopDoubaoVoice
    case switchToPrimary
}

public protocol SwitchCoordinatingServices: AnyObject {
    func switchToDoubao() -> Bool
    func switchToPrimary() -> Bool
    func startDoubaoVoice() -> Bool
    func stopDoubaoVoiceIfPossible() -> Bool
}

public struct SwitchCoordinator {
    public private(set) var state: SwitchState

    private let services: SwitchCoordinatingServices

    public init(services: SwitchCoordinatingServices, initialState: SwitchState = .idle) {
        self.services = services
        self.state = initialState
    }

    public mutating func handle(_ event: SwitchEvent) {
        guard state != .error else {
            return
        }

        switch event {
        case .leftControlPressed:
            return
        case .externalVoiceToolStarted:
            state = .suspended
        case .externalVoiceToolStopped:
            if state == .suspended {
                state = .idle
            }
        case .rightControlPressed:
            handleRightControlPressed()
        }
    }

    private mutating func handleRightControlPressed() {
        switch state {
        case .idle:
            enterDoubaoVoice()
        case .doubaoVoiceActive:
            exitDoubaoVoice()
        case .suspended, .error:
            return
        }
    }

    private mutating func enterDoubaoVoice() {
        guard services.switchToDoubao() else {
            state = .error
            return
        }

        guard services.startDoubaoVoice() else {
            state = .error
            return
        }

        state = .doubaoVoiceActive
    }

    private mutating func exitDoubaoVoice() {
        guard services.switchToPrimary() else {
            state = .error
            return
        }

        state = .idle
    }
}
