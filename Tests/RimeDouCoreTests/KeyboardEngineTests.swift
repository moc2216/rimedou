import XCTest
@testable import RimeDouCore

final class KeyboardEngineTests: XCTestCase {
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
            tapMaxDuration: 0.35,
            logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null"))
        )
        let down = KeyboardEvent.keyDown(keyCode: 54, timestamp: 0)
        let up = KeyboardEvent.keyUp(keyCode: 54, timestamp: 0.1)

        XCTAssertEqual(detector.process(event: down), .triggerDown)
        XCTAssertEqual(detector.process(event: up), .triggerTap)
    }

    func testTriggerDetectorHoldingTooLongIsNotTap() {
        let detector = TriggerDetector(
            triggerHotkey: Hotkey(keys: [.rightCommand]),
            tapMaxDuration: 0.35,
            logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null"))
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
            tapMaxDuration: 0.35,
            logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null"))
        )
        _ = detector.process(event: .keyDown(keyCode: 54, timestamp: 0))
        XCTAssertEqual(detector.process(event: .keyDown(keyCode: 0, timestamp: 0.05)), .cancelled(.otherKeyPressed))
    }
}
