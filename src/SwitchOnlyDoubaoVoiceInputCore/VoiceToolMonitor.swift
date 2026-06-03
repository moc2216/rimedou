import AppKit
import Foundation

public enum VoiceToolConfigurationWarning: Equatable {
    case externalVoiceAppPathMissing(String)
}

public struct VoiceToolMonitor {
    private let config: AppConfig
    private let runningBundleIds: () -> [String]
    private let pathExists: (String) -> Bool

    public init(
        config: AppConfig,
        runningBundleIds: @escaping () -> [String] = {
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        },
        pathExists: @escaping (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        }
    ) {
        self.config = config
        self.runningBundleIds = runningBundleIds
        self.pathExists = pathExists
    }

    public func isExternalVoiceToolRunning() -> Bool {
        runningBundleIds().contains(config.externalVoiceBundleId)
    }

    public func configurationWarnings() -> [VoiceToolConfigurationWarning] {
        if pathExists(config.externalVoiceAppPath) {
            return []
        }

        return [.externalVoiceAppPathMissing(config.externalVoiceAppPath)]
    }
}
