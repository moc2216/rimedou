import XCTest
@testable import DoubaoVoiceBridgeCore

final class BridgeConfigTests: XCTestCase {
    func testDefaultConfigMatchesProjectTimingSpec() {
        let config = BridgeConfig.default

        let configurableFields = Set(Mirror(reflecting: config).children.compactMap(\.label))
        XCTAssertFalse(configurableFields.contains("targetInputMethod"))
        XCTAssertFalse(configurableFields.contains("userInputMethod"))
        XCTAssertFalse(config.launchAtLogin)
        XCTAssertEqual(config.restoreDelay, 0.20)
        XCTAssertEqual(config.postSwitchSettleDelay, 1.20)
        XCTAssertEqual(config.switchWaitTimeout, 2.00)
        XCTAssertEqual(config.focusBounceBackDelay, 0.16)
        XCTAssertEqual(config.focusBounceSettleDelay, 0.16)
        XCTAssertEqual(config.optionWarmupTapDuration, 0.05)
        XCTAssertEqual(config.optionWarmupToHoldDelay, 0.22)
    }

    func testPartialJSONConfigKeepsDefaultsForMissingValues() throws {
        let data = """
        {
          "launchAtLogin": false,
          "restoreDelay": 0.35
        }
        """.data(using: .utf8)!

        let config = try BridgeConfig.load(from: data)

        XCTAssertFalse(config.launchAtLogin)
        XCTAssertEqual(config.restoreDelay, 0.35)
        XCTAssertEqual(config.postSwitchSettleDelay, 1.20)
    }

    func testDefaultLocationCreatesUserConfigFromProjectTemplateWhenMissing() throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let userConfigURL = tempDirectory
            .appendingPathComponent("Application Support/DoubaoVoiceBridge/config.json")
        let templateURL = tempDirectory.appendingPathComponent("template-config.json")
        try """
        {
          "launchAtLogin": false,
          "restoreDelay": 0.45
        }
        """.data(using: .utf8)!.write(to: templateURL)

        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }

        let config = BridgeConfig.loadFromDefaultLocation(
            userConfigURL: userConfigURL,
            templateURLs: [templateURL]
        )

        XCTAssertEqual(config.restoreDelay, 0.45)
        XCTAssertTrue(fileManager.fileExists(atPath: userConfigURL.path))
    }

    func testDefaultLocationPrefersExistingUserConfigOverTemplate() throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let userConfigURL = tempDirectory
            .appendingPathComponent("Application Support/DoubaoVoiceBridge/config.json")
        let templateURL = tempDirectory.appendingPathComponent("template-config.json")
        try fileManager.createDirectory(
            at: userConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "restoreDelay": 0.31
        }
        """.data(using: .utf8)!.write(to: userConfigURL)
        try """
        {
          "restoreDelay": 0.90
        }
        """.data(using: .utf8)!.write(to: templateURL)

        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }

        let config = BridgeConfig.loadFromDefaultLocation(
            userConfigURL: userConfigURL,
            templateURLs: [templateURL]
        )

        XCTAssertEqual(config.restoreDelay, 0.31)
    }

    func testDefaultLocationWritesBuiltInConfigWhenNoTemplateExists() throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let userConfigURL = tempDirectory
            .appendingPathComponent("Application Support/DoubaoVoiceBridge/config.json")

        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }

        let config = BridgeConfig.loadFromDefaultLocation(
            userConfigURL: userConfigURL,
            templateURLs: []
        )

        XCTAssertFalse(config.launchAtLogin)
        XCTAssertEqual(config.restoreDelay, BridgeConfig.default.restoreDelay)
        XCTAssertTrue(fileManager.fileExists(atPath: userConfigURL.path))
    }
}
