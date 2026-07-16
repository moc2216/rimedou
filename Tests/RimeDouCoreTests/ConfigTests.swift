import XCTest
@testable import RimeDouCore

final class ConfigTests: XCTestCase {
    func testDefaultConfig() {
        let config = RimeDouConfig.default
        XCTAssertEqual(config.triggerHotkey, Hotkey(keys: [.rightCommand]))
        XCTAssertEqual(config.voiceHotkey, Hotkey(keys: [.rightControl]))
        XCTAssertEqual(config.tapMaxDuration, 0.35)
        XCTAssertEqual(config.tapDuration, 0.15)
    }

    func testPartialJSONKeepsDefaults() throws {
        let data = """
        {
          "restoreDelay": 0.35
        }
        """.data(using: .utf8)!
        let config = try RimeDouConfig.load(from: data)
        XCTAssertEqual(config.restoreDelay, 0.35)
        XCTAssertEqual(config.tapDuration, 0.15)
        XCTAssertEqual(config.triggerHotkey, Hotkey(keys: [.rightCommand]))
    }

    func testHotkeyParsing() {
        let hotkey = Hotkey.parse("RightCommand+Space")
        XCTAssertEqual(hotkey, Hotkey(keys: [.rightCommand, .space]))
    }

    func testHotkeyParsingRejectsInvalidComponent() {
        XCTAssertNil(Hotkey.parse("RightCommand+NotAKey"))
        XCTAssertNil(Hotkey.parse("RightCommand+"))
    }

    func testTriggerHotkeyRejectsMultipleKeys() throws {
        let data = """
        {
          "triggerHotkey": "Space+Tab"
        }
        """.data(using: .utf8)!

        let config = try RimeDouConfig.load(from: data)

        XCTAssertEqual(config.triggerHotkey, RimeDouConfig.default.triggerHotkey)
    }

    func testUnknownKeysAreIgnored() throws {
        let data = """
        {
          "launchAtLogin": true,
          "restoreDelay": 0.33
        }
        """.data(using: .utf8)!
        let config = try RimeDouConfig.load(from: data)
        XCTAssertEqual(config.restoreDelay, 0.33)
    }

    func testRoundTripEncoding() throws {
        let config = RimeDouConfig.default
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let decoded = try RimeDouConfig.load(from: data)
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.triggerHotkey, config.triggerHotkey)
        XCTAssertEqual(decoded.voiceHotkey, config.voiceHotkey)
    }

    func testInvalidTimingValuesKeepDefaults() throws {
        let data = """
        {
          "restoreDelay": 61,
          "switchPollInterval": 0,
          "switchWaitTimeout": -1,
          "focusBounceBackDelay": -0.1,
          "focusBounceSettleDelay": 61,
          "tapMaxDuration": 0.0001,
          "tapDuration": 1000
        }
        """.data(using: .utf8)!

        let config = try RimeDouConfig.load(from: data)

        XCTAssertEqual(config.restoreDelay, RimeDouConfig.default.restoreDelay)
        XCTAssertEqual(config.switchPollInterval, RimeDouConfig.default.switchPollInterval)
        XCTAssertEqual(config.switchWaitTimeout, RimeDouConfig.default.switchWaitTimeout)
        XCTAssertEqual(config.focusBounceBackDelay, RimeDouConfig.default.focusBounceBackDelay)
        XCTAssertEqual(config.focusBounceSettleDelay, RimeDouConfig.default.focusBounceSettleDelay)
        XCTAssertEqual(config.tapMaxDuration, RimeDouConfig.default.tapMaxDuration)
        XCTAssertEqual(config.tapDuration, RimeDouConfig.default.tapDuration)
    }

    func testZeroIsAllowedForOptionalDelays() throws {
        let data = """
        {
          "restoreDelay": 0,
          "focusBounceBackDelay": 0,
          "focusBounceSettleDelay": 0
        }
        """.data(using: .utf8)!

        let config = try RimeDouConfig.load(from: data)

        XCTAssertEqual(config.restoreDelay, 0)
        XCTAssertEqual(config.focusBounceBackDelay, 0)
        XCTAssertEqual(config.focusBounceSettleDelay, 0)
    }
}
