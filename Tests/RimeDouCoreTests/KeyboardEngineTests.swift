import ApplicationServices
import XCTest
@testable import RimeDouCore

final class KeyboardEngineTests: XCTestCase {
    func testKeyboardEngineCapturesSyntheticShortcutsAtSessionEntry() {
        XCTAssertEqual(KeyboardEngine.eventTapLocation, .cgSessionEventTap)
    }

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

    func testTriggerDetectorCombinationWaitsForMainKeyAndRequiresAllModifiers() {
        let detector = TriggerDetector(
            triggerHotkey: Hotkey(keys: [.control, .option, .command, .character("v")]),
            tapMaxDuration: 0.35
        )
        let modifierFlags = (
            CGEventFlags.maskControl.rawValue
                | CGEventFlags.maskAlternate.rawValue
                | CGEventFlags.maskCommand.rawValue
        )

        XCTAssertEqual(
            detector.process(event: .flagsChanged(
                keyCode: 59,
                rawFlags: CGEventFlags.maskControl.rawValue,
                timestamp: 0
            )),
            .ignored
        )
        let ordinaryV = detector.process(
            event: .keyDown(keyCode: 9, rawFlags: 0, timestamp: 0.05)
        )
        XCTAssertEqual(ordinaryV, .ignored)
        XCTAssertFalse(detector.shouldSwallowEvent(keyCode: 9, after: ordinaryV))

        let triggerV = detector.process(
            event: .keyDown(keyCode: 9, rawFlags: modifierFlags, timestamp: 0.1)
        )
        XCTAssertEqual(triggerV, .triggerDown)
        XCTAssertTrue(detector.shouldSwallowEvent(keyCode: 9, after: triggerV))
        XCTAssertEqual(
            detector.process(event: .keyUp(keyCode: 9, rawFlags: modifierFlags, timestamp: 0.2)),
            .triggerTap
        )
    }

    func testTriggerDetectorIgnoresSynthesizedVoiceHotkeyWithoutMainKey() {
        let detector = TriggerDetector(
            triggerHotkey: Hotkey(keys: [.control, .option, .command, .character("v")]),
            tapMaxDuration: 0.35
        )

        XCTAssertEqual(
            detector.process(event: .flagsChanged(
                keyCode: 62,
                rawFlags: CGEventFlags.maskControl.rawValue,
                timestamp: 0
            )),
            .ignored
        )
        XCTAssertEqual(
            detector.process(event: .flagsChanged(keyCode: 62, rawFlags: 0, timestamp: 0.1)),
            .ignored
        )
    }

    func testTriggerDetectorCombinationCancelledWhenModifierReleasedBeforeKeyUp() {
        let detector = TriggerDetector(
            triggerHotkey: Hotkey(keys: [.control, .option, .command, .character("v")]),
            tapMaxDuration: 0.35
        )
        let modifierFlags = (
            CGEventFlags.maskControl.rawValue
                | CGEventFlags.maskAlternate.rawValue
                | CGEventFlags.maskCommand.rawValue
        )

        _ = detector.process(event: .keyDown(keyCode: 9, rawFlags: modifierFlags, timestamp: 0))
        XCTAssertEqual(
            detector.process(event: .flagsChanged(
                keyCode: 59,
                rawFlags: modifierFlags & ~CGEventFlags.maskControl.rawValue,
                timestamp: 0.05
            )),
            .cancelled(.otherKeyPressed)
        )
        // The keyUp still resolves as cancelled, so the swallowed keyDown keeps its
        // matching swallowed keyUp — no half-typed V leaks to the active app.
        let cancelledKeyUp = detector.process(event: .keyUp(keyCode: 9, rawFlags: modifierFlags, timestamp: 0.1))
        XCTAssertEqual(cancelledKeyUp, .cancelled(.otherKeyPressed))
        XCTAssertTrue(detector.shouldSwallowEvent(keyCode: 9, after: cancelledKeyUp))
    }

