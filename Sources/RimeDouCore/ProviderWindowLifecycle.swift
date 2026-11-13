import Foundation

public enum ProviderWindowCompletionEvent: Equatable, Sendable {
    case none
    case completed
    case timedOut
}

/// Pure, deterministic lifecycle tracker used by the Qianwen window monitor.
/// It tracks only window identifiers, never titles or text content.
public struct ProviderWindowLifecycleTracker: Equatable, Sendable {
    public private(set) var baseline: Set<Int>
    public private(set) var tracked: Set<Int> = []
    public private(set) var didObserveProviderWindow = false
    public private(set) var waitingStartedAt: TimeInterval?
    public private(set) var goneStartedAt: TimeInterval?

    public init(baseline: Set<Int> = []) {
        self.baseline = baseline
    }

    public mutating func beginWaiting(at now: TimeInterval) {
        waitingStartedAt = now
        goneStartedAt = nil
    }

    public mutating func observe(
        current: Set<Int>?,
        now: TimeInterval,
        completionTimeout: TimeInterval,
        goneStabilityDelay: TimeInterval
    ) -> ProviderWindowCompletionEvent {
        if let waitingStartedAt, now - waitingStartedAt >= completionTimeout {
            return .timedOut
        }
        guard let current else {
            goneStartedAt = nil
            return .none
        }
        let candidates = current.subtracting(baseline)
        if !candidates.isEmpty {
            tracked.formUnion(candidates)
            didObserveProviderWindow = true
        }

        guard waitingStartedAt != nil else { return .none }

        if didObserveProviderWindow {
            let stillVisible = !current.intersection(tracked).isEmpty
            if stillVisible {
                goneStartedAt = nil
            } else if let goneStartedAt {
                if now - goneStartedAt >= goneStabilityDelay {
                    return .completed
                }
            } else {
                goneStartedAt = now
            }
        }

        return .none
    }
}
