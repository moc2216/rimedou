import AppKit
import XCTest
@testable import RimeDouCore

@MainActor
private final class DoubaoInputs: InputSourceControlling {
    var current = "im.rime.inputmethod.Squirrel.Hans"
    var delays: [TimeInterval?] = []
    var selects: [String] = []
    var completion: ((InputSourceRestoreResult) -> Void)?
    func currentInputSourceIdentity() -> InputSourceIdentity? { InputSourceIdentity(identifier: current, localizedName: current, bundleIdentifier: nil) }
    func hasInputSource(identifier: String) -> Bool { true }
    func selectInputSource(identifier: String) -> Bool { selects.append(identifier); return true }
    func cancelPendingOperations() { completion = nil }
    func restoreInputSource(identifier: String, originalApp: NSRunningApplication?, originalWindow: AXUIElement?, config: RimeDouConfig, initialDelay: TimeInterval?, completion: @escaping (InputSourceRestoreResult) -> Void) {
        delays.append(initialDelay)
        self.completion = completion
    }
}

@MainActor
private final class DoubaoFixture {
    var time: TimeInterval = 100
    var windows: Set<Int>? = []
    var posts = 0
    var postedEvents: [CGEvent] = []
    var pauses = 0
    let inputs = DoubaoInputs()
    let logger = RimeDouLogger(url: URL(fileURLWithPath: "/dev/null"))
    var config: RimeDouConfig = {
        var c = RimeDouConfig.default
        c.tapDuration = 0.001
        c.restoreDelay = 1
        return c
    }()
    lazy var keyboard = KeyboardEngine(config: config, logger: logger, postEvent: { [weak self] event in
        self?.posts += 1
        self?.postedEvents.append(event)
    })
    lazy var coordinator = VoiceSessionCoordinator(keyboard: keyboard, inputMethods: inputs, logger: logger,
        doubaoWindows: { [weak self] in self?.windows }, now: { [weak self] in self?.time ?? 0 }, focusMatches: { _, _, _ in true })
    func start() async throws {
        coordinator.onRecoveryPaused = { [weak self] in self?.pauses += 1 }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .doubao, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        inputs.current = VoiceProviderRegistry.doubaoInputSourceIdentifier
    }
    func sample(_ windows: Set<Int>?, after delta: TimeInterval = 0.1) {
        time += delta
        self.windows = windows
        coordinator.poll()
    }
    func finishRestore() {
        inputs.current = "im.rime.inputmethod.Squirrel.Hans"
        inputs.completion?(.safe(inputs.current))
    }
    func key(_ code: CGKeyCode, down: Bool) -> CGEvent? {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = []
        return keyboard.handleKeyboardEvent(event, type: down ? .keyDown : .keyUp)?.takeUnretainedValue()
    }
    func modifier(_ code: CGKeyCode, down: Bool, flags: CGEventFlags = []) -> CGEvent? {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = flags
        return keyboard.handleKeyboardEvent(event, type: .flagsChanged)?.takeUnretainedValue()
    }
    func mouseTap() {
        _ = modifier(56, down: true, flags: .maskShift)
        _ = modifier(58, down: true, flags: [.maskShift, .maskAlternate])
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 6, keyDown: down)!
            event.flags = [.maskShift, .maskAlternate]
            event.setIntegerValueField(.eventSourceUserData, value: 42) // External remapper, not RimeDou.
            XCTAssertTrue(keyboard.handleKeyboardEvent(event, type: down ? .keyDown : .keyUp) == nil)
        }
        _ = modifier(58, down: false, flags: .maskShift)
        _ = modifier(56, down: false)
    }
}

