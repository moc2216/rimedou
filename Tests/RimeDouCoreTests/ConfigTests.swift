import XCTest
@testable import RimeDouCore

final class ConfigTests: XCTestCase {
    func testDefaultConfig() {
        let config = RimeDouConfig.default
        XCTAssertEqual(
            config.triggerHotkey,
            Hotkey(keys: [.rightCommand])
        )
        XCTAssertNil(config.triggerHotkey2)
        XCTAssertEqual(config.voiceHotkey, Hotkey(keys: [.rightControl]))
        XCTAssertEqual(config.tapMaxDuration, 0.35)
        XCTAssertEqual(config.tapDuration, 0.15)
    }

    func testTriggerHotkey2ParsesOptionalSecondTrigger() throws {
        let data = """
        {
          "triggerHotkey2": "LeftControl+LeftOption+LeftCommand+Z"
        }
        """.data(using: .utf8)!

        var warnings: [String] = []
        let config = try RimeDouConfig.load(from: data, onWarning: { warnings.append($0) })

        XCTAssertEqual(
            config.triggerHotkey2,
            Hotkey(keys: [.leftControl, .leftOption, .leftCommand, .character("z")])
        )
        XCTAssertEqual(warnings, [])
    }

    func testInvalidTriggerHotkey2EmitsWarningAndStaysNil() throws {
        let data = """
        {
          "triggerHotkey2": "Control+Option+Command"
        }
        """.data(using: .utf8)!

        var warnings: [String] = []
        let config = try RimeDouConfig.load(from: data, onWarning: { warnings.append($0) })

        XCTAssertNil(config.triggerHotkey2)
        XCTAssertEqual(config.triggerHotkey, RimeDouConfig.default.triggerHotkey)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("triggerHotkey2"), "warning was: \(warnings)")
    }

    func testTriggerHotkey2SameAsTriggerHotkeyIgnoredWithWarning() throws {
        let data = """
        {
          "triggerHotkey": "RightCommand",
          "triggerHotkey2": "RightCommand"
        }
        """.data(using: .utf8)!

        var warnings: [String] = []
        let config = try RimeDouConfig.load(from: data, onWarning: { warnings.append($0) })

        XCTAssertEqual(config.triggerHotkey, Hotkey(keys: [.rightCommand]))
        XCTAssertNil(config.triggerHotkey2)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("triggerHotkey2"), "warning was: \(warnings)")
    }

    func testTriggerHotkey2OverlappingVoiceHotkeyIsDropped() throws {
        let data = """
        {
          "triggerHotkey": "RightCommand",
          "triggerHotkey2": "RightControl"
        }
        """.data(using: .utf8)!

        var warnings: [String] = []
        let config = try RimeDouConfig.load(from: data, onWarning: { warnings.append($0) })

        XCTAssertEqual(config.triggerHotkey, Hotkey(keys: [.rightCommand]))
        XCTAssertNil(config.triggerHotkey2)
        XCTAssertEqual(config.voiceHotkey, RimeDouConfig.default.voiceHotkey)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("re-armed"), "warning was: \(warnings)")
    }

    func testRoundTripOmitsNilTriggerHotkey2AndKeepsSetValue() throws {
        let encoder = JSONEncoder()
        let defaultData = try encoder.encode(RimeDouConfig.default)
        XCTAssertFalse(
            String(data: defaultData, encoding: .utf8)!.contains("triggerHotkey2"),
            "default config should not contain triggerHotkey2"
        )

        var withSecond = RimeDouConfig.default
        withSecond.triggerHotkey2 = Hotkey(keys: [.control, .option, .command, .character("z")])
        let roundTripped = try RimeDouConfig.load(from: try encoder.encode(withSecond))
        XCTAssertEqual(roundTripped.triggerHotkey2, withSecond.triggerHotkey2)
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
        XCTAssertEqual(config.triggerHotkey, RimeDouConfig.default.triggerHotkey)
    }

    func testHotkeyParsing() {
        let hotkey = Hotkey.parse("RightCommand+Space")
        XCTAssertEqual(hotkey, Hotkey(keys: [.rightCommand, .space]))
    }

    func testHotkeyParsingRejectsInvalidComponent() {
        XCTAssertNil(Hotkey.parse("RightCommand+NotAKey"))
        XCTAssertNil(Hotkey.parse("RightCommand+"))
    }

    func testTriggerHotkeyAcceptsModifiersAndOneCharacterKey() throws {
        let data = """
        {
          "triggerHotkey": "Control+Option+Command+V"
        }
        """.data(using: .utf8)!

        let config = try RimeDouConfig.load(from: data)

        XCTAssertEqual(
            config.triggerHotkey,
            Hotkey(keys: [.control, .option, .command, .character("v")])
        )
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

    func testValidConfigEmitsNoWarnings() throws {
        let data = """
        {
          "restoreDelay": 0.4,
          "triggerHotkey": "LeftControl+LeftOption+LeftCommand+V",
          "voiceHotkey": "RightControl"
        }
        """.data(using: .utf8)!

        var warnings: [String] = []
        _ = try RimeDouConfig.load(from: data, onWarning: { warnings.append($0) })

        XCTAssertEqual(warnings, [])
    }

    func testModifiersOnlyTriggerHotkeyEmitsWarning() throws {
        let data = """
        {
          "triggerHotkey": "Control+Option+Command"
        }
        """.data(using: .utf8)!

        var warnings: [String] = []
        let config = try RimeDouConfig.load(from: data, onWarning: { warnings.append($0) })

        XCTAssertEqual(config.triggerHotkey, RimeDouConfig.default.triggerHotkey)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("triggerHotkey"), "warning was: \(warnings)")
    }

    func testUnparseableTriggerHotkeyEmitsWarning() throws {
        let data = """
        {
          "triggerHotkey": "NotAKey"
        }
        """.data(using: .utf8)!

        var warnings: [String] = []
        let config = try RimeDouConfig.load(from: data, onWarning: { warnings.append($0) })

        XCTAssertEqual(config.triggerHotkey, RimeDouConfig.default.triggerHotkey)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("triggerHotkey"), "warning was: \(warnings)")
    }

    func testUnparseableVoiceHotkeyEmitsWarning() throws {
        let data = """
        {
          "voiceHotkey": "NotAKey"
        }
        """.data(using: .utf8)!

        var warnings: [String] = []
        let config = try RimeDouConfig.load(from: data, onWarning: { warnings.append($0) })

        XCTAssertEqual(config.voiceHotkey, RimeDouConfig.default.voiceHotkey)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("voiceHotkey"), "warning was: \(warnings)")
    }

    func testInvalidNumericValueEmitsWarning() throws {
        let data = """
        {
          "restoreDelay": 61
        }
        """.data(using: .utf8)!

        var warnings: [String] = []
        let config = try RimeDouConfig.load(from: data, onWarning: { warnings.append($0) })

        XCTAssertEqual(config.restoreDelay, RimeDouConfig.default.restoreDelay)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("restoreDelay"), "warning was: \(warnings)")
    }

    func testUnknownConfigKeyEmitsWarning() throws {
        let data = """
        {
          "launchAtLogin": true,
          "restoreDelay": 0.33
        }
        """.data(using: .utf8)!

        var warnings: [String] = []
        let config = try RimeDouConfig.load(from: data, onWarning: { warnings.append($0) })

        XCTAssertEqual(config.restoreDelay, 0.33)
        XCTAssertEqual(warnings, ["unknown config key \"launchAtLogin\" ignored"])
    }

    func testTriggerVoiceHotkeyOverlapResetsBothToDefaults() throws {
        let data = """
        {
          "triggerHotkey": "RightControl",
          "voiceHotkey": "RightControl"
        }
        """.data(using: .utf8)!

        var warnings: [String] = []
        let config = try RimeDouConfig.load(from: data, onWarning: { warnings.append($0) })

        XCTAssertEqual(config.triggerHotkey, RimeDouConfig.default.triggerHotkey)
        XCTAssertEqual(config.voiceHotkey, RimeDouConfig.default.voiceHotkey)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("re-armed"), "warning was: \(warnings)")
    }

    func testCharacterTriggerMatchingVoiceHotkeyCodeResetsBoth() throws {
        // A bare normal-key trigger arms on that key's keyDown; the synthesized voice
        // keyDown of the same key would immediately end the session it just started.
        let data = """
        {
          "triggerHotkey": "V",
          "voiceHotkey": "V"
        }
        """.data(using: .utf8)!

        var warnings: [String] = []
        let config = try RimeDouConfig.load(from: data, onWarning: { warnings.append($0) })

        XCTAssertEqual(config.triggerHotkey, RimeDouConfig.default.triggerHotkey)
        XCTAssertEqual(config.voiceHotkey, RimeDouConfig.default.voiceHotkey)
        XCTAssertEqual(warnings.count, 1)
    }

    func testSingleKeyTriggerSharingModifierWithComboVoiceHotkeyResetsBoth() throws {
        // The combo voice hotkey synthesizes a Command flagsChanged, which alone arms
        // a modifier-only trigger.
        let data = """
        {
          "triggerHotkey": "LeftCommand",
          "voiceHotkey": "Command+V"
        }
        """.data(using: .utf8)!

        var warnings: [String] = []
        let config = try RimeDouConfig.load(from: data, onWarning: { warnings.append($0) })

        XCTAssertEqual(config.triggerHotkey, RimeDouConfig.default.triggerHotkey)
        XCTAssertEqual(config.voiceHotkey, RimeDouConfig.default.voiceHotkey)
        XCTAssertEqual(warnings.count, 1)
    }

    func testComboTriggerMayShareModifiersWithVoiceHotkey() throws {
        // Combination triggers arm on their normal key's keyDown, so a shared
        // modifier (generic Control includes RightControl's keycode) cannot
        // re-arm the trigger via synthesized flagsChanged events.
        let data = """
        {
          "triggerHotkey": "Control+Option+Command+V",
          "voiceHotkey": "Control"
        }
        """.data(using: .utf8)!

        var warnings: [String] = []
        let config = try RimeDouConfig.load(from: data, onWarning: { warnings.append($0) })

        XCTAssertEqual(
            config.triggerHotkey,
            Hotkey(keys: [.control, .option, .command, .character("v")])
        )
        XCTAssertEqual(config.voiceHotkey, Hotkey(keys: [.control]))
        XCTAssertEqual(warnings, [])
    }

    func testDisjointTriggerAndVoiceHotkeysAreKept() throws {
        let data = """
        {
          "triggerHotkey": "RightCommand",
          "voiceHotkey": "RightControl"
        }
        """.data(using: .utf8)!

        var warnings: [String] = []
        let config = try RimeDouConfig.load(from: data, onWarning: { warnings.append($0) })

        XCTAssertEqual(config.triggerHotkey, Hotkey(keys: [.rightCommand]))
        XCTAssertEqual(config.voiceHotkey, Hotkey(keys: [.rightControl]))
        XCTAssertEqual(warnings, [])
    }
}
