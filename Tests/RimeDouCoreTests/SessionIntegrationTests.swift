import AppKit
import XCTest
@testable import RimeDouCore

@MainActor
private final class FakeInputSources: InputSourceControlling {
    var current = "im.rime.inputmethod.Squirrel.Hans"
    var sourceAvailable = true
    var restores = 0
    var selects: [String] = []
    var completion: ((InputSourceRestoreResult) -> Void)?
    func currentInputSourceIdentity() -> InputSourceIdentity? { sourceAvailable ? InputSourceIdentity(identifier: current, localizedName: current, bundleIdentifier: nil) : nil }
    func hasInputSource(identifier: String) -> Bool { true }
    @discardableResult func selectInputSource(identifier: String) -> Bool { selects.append(identifier); return true }
    func cancelPendingOperations() { completion = nil }
    func restoreInputSource(identifier: String, originalApp: NSRunningApplication?, originalWindow: AXUIElement?, config: RimeDouConfig, initialDelay: TimeInterval?, completion: @escaping (InputSourceRestoreResult) -> Void) {
        restores += 1
        self.completion = completion
    }
}

@MainActor
private final class FakeWindowMonitor: ProviderWindowMonitoring {
    var hasObservedVoiceWindow = true
    var canRequestStop = true
    var windows: Set<Int>? = []
    var onIssue: ((ProviderWindowIssue) -> Void)?
    var completion: (() -> Void)?
    var waits = 0
    func currentWindows() -> Set<Int>? { windows }
    func startTracking(onIssue: @escaping (ProviderWindowIssue) -> Void) -> Bool { self.onIssue = onIssue; return true }
    func beginWaitingForGone(timeout: TimeInterval, goneStabilityDelay: TimeInterval, onCompletion: @escaping () -> Void) { waits += 1; completion = onCompletion }
    func stop() { completion = nil; onIssue = nil }
}

