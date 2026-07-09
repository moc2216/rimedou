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
}