final class DoubaoCompletionTests: XCTestCase {
    @MainActor func testMouseSideButtonStartsThenSendsOneStopAndWaitsForCompletion() async throws {
        let f = DoubaoFixture()
        f.config.triggerHotkey2 = Hotkey.parse("LeftShift+LeftOption+Z")
        defer { f.coordinator.shutdown() }
        let provider = try XCTUnwrap(VoiceProviderRegistry.definition(for: .doubao, config: f.config))
        f.coordinator.onIdleTrigger = { XCTAssertTrue(f.coordinator.start(provider: provider, config: f.config)) }
        f.mouseTap()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(f.coordinator.state, .voiceActive)
        XCTAssertEqual(f.posts, 2)
        f.inputs.current = provider.inputSourceIdentifier
        f.sample([10])
        f.mouseTap()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(f.coordinator.state, .waitingForProviderCompletion)
        XCTAssertEqual(f.posts, 4, "start and stop must each send one complete RightControl tap")
        XCTAssertEqual(f.postedEvents.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [62, 62, 62, 62])
        f.mouseTap()
        f.sample([10], after: 3)
        XCTAssertEqual(f.posts, 4, "repeated side clicks while processing must not toggle again")
        XCTAssertTrue(f.inputs.delays.isEmpty)
        f.sample([])
        f.sample([], after: 0.3)
        XCTAssertEqual(f.inputs.delays.count, 1)
        f.finishRestore()
        XCTAssertEqual(f.coordinator.state, .idle)
        XCTAssertEqual(f.keyboard.deferredEventCount, 0)
        XCTAssertFalse(f.postedEvents.contains { $0.getIntegerValueField(.keyboardEventKeycode) == 6 }, "mouse shortcut Z must never replay as text")
    }

    @MainActor func testPrimaryTriggerAlsoRequestsOneDoubaoStop() async throws {
        let f = DoubaoFixture()
        defer { f.coordinator.shutdown() }
        try await f.start()
        f.sample([10])
        _ = f.modifier(54, down: true, flags: .maskCommand)
        _ = f.modifier(54, down: false)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(f.posts, 4)
        XCTAssertEqual(f.coordinator.state, .waitingForProviderCompletion)
        XCTAssertTrue(f.inputs.delays.isEmpty)
    }

    @MainActor func testNativeDoubaoStopPassesThroughWithoutAnotherToggle() async throws {
        let f = DoubaoFixture()
        defer { f.coordinator.shutdown() }
        try await f.start()
        f.sample([10])
        XCTAssertNotNil(f.modifier(62, down: true, flags: .maskControl))
        XCTAssertNotNil(f.modifier(62, down: false))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(f.posts, 2, "the vendor already received its physical stop")
        XCTAssertEqual(f.coordinator.state, .waitingForProviderCompletion)
        XCTAssertEqual(f.keyboard.deferredEventCount, 0)
        f.sample([])
        f.sample([], after: 0.3)
        f.finishRestore()
        XCTAssertEqual(f.coordinator.state, .idle)
        XCTAssertEqual(f.posts, 2)
    }

    @MainActor func testRequestedStopDoesNotToggleAfterWindowAlreadyDisappeared() async throws {
        let f = DoubaoFixture()
        defer { f.coordinator.shutdown() }
        try await f.start()
        f.sample([10])
        f.windows = [] // Vendor stopped between the last poll and the second click.
        f.coordinator.keyboardEngineDidDetectTriggerTap(f.keyboard)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(f.posts, 2)
        f.sample([], after: 0.3)
        XCTAssertEqual(f.inputs.delays.count, 1)
    }

    @MainActor func testUnknownOrUnobservedWindowNeverReceivesBlindStopToggle() async throws {
        for observed in [false, true] {
            let f = DoubaoFixture()
            defer { f.coordinator.shutdown() }
            try await f.start()
            if observed { f.sample([10]); f.windows = nil }
            f.coordinator.keyboardEngineDidDetectTriggerTap(f.keyboard)
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertEqual(f.posts, 2)
            XCTAssertEqual(f.inputs.delays.count, observed ? 0 : 1)
            XCTAssertEqual(f.coordinator.state, observed ? .waitingForProviderCompletion : .restoringInputMethod,
                           "unknown windows retain the existing bounded-wait/restore fallback")
        }
    }