final class SessionIntegrationTests: XCTestCase {
    @MainActor func testMouseSideButtonKeepsQianwenStartStopAndCompletionGate() async throws {
        var config = try RimeDouConfig.load(from: Data(#"{"triggerHotkey2":"LeftShift+LeftOption+Z","qianwen_VoiceHotkey":"LeftShift+LeftControl"}"#.utf8))
        config.tapDuration = 0.001
        var posted: [CGEvent] = []
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { posted.append($0) })
        let inputs = FakeInputSources()
        let monitor = FakeWindowMonitor()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor, focusMatches: { _, _, _ in true })
        defer { coordinator.shutdown() }
        let provider = try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config))
        coordinator.onIdleTrigger = { XCTAssertTrue(coordinator.start(provider: provider, config: config)) }
        clickSideButton(engine)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(coordinator.state, .voiceActive)
        XCTAssertEqual(posted.count, 4)
        inputs.current = provider.inputSourceIdentifier
        clickSideButton(engine)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(coordinator.state, .waitingForProviderCompletion)
        XCTAssertEqual(posted.count, 8)
        clickSideButton(engine)
        XCTAssertEqual(posted.count, 8)
        XCTAssertEqual(inputs.restores, 0)
        monitor.completion?()
        XCTAssertEqual(inputs.restores, 1)
        inputs.current = "im.rime.inputmethod.Squirrel.Hans"
        inputs.completion?(.safe(inputs.current))
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(posted.contains { $0.getIntegerValueField(.keyboardEventKeycode) == 6 })
    }

    @MainActor private func clickSideButton(_ engine: KeyboardEngine) {
        for (code, down, flags, type): (CGKeyCode, Bool, CGEventFlags, CGEventType) in [
            (56, true, .maskShift, .flagsChanged),
            (58, true, [.maskShift, .maskAlternate], .flagsChanged),
            (6, true, [.maskShift, .maskAlternate], .keyDown),
            (6, false, [.maskShift, .maskAlternate], .keyUp),
            (58, false, .maskShift, .flagsChanged),
            (56, false, [], .flagsChanged)
        ] {
            let event = key(code, down)
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: 42)
            _ = engine.handleKeyboardEvent(event, type: type)
        }
    }

    @MainActor func testSideButtonQianwenEscapeEndsSessionAndAllowsNextStart() async throws {
        var config = try RimeDouConfig.load(from: Data(#"{"triggerHotkey2":"LeftShift+LeftOption+Z","qianwen_VoiceHotkey":"LeftShift+LeftControl"}"#.utf8))
        config.tapDuration = 0.001
        var posted: [CGEvent] = []
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { posted.append($0) })
        let inputs = FakeInputSources()
        let monitor = FakeWindowMonitor()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor, focusMatches: { _, _, _ in true })
        defer { coordinator.shutdown() }
        let provider = try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config))
        coordinator.onIdleTrigger = { XCTAssertTrue(coordinator.start(provider: provider, config: config)) }
        clickSideButton(engine)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(coordinator.state, .voiceActive)
        inputs.current = provider.inputSourceIdentifier
        XCTAssertTrue(engine.handleKeyboardEvent(key(53, true), type: .keyDown) != nil)
        XCTAssertTrue(engine.handleKeyboardEvent(key(53, false), type: .keyUp) != nil)
        XCTAssertEqual(coordinator.state, .waitingForProviderCompletion)
        XCTAssertEqual(engine.deferredEventCount, 0)
        XCTAssertEqual(posted.count, 4)
        monitor.completion?()
        XCTAssertEqual(inputs.restores, 1)
        inputs.current = "im.rime.inputmethod.Squirrel.Hans"
        inputs.completion?(.safe(inputs.current))
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(engine.isDeferringInput)
        XCTAssertFalse(posted.contains { $0.getIntegerValueField(.keyboardEventKeycode) == 53 })
        clickSideButton(engine)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(coordinator.state, .voiceActive)
        XCTAssertEqual(posted.count, 8)
    }

    @MainActor func testQianwenEscapeOrphanReleaseCancelsWithoutAnotherToggle() async throws {
        var config = RimeDouConfig.default
        config.qianwenVoiceHotkey = Hotkey(keys: [.leftShift, .leftControl])
        config.tapDuration = 0.001
        var posted = 0
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
        let inputs = FakeInputSources()
        let monitor = FakeWindowMonitor()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor)
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        inputs.current = VoiceProviderRegistry.qianwenInputSourceIdentifier
        XCTAssertTrue(engine.handleKeyboardEvent(key(53, false), type: .keyUp) != nil)
        XCTAssertEqual(coordinator.state, .waitingForProviderCompletion)
        monitor.completion?()
        inputs.current = "im.rime.inputmethod.Squirrel.Hans"
        inputs.completion?(.safe(inputs.current))
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(engine.deferredEventCount, 0)
        XCTAssertEqual(posted, 4)
    }

    @MainActor func testQianwenEscapeGesturesAndPostCancelInputStayOrdered() async throws {
        for scenario in ["held", "after-stop", "release-after-block", "blocked-window-closes-later", "restore-in-flight", "typing", "repeated-gesture"] {
            var config = RimeDouConfig.default
            config.qianwenVoiceHotkey = Hotkey(keys: [.leftShift, .leftControl])
            config.tapDuration = 0.001
            var posted: [CGEvent] = []
            let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { posted.append($0) })
            let inputs = FakeInputSources()
            let monitor = FakeWindowMonitor()
            let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor, focusMatches: { _, _, _ in true })
            defer { coordinator.shutdown() }
            XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config)), config: config))
            try await Task.sleep(for: .milliseconds(20))
            inputs.current = VoiceProviderRegistry.qianwenInputSourceIdentifier
            if scenario == "after-stop" {
                coordinator.keyboardEngineDidDetectTriggerTap(engine)
                try await Task.sleep(for: .milliseconds(20))
            }
            let before = posted.count
            if scenario == "release-after-block" {
                monitor.onIssue?(.windowDisappearedBeforeStop)
                XCTAssertEqual(coordinator.state, .blocked)
                XCTAssertTrue(engine.handleKeyboardEvent(key(53, false), type: .keyUp) != nil)
                coordinator.poll()
            } else if scenario == "blocked-window-closes-later" {
                monitor.onIssue?(.windowDisappearedBeforeStop)
                monitor.windows = [42]
                _ = engine.handleKeyboardEvent(key(53, true), type: .keyDown)
                _ = engine.handleKeyboardEvent(key(53, false), type: .keyUp)
                coordinator.poll()
                XCTAssertEqual(inputs.restores, 0)
                monitor.windows = []
                coordinator.poll()
            } else {
                XCTAssertTrue(engine.handleKeyboardEvent(key(53, true), type: .keyDown) != nil)
                XCTAssertEqual(coordinator.state, .waitingForProviderCompletion)
                if scenario == "held" {
                    let repeated = key(53, true)
                    repeated.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
                    XCTAssertTrue(engine.handleKeyboardEvent(repeated, type: .keyDown) != nil)
                }
                if scenario == "repeated-gesture" {
                    _ = engine.handleKeyboardEvent(key(53, false), type: .keyUp)
                    _ = engine.handleKeyboardEvent(key(53, true), type: .keyDown)
                    XCTAssertEqual(monitor.waits, 1)
                }
                if scenario == "typing" {
                    XCTAssertTrue(engine.handleKeyboardEvent(key(18, true), type: .keyDown) == nil)
                    XCTAssertTrue(engine.handleKeyboardEvent(key(18, false), type: .keyUp) == nil)
                }
                monitor.completion?()
            }
            XCTAssertEqual(inputs.restores, 1)
            if scenario == "restore-in-flight" {
                XCTAssertTrue(engine.handleKeyboardEvent(key(53, true), type: .keyDown) != nil)
                XCTAssertTrue(engine.handleKeyboardEvent(key(53, false), type: .keyUp) != nil)
                XCTAssertEqual(inputs.restores, 1)
                XCTAssertEqual(engine.deferredEventCount, 0)
            }
            inputs.current = "im.rime.inputmethod.Squirrel.Hans"
            inputs.completion?(.safe(inputs.current))
            if scenario == "typing" {
                XCTAssertEqual(coordinator.state, .restoringInputMethod)
                XCTAssertEqual(engine.deferredEventCount, 2)
            }
            XCTAssertTrue(engine.handleKeyboardEvent(key(53, false), type: .keyUp) != nil)
            coordinator.poll()
            XCTAssertEqual(coordinator.state, .idle, scenario)
            XCTAssertEqual(engine.deferredEventCount, 0, scenario)
            XCTAssertEqual(posted.count, before + (scenario == "typing" ? 2 : 0), scenario)
            XCTAssertFalse(posted.contains { $0.getIntegerValueField(.keyboardEventKeycode) == 53 }, scenario)
        }
    }

    @MainActor func testQianwenEscapeDuringStartupKeepsUnknownStateProtected() async throws {
        for scenario in ["start-not-observed", "observed-later", "gone-before-poll", "unknown-windows", "unknown-source"] {
            var config = RimeDouConfig.default
            config.qianwenVoiceHotkey = Hotkey(keys: [.leftShift, .leftControl])
            config.tapDuration = 0.001
            var posted = 0
            let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
            let inputs = FakeInputSources()
            let monitor = FakeWindowMonitor()
            monitor.hasObservedVoiceWindow = false
            let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor)
            defer { coordinator.shutdown() }
            XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config)), config: config))
            try await Task.sleep(for: .milliseconds(20))
            inputs.current = VoiceProviderRegistry.qianwenInputSourceIdentifier
            XCTAssertTrue(engine.handleKeyboardEvent(key(53, true), type: .keyDown) != nil)
            XCTAssertTrue(engine.handleKeyboardEvent(key(53, false), type: .keyUp) != nil)
            XCTAssertTrue(engine.isDeferringInput)
            if scenario == "observed-later" {
                monitor.hasObservedVoiceWindow = true
                coordinator.poll()
                XCTAssertEqual(coordinator.state, .waitingForProviderCompletion)
                monitor.completion?()
            } else {
                if scenario == "unknown-windows" { monitor.windows = nil }
                if scenario == "unknown-source" { inputs.sourceAvailable = false }
                monitor.onIssue?(scenario == "gone-before-poll" ? .windowDisappearedBeforeStop : .startNotObserved)
            }
            if scenario.hasPrefix("unknown-") {
                XCTAssertEqual(coordinator.state, .blocked)
                XCTAssertEqual(inputs.restores, 0)
            } else {
                XCTAssertEqual(inputs.restores, 1)
                inputs.current = "im.rime.inputmethod.Squirrel.Hans"
                inputs.completion?(.safe(inputs.current))
                XCTAssertEqual(coordinator.state, .idle)
            }
            XCTAssertEqual(posted, 4)
            XCTAssertEqual(engine.deferredEventCount, 0)
        }
    }

    @MainActor func testQianwenWindowLossWithoutBareEscapeStillBlocks() async throws {
        for flags: CGEventFlags in [.maskControl, .maskShift, .maskAlternate, .maskCommand] {
            var config = RimeDouConfig.default
            config.qianwenVoiceHotkey = Hotkey(keys: [.leftShift, .leftControl])
            config.tapDuration = 0.001
            var posted = 0
            let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
            let inputs = FakeInputSources()
            let monitor = FakeWindowMonitor()
            let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor)
            defer { coordinator.shutdown() }
            XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config)), config: config))
            try await Task.sleep(for: .milliseconds(20))
            for down in [true, false] {
                let event = key(53, down)
                event.flags = flags
                _ = engine.handleKeyboardEvent(event, type: down ? .keyDown : .keyUp)
            }
            let synthetic = key(53, true)
            synthetic.setIntegerValueField(.eventSourceUserData, value: engine.syntheticEventMarker)
            _ = engine.handleKeyboardEvent(synthetic, type: .keyDown)
            XCTAssertEqual(coordinator.state, .voiceActive)
            monitor.onIssue?(.windowDisappearedBeforeStop)
            XCTAssertEqual(coordinator.state, .blocked)
            XCTAssertEqual(inputs.restores, 0)
            XCTAssertEqual(posted, 4)
        }
    }

    @MainActor func testQianwenCancelRestoreFailureRetainsInputAndStopsAutomaticRetry() async throws {
        var config = RimeDouConfig.default
        config.qianwenVoiceHotkey = Hotkey(keys: [.leftShift, .leftControl])
        config.tapDuration = 0.001
        var posted = 0
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
        let inputs = FakeInputSources()
        let monitor = FakeWindowMonitor()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor)
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        inputs.current = VoiceProviderRegistry.qianwenInputSourceIdentifier
        _ = engine.handleKeyboardEvent(key(53, true), type: .keyDown)
        _ = engine.handleKeyboardEvent(key(53, false), type: .keyUp)
        _ = engine.handleKeyboardEvent(key(18, true), type: .keyDown)
        _ = engine.handleKeyboardEvent(key(18, false), type: .keyUp)
        monitor.completion?()
        inputs.completion?(.failed)
        for _ in 0..<3 { coordinator.poll() }
        XCTAssertEqual(coordinator.state, .blocked)
        XCTAssertEqual(inputs.restores, 1)
        XCTAssertEqual(engine.deferredEventCount, 2)
        XCTAssertEqual(posted, 4)
    }

    @MainActor func testFreshEscapeCancelsNextSessionAfterPreviousReleaseWasConsumed() async throws {
        var config = RimeDouConfig.default
        config.qianwenVoiceHotkey = Hotkey(keys: [.leftShift, .leftControl])
        config.tapDuration = 0.001
        var posted = 0
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
        let inputs = FakeInputSources()
        let monitor = FakeWindowMonitor()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor)
        defer { coordinator.shutdown() }
        for _ in 0..<2 {
            XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config)), config: config))
            try await Task.sleep(for: .milliseconds(20))
            inputs.current = VoiceProviderRegistry.qianwenInputSourceIdentifier
            XCTAssertTrue(engine.handleKeyboardEvent(key(53, true), type: .keyDown) != nil)
            XCTAssertEqual(coordinator.state, .waitingForProviderCompletion)
            monitor.completion?()
            inputs.current = "im.rime.inputmethod.Squirrel.Hans"
            inputs.completion?(.safe(inputs.current))
            XCTAssertEqual(coordinator.state, .idle)
        }
        XCTAssertTrue(engine.handleKeyboardEvent(key(53, false), type: .keyUp) != nil)
        XCTAssertEqual(monitor.waits, 2)
        XCTAssertEqual(posted, 8)
    }

    @MainActor func testProviderSelectionDoesNotWaitForUnrelatedKeyRelease() {
        let engine = KeyboardEngine(config: .default, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: FakeInputSources(), logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: FakeWindowMonitor())
        defer { coordinator.shutdown() }
        _ = engine.handleKeyboardEvent(key(18, true), type: .keyDown)
        XCTAssertFalse(engine.canReconfigure, "replacing the engine still waits for complete key gestures")
        XCTAssertTrue(coordinator.canSelectProvider, "choosing the next provider does not replace the keyboard engine or replay input")
        engine.beginInputDeferral()
        XCTAssertFalse(coordinator.canSelectProvider, "buffered input still protects the active destination")
    }

    @MainActor func testProviderSelectionStaysLockedDuringTransportAndVoiceSession() async throws {
        var config = RimeDouConfig.default
        config.qianwenVoiceHotkey = Hotkey(keys: [.leftOption, .leftControl])
        config.tapDuration = 0.001
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let monitor = FakeWindowMonitor()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: FakeInputSources(), logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor)
        defer { coordinator.shutdown() }
        XCTAssertTrue(engine.sendHotkey(config.voiceHotkey))
        XCTAssertFalse(coordinator.canSelectProvider)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(coordinator.canSelectProvider)
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config)), config: config))
        XCTAssertFalse(coordinator.canSelectProvider)
        try await Task.sleep(for: .milliseconds(20))
        coordinator.keyboardEngineDidDetectTriggerTap(engine)
        XCTAssertFalse(coordinator.canSelectProvider)
        monitor.onIssue?(.completionTimedOut)
        XCTAssertFalse(coordinator.canSelectProvider)
    }

    @MainActor func testIdleTriggerDoesNotReadAccessibilityInsideKeyboardCallback() async throws {
        let engine = KeyboardEngine(config: .default, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: FakeInputSources(), logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: FakeWindowMonitor())
        defer { coordinator.shutdown() }
        var callbackReturned = false
        var starts = 0
        coordinator.onIdleTrigger = {
            XCTAssertTrue(callbackReturned, "AX destination capture must run after the event tap callback returns")
            starts += 1
        }
        coordinator.keyboardEngineDidDetectTriggerTap(engine)
        callbackReturned = true
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(starts, 1)
    }

    @MainActor func testVerifiedRestoreCannotTrapTypingForeverWhenReplayIsUnavailable() async throws {
        for missingFocus in [false, true] {
            var time: TimeInterval = 10
            var config = RimeDouConfig.default
            config.qianwenVoiceHotkey = Hotkey(keys: [.leftOption, .leftControl])
            config.tapDuration = 0.001
            var posted = 0
            let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
            let inputs = FakeInputSources()
            let monitor = FakeWindowMonitor()
            let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor, now: { time }, focusMatches: { _, _, _ in !missingFocus })
            defer { coordinator.shutdown() }
            var pauses = 0
            coordinator.onRecoveryPaused = { pauses += 1 }
            XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config)), config: config))
            try await Task.sleep(for: .milliseconds(20))
            coordinator.keyboardEngineDidDetectTriggerTap(engine)
            _ = engine.handleKeyboardEvent(key(18, true), type: .keyDown)
            if missingFocus { _ = engine.handleKeyboardEvent(key(18, false), type: .keyUp) }
            try await Task.sleep(for: .milliseconds(20))
            monitor.completion?()
            inputs.completion?(.safe(inputs.current))
            XCTAssertEqual(coordinator.state, .restoringInputMethod)
            inputs.current = VoiceProviderRegistry.qianwenInputSourceIdentifier
            time += 10
            coordinator.poll()
            XCTAssertEqual(pauses, 0, "a voice or unknown source must never take the ordinary-source fallback")
            inputs.current = "im.rime.inputmethod.Squirrel.Hans"
            coordinator.poll()
            time += 6
            coordinator.poll()
            XCTAssertEqual(coordinator.state, .blocked, "a restore gate needs an escape path, not endless global interception")
            XCTAssertEqual(pauses, 1)
            coordinator.poll()
            XCTAssertEqual(pauses, 1, "suspended recovery must not keep running")
            XCTAssertNotNil(coordinator.message)
            XCTAssertEqual(engine.deferredEventCount, missingFocus ? 2 : 1, "retain the original buffer without guessing its destination or a missing release")
            XCTAssertEqual(posted, 8, "no unverified replay and no extra vendor toggle")
        }
    }

    @MainActor func testDiscardAndRecoverAfterReplayTimeoutDoesNotRequireRestart() async throws {
        for provider in VoiceProviderID.allCases {
            for scenario in ["missing-release", "changed-focus", "empty-after-discard", "before-timeout"] {
                var time: TimeInterval = 10
                var config = RimeDouConfig.default
                config.qianwenVoiceHotkey = Hotkey(keys: [.leftOption, .leftControl])
                config.tapDuration = 0.001
                var posted = 0
                let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
                let inputs = FakeInputSources()
                let monitor = FakeWindowMonitor()
                let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor, doubaoWindows: { [] }, now: { time }, focusMatches: { _, _, _ in scenario != "changed-focus" })
                defer { coordinator.shutdown() }
                XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: provider, config: config)), config: config))
                try await Task.sleep(for: .milliseconds(20))
                // Recovery is tested after a real provider stop, not an unverified
                // Doubao toggle request with no observed voice window.
                if provider == .doubao { coordinator.keyboardEngineDidDetectManagedVoiceHotkeyTap(engine) }
                else { coordinator.keyboardEngineDidDetectTriggerTap(engine) }
                _ = engine.handleKeyboardEvent(key(18, true), type: .keyDown)
                if scenario == "changed-focus" { _ = engine.handleKeyboardEvent(key(18, false), type: .keyUp) }
                try await Task.sleep(for: .milliseconds(20))
                monitor.completion?()
                inputs.completion?(.safe(inputs.current))
                if scenario == "before-timeout" {
                    XCTAssertEqual(coordinator.state, .restoringInputMethod)
                } else {
                    time += 6
                    coordinator.poll()
                    XCTAssertEqual(coordinator.state, .blocked)
                }
                if scenario == "empty-after-discard" {
                    coordinator.discardBufferedInput()
                    XCTAssertEqual(engine.deferredEventCount, 0)
                }
                let postedBeforeRecovery = posted
                XCTAssertTrue(coordinator.recoverByDiscardingInput())
                XCTAssertEqual(coordinator.state, .idle)
                XCTAssertNil(coordinator.sessionProvider)
                XCTAssertNil(coordinator.message)
                XCTAssertTrue(coordinator.canSelectProvider)
                XCTAssertFalse(engine.isDeferringInput)
                XCTAssertEqual(engine.deferredEventCount, 0)
                XCTAssertNil(engine.replayTargetPID)
                XCTAssertEqual(posted, postedBeforeRecovery, "discarding must not replay keys or send another vendor toggle")
            }
        }
    }

    @MainActor func testDiscardRecoveryAfterEarlyWindowLossDoesNotNeedPriorRestore() async throws {
        for provider in VoiceProviderID.allCases {
            var config = RimeDouConfig.default
            config.qianwenVoiceHotkey = Hotkey(keys: [.leftShift, .leftControl])
            config.tapDuration = 0.001
            var posted = 0
            let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
            let inputs = FakeInputSources()
            let monitor = FakeWindowMonitor()
            let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor, doubaoWindows: { [] })
            defer { coordinator.shutdown() }
            let definition = try XCTUnwrap(VoiceProviderRegistry.definition(for: provider, config: config))
            XCTAssertTrue(coordinator.start(provider: definition, config: config))
            try await Task.sleep(for: .milliseconds(20))
            if provider == .qianwen { monitor.onIssue?(.windowDisappearedBeforeStop) }
            else { coordinator.suspend(reason: "interrupted startup") }
            _ = engine.handleKeyboardEvent(key(18, true), type: .keyDown)
            XCTAssertEqual(coordinator.state, .blocked)
            XCTAssertEqual(inputs.restores, 0)
            let before = posted
            XCTAssertTrue(coordinator.recoverByDiscardingInput())
            XCTAssertEqual(coordinator.state, .idle)
            XCTAssertEqual(engine.deferredEventCount, 0)
            XCTAssertFalse(engine.isDeferringInput)
            XCTAssertEqual(posted, before)
            XCTAssertNil(coordinator.message)
        }
    }

    @MainActor func testDiscardRecoveryRestoresProviderSourceAfterEarlyWindowLoss() async throws {
        for provider in VoiceProviderID.allCases {
            var config = RimeDouConfig.default
            config.qianwenVoiceHotkey = Hotkey(keys: [.leftShift, .leftControl])
            config.tapDuration = 0.001
            var posted = 0
            let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
            let inputs = FakeInputSources()
            let monitor = FakeWindowMonitor()
            let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor)
            defer { coordinator.shutdown() }
            XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: provider, config: config)), config: config))
            try await Task.sleep(for: .milliseconds(20))
            inputs.current = VoiceProviderRegistry.inputSourceIdentifier(for: provider)
            if provider == .qianwen { monitor.onIssue?(.windowDisappearedBeforeStop) }
            else { coordinator.suspend(reason: "interrupted voice") }
            _ = engine.handleKeyboardEvent(key(18, true), type: .keyDown)
            let before = posted
            var completed: [Bool] = []
            XCTAssertTrue(coordinator.recoverByDiscardingInput { completed.append($0) })
            XCTAssertEqual(coordinator.state, .restoringInputMethod)
            XCTAssertEqual(inputs.restores, 1)
            XCTAssertEqual(engine.deferredEventCount, 1)
            inputs.current = "im.rime.inputmethod.Squirrel.Hans"
            inputs.completion?(.safe(inputs.current))
            XCTAssertEqual(coordinator.state, .idle)
            XCTAssertEqual(engine.deferredEventCount, 0)
            XCTAssertEqual(posted, before)
            XCTAssertEqual(completed, [true])
            XCTAssertTrue(inputs.selects.isEmpty)
        }
    }

    @MainActor func testDiscardRecoveryFailuresRemainRetryableAndKeepBufferedInput() async throws {
        for provider in VoiceProviderID.allCases {
            for scenario in ["restore-failed", "timeout", "window-reappeared", "unknown-windows", "unknown-source", "provider-source", "cancelled", "suspended", "shutdown"] {
                var time: TimeInterval = 10
                var windows: Set<Int>? = []
                var config = RimeDouConfig.default
                config.qianwenVoiceHotkey = Hotkey(keys: [.leftShift, .leftControl])
                config.tapDuration = 0.001
                var posted = 0
                let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
                let inputs = FakeInputSources()
                let monitor = FakeWindowMonitor()
                let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor, doubaoWindows: { windows }, now: { time })
                defer { coordinator.shutdown() }
                XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: provider, config: config)), config: config))
                try await Task.sleep(for: .milliseconds(20))
                coordinator.suspend(reason: "interrupted voice")
                inputs.current = VoiceProviderRegistry.inputSourceIdentifier(for: provider)
                _ = engine.handleKeyboardEvent(key(18, true), type: .keyDown)
                _ = engine.handleKeyboardEvent(key(18, false), type: .keyUp)
                let before = posted
                var completed: [Bool] = []
                XCTAssertTrue(coordinator.recoverByDiscardingInput { completed.append($0) })
                XCTAssertTrue(coordinator.isRecoveringInput)
                XCTAssertFalse(coordinator.recoverByDiscardingInput { _ in XCTFail("duplicate recovery callback") })
                XCTAssertEqual(inputs.restores, 1)
                let restoreCompletion = try XCTUnwrap(inputs.completion)
                inputs.current = "im.rime.inputmethod.Squirrel.Hans"
                switch scenario {
                case "restore-failed": restoreCompletion(.failed)
                case "timeout": time += config.switchWaitTimeout + 3; coordinator.poll()
                case "window-reappeared": windows = [42]; monitor.windows = windows; restoreCompletion(.safe(inputs.current))
                case "unknown-windows": windows = nil; monitor.windows = nil; restoreCompletion(.safe(inputs.current))
                case "unknown-source": inputs.sourceAvailable = false; restoreCompletion(.safe(inputs.current))
                case "provider-source": inputs.current = VoiceProviderRegistry.inputSourceIdentifier(for: provider); restoreCompletion(.safe(inputs.current))
                case "cancelled": restoreCompletion(.cancelled)
                case "suspended": coordinator.suspend(reason: "sleep interrupted recovery")
                case "shutdown": coordinator.shutdown()
                default: XCTFail("unknown test scenario")
                }
                XCTAssertFalse(coordinator.isRecoveringInput, scenario)
                XCTAssertEqual(completed, scenario == "shutdown" ? [] : [false], scenario)
                XCTAssertEqual(engine.deferredEventCount, 2, scenario)
                XCTAssertEqual(posted, before, scenario)
                // A late completion must preserve the failed attempt's retained input.
                restoreCompletion(.safe("im.rime.inputmethod.Squirrel.Hans"))
                XCTAssertEqual(engine.deferredEventCount, 2)
                if scenario != "shutdown" {
                    XCTAssertEqual(coordinator.state, .blocked, scenario)
                    inputs.current = "im.rime.inputmethod.Squirrel.Hans"
                    inputs.sourceAvailable = true
                    windows = []
                    monitor.windows = []
                    XCTAssertTrue(coordinator.recoverByDiscardingInput())
                    XCTAssertEqual(coordinator.state, .idle, scenario)
                    XCTAssertEqual(engine.deferredEventCount, 0)
                }
            }
        }
    }

    @MainActor func testStaleRestoreCompletionCannotFinishNewDiscardRecovery() async throws {
        var config = RimeDouConfig.default
        config.qianwenVoiceHotkey = Hotkey(keys: [.leftShift, .leftControl])
        config.tapDuration = 0.001
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let inputs = FakeInputSources()
        let monitor = FakeWindowMonitor()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor)
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        coordinator.keyboardEngineDidDetectTriggerTap(engine)
        try await Task.sleep(for: .milliseconds(20))
        monitor.completion?()
        let oldCompletion = try XCTUnwrap(inputs.completion)
        coordinator.suspend(reason: "interrupted original restore")
        inputs.current = VoiceProviderRegistry.qianwenInputSourceIdentifier
        _ = engine.handleKeyboardEvent(key(18, true), type: .keyDown)
        var completed: [Bool] = []
        XCTAssertTrue(coordinator.recoverByDiscardingInput { completed.append($0) })
        let newCompletion = try XCTUnwrap(inputs.completion)
        inputs.current = "im.rime.inputmethod.Squirrel.Hans"
        oldCompletion(.safe(inputs.current))
        XCTAssertTrue(coordinator.isRecoveringInput)
        XCTAssertEqual(coordinator.state, .restoringInputMethod)
        XCTAssertTrue(completed.isEmpty)
        XCTAssertEqual(engine.deferredEventCount, 1)
        newCompletion(.safe(inputs.current))
        XCTAssertEqual(completed, [true])
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(engine.deferredEventCount, 0)
        XCTAssertFalse(coordinator.isRecoveringInput)
    }

    @MainActor func testRecoveryRejectsUnsafeConditionsWithoutDiscardingInput() async throws {
        for provider in VoiceProviderID.allCases {
            for issue in ["unknown-source", "empty-source", "visible-window", "unknown-windows", "hotkey-sending"] {
                var time: TimeInterval = 10
                var windows: Set<Int>? = []
                var config = RimeDouConfig.default
                config.qianwenVoiceHotkey = Hotkey(keys: [.leftOption, .leftControl])
                config.tapDuration = 0.001
                var posted = 0
                let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
                let inputs = FakeInputSources()
                let monitor = FakeWindowMonitor()
                let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor, doubaoWindows: { windows }, now: { time }, focusMatches: { _, _, _ in false })
                defer { coordinator.shutdown() }
                XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: provider, config: config)), config: config))
                try await Task.sleep(for: .milliseconds(20))
                coordinator.keyboardEngineDidDetectTriggerTap(engine)
                _ = engine.handleKeyboardEvent(key(18, true), type: .keyDown)
                _ = engine.handleKeyboardEvent(key(18, false), type: .keyUp)
                try await Task.sleep(for: .milliseconds(20))
                monitor.completion?()
                inputs.completion?(.safe(inputs.current))
                time += 6
                coordinator.poll()
                XCTAssertEqual(coordinator.state, .blocked)
                if issue == "unknown-source" { inputs.sourceAvailable = false }
                if issue == "empty-source" { inputs.current = "" }
                if issue == "visible-window" { windows = [42]; monitor.windows = windows }
                if issue == "unknown-windows" { windows = nil; monitor.windows = nil }
                if issue == "hotkey-sending" { XCTAssertTrue(engine.sendHotkey(config.voiceHotkey)) }
                let postedBeforeRecovery = posted
                XCTAssertFalse(coordinator.recoverByDiscardingInput())
                XCTAssertEqual(coordinator.state, .blocked)
                XCTAssertEqual(engine.deferredEventCount, 2, "a rejected recovery must retain all input")
                XCTAssertTrue(engine.isDeferringInput)
                XCTAssertNotNil(coordinator.message)
                XCTAssertEqual(posted, postedBeforeRecovery)
            }
        }
    }

    @MainActor func testQueuedIdleStartIsCoalescedAndCancelledOnShutdown() async throws {
        let engine = KeyboardEngine(config: .default, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: FakeInputSources(), logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: FakeWindowMonitor())
        var starts = 0
        coordinator.onIdleTrigger = { starts += 1 }
        coordinator.keyboardEngineDidDetectTriggerTap(engine)
        coordinator.keyboardEngineDidDetectTriggerTap(engine)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(starts, 1)
        coordinator.keyboardEngineDidDetectTriggerTap(engine)
        coordinator.shutdown()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(starts, 1)
    }

    @MainActor func testUncertainStartupOrExistingBufferNeverFailsOpen() async throws {
        for (windows, buffered): (Set<Int>?, Bool) in [(nil, false), ([987], false), ([], true)] {
            var config = RimeDouConfig.default
            config.qianwenVoiceHotkey = Hotkey(keys: [.leftOption, .leftControl])
            config.tapDuration = 0.001
            let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
            let monitor = FakeWindowMonitor()
            monitor.hasObservedVoiceWindow = false
            let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: FakeInputSources(), logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor)
            defer { coordinator.shutdown() }
            XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config)), config: config))
            try await Task.sleep(for: .milliseconds(20))
            monitor.windows = windows
            if buffered {
                engine.beginInputDeferral()
                _ = engine.handleKeyboardEvent(key(0, true), type: .keyDown)
                _ = engine.handleKeyboardEvent(key(0, false), type: .keyUp)
            }
            monitor.onIssue?(.startNotObserved)
            XCTAssertEqual(coordinator.state, .blocked)
            XCTAssertTrue(engine.handleKeyboardEvent(key(1, true), type: .keyDown) == nil)
            XCTAssertTrue(engine.handleKeyboardEvent(key(1, false), type: .keyUp) == nil)
            XCTAssertEqual(engine.deferredEventCount, buffered ? 4 : 2)
        }
    }

    @MainActor func testUnobservedStartOnOriginalOrdinarySourceDoesNotTrapTyping() async throws {
        var config = RimeDouConfig.default
        config.qianwenVoiceHotkey = Hotkey(keys: [.leftOption, .leftControl])
        config.tapDuration = 0.001
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let inputs = FakeInputSources()
        let monitor = FakeWindowMonitor()
        monitor.hasObservedVoiceWindow = false
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor)
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        monitor.onIssue?(.startNotObserved)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(engine.isDeferringInput)
        XCTAssertTrue(engine.handleKeyboardEvent(key(0, true), type: .keyDown) != nil)
        XCTAssertTrue(engine.handleKeyboardEvent(key(0, false), type: .keyUp) != nil)
        XCTAssertEqual(engine.deferredEventCount, 0)
        XCTAssertNotNil(coordinator.message)
        XCTAssertEqual(inputs.restores, 0)
    }

    @MainActor func testManualQianwenHotkeyBeforeObservedStartIsNotAssumedToStop() async throws {
        var config = RimeDouConfig.default
        config.qianwenVoiceHotkey = Hotkey(keys: [.leftOption, .leftControl])
        config.tapDuration = 0.001
        var posted = 0
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
        let monitor = FakeWindowMonitor()
        monitor.hasObservedVoiceWindow = false
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: FakeInputSources(), logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor)
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        coordinator.keyboardEngineDidDetectManagedVoiceHotkeyTap(engine)
        XCTAssertEqual(coordinator.state, .voiceActive)
        XCTAssertFalse(engine.isDeferringInput)
        XCTAssertNil(monitor.completion)
        XCTAssertEqual(posted, 4, "the physical gesture must not generate an additional toggle")
    }

    @MainActor func testProviderReSeizingInputSourceAfterRestoreIsCorrected() async throws {
        var time: TimeInterval = 100
        var config = RimeDouConfig.default
        config.tapDuration = 0.001
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let inputs = FakeInputSources()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: FakeWindowMonitor(), now: { time })
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .doubao, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        inputs.current = VoiceProviderRegistry.doubaoInputSourceIdentifier
        coordinator.keyboardEngineDidDetectExternalVoiceEnd(engine)
        inputs.current = "im.rime.inputmethod.Squirrel.Hans"
        inputs.completion?(.safe(inputs.current))
        XCTAssertEqual(inputs.selects, [VoiceProviderRegistry.doubaoInputSourceIdentifier, "im.rime.inputmethod.Squirrel.Hans"],
                       "a verified doubao restore re-binds the input context via a real select pair")
        coordinator.poll()
        XCTAssertEqual(coordinator.state, .idle)
        // The vendor overlay re-seizes the source after the verified restore.
        inputs.current = VoiceProviderRegistry.doubaoInputSourceIdentifier
        time += 2
        coordinator.driftWatchTick()
        XCTAssertEqual(inputs.selects.dropFirst(2), ["im.rime.inputmethod.Squirrel.Hans"], "after the bounce pair, one correction per re-seizure")
        // A long vendor finalize outlasts the original window; each fight extends it.
        time += 4
        coordinator.driftWatchTick()
        XCTAssertEqual(inputs.selects.count, 4, "the watch must survive past the original 5s deadline")
        for _ in 0..<4 {
            time += 2
            coordinator.driftWatchTick()
        }
        XCTAssertEqual(inputs.selects.count, 8, "correction stays bounded")
        time += 2
        coordinator.driftWatchTick()
        XCTAssertEqual(inputs.selects.count, 8, "correction gives up visibly after the cap")
        XCTAssertEqual(coordinator.state, .idle, "drift correction never disturbs the session state")
    }

    @MainActor func testDriftWatchStopsWhenUserSettlesOnOrdinarySource() async throws {
        var config = RimeDouConfig.default
        config.tapDuration = 0.001
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let inputs = FakeInputSources()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: FakeWindowMonitor())
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .doubao, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        inputs.current = VoiceProviderRegistry.doubaoInputSourceIdentifier
        coordinator.keyboardEngineDidDetectExternalVoiceEnd(engine)
        inputs.current = "com.apple.keylayout.ABC"
        inputs.completion?(.safe(inputs.current))
        coordinator.poll()
        XCTAssertEqual(coordinator.state, .idle)
        // The bounce pair ran at restore completion; afterwards the user's chosen
        // ordinary source is never yanked back by the drift watch.
        XCTAssertEqual(inputs.selects, [VoiceProviderRegistry.doubaoInputSourceIdentifier, "im.rime.inputmethod.Squirrel.Hans"])
        coordinator.driftWatchTick()
        XCTAssertEqual(inputs.selects.count, 2)
    }

    @MainActor func testRestoreThatNeverReportsBackBlocksVisibly() async throws {
        var time: TimeInterval = 10
        var config = RimeDouConfig.default
        config.tapDuration = 0.001
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let inputs = FakeInputSources()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: FakeWindowMonitor(), now: { time })
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .doubao, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        inputs.current = VoiceProviderRegistry.doubaoInputSourceIdentifier
        // Ordinary-key stop starts the legacy restore; the fake never completes,
        // mirroring the silently vanished restore task observed on 2026-09-12.
        coordinator.keyboardEngineDidDetectExternalVoiceEnd(engine)
        XCTAssertEqual(coordinator.state, .restoringInputMethod)
        time += config.switchWaitTimeout + 2.1
        coordinator.poll()
        XCTAssertEqual(coordinator.state, .blocked, "a stuck restore must surface, not swallow keys forever")
        XCTAssertTrue(coordinator.message?.contains("恢复输入法超时") == true)
    }

    @MainActor func testDoubaoStartRefusesWhileDoubaoVoiceMayBeRunning() async throws {
        var config = RimeDouConfig.default
        config.tapDuration = 0.001
        var posted = 0
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
        let inputs = FakeInputSources()
        // A previous doubao voice session may still be running after an interrupted
        // recovery (2026-09-12): the input source is still doubao. A transport tap
        // now would toggle that voice OFF instead of starting a new one.
        inputs.current = VoiceProviderRegistry.doubaoInputSourceIdentifier
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: FakeWindowMonitor())
        defer { coordinator.shutdown() }
        XCTAssertFalse(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .doubao, config: config)), config: config))
        XCTAssertEqual(coordinator.state, .idle, "no session must be created on top of a possibly running voice")
        XCTAssertEqual(posted, 0, "no transport tap may be sent while doubao may already be listening")
        XCTAssertNotNil(coordinator.message)
        // Once the user is back on an ordinary source, starting works again.
        inputs.current = "im.rime.inputmethod.Squirrel.Hans"
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .doubao, config: config)), config: config))
    }

    @MainActor func testStrayModifierFlagChangeDoesNotEndDoubaoVoice() async throws {
        var config = RimeDouConfig.default
        config.tapDuration = 0.001
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let inputs = FakeInputSources()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: FakeWindowMonitor())
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .doubao, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        inputs.current = VoiceProviderRegistry.doubaoInputSourceIdentifier
        // Session-level tooling emits lone modifier flagsChanged events (observed
        // 2026-09-12: stray left-control taps killed a doubao session 5ms in).
        // A modifier-only tap is not the user typing and must not end the voice.
        let stray = key(59, true)
        stray.flags = .maskControl
        _ = engine.handleKeyboardEvent(stray, type: .flagsChanged)
        _ = engine.handleKeyboardEvent(key(59, false), type: .flagsChanged)
        XCTAssertEqual(coordinator.state, .voiceActive, "a modifier-only tap is not typing")
        XCTAssertEqual(inputs.restores, 0)
        _ = engine.handleKeyboardEvent(key(0, true), type: .keyDown)
        XCTAssertEqual(coordinator.state, .restoringInputMethod, "a real key press still ends voice promptly")
        XCTAssertEqual(inputs.restores, 1)
    }

    @MainActor func testInputSourceSwitchShortcutDoesNotEndDoubaoVoice() async throws {
        var config = RimeDouConfig.default
        config.tapDuration = 0.001
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let inputs = FakeInputSources()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: FakeWindowMonitor())
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .doubao, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        inputs.current = VoiceProviderRegistry.doubaoInputSourceIdentifier
        // Doubao's own voice startup synthesizes Ctrl+Space (the macOS input-source
        // hotkey) to select itself (observed 2026-09-12, 10ms after session start).
        // A shortcut-modified keyDown is not typing and must not end the voice.
        let inputSwitch = key(49, true)
        inputSwitch.flags = .maskControl
        _ = engine.handleKeyboardEvent(inputSwitch, type: .keyDown)
        _ = engine.handleKeyboardEvent(key(49, false), type: .keyUp)
        XCTAssertEqual(coordinator.state, .voiceActive, "an input-source switch shortcut is not typing")
        XCTAssertEqual(inputs.restores, 0)
        // Shifted typing is still typing.
        let capital = key(0, true)
        capital.flags = .maskShift
        _ = engine.handleKeyboardEvent(capital, type: .keyDown)
        XCTAssertEqual(coordinator.state, .restoringInputMethod, "shifted typing still ends voice promptly")
        XCTAssertEqual(inputs.restores, 1)
    }

    @MainActor func testOrphanKeyUpAfterVendorConsumedKeyDownEndsDoubaoVoice() async throws {
        var config = RimeDouConfig.default
        config.tapDuration = 0.001
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let inputs = FakeInputSources()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: FakeWindowMonitor())
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .doubao, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        inputs.current = VoiceProviderRegistry.doubaoInputSourceIdentifier
        // While doubao's overlay listens it consumes ordinary keyDowns above the
        // session layer (observed 2026-09-12); only the keyUp still arrives.
        // A keyUp with no matching seen keyDown can only mean the vendor took the
        // key and the voice is over — the session must restore, not hang.
        _ = engine.handleKeyboardEvent(key(40, false), type: .keyUp)
        XCTAssertEqual(coordinator.state, .restoringInputMethod, "an orphan keyUp must end the vendor-consumed voice")
        XCTAssertEqual(inputs.restores, 1)
    }

    @MainActor func testMissingTriggerKeyUpIsReconciledFromSystemModifierFlags() async throws {
        var time: TimeInterval = 100
        var windows: Set<Int> = []
        var config = RimeDouConfig.default
        config.tapDuration = 0.001
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let inputs = FakeInputSources()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: FakeWindowMonitor(), doubaoWindows: { windows }, now: { time })
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .doubao, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        inputs.current = VoiceProviderRegistry.doubaoInputSourceIdentifier
        windows = [10]
        coordinator.poll()
        // The user presses right-Command to stop; HID-level tooling ate the keyUp
        // (observed 2026-09-12 22:41). Only the down reaches the engine.
        let down = key(54, true)
        down.flags = .maskCommand
        _ = engine.handleKeyboardEvent(down, type: .flagsChanged)
        XCTAssertEqual(coordinator.state, .voiceActive, "the incomplete gesture alone must not stop the voice")
        // The system's live modifier flags say the key is up: reconstruct the tap.
        XCTAssertTrue(engine.reconcileTriggerGestures(), "the consumed release must be reconstructed from live flags")
        XCTAssertEqual(coordinator.state, .waitingForProviderCompletion, "the reconstructed tap requests stop and waits for commit")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(inputs.restores, 0)
        windows = []
        coordinator.poll()
        time += 0.3
        coordinator.poll()
        XCTAssertEqual(inputs.restores, 1)
    }

    @MainActor private func key(_ code: CGKeyCode, _ down: Bool) -> CGEvent {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        e.flags = []
        return e
    }

    @MainActor func testQianwenStopDefersUntilCompletionAndVerifiedRestore() async throws {
        var config = RimeDouConfig.default
        config.qianwenVoiceHotkey = Hotkey(keys: [.rightOption])
        config.tapDuration = 0.001
        var posted: [CGEvent] = []
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { posted.append($0) })
        let inputs = FakeInputSources()
        let monitor = FakeWindowMonitor()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor, focusMatches: { _, _, _ in true })
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config)), config: config))
        // Overlapping trigger while transport keyDown/keyUp is in flight does nothing.
        coordinator.keyboardEngineDidDetectTriggerTap(engine)
        XCTAssertEqual(coordinator.state, .voiceActive)
        try await Task.sleep(for: .milliseconds(20))
        inputs.current = VoiceProviderRegistry.qianwenInputSourceIdentifier
        coordinator.keyboardEngineDidDetectTriggerTap(engine)
        XCTAssertEqual(coordinator.state, .waitingForProviderCompletion)
        XCTAssertEqual(inputs.restores, 0)
        XCTAssertTrue(engine.handleKeyboardEvent(key(0, true), type: .keyDown) == nil)
        XCTAssertTrue(engine.handleKeyboardEvent(key(0, false), type: .keyUp) == nil)
        XCTAssertEqual(engine.deferredEventCount, 2)
        for _ in 0..<5 { coordinator.keyboardEngineDidDetectTriggerTap(engine) }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(posted.count, 4, "one complete start and one complete stop")
        monitor.completion?()
        XCTAssertEqual(inputs.restores, 1)
        XCTAssertEqual(posted.count, 4, "buffer must not replay before verified restore")
        inputs.current = "im.rime.inputmethod.Squirrel.Hans"
        inputs.completion?(.safe(inputs.current))
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(posted.count, 6, "4 transport events + 2 replayed inputs; no synthetic flush of any kind")
    }

    @MainActor func testPhysicalQianwenStopIsNotSynthesizedAgain() async throws {
        var config = RimeDouConfig.default
        config.qianwenVoiceHotkey = Hotkey(keys: [.rightOption])
        config.tapDuration = 0.001
        var posted = 0
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
        let inputs = FakeInputSources()
        let monitor = FakeWindowMonitor()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor)
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        inputs.current = VoiceProviderRegistry.qianwenInputSourceIdentifier
        let down = key(61, true)
        down.flags = .maskAlternate
        XCTAssertTrue(engine.handleKeyboardEvent(down, type: .flagsChanged) != nil)
        XCTAssertTrue(engine.handleKeyboardEvent(key(61, false), type: .flagsChanged) != nil)
        XCTAssertEqual(coordinator.state, .waitingForProviderCompletion)
        XCTAssertEqual(posted, 2, "only the start transport was synthesized")
        XCTAssertEqual(engine.deferredEventCount, 0, "physical stop release must pass through")
        XCTAssertTrue(engine.handleKeyboardEvent(key(0, true), type: .keyDown) == nil)
        XCTAssertEqual(engine.deferredEventCount, 1)
    }

    @MainActor func testUnverifiedStartDoesNotReceiveBlindSecondToggle() async throws {
        var config = RimeDouConfig.default
        config.qianwenVoiceHotkey = Hotkey(keys: [.rightOption])
        config.tapDuration = 0.001
        var posted = 0
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
        let monitor = FakeWindowMonitor()
        monitor.hasObservedVoiceWindow = false
        let inputs = FakeInputSources()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor)
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        coordinator.keyboardEngineDidDetectTriggerTap(engine)
        XCTAssertEqual(posted, 2)
        XCTAssertEqual(coordinator.state, .voiceActive)
        inputs.current = VoiceProviderRegistry.qianwenInputSourceIdentifier
        monitor.onIssue?(.startNotObserved)
        XCTAssertEqual(coordinator.state, .blocked)
    }

    @MainActor func testRestoreFailureRetainsBufferAndBlocksNewSession() async throws {
        var config = RimeDouConfig.default
        config.tapDuration = 0.001
        var posted = 0
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
        let inputs = FakeInputSources()
        let monitor = FakeWindowMonitor()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor)
        defer { coordinator.shutdown() }
        let provider = try XCTUnwrap(VoiceProviderRegistry.definition(for: .doubao, config: config))
        XCTAssertTrue(coordinator.start(provider: provider, config: config))
        try await Task.sleep(for: .milliseconds(20))
        inputs.current = provider.inputSourceIdentifier
        _ = engine.handleKeyboardEvent(key(0, true), type: .keyDown)
        _ = engine.handleKeyboardEvent(key(0, false), type: .keyUp)
        XCTAssertEqual(inputs.restores, 1, "Doubao restores without a completion window")
        inputs.completion?(.failed)
        XCTAssertEqual(coordinator.state, .blocked)
        XCTAssertEqual(engine.deferredEventCount, 2)
        XCTAssertEqual(posted, 2, "no extra Doubao toggle and no unsafe replay")
        XCTAssertFalse(coordinator.start(provider: provider, config: config))
    }

    @MainActor func testQianwenTimeoutDoesNotRestoreOrRetryToggle() async throws {
        var config = RimeDouConfig.default
        config.qianwenVoiceHotkey = Hotkey(keys: [.rightOption])
        config.tapDuration = 0.001
        var posted = 0
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in posted += 1 })
        let inputs = FakeInputSources()
        let monitor = FakeWindowMonitor()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: monitor)
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        inputs.current = VoiceProviderRegistry.qianwenInputSourceIdentifier
        coordinator.keyboardEngineDidDetectTriggerTap(engine)
        try await Task.sleep(for: .milliseconds(20))
        monitor.onIssue?(.completionTimedOut)
        coordinator.keyboardEngineDidDetectTriggerTap(engine)
        coordinator.requestFinishForQuit()
        XCTAssertEqual(coordinator.state, .blocked)
        XCTAssertEqual(inputs.restores, 0)
        XCTAssertEqual(posted, 4)
    }

    @MainActor func testFocusChangeRetainsInputUntilOriginalFieldReturns() async throws {
        var config = RimeDouConfig.default
        config.tapDuration = 0.001
        var safeFocus = false
        let engine = KeyboardEngine(config: config, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), postEvent: { _ in })
        let inputs = FakeInputSources()
        let coordinator = VoiceSessionCoordinator(keyboard: engine, inputMethods: inputs, logger: RimeDouLogger(url: URL(fileURLWithPath: "/dev/null")), monitor: FakeWindowMonitor(), focusMatches: { _, _, _ in safeFocus })
        defer { coordinator.shutdown() }
        XCTAssertTrue(coordinator.start(provider: try XCTUnwrap(VoiceProviderRegistry.definition(for: .doubao, config: config)), config: config))
        try await Task.sleep(for: .milliseconds(20))
        inputs.current = VoiceProviderRegistry.doubaoInputSourceIdentifier
        _ = engine.handleKeyboardEvent(key(0, true), type: .keyDown)
        _ = engine.handleKeyboardEvent(key(0, false), type: .keyUp)
        inputs.current = "im.rime.inputmethod.Squirrel.Hans"
        inputs.completion?(.safe(inputs.current))
        XCTAssertEqual(engine.deferredEventCount, 2)
        safeFocus = true
        coordinator.poll()
        XCTAssertEqual(engine.deferredEventCount, 0)
        XCTAssertEqual(coordinator.state, .idle)
    }
}
