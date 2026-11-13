import Foundation

public enum InputSourceRestoreResult: Equatable, Sendable {
    case safe(String)
    case failed
    case cancelled
}

/// Verifies the actual source, including after focus settling. Dependencies allow
/// failure/cancellation tests without changing the machine's real input method.
@MainActor
final class InputSourceRestorer {
    let current: () -> String?
    let select: (String) -> Bool
    let settleFocus: () async -> Void
    let sleep: (TimeInterval) async -> Void

    init(current: @escaping () -> String?, select: @escaping (String) -> Bool,
         settleFocus: @escaping () async -> Void,
         sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.current = current
        self.select = select
        self.settleFocus = settleFocus
        self.sleep = sleep
    }

    func restore(target: String, config: RimeDouConfig, initialDelay: TimeInterval) async -> InputSourceRestoreResult {
        guard !VoiceProviderRegistry.isVoiceInputSourceIdentifier(target) else { return .failed }
        await sleep(initialDelay)
        let attempts = max(1, Int(ceil(config.switchWaitTimeout / config.switchPollInterval)))
        var didSelect = false
        for attempt in 0...attempts {
            guard !Task.isCancelled else { return .cancelled }
            if let identifier = current(), !VoiceProviderRegistry.isVoiceInputSourceIdentifier(identifier) {
                if didSelect, identifier == target {
                    await settleFocus()
                    guard !Task.isCancelled else { return .cancelled }
                    guard let settled = current(), !VoiceProviderRegistry.isVoiceInputSourceIdentifier(settled) else { return .failed }
                    return .safe(settled)
                }
                return .safe(identifier)
            }
            guard attempt < attempts else { return .failed }
            didSelect = select(target) || didSelect
            await sleep(config.switchPollInterval)
        }
        return .failed
    }
}
