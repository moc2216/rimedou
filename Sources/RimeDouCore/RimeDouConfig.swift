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

    public var stringRepresentation: String {
        switch self {
        case .leftShift: return "LeftShift"
        case .rightShift: return "RightShift"
        case .shift: return "Shift"
        case .leftControl: return "LeftControl"
        case .rightControl: return "RightControl"
        case .control: return "Control"
        case .leftOption: return "LeftOption"
        case .rightOption: return "RightOption"
        case .option: return "Option"
        case .leftCommand: return "LeftCommand"
        case .rightCommand: return "RightCommand"
        case .command: return "Command"
        case .tab: return "Tab"
        case .space: return "Space"
        case .character(let c): return c
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringRepresentation)
    }
}

public struct Hotkey: Equatable, Sendable, Encodable {
    public var keys: [Key]

    public init(keys: [Key]) {
        self.keys = keys
    }

    public var stringRepresentation: String {
        keys.map(\.stringRepresentation).joined(separator: "+")
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

    private enum CodingKeys: String, CodingKey {
        case restoreDelay
        case switchPollInterval
        case switchWaitTimeout
        case focusBounceBackDelay
        case focusBounceSettleDelay
        case tapMaxDuration
        case tapDuration
        case triggerHotkey
        case voiceHotkey
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(restoreDelay, forKey: .restoreDelay)
        try container.encode(switchPollInterval, forKey: .switchPollInterval)
        try container.encode(switchWaitTimeout, forKey: .switchWaitTimeout)
        try container.encode(focusBounceBackDelay, forKey: .focusBounceBackDelay)
        try container.encode(focusBounceSettleDelay, forKey: .focusBounceSettleDelay)
        try container.encode(tapMaxDuration, forKey: .tapMaxDuration)
        try container.encode(tapDuration, forKey: .tapDuration)
        try container.encode(triggerHotkey.stringRepresentation, forKey: .triggerHotkey)
        try container.encode(voiceHotkey.stringRepresentation, forKey: .voiceHotkey)
    }

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
