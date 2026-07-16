import ApplicationServices
import XCTest
@testable import RimeDouCore

final class KeyboardEngineTests: XCTestCase {
    func testDeferredEventBufferPreservesEventsUntilDrain() {
        var buffer = DeferredEventBuffer<String>()

        XCTAssertFalse(buffer.append("before restore"))
        buffer.begin()
        XCTAssertTrue(buffer.append("key down"))
        XCTAssertTrue(buffer.append("key up"))

        XCTAssertEqual(buffer.drain(), ["key down", "key up"])
        XCTAssertFalse(buffer.isActive)
        XCTAssertEqual(buffer.drain(), [])
    }

    func testBeginningDeferralTwiceDoesNotDiscardAlreadyBufferedEvents() {
        var buffer = DeferredEventBuffer<String>()
        buffer.begin()
        _ = buffer.append("first key")

        buffer.begin()

        XCTAssertEqual(buffer.drain(), ["first key"])
    }

    func testKeyCodeMappingForRightCommand() {
        XCTAssertEqual(Key.rightCommand.keyCodes, [54])
    }

    func testHotkeyParseRightCommandSpace() {
        let hotkey = Hotkey.parse("RightCommand+Space")
        XCTAssertEqual(hotkey?.keys, [.rightCommand, .space])
    }

    func testTriggerDetectorCleanTap() {
        let detector = TriggerDetector(
            triggerHotkey: Hotkey(keys: [.rightCommand]),
            tapMaxDuration: 0.35
        )
        let down = KeyboardEvent.keyDown(keyCode: 54, timestamp: 0)
        let up = KeyboardEvent.keyUp(keyCode: 54, timestamp: 0.1)

        XCTAssertEqual(detector.process(event: down), .triggerDown)
        XCTAssertEqual(detector.process(event: up), .triggerTap)
    }

    func testTriggerDetectorHoldingTooLongIsNotTap() {
        let detector = TriggerDetector(
            triggerHotkey: Hotkey(keys: [.rightCommand]),
            tapMaxDuration: 0.35
        )
        _ = detector.process(event: .keyDown(keyCode: 54, timestamp: 0))
        XCTAssertEqual(
            detector.process(event: .keyUp(keyCode: 54, timestamp: 0.5)),
            .cancelled(.heldTooLong)
        )
    }

    func testTriggerDetectorOtherKeyCancelsTap() {
        let detector = TriggerDetector(
            triggerHotkey: Hotkey(keys: [.rightCommand]),
            tapMaxDuration: 0.35
        )
        _ = detector.process(event: .keyDown(keyCode: 54, timestamp: 0))
        XCTAssertEqual(detector.process(event: .keyDown(keyCode: 0, timestamp: 0.05)), .cancelled(.otherKeyPressed))
    }

    func testTriggerDetectorRepeatedKeyDownDoesNotResetTapDuration() {
        let detector = TriggerDetector(
            triggerHotkey: Hotkey(keys: [.space]),
            tapMaxDuration: 0.35
        )
        _ = detector.process(event: .keyDown(keyCode: 49, timestamp: 0))
        _ = detector.process(event: .keyDown(keyCode: 49, timestamp: 0.3))

        XCTAssertEqual(
            detector.process(event: .keyUp(keyCode: 49, timestamp: 0.4)),
            .cancelled(.heldTooLong)
        )
    }

    func testTriggerDetectorModifierTapFromFlagsChangedEvents() {
        let detector = TriggerDetector(
            triggerHotkey: Hotkey(keys: [.rightCommand]),
            tapMaxDuration: 0.35
        )

        XCTAssertEqual(
            detector.process(event: .flagsChanged(
                keyCode: 54,
                rawFlags: CGEventFlags.maskCommand.rawValue,
                timestamp: 0
            )),
            .triggerDown
        )
        XCTAssertEqual(
            detector.process(event: .flagsChanged(keyCode: 54, rawFlags: 0, timestamp: 0.1)),
            .triggerTap
        )
    }

    func testTriggerDetectorIgnoresOtherSideOfModifier() {
        let detector = TriggerDetector(
            triggerHotkey: Hotkey(keys: [.rightCommand]),
            tapMaxDuration: 0.35
        )

        XCTAssertEqual(
            detector.process(event: .flagsChanged(
                keyCode: 55,
                rawFlags: CGEventFlags.maskCommand.rawValue,
                timestamp: 0
            )),
            .ignored
        )
    }

    func testTriggerDetectorOtherModifierCancelsModifierTap() {
        let detector = TriggerDetector(
            triggerHotkey: Hotkey(keys: [.rightCommand]),
            tapMaxDuration: 0.35
        )
        _ = detector.process(event: .flagsChanged(
            keyCode: 54,
            rawFlags: CGEventFlags.maskCommand.rawValue,
            timestamp: 0
        ))

        XCTAssertEqual(
            detector.process(event: .flagsChanged(
                keyCode: 56,
                rawFlags: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue,
                timestamp: 0.05
            )),
            .cancelled(.otherKeyPressed)
        )
        XCTAssertEqual(
            detector.process(event: .flagsChanged(keyCode: 54, rawFlags: 0, timestamp: 0.1)),
            .cancelled(.otherKeyPressed)
        )
    }

    func testTriggerDetectorResetClearsPressedKey() {
        let detector = TriggerDetector(
            triggerHotkey: Hotkey(keys: [.space]),
            tapMaxDuration: 0.35
        )
        _ = detector.process(event: .keyDown(keyCode: 49, timestamp: 0))

        detector.reset()

        XCTAssertEqual(
            detector.process(event: .keyUp(keyCode: 49, timestamp: 0.1)),
            .ignored
        )
    }
}
