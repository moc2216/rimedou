import ApplicationServices
import XCTest
@testable import RimeDouCore

@MainActor
private final class EngineDelegate: KeyboardEngineDelegate {
    var triggers = 0
    var externalEnds = 0
    var providerStops = 0
    func keyboardEngineDidDetectTriggerTap(_ engine: KeyboardEngine) { triggers += 1 }
    func keyboardEngineDidDetectExternalVoiceEnd(_ engine: KeyboardEngine) {
        externalEnds += 1
        engine.beginInputDeferral()
    }
    func keyboardEngineDidDetectManagedVoiceHotkeyTap(_ engine: KeyboardEngine) {
        providerStops += 1
        engine.beginInputDeferral(afterCurrentEvent: true)
    }
    func keyboardEngineDidOverflowInputBuffer(_ engine: KeyboardEngine) {}
}

final class InputProtectionTests: XCTestCase {
    @MainActor func testEmptyDeferralFinishesDespitePreexistingPressedKey() {
        var posted = 0
        let engine = KeyboardEngine(config: .default, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
        // A release may be consumed upstream while the provider owns input.
        _ = engine.handleKeyboardEvent(event(0, down: true), type: .keyDown)
        engine.beginInputDeferral()
        XCTAssertEqual(engine.deferredEventCount, 0)
        XCTAssertNil(engine.inputDeferralWaitReason)
        XCTAssertTrue(engine.completeInputDeferral())
        XCTAssertFalse(engine.isDeferringInput)
        XCTAssertEqual(posted, 0)
    }

    @MainActor func testTriggerHeldAcrossEmptyRecoveryCannotStartAnotherSessionOnRelease() {
        let engine = KeyboardEngine(config: .default, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let delegate = EngineDelegate()
        engine.delegate = delegate
        _ = engine.handleKeyboardEvent(event(54, down: true, flags: .maskCommand), type: .flagsChanged)
        // Window completion can restore the source before this stop gesture ends.
        engine.beginInputDeferral()
        XCTAssertTrue(engine.completeInputDeferral())
        _ = engine.handleKeyboardEvent(event(54, down: false), type: .flagsChanged)
        XCTAssertEqual(delegate.triggers, 0, "the old gesture's release must not reopen voice")
        _ = engine.handleKeyboardEvent(event(54, down: true, flags: .maskCommand), type: .flagsChanged)
        _ = engine.handleKeyboardEvent(event(54, down: false), type: .flagsChanged)
        XCTAssertEqual(delegate.triggers, 1, "the next fresh tap must still work")
    }

    @MainActor func testQianwenChordPassesBothReleasesThenFiltersOnlyRepeatedTransport() {
        var config = RimeDouConfig.default
        config.qianwenVoiceHotkey = Hotkey(keys: [.leftOption, .leftControl])
        var replayed: [CGEvent] = []
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { replayed.append($0) })
        let delegate = EngineDelegate()
        engine.delegate = delegate
        engine.setVoiceProvider(VoiceProviderRegistry.definition(for: .qianwen, config: config))
        let gesture: [(CGKeyCode, Bool, CGEventFlags)] = [(58, true, .maskAlternate), (59, true, [.maskAlternate, .maskControl]), (59, false, .maskAlternate), (58, false, [])]
        for (code, down, flags) in gesture {
            XCTAssertTrue(engine.handleKeyboardEvent(event(code, down: down, flags: flags), type: .flagsChanged) != nil)
        }
        XCTAssertEqual(delegate.providerStops, 1)
        XCTAssertEqual(engine.deferredEventCount, 0)
        for (code, down, flags) in gesture {
            XCTAssertTrue(engine.handleKeyboardEvent(event(code, down: down, flags: flags), type: .flagsChanged) == nil)
        }
        XCTAssertEqual(delegate.providerStops, 1)
        XCTAssertEqual(engine.deferredEventCount, 0)
        // Shared modifiers used for real typing must keep their complete events.
        _ = engine.handleKeyboardEvent(event(59, down: true, flags: .maskControl), type: .flagsChanged)
        _ = engine.handleKeyboardEvent(event(0, down: true, flags: .maskControl), type: .keyDown)
        _ = engine.handleKeyboardEvent(event(0, down: false, flags: .maskControl), type: .keyUp)
        _ = engine.handleKeyboardEvent(event(59, down: false), type: .flagsChanged)
        XCTAssertEqual(engine.deferredEventCount, 4)
        for (code, down, flags) in gesture {
            _ = engine.handleKeyboardEvent(event(code, down: down, flags: flags), type: .flagsChanged)
        }
        XCTAssertEqual(engine.deferredEventCount, 4, "Filtering the next voice gesture must retain the previous typing shortcut's release")
        XCTAssertTrue(engine.completeInputDeferral())
        XCTAssertEqual(replayed.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [59, 0, 0, 59])
    }

    @MainActor func testMouseTriggerSharingQianwenModifiersIsNotPhysicalProviderStop() throws {
        let config = try RimeDouConfig.load(from: Data(#"{"triggerHotkey2":"LeftControl+LeftOption+LeftCommand+Z","qianwenVoiceHotkey":"LeftOption+LeftControl"}"#.utf8))
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let delegate = EngineDelegate()
        engine.delegate = delegate
        engine.setVoiceProvider(VoiceProviderRegistry.definition(for: .qianwen, config: config))
        _ = engine.handleKeyboardEvent(event(59, down: true, flags: .maskControl), type: .flagsChanged)
        _ = engine.handleKeyboardEvent(event(58, down: true, flags: [.maskControl, .maskAlternate]), type: .flagsChanged)
        _ = engine.handleKeyboardEvent(event(55, down: true, flags: [.maskControl, .maskAlternate, .maskCommand]), type: .flagsChanged)
        XCTAssertTrue(engine.handleKeyboardEvent(event(6, down: true, flags: [.maskControl, .maskAlternate, .maskCommand]), type: .keyDown) == nil)
        XCTAssertTrue(engine.handleKeyboardEvent(event(6, down: false, flags: [.maskControl, .maskAlternate, .maskCommand]), type: .keyUp) == nil)
        _ = engine.handleKeyboardEvent(event(55, down: false, flags: [.maskControl, .maskAlternate]), type: .flagsChanged)
        _ = engine.handleKeyboardEvent(event(58, down: false, flags: .maskControl), type: .flagsChanged)
        _ = engine.handleKeyboardEvent(event(59, down: false), type: .flagsChanged)
        XCTAssertEqual(delegate.triggers, 1)
        XCTAssertEqual(delegate.providerStops, 0)
    }

    @MainActor func testLongTransportGestureDuringDeferralIsNotReplayedAsShortTap() async {
        var config = RimeDouConfig.default
        config.tapMaxDuration = 0.001
        config.qianwenVoiceHotkey = Hotkey(keys: [.leftOption, .leftControl])
        var replayed = 0
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in replayed += 1 })
        engine.setVoiceProvider(VoiceProviderRegistry.definition(for: .qianwen, config: config))
        engine.beginInputDeferral()
        _ = engine.handleKeyboardEvent(event(58, down: true, flags: .maskAlternate), type: .flagsChanged)
        _ = engine.handleKeyboardEvent(event(59, down: true, flags: [.maskAlternate, .maskControl]), type: .flagsChanged)
        try? await Task.sleep(for: .milliseconds(10))
        _ = engine.handleKeyboardEvent(event(59, down: false, flags: .maskAlternate), type: .flagsChanged)
        _ = engine.handleKeyboardEvent(event(58, down: false), type: .flagsChanged)
        XCTAssertEqual(engine.deferredEventCount, 0)
        XCTAssertTrue(engine.completeInputDeferral())
        XCTAssertEqual(replayed, 0)
    }

    @MainActor private func event(_ code: CGKeyCode, down: Bool, flags: CGEventFlags = [], marker: Int64 = 0) -> CGEvent {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        e.flags = flags
        e.setIntegerValueField(.eventSourceUserData, value: marker)
        return e
    }

    @MainActor func testDoubaoEndingFirstKeyIsDeferredSynchronouslyIncludingBareMouseActivationKey() {
        var config = RimeDouConfig.default
        config.triggerHotkey2 = Hotkey.parse("Control+Option+Command+Z")
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let delegate = EngineDelegate()
        engine.delegate = delegate
        engine.setVoiceProvider(VoiceProviderRegistry.definition(for: .doubao, config: config))
        XCTAssertTrue(engine.handleKeyboardEvent(event(6, down: true), type: .keyDown) == nil)
        XCTAssertEqual(delegate.externalEnds, 1)
        XCTAssertEqual(engine.deferredEventCount, 1)
        XCTAssertTrue(engine.handleKeyboardEvent(event(6, down: false), type: .keyUp) == nil)
        XCTAssertEqual(engine.deferredEventCount, 2)
    }

    @MainActor func testQianwenOrdinaryKeyDoesNotEndAndPhysicalStopPassesThroughOnce() {
        var config = RimeDouConfig.default
        config.qianwenVoiceHotkey = Hotkey(keys: [.rightOption])
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let delegate = EngineDelegate()
        engine.delegate = delegate
        engine.setVoiceProvider(VoiceProviderRegistry.definition(for: .qianwen, config: config))
        XCTAssertTrue(engine.handleKeyboardEvent(event(0, down: true), type: .keyDown) != nil)
        XCTAssertTrue(engine.handleKeyboardEvent(event(0, down: false), type: .keyUp) != nil)
        XCTAssertEqual(delegate.externalEnds, 0)
        XCTAssertTrue(engine.handleKeyboardEvent(event(61, down: true, flags: .maskAlternate), type: .flagsChanged) != nil)
        XCTAssertTrue(engine.handleKeyboardEvent(event(61, down: false), type: .flagsChanged) != nil)
        XCTAssertEqual(delegate.providerStops, 1)
        XCTAssertEqual(engine.deferredEventCount, 0)
        XCTAssertTrue(engine.handleKeyboardEvent(event(0, down: true), type: .keyDown) == nil)
        XCTAssertEqual(engine.deferredEventCount, 1)
        // Further transport gestures must never be replayed to reopen Qianwen.
        XCTAssertTrue(engine.handleKeyboardEvent(event(61, down: true, flags: .maskAlternate), type: .flagsChanged) == nil)
        XCTAssertTrue(engine.handleKeyboardEvent(event(61, down: false), type: .flagsChanged) == nil)
        XCTAssertEqual(delegate.providerStops, 1)
        XCTAssertEqual(engine.deferredEventCount, 1)
    }

    @MainActor func testOnlyOurMarkerIsIgnoredAndMouseSyntheticTriggerWorks() {
        let engine = KeyboardEngine(config: .default, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let delegate = EngineDelegate()
        engine.delegate = delegate
        for marker in [engine.syntheticEventMarker, 23] {
            _ = engine.handleKeyboardEvent(event(54, down: true, flags: .maskCommand, marker: marker), type: .flagsChanged)
            _ = engine.handleKeyboardEvent(event(54, down: false, marker: marker), type: .flagsChanged)
        }
        XCTAssertEqual(delegate.triggers, 1)
    }

    @MainActor func testReplayWaitsForKeyReleaseAndTagsEvents() {
        var posted: [CGEvent] = []
        let engine = KeyboardEngine(config: .default, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { posted.append($0) })
        engine.beginInputDeferral()
        _ = engine.handleKeyboardEvent(event(0, down: true), type: .keyDown)
        XCTAssertFalse(engine.completeInputDeferral())
        XCTAssertEqual(posted.count, 0)
        _ = engine.handleKeyboardEvent(event(0, down: false), type: .keyUp)
        XCTAssertTrue(engine.completeInputDeferral())
        XCTAssertEqual(posted.map { $0.type }, [.keyDown, .keyUp])
        XCTAssertTrue(posted.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == engine.syntheticEventMarker })
    }

    @MainActor func testStopDoesNotReplayBufferedInputToUnknownSource() {
        var posted = 0
        let engine = KeyboardEngine(config: .default, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
        engine.beginInputDeferral()
        _ = engine.handleKeyboardEvent(event(0, down: true), type: .keyDown)
        engine.stop()
        XCTAssertEqual(posted, 0)
        XCTAssertEqual(engine.deferredEventCount, 1)
    }

    @MainActor func testOverflowRetainsOnlyCompleteGesturesAndNeverReplaysUnmatchedDown() {
        var posted: [CGEvent] = []
        let engine = KeyboardEngine(config: .default, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { posted.append($0) })
        let delegate = EngineDelegate()
        engine.delegate = delegate
        engine.beginInputDeferral()
        _ = engine.handleKeyboardEvent(event(0, down: true), type: .keyDown)
        _ = engine.handleKeyboardEvent(event(0, down: false), type: .keyUp)
        for _ in 0..<2050 { _ = engine.handleKeyboardEvent(event(1, down: true), type: .keyDown) }
        _ = engine.handleKeyboardEvent(event(1, down: false), type: .keyUp)
        XCTAssertEqual(engine.deferredEventCount, 2)
        XCTAssertTrue(engine.completeInputDeferral())
        XCTAssertEqual(posted.map { $0.type }, [.keyDown, .keyUp])
    }

    func testBufferIsBoundedAndKeepsExistingContentOnOverflow() {
        var buffer = DeferredEventBuffer<Int>(capacity: 2)
        buffer.begin()
        XCTAssertTrue(buffer.append(1))
        XCTAssertTrue(buffer.append(2))
        XCTAssertFalse(buffer.append(3))
        XCTAssertEqual(buffer.drain(), [1, 2])
    }
}
