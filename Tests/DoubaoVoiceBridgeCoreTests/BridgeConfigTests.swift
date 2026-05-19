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
}
