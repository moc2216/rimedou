public struct RightControlRapidRepeatGuard {
    private let minimumIntervalSeconds: Double
    private var lastAcceptedPressTime: Double?

    public init(minimumIntervalSeconds: Double = 1.0) {
        self.minimumIntervalSeconds = minimumIntervalSeconds
    }

    public mutating func shouldSuppressPress(at time: Double) -> Bool {
        guard let lastAcceptedPressTime else {
            self.lastAcceptedPressTime = time
            return false
        }

        if time - lastAcceptedPressTime < minimumIntervalSeconds {
            return true
        }

        self.lastAcceptedPressTime = time
        return false
    }
}