    @MainActor func testMissingEntireStopGestureRestoresAfterWindowGoneWithoutOrdinaryKey() async throws {
        let f = DoubaoFixture()
        defer { f.coordinator.shutdown() }
        try await f.start()
        f.sample([293])
        f.sample([293], after: 90) // Recording duration is not a completion timeout.
        XCTAssertTrue(f.inputs.delays.isEmpty)
        f.sample([])
        f.sample([], after: 0.3)
        XCTAssertEqual(f.inputs.delays.count, 1, "no stop gesture or ordinary key reached RimeDou")
        XCTAssertEqual(f.inputs.delays.first ?? nil, 0, "confirmed completion must not add the old one-second delay")
        XCTAssertEqual(f.posts, 2, "only the start hotkey; no blind stop toggle")
        f.finishRestore()
        XCTAssertEqual(f.coordinator.state, .idle)
        XCTAssertTrue(f.inputs.selects.isEmpty, "do not reselect Doubao after its completed window lifecycle")
        XCTAssertNotNil(f.key(26, down: true))
        XCTAssertNotNil(f.key(26, down: false))
        XCTAssertEqual(f.keyboard.deferredEventCount, 0)
        XCTAssertEqual(f.inputs.delays.count, 1)
    }

    @MainActor func testObservedStopWaitsForProcessingAndCompletesOnlyOnce() async throws {
        let f = DoubaoFixture()
        defer { f.coordinator.shutdown() }
        try await f.start()
        f.sample([10])
        f.coordinator.keyboardEngineDidDetectTriggerTap(f.keyboard)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(f.coordinator.state, .waitingForProviderCompletion)
        XCTAssertTrue(f.inputs.delays.isEmpty)
        f.sample([10], after: 3)
        XCTAssertTrue(f.inputs.delays.isEmpty)
        f.sample([])
        f.sample([], after: 0.3)
        f.coordinator.keyboardEngineDidDetectExternalVoiceEnd(f.keyboard)
        f.coordinator.keyboardEngineDidDetectTriggerTap(f.keyboard)
        f.sample([], after: 1)
        XCTAssertEqual(f.inputs.delays.count, 1)
        f.finishRestore()
        f.sample([], after: 1)
        XCTAssertEqual(f.inputs.delays.count, 1)
        XCTAssertEqual(f.coordinator.state, .idle)
        XCTAssertEqual(f.posts, 4)
    }

    @MainActor func testFirstKeyDuringGoneConfirmationReplaysOnceAfterVerifiedRestore() async throws {
        let f = DoubaoFixture()
        defer { f.coordinator.shutdown() }
        try await f.start()
        f.sample([10])
        f.sample([])
        XCTAssertNil(f.key(26, down: true))
        XCTAssertNil(f.key(26, down: false))
        XCTAssertTrue(f.inputs.delays.isEmpty, "first key must not bypass completion confirmation")
        f.sample([], after: 0.3)
        XCTAssertEqual(f.inputs.delays.count, 1)
        XCTAssertEqual(f.posts, 2)
        f.finishRestore()
        XCTAssertEqual(f.posts, 4, "one start gesture and one complete replayed digit")
        XCTAssertEqual(f.keyboard.deferredEventCount, 0)
        f.sample([], after: 1)
        XCTAssertEqual(f.posts, 4)
    }

    @MainActor func testBaselineFlickerReplacementAndFailedReadCannotPrematurelyComplete() async throws {
        let f = DoubaoFixture()
        f.windows = [1]
        defer { f.coordinator.shutdown() }
        try await f.start()
        f.sample([])
        f.sample([], after: 1)
        XCTAssertTrue(f.inputs.delays.isEmpty, "baseline or never-seen voice is not completion")
        f.sample([1, 2])
        f.sample([1])
        f.sample(nil, after: 0.3)
        f.sample([1])
        f.sample([1, 3], after: 0.1)
        f.sample([1, 3], after: 1)
        XCTAssertTrue(f.inputs.delays.isEmpty)
        f.sample([1])
        f.sample([1], after: 0.3)
        XCTAssertEqual(f.inputs.delays.count, 1)
    }

