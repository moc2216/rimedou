import Foundation

public struct BridgeConfig: Equatable, Sendable {
    public var launchAtLogin: Bool
    public var restoreDelay: TimeInterval
    public var postSwitchSettleDelay: TimeInterval
    public var switchWaitTimeout: TimeInterval
    public var switchPollInterval: TimeInterval
    public var focusBounceBackDelay: TimeInterval
    public var focusBounceSettleDelay: TimeInterval
    public var optionWarmupTapDuration: TimeInterval
    public var optionWarmupToHoldDelay: TimeInterval

    public static let `default` = BridgeConfig(
        launchAtLogin: false,
        restoreDelay: 0.20,
        postSwitchSettleDelay: 1.20,
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
        config.launchAtLogin = partial.launchAtLogin ?? config.launchAtLogin
        config.restoreDelay = partial.restoreDelay ?? config.restoreDelay
        config.postSwitchSettleDelay = partial.postSwitchSettleDelay ?? config.postSwitchSettleDelay
        config.switchWaitTimeout = partial.switchWaitTimeout ?? config.switchWaitTimeout
        config.switchPollInterval = partial.switchPollInterval ?? config.switchPollInterval
        config.focusBounceBackDelay = partial.focusBounceBackDelay ?? config.focusBounceBackDelay
        config.focusBounceSettleDelay = partial.focusBounceSettleDelay ?? config.focusBounceSettleDelay
        config.optionWarmupTapDuration = partial.optionWarmupTapDuration ?? config.optionWarmupTapDuration
        config.optionWarmupToHoldDelay = partial.optionWarmupToHoldDelay ?? config.optionWarmupToHoldDelay
        return config
    }

    public static func loadFromDefaultLocation() -> BridgeConfig {
        loadFromDefaultLocation(
            userConfigURL: defaultUserConfigURL,
            templateURLs: candidateTemplateConfigURLs()
        )
    }

    public static func loadFromDefaultLocation(
        userConfigURL: URL,
        templateURLs: [URL],
        fileManager: FileManager = .default
    ) -> BridgeConfig {
        ensureUserConfigExists(
            at: userConfigURL,
            templateURLs: templateURLs,
            fileManager: fileManager
        )

        guard let data = try? Data(contentsOf: userConfigURL) else {
            return .default
        }
        return (try? load(from: data)) ?? .default
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
            .appendingPathComponent("DoubaoVoiceBridge", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private static func candidateTemplateConfigURLs() -> [URL] {
        var urls: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent("config.json"))
        }

        urls.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("config.json"))

        return urls
    }

    private static func ensureUserConfigExists(
        at url: URL,
        templateURLs: [URL],
        fileManager: FileManager
    ) {
        guard !fileManager.fileExists(atPath: url.path) else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = firstValidTemplateData(from: templateURLs) ?? defaultConfigData
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    private static func firstValidTemplateData(from urls: [URL]) -> Data? {
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  (try? load(from: data)) != nil else {
                continue
            }
            return data
        }
        return nil
    }

    private static var defaultConfigData: Data {
        """
        {
          "launchAtLogin": false,
          "restoreDelay": 0.2,
          "postSwitchSettleDelay": 1.2,
          "switchWaitTimeout": 2.0,
          "switchPollInterval": 0.05,
          "focusBounceBackDelay": 0.16,
          "focusBounceSettleDelay": 0.16,
          "optionWarmupTapDuration": 0.05,
          "optionWarmupToHoldDelay": 0.22
        }
        """.data(using: .utf8)!
    }
}

private struct PartialBridgeConfig: Decodable {
    var launchAtLogin: Bool?
    var restoreDelay: TimeInterval?
    var postSwitchSettleDelay: TimeInterval?
    var switchWaitTimeout: TimeInterval?
    var switchPollInterval: TimeInterval?
    var focusBounceBackDelay: TimeInterval?
    var focusBounceSettleDelay: TimeInterval?
    var optionWarmupTapDuration: TimeInterval?
    var optionWarmupToHoldDelay: TimeInterval?
}
