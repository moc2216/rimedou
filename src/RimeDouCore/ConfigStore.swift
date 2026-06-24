import Foundation

public struct AppConfig: Equatable {
    public let externalVoiceAppPath: String
    public let externalVoiceBundleId: String
    public let primaryInputSourceId: String
    public let doubaoInputSourceId: String
    public let doubaoVoiceHotkey: DoubaoVoiceHotkey
    public let triggerKey: TriggerKey

    public init(
        externalVoiceAppPath: String,
        externalVoiceBundleId: String,
        primaryInputSourceId: String,
        doubaoInputSourceId: String,
        doubaoVoiceHotkey: DoubaoVoiceHotkey = .rightControl,
        triggerKey: TriggerKey = .rightCommand
    ) {
        self.externalVoiceAppPath = externalVoiceAppPath
        self.externalVoiceBundleId = externalVoiceBundleId
        self.primaryInputSourceId = primaryInputSourceId
        self.doubaoInputSourceId = doubaoInputSourceId
        self.doubaoVoiceHotkey = doubaoVoiceHotkey
        self.triggerKey = triggerKey
    }
}

public enum DoubaoVoiceHotkey: String, Equatable, Decodable {
    case rightControl
}

public enum TriggerKey: String, Equatable, Decodable {
    case rightCommand
    case rightControl

    public var keyCode: Int64 {
        switch self {
        case .rightCommand: return HotkeyKeyCode.rightCommand
        case .rightControl: return HotkeyKeyCode.rightControl
        }
    }
}

public enum ConfigError: Error, CustomStringConvertible, Equatable {
    case fileNotFound(String)
    case missingField(String)
    case unsupportedValue(field: String, value: String)
    case invalidJSON(String)

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "Config file not found: \(path)"
        case .missingField(let field):
            return "Missing config field: \(field)"
        case .unsupportedValue(let field, let value):
            return "Unsupported config value: \(field)=\(value)"
        case .invalidJSON(let message):
            return "Invalid config JSON: \(message)"
        }
    }
}

public struct ConfigStore {
    public init() {}

    public func load(path: String) throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ConfigError.fileNotFound(path)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))

        do {
            let rawConfig = try JSONDecoder().decode(RawAppConfig.self, from: data)
            return try rawConfig.validate()
        } catch let error as ConfigError {
            throw error
        } catch let error as DecodingError {
            throw decodeConfigError(error)
        } catch {
            throw ConfigError.invalidJSON(String(describing: error))
        }
    }

    private func decodeConfigError(_ error: DecodingError) -> ConfigError {
        switch error {
        case .keyNotFound(let key, _):
            return .missingField(key.stringValue)
        case .dataCorrupted(let context),
             .typeMismatch(_, let context),
             .valueNotFound(_, let context):
            return .invalidJSON(context.debugDescription)
        @unknown default:
            return .invalidJSON(String(describing: error))
        }
    }
}

private struct RawAppConfig: Decodable {
    let externalVoiceAppPath: String?
    let externalVoiceBundleId: String?
    let primaryInputSourceId: String?
    let doubaoInputSourceId: String?
    let doubaoVoiceHotkey: String?
    let triggerKey: String?

    func validate() throws -> AppConfig {
        guard let externalVoiceAppPath else {
            throw ConfigError.missingField("externalVoiceAppPath")
        }
        guard let externalVoiceBundleId else {
            throw ConfigError.missingField("externalVoiceBundleId")
        }
        guard let primaryInputSourceId else {
            throw ConfigError.missingField("primaryInputSourceId")
        }
        guard let doubaoInputSourceId else {
            throw ConfigError.missingField("doubaoInputSourceId")
        }
        guard let doubaoVoiceHotkey else {
            throw ConfigError.missingField("doubaoVoiceHotkey")
        }
        guard let parsedDoubaoVoiceHotkey = DoubaoVoiceHotkey(rawValue: doubaoVoiceHotkey) else {
            throw ConfigError.unsupportedValue(field: "doubaoVoiceHotkey", value: doubaoVoiceHotkey)
        }

        let parsedTriggerKey: TriggerKey
        if let triggerKey {
            guard let parsed = TriggerKey(rawValue: triggerKey) else {
                throw ConfigError.unsupportedValue(field: "triggerKey", value: triggerKey)
            }
            parsedTriggerKey = parsed
        } else {
            parsedTriggerKey = .rightCommand
        }

        return AppConfig(
            externalVoiceAppPath: externalVoiceAppPath,
            externalVoiceBundleId: externalVoiceBundleId,
            primaryInputSourceId: primaryInputSourceId,
            doubaoInputSourceId: doubaoInputSourceId,
            doubaoVoiceHotkey: parsedDoubaoVoiceHotkey,
            triggerKey: parsedTriggerKey
        )
    }
}
