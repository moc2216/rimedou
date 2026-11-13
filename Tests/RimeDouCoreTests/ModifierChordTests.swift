import ApplicationServices
import IOKit.hidsystem
import XCTest
@testable import RimeDouCore

final class ModifierChordTests: XCTestCase {
    private let chord = Hotkey(keys: [.leftOption, .leftControl])
    private let both: CGEventFlags = [.maskAlternate, .maskControl]

    func testQianwenAcceptsOnlyOneOrTwoModifierKeys() throws {
        for value in ["LeftOption+LeftControl+LeftShift", "LeftOption+Space", "LeftControl+A", "Space", "A"] {
            let config = try RimeDouConfig.load(from: JSONSerialization.data(withJSONObject: ["qianwenVoiceHotkey": value]))
            XCTAssertNil(config.qianwenVoiceHotkey, value)
        }
    }

    @MainActor func testSenderIncludesNativeLeftRightModifierFlags() {
        var events: [CGEvent] = []
        let sender = HotkeySender(marker: 1234, postEvent: { events.append($0) })
        XCTAssertTrue(sender.tap(chord, duration: 10, completion: {}))
        sender.releaseAll()
        XCTAssertEqual(events.map { $0.type }, [.flagsChanged, .flagsChanged, .flagsChanged, .flagsChanged])
        XCTAssertEqual(events.map { $0.flags.rawValue }, [
            CGEventFlags.maskAlternate.rawValue | UInt64(NX_DEVICELALTKEYMASK),
            both.rawValue | UInt64(NX_DEVICELALTKEYMASK | NX_DEVICELCTLKEYMASK),
            CGEventFlags.maskAlternate.rawValue | UInt64(NX_DEVICELALTKEYMASK), 0
        ])
    }

    func testActualQianwenChordCoexistsWithMouseTrigger() throws {
        var warnings: [String] = []
        let config = try RimeDouConfig.load(from: Data(#"{"triggerHotkey2":"LeftControl+LeftOption+LeftCommand+Z","qianwenVoiceHotkey":"LeftOption+LeftControl"}"#.utf8), onWarning: { warnings.append($0) })
        XCTAssertEqual(config.qianwenVoiceHotkey, chord)
        XCTAssertEqual(config.triggerHotkey2, Hotkey.parse("LeftControl+LeftOption+LeftCommand+Z"))
        XCTAssertNotNil(VoiceProviderRegistry.definition(for: .qianwen, config: config))
        XCTAssertTrue(warnings.isEmpty)
        XCTAssertEqual(try RimeDouConfig.load(from: JSONEncoder().encode(config)), config)
    }

    func testChordStillRejectsProviderPrefixesAndTriggerRearming() throws {
        for object in [
            ["qianwenVoiceHotkey": "LeftOption+RightControl"],
            ["triggerHotkey": "LeftOption", "qianwenVoiceHotkey": "LeftOption+LeftControl"],
            ["qianwenVoiceHotkey": "Control+LeftControl"],
            ["qianwenVoiceHotkey": "LeftOption+LeftOption"]
        ] {
            let config = try RimeDouConfig.load(from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNil(config.qianwenVoiceHotkey, object.description)
        }
    }

    func testChordRequiresBothSidesAndFinishesOnlyOnFinalRelease() {
        for codes: [Int64] in [[58, 59], [59, 58]] {
            let detector = TriggerDetector(triggerHotkey: chord, tapMaxDuration: 0.35)
            let first: CGEventFlags = codes[0] == 58 ? .maskAlternate : .maskControl
            XCTAssertEqual(detector.process(event: .flagsChanged(keyCode: codes[0], rawFlags: first.rawValue, timestamp: 0)), .ignored)
            XCTAssertEqual(detector.process(event: .flagsChanged(keyCode: codes[1], rawFlags: both.rawValue, timestamp: 0.02)), .triggerDown)
            XCTAssertEqual(detector.process(event: .flagsChanged(keyCode: codes[1], rawFlags: first.rawValue, timestamp: 0.05)), .ignored)
            XCTAssertEqual(detector.process(event: .flagsChanged(keyCode: codes[0], rawFlags: 0, timestamp: 0.1)), .triggerTap)
        }
        let wrongSide = TriggerDetector(triggerHotkey: chord, tapMaxDuration: 0.35)
        let results = [
            wrongSide.process(event: .flagsChanged(keyCode: 61, rawFlags: CGEventFlags.maskAlternate.rawValue, timestamp: 0)),
            wrongSide.process(event: .flagsChanged(keyCode: 59, rawFlags: both.rawValue, timestamp: 0.02)),
            wrongSide.process(event: .flagsChanged(keyCode: 59, rawFlags: CGEventFlags.maskAlternate.rawValue, timestamp: 0.05)),
            wrongSide.process(event: .flagsChanged(keyCode: 61, rawFlags: 0, timestamp: 0.1))
        ]
        XCTAssertFalse(results.contains(.triggerTap))
    }

    func testMouseModifiersAndOrdinaryShortcutsCancelChordUntilReleased() {
        for extra in [KeyboardEvent.keyDown(keyCode: 0, rawFlags: both.rawValue, timestamp: 0.03),
                      .flagsChanged(keyCode: 55, rawFlags: both.union(.maskCommand).rawValue, timestamp: 0.03)] {
            let detector = TriggerDetector(triggerHotkey: chord, tapMaxDuration: 0.35)
            _ = detector.process(event: .flagsChanged(keyCode: 58, rawFlags: CGEventFlags.maskAlternate.rawValue, timestamp: 0))
            _ = detector.process(event: .flagsChanged(keyCode: 59, rawFlags: both.rawValue, timestamp: 0.02))
            _ = detector.process(event: extra)
            _ = detector.process(event: .flagsChanged(keyCode: 55, rawFlags: both.rawValue, timestamp: 0.04))
            _ = detector.process(event: .flagsChanged(keyCode: 59, rawFlags: CGEventFlags.maskAlternate.rawValue, timestamp: 0.05))
            XCTAssertNotEqual(detector.process(event: .flagsChanged(keyCode: 58, rawFlags: 0, timestamp: 0.1)), .triggerTap)
        }
    }

    func testLongChordIsNotShortTap() {
        let detector = TriggerDetector(triggerHotkey: chord, tapMaxDuration: 0.35)
        _ = detector.process(event: .flagsChanged(keyCode: 58, rawFlags: CGEventFlags.maskAlternate.rawValue, timestamp: 0))
        _ = detector.process(event: .flagsChanged(keyCode: 59, rawFlags: both.rawValue, timestamp: 0.02))
        _ = detector.process(event: .flagsChanged(keyCode: 59, rawFlags: CGEventFlags.maskAlternate.rawValue, timestamp: 1))
        XCTAssertEqual(detector.process(event: .flagsChanged(keyCode: 58, rawFlags: 0, timestamp: 1.02)), .cancelled(.heldTooLong))
    }

    @MainActor func testSenderPostsChordInOrderAndReleasesWithoutStuckModifiers() {
        var events: [CGEvent] = []
        let sender = HotkeySender(marker: 1234, postEvent: { events.append($0) })
        XCTAssertTrue(sender.tap(chord, duration: 10, completion: {}))
        sender.releaseAll()
        XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [58, 59, 59, 58])
        let modifiers: CGEventFlags = [.maskShift, .maskAlternate, .maskControl, .maskCommand]
        XCTAssertEqual(events.map { $0.flags.intersection(modifiers) }, [.maskAlternate, both, .maskAlternate, []])
        XCTAssertTrue(events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == 1234 })
    }
}
