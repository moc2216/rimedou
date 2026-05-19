import XCTest
@testable import DoubaoVoiceBridgeCore

final class BridgeConfigTests: XCTestCase {
    func testDefaultConfigMatchesProjectTimingSpec() {
        let config = BridgeConfig.default

        XCTAssertEqual(config.targetInputMethod, "豆包输入法")
        XCTAssertEqual(config.userInputMethod, "Squirrel - Simplified")
        XCTAssertTrue(config.launchAtLogin)
        XCTAssertEqual(config.restoreDelay, 0.20)
        XCTAssertEqual(config.postSwitchSettleDelay, 1.20)
        XCTAssertEqual(config.recentRestoreSettleDelay, 1.50)
        XCTAssertEqual(config.switchWaitTimeout, 2.00)
        XCTAssertEqual(config.focusBounceBackDelay, 0.16)
        XCTAssertEqual(config.focusBounceSettleDelay, 0.16)
        XCTAssertEqual(config.optionWarmupTapDuration, 0.05)
        XCTAssertEqual(config.optionWarmupToHoldDelay, 0.22)
    }

    func testPartialJSONConfigKeepsDefaultsForMissingValues() throws {
        let data = """
        {
          "targetInputMethod": "Custom Doubao",
          "launchAtLogin": false,
          "restoreDelay": 0.35
        }
        """.data(using: .utf8)!

        let config = try BridgeConfig.load(from: data)

        XCTAssertEqual(config.targetInputMethod, "Custom Doubao")
        XCTAssertEqual(config.userInputMethod, "Squirrel - Simplified")
        XCTAssertFalse(config.launchAtLogin)
        XCTAssertEqual(config.restoreDelay, 0.35)
        XCTAssertEqual(config.postSwitchSettleDelay, 1.20)
    }

    func testDefaultLocationLoadsConfigFromCurrentDirectory() throws {
        let fileManager = FileManager.default
        let originalDirectory = fileManager.currentDirectoryPath
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let configURL = tempDirectory.appendingPathComponent("config.json")
        try """
        {
          "targetInputMethod": "Project Doubao",
          "launchAtLogin": false
        }
        """.data(using: .utf8)!.write(to: configURL)

        defer {
            _ = fileManager.changeCurrentDirectoryPath(originalDirectory)
            try? fileManager.removeItem(at: tempDirectory)
        }

        XCTAssertTrue(fileManager.changeCurrentDirectoryPath(tempDirectory.path))

        let config = BridgeConfig.loadFromDefaultLocation()

        XCTAssertEqual(config.targetInputMethod, "Project Doubao")
        XCTAssertFalse(config.launchAtLogin)
        XCTAssertEqual(config.userInputMethod, "Squirrel - Simplified")
    }
}