    func testSingleModifierTriggerEventsAreNotSwallowed() {
        // A modifiers-only trigger keeps its flagsChanged events flowing to the system:
        // modifiers alone produce no input, and swallowing them would break their
        // normal use (e.g. ⌘-click) for other purposes.
        let detector = TriggerDetector(
            triggerHotkey: Hotkey(keys: [.rightCommand]),
            tapMaxDuration: 0.35
        )

        let down = detector.process(event: .flagsChanged(
            keyCode: 54,
            rawFlags: CGEventFlags.maskCommand.rawValue,
            timestamp: 0
        ))
        XCTAssertEqual(down, .triggerDown)
        XCTAssertFalse(detector.shouldSwallowEvent(keyCode: 54, after: down))

        let up = detector.process(event: .flagsChanged(keyCode: 54, rawFlags: 0, timestamp: 0.1))
        XCTAssertEqual(up, .triggerTap)
        XCTAssertFalse(detector.shouldSwallowEvent(keyCode: 54, after: up))
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

    // MARK: - TriggerDetectorGroup (dual trigger hotkeys)

    private let keyboardCombo = Hotkey(keys: [.control, .option, .command, .character("z")])
    private let comboFlags = CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskCommand.rawValue

    func testGroupEitherHotkeyCanFireTriggerTap() {
        let group = TriggerDetectorGroup(
            hotkeys: [Hotkey(keys: [.rightCommand]), keyboardCombo],
            tapMaxDuration: 0.35
        )

        let keyResults = group.process(event: .flagsChanged(
            keyCode: 54,
            rawFlags: CGEventFlags.maskCommand.rawValue,
            timestamp: 0
        ))
        XCTAssertTrue(keyResults[0] == .triggerDown)
        XCTAssertTrue(
            group.process(event: .flagsChanged(keyCode: 54, rawFlags: 0, timestamp: 0.1))[0] == .triggerTap
        )

        let comboResults = group.process(event: .keyDown(keyCode: 6, rawFlags: comboFlags, timestamp: 0.3))
        XCTAssertTrue(comboResults[1] == .triggerDown)
        XCTAssertTrue(
            group.process(event: .keyUp(keyCode: 6, rawFlags: comboFlags, timestamp: 0.4))[1] == .triggerTap
        )
    }

    func testGroupTapResetsAllDetectors() {
        let group = TriggerDetectorGroup(
            hotkeys: [Hotkey(keys: [.rightCommand]), keyboardCombo],
            tapMaxDuration: 0.35
        )

        // Arm the combo trigger, then finish via a RightCommand tap instead.
        XCTAssertTrue(
            group.process(event: .keyDown(keyCode: 6, rawFlags: comboFlags, timestamp: 0))[1] == .triggerDown
        )
        _ = group.process(event: .flagsChanged(
            keyCode: 54,
            rawFlags: CGEventFlags.maskCommand.rawValue,
            timestamp: 0.05
        ))
        XCTAssertTrue(
            group.process(event: .flagsChanged(keyCode: 54, rawFlags: 0, timestamp: 0.1))[0] == .triggerTap
        )

        // The still-armed combo trigger must not fire a second tap after the group reset.
        let lateComboUp = group.process(event: .keyUp(keyCode: 6, rawFlags: comboFlags, timestamp: 0.15))
        XCTAssertFalse(lateComboUp.contains(.triggerTap))
        XCTAssertFalse(group.shouldSwallowEvent(keyCode: 6, after: lateComboUp))
    }

    func testGroupSwallowUnionsActivationKeysAndPassesModifiers() {
        let group = TriggerDetectorGroup(
            hotkeys: [Hotkey(keys: [.rightCommand]), keyboardCombo],
            tapMaxDuration: 0.35
        )

        // A full combo gesture (as synthesized by mouse tools) swallows its Z events.
        let comboDown = group.process(event: .keyDown(keyCode: 6, rawFlags: comboFlags, timestamp: 0))
        XCTAssertTrue(group.shouldSwallowEvent(keyCode: 6, after: comboDown))
        let comboUp = group.process(event: .keyUp(keyCode: 6, rawFlags: comboFlags, timestamp: 0.1))
        XCTAssertTrue(comboUp.contains(.triggerTap))
        XCTAssertTrue(group.shouldSwallowEvent(keyCode: 6, after: comboUp))

        // Modifier-only trigger events still pass through to the system.
        let modifierDown = group.process(event: .flagsChanged(
            keyCode: 54,
            rawFlags: CGEventFlags.maskCommand.rawValue,
            timestamp: 0.2
        ))
        XCTAssertTrue(modifierDown.contains(.triggerDown))
        XCTAssertFalse(group.shouldSwallowEvent(keyCode: 54, after: modifierDown))
        _ = group.process(event: .flagsChanged(keyCode: 54, rawFlags: 0, timestamp: 0.3))

        // With no gesture in progress, a plain Z is nobody's trigger and passes through.
        let plainZ = group.process(event: .keyDown(keyCode: 6, rawFlags: 0, timestamp: 0.4))
        XCTAssertFalse(plainZ.contains { $0 != .ignored })
        XCTAssertFalse(group.shouldSwallowEvent(keyCode: 6, after: plainZ))
    }

    func testGroupWithSingleHotkeyKeepsExistingBehavior() {
        let group = TriggerDetectorGroup(hotkeys: [Hotkey(keys: [.rightCommand])], tapMaxDuration: 0.35)

        XCTAssertTrue(
            group.process(event: .flagsChanged(
                keyCode: 54,
                rawFlags: CGEventFlags.maskCommand.rawValue,
                timestamp: 0
            )) == [.triggerDown]
        )
        XCTAssertTrue(
            group.process(event: .flagsChanged(keyCode: 54, rawFlags: 0, timestamp: 0.1)) == [.triggerTap]
        )
    }
}
