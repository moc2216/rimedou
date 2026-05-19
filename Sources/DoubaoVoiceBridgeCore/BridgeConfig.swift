import Foundation

public struct BridgeConfig: Equatable, Sendable {
    public var targetInputMethod: String
    public var userInputMethod: String
    public var restoreDelay: TimeInterval
    public var postSwitchSettleDelay: TimeInterval
    public var recentRestoreSettleDelay: TimeInterval
    public var switchWaitTimeout: TimeInterval
    public var switchPollInterval: TimeInterval
    public var focusBounceBackDelay: TimeInterval
    public var focusBounceSettleDelay: TimeInterval
    public var optionWarmupTapDuration: TimeInterval
    public var optionWarmupToHoldDelay: TimeInterval

    public static let `default` = BridgeConfig(
        targetInputMethod: "豆包输入法",
        userInputMethod: "Squirrel - Simplified",
        restoreDelay: 0.20,
        postSwitchSettleDelay: 1.20,
        recentRestoreSettleDelay: 1.50,
        switchWaitTimeout: 2.00,
        switchPollInterval: 0.05,
        focusBounceBackDelay: 0.16,
        focusBounceSettleDelay: 0.16,
        optionWarmupTapDuration: 0.05,
        optionWarmupToHoldDelay: 0.22
    )

    public static func load(from data: Data) throws -> BridgeConfig {
        let partial = try JSONDecoder().decode(PartialBridgeConfig.self, from: data)
        var config = BridgeConfig.default
        config.targetInputMethod = partial.targetInputMethod ?? config.targetInputMethod
        config.userInputMethod = partial.userInputMethod ?? config.userInputMethod
        config.restoreDelay = partial.restoreDelay ?? config.restoreDelay
        config.postSwitchSettleDelay = partial.postSwitchSettleDelay ?? config.postSwitchSettleDelay
        config.recentRestoreSettleDelay = partial.recentRestoreSettleDelay ?? config.recentRestoreSettleDelay
        config.switchWaitTimeout = partial.switchWaitTimeout ?? config.switchWaitTimeout
        config.switchPollInterval = partial.switchPollInterval ?? config.switchPollInterval
        config.focusBounceBackDelay = partial.focusBounceBackDelay ?? config.focusBounceBackDelay
        config.focusBounceSettleDelay = partial.focusBounceSettleDelay ?? config.focusBounceSettleDelay
        config.optionWarmupTapDuration = partial.optionWarmupTapDuration ?? config.optionWarmupTapDuration
        config.optionWarmupToHoldDelay = partial.optionWarmupToHoldDelay ?? config.optionWarmupToHoldDelay
        return config
    }

    public static func loadFromDefaultLocation() -> BridgeConfig {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/doubao-voice-bridge/config.json")
        guard let data = try? Data(contentsOf: url) else {
            return .default
        }
        return (try? load(from: data)) ?? .default
    }
}

private struct PartialBridgeConfig: Decodable {
    var targetInputMethod: String?
    var userInputMethod: String?
    var restoreDelay: TimeInterval?
    var postSwitchSettleDelay: TimeInterval?
    var recentRestoreSettleDelay: TimeInterval?
    var switchWaitTimeout: TimeInterval?
    var switchPollInterval: TimeInterval?
    var focusBounceBackDelay: TimeInterval?
    var focusBounceSettleDelay: TimeInterval?
    var optionWarmupTapDuration: TimeInterval?
    var optionWarmupToHoldDelay: TimeInterval?
}
