import Foundation

public enum Key: Equatable, Hashable, Sendable {
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
}

public struct Hotkey: Equatable, Sendable {
    public var keys: [Key]

    public init(keys: [Key]) {
        self.keys = keys
    }

    /// True when the hotkey consists only of modifier keys: it is armed by
    /// `flagsChanged` events instead of the keyDown of a normal key.
    public var isModifierOnly: Bool {
        keys.allSatisfy(\.isModifier)
    }

    public var stringRepresentation: String {
        keys.map(\.stringRepresentation).joined(separator: "+")
    }

    public static func parse(_ value: String) -> Hotkey? {
        let components = value
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !components.isEmpty else { return nil }

        var keys: [Key] = []
        for component in components {
            guard !component.isEmpty, let key = parseKey(component) else { return nil }
            keys.append(key)
        }
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
    /// Optional second trigger hotkey (e.g. a keyboard combo a mouse tool synthesizes
    /// for a side button). `nil` disables it; it is declarative and device-independent,
    /// so a missing source device just leaves it dormant — never an error.
    public var triggerHotkey2: Hotkey?
    public var voiceHotkey: Hotkey
    public var qianwenVoiceHotkey: Hotkey? = nil
    public var qianwenCompletionTimeout: TimeInterval = 60
    public var qianwenGoneStabilityDelay: TimeInterval = 0.15

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case restoreDelay
        case switchPollInterval
        case switchWaitTimeout
        case focusBounceBackDelay
        case focusBounceSettleDelay
        case tapMaxDuration
        case tapDuration
        case triggerHotkey
        case triggerHotkey2
        case voiceHotkey = "doubao_VoiceHotkey"
        case qianwenVoiceHotkey = "qianwen_VoiceHotkey"
        case qianwenCompletionTimeout
        case qianwenGoneStabilityDelay
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
        try container.encodeIfPresent(triggerHotkey2?.stringRepresentation, forKey: .triggerHotkey2)
        try container.encode(voiceHotkey.stringRepresentation, forKey: .voiceHotkey)
        try container.encodeIfPresent(qianwenVoiceHotkey?.stringRepresentation, forKey: .qianwenVoiceHotkey)
        try container.encode(qianwenCompletionTimeout, forKey: .qianwenCompletionTimeout)
        try container.encode(qianwenGoneStabilityDelay, forKey: .qianwenGoneStabilityDelay)
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

    /// Loads a config, layering parsed values over the defaults.
    /// Invalid values fall back to the default and are reported through `onWarning`
    /// instead of failing silently, so a typo in the JSON shows up in the log.
    public static func load(
        from data: Data,
        installedProviders: Set<VoiceProviderID> = Set(VoiceProviderID.allCases),
        onWarning: ((String) -> Void)? = nil
    ) throws -> RimeDouConfig {
        let decoder = JSONDecoder()
        let partial = try decoder.decode(PartialRimeDouConfig.self, from: data)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let object {
            let knownKeys = Set(CodingKeys.allCases.map(\.stringValue)).union(["voiceHotkey", "qianwenVoiceHotkey"])
            for key in object.keys.sorted() where !knownKeys.contains(key) {
                onWarning?("unknown config key \"\(key)\" ignored")
            }
        }
        var config = RimeDouConfig.default
        let doubaoInstalled = installedProviders.contains(.doubao)
        applyTiming(&config.restoreDelay, partial.restoreDelay, name: "restoreDelay", isValid: validDelay, onWarning: onWarning)
        applyTiming(&config.switchPollInterval, partial.switchPollInterval, name: "switchPollInterval", isValid: validDuration, onWarning: onWarning)
        applyTiming(&config.switchWaitTimeout, partial.switchWaitTimeout, name: "switchWaitTimeout", isValid: validDuration, onWarning: onWarning)
        applyTiming(&config.focusBounceBackDelay, partial.focusBounceBackDelay, name: "focusBounceBackDelay", isValid: validDelay, onWarning: onWarning)
        applyTiming(&config.focusBounceSettleDelay, partial.focusBounceSettleDelay, name: "focusBounceSettleDelay", isValid: validDelay, onWarning: onWarning)
        applyTiming(&config.tapMaxDuration, partial.tapMaxDuration, name: "tapMaxDuration", isValid: validDuration, onWarning: onWarning)
        applyTiming(&config.tapDuration, partial.tapDuration, name: "tapDuration", isValid: validDuration, onWarning: onWarning)
        if let value = partial.triggerHotkey {
            if let hotkey = Hotkey.parse(value) {
                if validTriggerHotkey(hotkey) {
                    config.triggerHotkey = hotkey
                } else {
                    onWarning?("invalid triggerHotkey \"\(value)\": use a single key, or modifiers plus exactly one normal key; keeping default \"\(RimeDouConfig.default.triggerHotkey.stringRepresentation)\"")
                }
            } else {
                onWarning?("unparseable triggerHotkey \"\(value)\"; keeping default \"\(RimeDouConfig.default.triggerHotkey.stringRepresentation)\"")
            }
        }
        // Presence, rather than ??, makes an explicit new null override a legacy value.
        let doubaoHotkey = object?[CodingKeys.voiceHotkey.rawValue] != nil ? partial.doubao_VoiceHotkey : partial.voiceHotkey
        if let value = doubaoHotkey {
            if let hotkey = Hotkey.parse(value) {
                config.voiceHotkey = hotkey
            } else {
                onWarning?("unparseable doubao_VoiceHotkey \"\(value)\"; keeping default \"\(RimeDouConfig.default.voiceHotkey.stringRepresentation)\"")
            }
        }
        // Reject a trigger the voice hotkey's own synthesized events could re-arm.
        if doubaoInstalled, let warning = selfTriggerWarning(for: config.triggerHotkey, voice: config.voiceHotkey) {
            onWarning?("\(warning); resetting both to defaults")
            config.triggerHotkey = RimeDouConfig.default.triggerHotkey
            config.voiceHotkey = RimeDouConfig.default.voiceHotkey
        }
        // The optional second trigger never affects the primary trigger or the voice
        // hotkey: any problem with it only drops the second trigger itself.
        if let value = partial.triggerHotkey2 {
            config.triggerHotkey2 = resolveSecondaryTrigger(
                value,
                primary: config.triggerHotkey,
                voice: doubaoInstalled ? config.voiceHotkey : nil,
                onWarning: onWarning
            )
        }
        applyTiming(&config.qianwenCompletionTimeout, partial.qianwenCompletionTimeout,
                    name: "qianwenCompletionTimeout", isValid: { (1...300).contains($0) }, onWarning: onWarning)
        applyTiming(&config.qianwenGoneStabilityDelay, partial.qianwenGoneStabilityDelay,
                    name: "qianwenGoneStabilityDelay", isValid: { (0.1...1).contains($0) }, onWarning: onWarning)
        let qianwenHotkey = object?[CodingKeys.qianwenVoiceHotkey.rawValue] != nil ? partial.qianwen_VoiceHotkey : partial.qianwenVoiceHotkey
        if let value = qianwenHotkey {
            let triggers = [config.triggerHotkey] + (config.triggerHotkey2.map { [$0] } ?? [])
            // A transport may share modifiers with a typing/mouse combination:
            // it cannot re-arm that trigger without synthesizing its normal key.
            // Between vendor transports, retain the stricter prefix collision rule.
            if let hotkey = Hotkey.parse(value), validTransportHotkey(hotkey),
               (!installedProviders.contains(.qianwen) ||
                ((!doubaoInstalled || !activationCollision(hotkey, config.voiceHotkey)) &&
                 !triggers.contains(where: { selfTriggerWarning(for: $0, voice: hotkey) != nil }))) {
                config.qianwenVoiceHotkey = hotkey
            } else {
                onWarning?("invalid or conflicting qianwen_VoiceHotkey; Qianwen will stay disabled")
            }
        }
        return config
    }

    /// Returns a warning when the voice hotkey's own synthesized events could re-arm
    /// the given trigger: a modifier-only trigger arms on flagsChanged (any shared key
    /// loops), while a combination trigger arms on its normal key's keyDown (only a
    /// shared normal key on the voice hotkey can synthesize that).
    private static func selfTriggerWarning(for trigger: Hotkey, voice: Hotkey) -> String? {
        let triggerArmingKeyCodes: Set<Int>
        let voiceSynthesizedKeyCodes: Set<Int>
        if trigger.isModifierOnly {
            triggerArmingKeyCodes = Set(trigger.keys.flatMap(\.keyCodes))
            voiceSynthesizedKeyCodes = Set(voice.keys.flatMap(\.keyCodes))
        } else {
            triggerArmingKeyCodes = Set(trigger.keys.filter { !$0.isModifier }.flatMap(\.keyCodes))
            voiceSynthesizedKeyCodes = Set(voice.keys.filter { !$0.isModifier }.flatMap(\.keyCodes))
        }
        guard !triggerArmingKeyCodes.isDisjoint(with: voiceSynthesizedKeyCodes) else { return nil }
        return "triggerHotkey \"\(trigger.stringRepresentation)\" can be re-armed by the synthesized voice shortcut \"\(voice.stringRepresentation)\""
    }

    /// A modifier transport can activate while another transport is being assembled.
    /// Generic modifier names overlap either side; combinations with the same normal
    /// key are conservatively rejected because vendor modifier matching may vary.
    static func activationCollision(_ first: Hotkey, _ second: Hotkey) -> Bool {
        if first.isModifierOnly || second.isModifierOnly {
            return !Set(first.keys.flatMap(\.keyCodes)).isDisjoint(with: second.keys.flatMap(\.keyCodes))
        }
        return !Set(first.keys.filter { !$0.isModifier }.flatMap(\.keyCodes))
            .isDisjoint(with: second.keys.filter { !$0.isModifier }.flatMap(\.keyCodes))
    }

    private static func resolveSecondaryTrigger(
        _ value: String,
        primary: Hotkey,
        voice: Hotkey?,
        onWarning: ((String) -> Void)?
    ) -> Hotkey? {
        guard let hotkey = Hotkey.parse(value) else {
            onWarning?("unparseable triggerHotkey2 \"\(value)\"; ignoring it")
            return nil
        }
        guard validTriggerHotkey(hotkey) else {
            onWarning?("invalid triggerHotkey2 \"\(value)\": use a single key, or modifiers plus exactly one normal key; ignoring it")
            return nil
        }
        guard hotkey != primary else {
            onWarning?("triggerHotkey2 \"\(value)\" is identical to triggerHotkey; ignoring it")
            return nil
        }
        if let voice, let warning = selfTriggerWarning(for: hotkey, voice: voice) {
            onWarning?("\(warning) on triggerHotkey2; ignoring triggerHotkey2")
            return nil
        }
        return hotkey
    }

    private static func applyTiming(
        _ target: inout TimeInterval,
        _ value: TimeInterval?,
        name: String,
        isValid: (TimeInterval) -> Bool,
        onWarning: ((String) -> Void)?
    ) {
        guard let value else { return }
        if isValid(value) {
            target = value
        } else {
            onWarning?("invalid \(name) \(value); keeping default \(target)")
        }
    }

    private static func validDelay(_ value: TimeInterval) -> Bool {
        value.isFinite && (0...60).contains(value)
    }

    private static func validDuration(_ value: TimeInterval) -> Bool {
        value.isFinite && (0.001...60).contains(value)
    }

    private static func validTriggerHotkey(_ hotkey: Hotkey) -> Bool {
        guard !hotkey.keys.isEmpty, Set(hotkey.keys).count == hotkey.keys.count else {
            return false
        }
        if hotkey.keys.count == 1 {
            return true
        }
        return hotkey.keys.filter { !$0.isModifier }.count == 1
    }

    private static func validTransportHotkey(_ hotkey: Hotkey) -> Bool {
        // Qianwen's settings support only one or two modifier keys.
        guard (1...2).contains(hotkey.keys.count), hotkey.isModifierOnly else { return false }
        let codes = hotkey.keys.flatMap(\.keyCodes)
        return Set(codes).count == codes.count
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

    public static func loadFromDefaultLocation(
        installedProviders: Set<VoiceProviderID> = Set(VoiceProviderID.allCases),
        onWarning: ((String) -> Void)? = nil
    ) -> RimeDouConfig {
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
        do {
            return try load(from: data, installedProviders: installedProviders, onWarning: onWarning)
        } catch {
            onWarning?("failed to parse config: \(error.localizedDescription); using defaults")
            return .default
        }
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
    var triggerHotkey2: String?
    var doubao_VoiceHotkey: String?
    var qianwen_VoiceHotkey: String?
    // Older v2/v3 config files remain readable; encoding always uses provider names.
    var voiceHotkey: String?
    var qianwenVoiceHotkey: String?
    var qianwenCompletionTimeout: TimeInterval?
    var qianwenGoneStabilityDelay: TimeInterval?
}
