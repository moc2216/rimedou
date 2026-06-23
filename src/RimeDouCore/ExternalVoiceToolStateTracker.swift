public struct ExternalVoiceToolStateTracker {
    private var wasRunning: Bool

    public init(initiallyRunning: Bool = false) {
        self.wasRunning = initiallyRunning
    }

    public mutating func update(isRunning: Bool) -> SwitchEvent? {
        defer {
            wasRunning = isRunning
        }

        if !wasRunning && isRunning {
            return .externalVoiceToolStarted
        }

        if wasRunning && !isRunning {
            return .externalVoiceToolStopped
        }

        return nil
    }
}
