import Foundation

public enum VoiceProviderID: String, CaseIterable, Codable, Sendable {
    case doubao
    case qianwen

    public var displayName: String {
        switch self {
        case .doubao: return "豆包"
        case .qianwen: return "千问"
        }
    }

    public var statusGlyph: String {
        switch self {
        case .doubao: return "豆"
        case .qianwen: return "千"
        }
    }
}

public enum VoiceExternalStopPolicy: Equatable, Sendable {
    /// The provider stops its own voice session when it sees ordinary user keyboard input.
    case anyUserKeyboardInput
    /// Ordinary keyboard input does not end voice; the provider must receive its toggle hotkey.
    case explicitToggleOnly
}

public enum VoiceRestorePolicy: Equatable, Sendable {
    /// It is safe to restore the previous text input source immediately after voice is stopped.
    case immediate
    /// Keep the provider active until its voice/processing overlay has gone away.
    case waitForProviderWindow
}

public struct VoiceProviderDefinition: Equatable, Sendable {
    public let id: VoiceProviderID
    public let inputSourceIdentifier: String
    public let transportHotkey: Hotkey
    public let externalStopPolicy: VoiceExternalStopPolicy
    public let restorePolicy: VoiceRestorePolicy

    public init(
        id: VoiceProviderID,
        inputSourceIdentifier: String,
        transportHotkey: Hotkey,
        externalStopPolicy: VoiceExternalStopPolicy,
        restorePolicy: VoiceRestorePolicy
    ) {
        self.id = id
        self.inputSourceIdentifier = inputSourceIdentifier
        self.transportHotkey = transportHotkey
        self.externalStopPolicy = externalStopPolicy
        self.restorePolicy = restorePolicy
    }
}

public enum VoiceProviderRegistry {
    public static let doubaoInputSourceIdentifier = "com.bytedance.inputmethod.doubaoime.pinyin"
    // Verified on the development Mac (2026-09-10). Older handoff/probe used .hans.
    public static let qianwenInputSourceIdentifier = "com.qianwen.inputmethod.desktopime.pinyin"
    public static let qianwenLegacyInputSourceIdentifier = "com.qianwen.inputmethod.desktopime.hans"
    public static let qianwenServiceBundleIdentifier = "com.qianwen.inputmethod.desktopime.service"

    public static func definition(
        for provider: VoiceProviderID,
        config: RimeDouConfig
    ) -> VoiceProviderDefinition? {
        switch provider {
        case .doubao:
            return VoiceProviderDefinition(
                id: .doubao,
                inputSourceIdentifier: doubaoInputSourceIdentifier,
                transportHotkey: config.voiceHotkey,
                externalStopPolicy: .anyUserKeyboardInput,
                restorePolicy: .immediate
            )
        case .qianwen:
            guard let hotkey = config.qianwenVoiceHotkey else { return nil }
            return VoiceProviderDefinition(
                id: .qianwen,
                inputSourceIdentifier: qianwenInputSourceIdentifier,
                transportHotkey: hotkey,
                externalStopPolicy: .explicitToggleOnly,
                restorePolicy: .waitForProviderWindow
            )
        }
    }

    public static func inputSourceIdentifier(for provider: VoiceProviderID) -> String {
        switch provider {
        case .doubao: return doubaoInputSourceIdentifier
        case .qianwen: return qianwenInputSourceIdentifier
        }
    }

    public static func inputSourceIdentifiers(for provider: VoiceProviderID) -> [String] {
        switch provider {
        case .doubao: return [doubaoInputSourceIdentifier]
        case .qianwen: return [qianwenInputSourceIdentifier, qianwenLegacyInputSourceIdentifier]
        }
    }

    public static func installedProviders(hasInputSource: (String) -> Bool) -> Set<VoiceProviderID> {
        Set(VoiceProviderID.allCases.filter { provider in
            inputSourceIdentifiers(for: provider).contains(where: hasInputSource)
        })
    }

    public static func provider(forInputSourceIdentifier identifier: String) -> VoiceProviderID? {
        switch identifier {
        case doubaoInputSourceIdentifier: return .doubao
        case qianwenInputSourceIdentifier, qianwenLegacyInputSourceIdentifier: return .qianwen
        default: return nil
        }
    }

    public static func isVoiceInputSourceIdentifier(_ identifier: String?) -> Bool {
        guard let identifier else { return false }
        return provider(forInputSourceIdentifier: identifier) != nil
    }
}

public enum VoiceProviderSelectionResolver {
    /// Resolves only the initial selection. An explicit saved choice is preserved even
    /// if it is currently unusable; this prevents silent vendor failover.
    public static func resolve(
        saved: VoiceProviderID?,
        usableProviders: Set<VoiceProviderID>
    ) -> VoiceProviderID? {
        if let saved {
            return saved
        }
        if usableProviders.contains(.doubao) {
            return .doubao
        }
        if usableProviders.contains(.qianwen) {
            return .qianwen
        }
        return nil
    }
}

/// Immutable values belonging to one session, independent of menu/config changes.
public struct VoiceSessionSnapshot: Equatable, Sendable {
    public let id = UUID()
    public let provider: VoiceProviderDefinition
    public let config: RimeDouConfig
    public let restoreInputSourceIdentifier: String

    public init(provider: VoiceProviderDefinition, config: RimeDouConfig, restoreInputSourceIdentifier: String) {
        self.provider = provider
        self.config = config
        self.restoreInputSourceIdentifier = restoreInputSourceIdentifier
    }
}