    @MainActor func testUnavailableWindowObservationKeepsOrdinaryKeyStopFallback() async throws {
        let f = DoubaoFixture()
        f.windows = nil
        defer { f.coordinator.shutdown() }
        try await f.start()
        _ = f.key(26, down: true)
        _ = f.key(26, down: false)
        XCTAssertEqual(f.inputs.delays.count, 1)
        XCTAssertEqual(f.inputs.delays.first ?? nil, 1)
    }

    @MainActor func testOrdinaryKeyWhileWindowVisibleKeepsLegacyStop() async throws {
        let f = DoubaoFixture()
        defer { f.coordinator.shutdown() }
        try await f.start()
        f.sample([10])
        _ = f.key(26, down: true)
        _ = f.key(26, down: false)
        // This key is intercepted for replay, so it may never reach Doubao to
        // close its window. Do not deadlock by waiting for that same window.
        XCTAssertEqual(f.coordinator.state, .restoringInputMethod)
        XCTAssertEqual(f.inputs.delays.count, 1)
        XCTAssertEqual(f.inputs.delays.first ?? nil, 1)
        XCTAssertEqual(f.keyboard.deferredEventCount, 2)
    }

    @MainActor func testFailedRestoreDoesNotReleaseBufferedKey() async throws {
        let f = DoubaoFixture()
        defer { f.coordinator.shutdown() }
        try await f.start()
        f.sample([10])
        f.sample([])
        _ = f.key(26, down: true)
        _ = f.key(26, down: false)
        f.sample([], after: 0.3)
        f.inputs.completion?(.failed)
        XCTAssertEqual(f.coordinator.state, .blocked)
        XCTAssertEqual(f.keyboard.deferredEventCount, 2)
        XCTAssertEqual(f.posts, 2)
    }

    @MainActor func testNewSessionCannotUsePreviousWindowCompletion() async throws {
        let f = DoubaoFixture()
        defer { f.coordinator.shutdown() }
        try await f.start()
        f.sample([10])
        f.sample([])
        f.sample([], after: 0.3)
        f.finishRestore()
        try await f.start()
        f.sample([], after: 1)
        XCTAssertEqual(f.coordinator.state, .voiceActive)
        XCTAssertEqual(f.inputs.delays.count, 1)
        f.sample([10]) // Reused window ID belongs to the new baseline/session.
        f.sample([])
        f.sample([], after: 0.3)
        XCTAssertEqual(f.inputs.delays.count, 2)
    }

    @MainActor func testExplicitStopTimeoutPausesInsteadOfInterceptingForever() async throws {
        let f = DoubaoFixture()
        defer { f.coordinator.shutdown() }
        try await f.start()
        f.sample([10])
        f.coordinator.keyboardEngineDidDetectTriggerTap(f.keyboard)
        _ = f.key(26, down: true)
        _ = f.key(26, down: false)
        f.sample(nil, after: 61)
        XCTAssertEqual(f.pauses, 1)
        XCTAssertTrue(f.inputs.delays.isEmpty)
        XCTAssertEqual(f.keyboard.deferredEventCount, 2)
        f.sample([], after: 2)
        XCTAssertEqual(f.pauses, 1)
        XCTAssertTrue(f.inputs.delays.isEmpty)
    }

    @MainActor func testShutdownStopsPendingWindowRecovery() async throws {
        let f = DoubaoFixture()
        try await f.start()
        f.sample([10])
        f.sample([])
        f.coordinator.shutdown()
        f.sample([], after: 1)
        XCTAssertTrue(f.inputs.delays.isEmpty)
    }
}
