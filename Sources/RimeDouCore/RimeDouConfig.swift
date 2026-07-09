import Foundation

public enum Key: Equatable, Hashable, Sendable, Encodable {
    case leftShift, rightShift, shift
    case leftControl, rightControl, control
    case leftOption, rightOption, option
    case leftCommand, rightCommand, command
    case tab, space
    case character(String)

    public var isModifier: Bool {
        switch self {
        case .leftShift, .rightShift, .shift,
             .leftControl, .rightControl, .control,
             .leftOption, .rightOption, .option,
             .leftCommand, .rightCommand, .command:
            return true
        case .tab, .space, .character:
            return false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .leftShift: try container.encode("leftShift")
        case .rightShift: try container.encode("rightShift")
        case .shift: try container.encode("shift")
        case .leftControl: try container.encode("leftControl")
        case .rightControl: try container.encode("rightControl")
        case .control: try container.encode("control")
        case .leftOption: try container.encode("leftOption")
        case .rightOption: try container.encode("rightOption")
        case .option: try container.encode("option")
        case .leftCommand: try container.encode("leftCommand")
        case .rightCommand: try container.encode("rightCommand")
        case .command: try container.encode("command")
        case .tab: try container.encode("tab")
        case .space: try container.encode("space")
        case .character(let c): try container.encode("character(\(c))")
        }
    }
}

public struct Hotkey: Equatable, Sendable, Encodable {
    public var keys: [Key]

    public init(keys: [Key]) {
        self.keys = keys
    }

    public static func parse(_ value: String) -> Hotkey? {
        let keys = value
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap(parseKey)
        guard !keys.isEmpty else { return nil }
        return Hotkey(keys: keys)
    }

    private static func parseKey(_ value: String) -> Key? {
        let normalized = value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .lowercased()

        switch normalized {
        case "leftshift", "lshift": return .leftShift
        case "rightshift", "rshift": return .rightShift
        case "shift": return .shift
        case "leftcontrol", "lcontrol", "leftctrl", "lctrl": return .leftControl
        case "rightcontrol", "rcontrol", "rightctrl", "rctrl": return .rightControl
        case "control", "ctrl": return .control
        case "leftoption", "loption", "leftalt", "lalt": return .leftOption
        case "rightoption", "roption", "rightalt", "ralt": return .rightOption
        case "option", "alt": return .option
        case "leftcommand", "lcommand", "leftcmd", "lcmd": return .leftCommand
        case "rightcommand", "rcommand", "rightcmd", "rcmd": return .rightCommand
        case "command", "cmd": return .command
        case "tab": return .tab
        case "space": return .space
        default: return parseCharacterKey(value)
        }
    }

    private static func parseCharacterKey(_ value: String) -> Key? {
        let lowercased = value.lowercased()
        guard lowercased.count == 1, let scalar = lowercased.unicodeScalars.first else {
            return nil
        }
        let accepted = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789`-=[]\\;',./")
        guard accepted.contains(scalar) else { return nil }
        return .character(lowercased)
    }
}

public struct RimeDouConfig: Equatable, Sendable, Encodable {
    public var restoreDelay: TimeInterval
    public var switchPollInterval: TimeInterval
    public var switchWaitTimeout: TimeInterval
    public var focusBounceBackDelay: TimeInterval
    public var focusBounceSettleDelay: TimeInterval
    public var tapMaxDuration: TimeInterval
    public var tapDuration: TimeInterval
    public var triggerHotkey: Hotkey
    public var voiceHotkey: Hotkey

    public static let `default` = RimeDouConfig(
        restoreDelay: 0.50,
        switchPollInterval: 0.05,
        switchWaitTimeout: 2.00,
        focusBounceBackDelay: 0.10,
        focusBounceSettleDelay: 0.10,
        tapMaxDuration: 0.35,
        tapDuration: 0.15,
        triggerHotkey: Hotkey(keys: [.rightCommand]),
        voiceHotkey: Hotkey(keys: [.rightControl])
    )

    public static func load(from data: Data) throws -> RimeDouConfig {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        let partial = try decoder.decode(PartialRimeDouConfig.self, from: data)
        var config = RimeDouConfig.default
        if let value = partial.restoreDelay { config.restoreDelay = value }
        if let value = partial.switchPollInterval { config.switchPollInterval = value }
        if let value = partial.switchWaitTimeout { config.switchWaitTimeout = value }
        if let value = partial.focusBounceBackDelay { config.focusBounceBackDelay = value }
        if let value = partial.focusBounceSettleDelay { config.focusBounceSettleDelay = value }
        if let value = partial.tapMaxDuration { config.tapMaxDuration = value }
        if let value = partial.tapDuration { config.tapDuration = value }
        if let value = partial.triggerHotkey {
            config.triggerHotkey = Hotkey.parse(value) ?? config.triggerHotkey
        }
        if let value = partial.voiceHotkey {
            config.voiceHotkey = Hotkey.parse(value) ?? config.voiceHotkey
        }
        return config
    }

    public static var defaultUserConfigURL: URL {
        let applicationSupportURL = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupportURL
            .appendingPathComponent("rimedou", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    public static func loadFromDefaultLocation() -> RimeDouConfig {
        let url = defaultUserConfigURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(RimeDouConfig.default) {
                try? data.write(to: url, options: .atomic)
            }
        }
        guard let data = try? Data(contentsOf: url) else {
            return .default
        }
        return (try? load(from: data)) ?? .default
    }
}

private struct PartialRimeDouConfig: Decodable {
    var restoreDelay: TimeInterval?
    var switchPollInterval: TimeInterval?
    var switchWaitTimeout: TimeInterval?
    var focusBounceBackDelay: TimeInterval?
    var focusBounceSettleDelay: TimeInterval?
    var tapMaxDuration: TimeInterval?
    var tapDuration: TimeInterval?
    var triggerHotkey: String?
    var voiceHotkey: String?
}
