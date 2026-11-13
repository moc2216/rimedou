import AppKit
import Foundation

/// Local orchestration for the two supported vendors. All event decisions remain
/// synchronous on the main run loop; only window polling and restoration are async.
@MainActor
public final class VoiceSessionCoordinator: KeyboardEngineDelegate {
    private struct Session {
        let snapshot: VoiceSessionSnapshot
        let app: NSRunningApplication?
        let window: AXUIElement?
        let element: AXUIElement?
        var stopSent = false
        var cancelRequested = false
    }

    public let keyboard: KeyboardEngine
    private let inputMethods: any InputSourceControlling
    private let logger: RimeDouLogger
    private let monitor: any ProviderWindowMonitoring
    private let doubaoWindows: () -> Set<Int>?
    private var doubaoTracker: ProviderWindowLifecycleTracker?
    private var doubaoStopStartedAt: TimeInterval?
    private let focusMatches: (NSRunningApplication?, AXUIElement?, AXUIElement?) -> Bool
    private var machine = VoiceStateMachine()
    private var session: Session?
    private var timer: Timer?
    private var suspended = false
    private var commitConfirmed = false
    private var restoreVerified = false
    private var safeSince: TimeInterval?
    private let now: () -> TimeInterval
    private var replayWaitingSince: TimeInterval?
    private var replayWaitReason: String?
    private var idleTriggerPending = false
    private var lastOrdinarySource: String?
    private var restoreStartedAt: TimeInterval?
    private var restoreAttempt: UUID?
    private var discardRecoveryCompletion: ((Bool) -> Void)?
    private var driftWatchTimer: Timer?
    private var driftWatchTarget: String?
    private var driftWatchRetries = 0
    private var driftWatchUntil: TimeInterval = 0
    private var driftWatchStartedAt: TimeInterval = 0
    public private(set) var message: String?
    public var onChange: (() -> Void)?
    public var onIdleTrigger: (() -> Void)?
    public var onRecoveryPaused: (() -> Void)?
    public var state: VoiceState { machine.state }
    public var sessionProvider: VoiceProviderID? { session?.snapshot.provider.id }
    public var isRecoveringInput: Bool { discardRecoveryCompletion != nil }
    // Selecting a provider changes the next session, not the live keyboard engine.
    // Unrelated held-key bookkeeping must not disable a mouse-driven menu choice.
    public var canSelectProvider: Bool {
        state == .idle && !keyboard.isSendingHotkey && !keyboard.isDeferringInput
    }

    public init(keyboard: KeyboardEngine, inputMethods: any InputSourceControlling, logger: RimeDouLogger,
                monitor: any ProviderWindowMonitoring = QianwenWindowMonitor(),
                doubaoWindows: @escaping () -> Set<Int>? = { DoubaoWindowQuery.visibleWindowIDs() },
                now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                focusMatches: @escaping (NSRunningApplication?, AXUIElement?, AXUIElement?) -> Bool = { app, window, _ in
        // The focused window is the replay boundary. Requiring frontmost app plus
        // element identity proved too strict in real voice sessions (2026-09-12:
        // doubao's commit-time focus churn blocked same-document replays and put
        // the ending key in 5s pause limbo). Replaying into the original window
        // can never lose text; a different window still retains the buffer.
        guard let window,
              let focused = InputMethodController.focusedWindow(for: app) else { return false }
        return CFEqual(window, focused)
    }) {
        self.monitor = monitor
        self.doubaoWindows = doubaoWindows
        self.now = now
        self.focusMatches = focusMatches
        self.keyboard = keyboard
        self.inputMethods = inputMethods
        self.logger = logger
        keyboard.delegate = self
        rememberOrdinarySource()
    }

    public func rememberOrdinarySource() {
        if let current = inputMethods.currentInputSourceIdentity()?.identifier,
           !VoiceProviderRegistry.isVoiceInputSourceIdentifier(current) { lastOrdinarySource = current }
    }

    @discardableResult
    public func start(provider: VoiceProviderDefinition, config: RimeDouConfig) -> Bool {
        guard state == .idle, !keyboard.isSendingHotkey,
              VoiceProviderRegistry.inputSourceIdentifiers(for: provider.id).contains(where: { inputMethods.hasInputSource(identifier: $0) }) else { return false }
        rememberOrdinarySource()
        let target = lastOrdinarySource ?? "im.rime.inputmethod.Squirrel.Hans"
        guard inputMethods.hasInputSource(identifier: target) else {
            message = "请先切到 RIME 或其他日常输入法，再开始语音"
            onChange?()
            return false
        }
        let app = NSWorkspace.shared.frontmostApplication
        // A doubao voice session may still be running after an interrupted recovery
        // (observed 2026-09-12): the source is still doubao then, and a transport tap
        // would toggle that voice OFF instead of starting a new one.
        if provider.id == .doubao,
           let current = inputMethods.currentInputSourceIdentity()?.identifier,
           current == VoiceProviderRegistry.doubaoInputSourceIdentifier {
            message = "豆包语音可能仍在运行：请先结束它并切回 RIME，再按快捷键"
            logger.log("doubao start refused while doubao input source still active")
            onChange?()
            return false
        }
        let snapshot = VoiceSessionSnapshot(provider: provider, config: config, restoreInputSourceIdentifier: target)
        if provider.id == .qianwen {
            guard let windows = monitor.currentWindows(), windows.isEmpty else {
                message = "请先结束当前千问语音并关闭结果窗口"
                onChange?()
                return false
            }
            guard monitor.startTracking(onIssue: { [weak self] issue in self?.handleWindowIssue(issue) }) else { return false }
        }
        doubaoTracker = nil
        doubaoStopStartedAt = nil
        if provider.id == .doubao {
            if let baseline = doubaoWindows() {
                var tracker = ProviderWindowLifecycleTracker(baseline: baseline)
                // Arm before sending start. Doubao may consume the entire stop
                // gesture before our event tap, so completion cannot require it.
                tracker.beginWaiting(at: now())
                doubaoTracker = tracker
            } else {
                logger.log("doubao window observation unavailable; using keyboard stop fallback")
            }
        }
        let field = InputMethodController.focusedElementCapture(for: app)
        session = Session(snapshot: snapshot, app: app,
                          window: InputMethodController.focusedWindow(for: app),
                          element: field.element)
        keyboard.replayTargetPID = app?.processIdentifier
        logger.log("voice destination captured: app=\(app != nil) window=\(session?.window != nil) field=\(field.element != nil) fieldError=\(field.axError.map { String($0.rawValue) } ?? "none")")
        commitConfirmed = false
        restoreVerified = false
        restoreStartedAt = nil
        stopDriftWatch()
        replayWaitingSince = nil
        replayWaitReason = nil
        message = nil
        _ = machine.handle(.triggerTap)
        keyboard.setVoiceProvider(provider)
        startPolling()
        logger.log("voice start requested: \(provider.id.rawValue)")
        if !keyboard.sendHotkey(provider.transportHotkey) {
            block("语音快捷键未能完整发送，请确认语音状态并切回 RIME")
        }
        onChange?()
        return true
    }

    public func keyboardEngineDidDetectTriggerTap(_ engine: KeyboardEngine) {
        if state == .idle {
            guard !idleTriggerPending else { return }
            idleTriggerPending = true
            let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            // AX requests can need the target app to finish processing this event.
            // Do not wait for that app from inside the global event-tap callback.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.idleTriggerPending = false
                guard !self.suspended, self.state == .idle,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else { return }
                self.onIdleTrigger?()
            }
            return
        }
        guard state == .voiceActive, !keyboard.isSendingHotkey, let session else { return }
        if session.snapshot.provider.id == .qianwen {
            // While start is still being verified, a second toggle is unsafe.
            guard monitor.hasObservedVoiceWindow else { return }
            guard monitor.canRequestStop else {
                keyboard.beginInputDeferral(afterCurrentEvent: true)
                block("未能确认千问仍在录音，请手动确认并切回 RIME")
                return
            }
            beginQianwenStop(alreadyReceivedByProvider: false)
        } else {
            requestDoubaoStop()
        }
    }

    public func keyboardEngineDidDetectExternalVoiceEnd(_ engine: KeyboardEngine) {
        guard state == .voiceActive, sessionProvider == .doubao else { return }
        // An intercepted ordinary key may never reach Doubao to stop recording.
        // Wait only if window exit is already being confirmed; otherwise retain
        // the existing keyboard fallback instead of waiting for our own buffer.
        beginDoubaoStop(afterCurrentEvent: false, waitForWindow: doubaoTracker?.goneStartedAt != nil)
    }

    public func keyboardEngineDidDetectVoiceCancel(_ engine: KeyboardEngine) -> Bool {
        guard var current = session, current.snapshot.provider.id == .qianwen else { return false }
        if state == .restoringInputMethod { return true }
        guard state == .voiceActive || state == .waitingForProviderCompletion || state == .blocked else { return false }
        current.cancelRequested = true
        session = current
        keyboard.beginInputDeferral(afterCurrentEvent: true)
        message = "已请求取消千问，等待语音窗口关闭…"
        logger.log("qianwen cancel observed; waiting for window completion")
        if state == .voiceActive, monitor.hasObservedVoiceWindow {
            beginQianwenStop(alreadyReceivedByProvider: true)
        }
        onChange?()
        return true
    }

    public func keyboardEngineDidDetectManagedVoiceHotkeyTap(_ engine: KeyboardEngine) {
        guard state == .voiceActive, let session else { return }
        if session.snapshot.provider.id == .qianwen, !keyboard.isSendingHotkey, !monitor.hasObservedVoiceWindow {
            logger.log("physical Qianwen hotkey observed before confirmed start; toggle direction unknown")
            return
        }
        keyboard.beginInputDeferral(afterCurrentEvent: true)
        guard !keyboard.isSendingHotkey else {
            block("语音快捷键发生重叠：请确认语音已结束，并手动切回 RIME")
            return
        }
        if session.snapshot.provider.id == .qianwen {
            beginQianwenStop(alreadyReceivedByProvider: true)
        } else {
            beginDoubaoStop(afterCurrentEvent: true)
        }
    }

    private func requestDoubaoStop() {
        guard state == .voiceActive, var current = session, !current.stopSent else { return }
        // The RimeDou trigger is consumed by our event tap. Unlike the provider's
        // physical shortcut, it cannot stop Doubao without forwarding a toggle.
        // Refresh once: a window may have closed since the last polling tick.
        guard var tracker = doubaoTracker, let windows = doubaoWindows() else {
            beginDoubaoStop(afterCurrentEvent: true)
            return
        }
        _ = tracker.observe(current: windows, now: now(), completionTimeout: .infinity, goneStabilityDelay: 0.2)
        doubaoTracker = tracker
        if !tracker.didObserveProviderWindow || windows.isDisjoint(with: tracker.tracked) {
            // Unconfirmed start keeps the old fallback; an already-ending window
            // keeps its stable-disappearance gate. Neither permits a blind toggle.
            beginDoubaoStop(afterCurrentEvent: true)
            return
        }
        current.stopSent = true
        session = current
        keyboard.beginInputDeferral(afterCurrentEvent: true)
        _ = machine.handle(.explicitStopRequested)
        doubaoStopStartedAt = now()
        logger.log("doubao stop requested; waiting for voice window completion")
        if !keyboard.sendHotkey(current.snapshot.provider.transportHotkey) {
            block("豆包停止快捷键发送失败：不会重复尝试，请手动确认语音状态")
        }
        onChange?()
    }

    private func beginDoubaoStop(afterCurrentEvent: Bool, waitForWindow: Bool = true) {
        keyboard.beginInputDeferral(afterCurrentEvent: afterCurrentEvent)
        if waitForWindow, doubaoTracker?.didObserveProviderWindow == true {
            _ = machine.handle(.explicitStopObserved)
            doubaoStopStartedAt = now()
            logger.log("doubao stop observed; waiting for voice window completion")
            onChange?()
        } else {
            logger.log("doubao completion not confirmed; using keyboard stop fallback")
            _ = machine.handle(.externalVoiceEnd)
            restore()
        }
    }

    private func pollDoubaoWindow() {
        guard sessionProvider == .doubao,
              state == .voiceActive || state == .waitingForProviderCompletion,
              var tracker = doubaoTracker else { return }
        let time = now()
        // This deadline starts only after a stop we actually observed. Recording
        // itself may last arbitrarily long and must not inherit Qianwen's timeout.
        if let stopped = doubaoStopStartedAt, time - stopped >= 60 {
            suspend(reason: "未能确认豆包整理完成，已暂停快捷键；暂存仍保留，请确认语音状态并切回 RIME")
            onRecoveryPaused?()
            return
        }
        let previouslyObserved = tracker.didObserveProviderWindow
        let result = tracker.observe(current: doubaoWindows(), now: time,
                                     completionTimeout: .infinity, goneStabilityDelay: 0.2)
        doubaoTracker = tracker
        if !previouslyObserved, tracker.didObserveProviderWindow {
            logger.log("doubao voice window observed")
        }
        guard result == .completed else { return }
        doubaoTracker = nil
        doubaoStopStartedAt = nil
        commitConfirmed = true
        if state == .voiceActive {
            keyboard.beginInputDeferral()
            _ = machine.handle(.explicitStopObserved)
        }
        logger.log("doubao voice window completed; restoring without another key")
    }

    private func beginQianwenStop(alreadyReceivedByProvider: Bool) {
        guard state == .voiceActive, var current = session, !current.stopSent else { return }
        current.stopSent = true
        session = current
        keyboard.beginInputDeferral(afterCurrentEvent: true)
        _ = machine.handle(alreadyReceivedByProvider ? .explicitStopObserved : .explicitStopRequested)
        monitor.beginWaitingForGone(timeout: current.snapshot.config.qianwenCompletionTimeout,
                                    goneStabilityDelay: current.snapshot.config.qianwenGoneStabilityDelay) { [weak self] in
            self?.commitConfirmed = true
            self?.poll()
        }
        if !alreadyReceivedByProvider, !keyboard.sendHotkey(current.snapshot.provider.transportHotkey) {
            block("千问停止快捷键发送失败：不会重复尝试，请手动确认语音状态")
        }
        onChange?()
    }

    private func restore() {
        guard let session else { return }
        if session.cancelRequested { message = "正在恢复取消前的日常输入法…" }
        self.session?.cancelRequested = false
        monitor.stop()
        doubaoTracker = nil
        doubaoStopStartedAt = nil
        keyboard.beginInputDeferral()
        let snapshot = session.snapshot
        let attempt = UUID()
        restoreAttempt = attempt
        restoreStartedAt = now()
        inputMethods.restoreInputSource(identifier: snapshot.restoreInputSourceIdentifier,
                                        originalApp: session.app, originalWindow: session.window,
                                        config: snapshot.config,
                                        initialDelay: snapshot.provider.restorePolicy == .immediate && !commitConfirmed ? snapshot.config.restoreDelay : 0) { [weak self] result in
            guard let self, self.session?.snapshot.id == snapshot.id,
                  self.restoreAttempt == attempt, self.state == .restoringInputMethod else { return }
            switch result {
            case .safe:
                self.restoreVerified = true
                // Retain the legacy fallback's select pair only when window
                // completion was unavailable. Confirmed completion must not
                // deliberately select the voice provider again after restoring.
                if !self.isRecoveringInput, self.session?.snapshot.provider.id == .doubao, !self.commitConfirmed,
                   let target = self.session?.snapshot.restoreInputSourceIdentifier {
                    _ = self.inputMethods.selectInputSource(identifier: VoiceProviderRegistry.doubaoInputSourceIdentifier)
                    _ = self.inputMethods.selectInputSource(identifier: target)
                    self.logger.log("input context re-bound via provider bounce")
                }
                self.poll()
            case .failed: self.block("未能恢复输入法：暂存按键已保留，请手动切回 RIME")
            case .cancelled:
                if self.isRecoveringInput {
                    self.block("恢复日常输入法已中断，快捷键已暂停；暂存仍保留，可再次选择恢复")
                }
            }
        }
        onChange?()
    }

    public func keyboardEngineDidOverflowInputBuffer(_ engine: KeyboardEngine) {
        block("暂存已满：已有按键保留，后续按键无法保存。请停止打字并手动恢复")
        NSSound.beep()
    }

    private func block(_ reason: String) {
        guard state != .idle else { return }
        let recoveryCompletion = discardRecoveryCompletion
        discardRecoveryCompletion = nil
        restoreAttempt = nil
        _ = machine.handle(.failed)
        inputMethods.cancelPendingOperations()
        monitor.stop()
        doubaoTracker = nil
        doubaoStopStartedAt = nil
        keyboard.beginInputDeferral()
        safeSince = nil
        message = reason
        logger.log("voice session blocked: \(reason)")
        if recoveryCompletion != nil {
            suspended = true
            keyboard.stop()
            onRecoveryPaused?()
        }
        onChange?()
        recoveryCompletion?(false)
    }

    private func handleWindowIssue(_ issue: ProviderWindowIssue) {
        if state == .voiceActive, session?.cancelRequested == true,
           issue == .startNotObserved || issue == .windowDisappearedBeforeStop,
           !keyboard.isSendingHotkey,
           let windows = monitor.currentWindows(), windows.isEmpty,
           let source = inputMethods.currentInputSourceIdentity()?.identifier, !source.isEmpty {
            commitConfirmed = true
            _ = machine.handle(.externalVoiceEnd)
            logger.log("qianwen cancel confirmed with closed windows; restoring ordinary source")
            restore()
            return
        }
        // Failed startup with an unchanged ordinary input source has no committed
        // voice session to protect. Do not turn the user's next keystrokes into a
        // permanent buffer. Unknown source/window state still takes the safe path.
        if issue == .startNotObserved, state == .voiceActive, let current = session,
           !current.stopSent, !keyboard.isSendingHotkey, !keyboard.isDeferringInput,
           keyboard.deferredEventCount == 0,
           !VoiceProviderRegistry.isVoiceInputSourceIdentifier(current.snapshot.restoreInputSourceIdentifier),
           inputMethods.currentInputSourceIdentity()?.identifier == current.snapshot.restoreInputSourceIdentifier,
           let windows = monitor.currentWindows(), windows.isEmpty {
            monitor.stop()
            timer?.invalidate()
            timer = nil
            _ = machine.handle(.failed)
            _ = machine.handle(.recovered)
            keyboard.setVoiceProvider(nil)
            session = nil
            keyboard.replayTargetPID = nil
            message = "未能唤起千问，本次操作已结束；可以继续正常打字"
            logger.log("unconfirmed Qianwen start cancelled on original ordinary source; typing remains available")
            onChange?()
            return
        }
        block(issue.message)
    }

    private func startPolling() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func poll() {
        guard !suspended, let session else { return }
        if isRecoveringInput {
            pollDiscardRecovery()
            return
        }
        // Runs even while voice is active: a stop trigger whose keyUp was consumed
        // above the tap is only observable through modifier-flag reconciliation.
        _ = keyboard.reconcileTriggerGestures()
        if state == .voiceActive, session.cancelRequested, monitor.hasObservedVoiceWindow {
            beginQianwenStop(alreadyReceivedByProvider: true)
        }
        if state == .blocked, session.cancelRequested, !keyboard.isSendingHotkey,
           let windows = monitor.currentWindows(), windows.isEmpty,
           let source = inputMethods.currentInputSourceIdentity()?.identifier, !source.isEmpty {
            commitConfirmed = true
            _ = machine.handle(.recoveryRequested)
            restore()
            return
        }
        pollDoubaoWindow()
        guard !suspended else { return }
        if state == .waitingForProviderCompletion, commitConfirmed, !keyboard.isSendingHotkey {
            _ = machine.handle(.providerCompletion)
            restore()
            return
        }
        // A restore whose task never reports back (observed 2026-09-12) must surface
        // as a visible blocked state instead of swallowing keys forever.
        if state == .restoringInputMethod, !restoreVerified, let started = restoreStartedAt,
           now() - started > session.snapshot.config.switchWaitTimeout + 2 {
            block("恢复输入法超时：暂存按键已保留，请手动切回 RIME，并可用菜单暂停快捷键")
            return
        }
        guard state == .blocked || (state == .restoringInputMethod && restoreVerified) else { return }
        guard let current = inputMethods.currentInputSourceIdentity()?.identifier,
              !VoiceProviderRegistry.isVoiceInputSourceIdentifier(current) else {
            safeSince = nil
            replayWaitingSince = nil
            return
        }
        if state == .blocked, session.snapshot.provider.id == .qianwen {
            guard let windows = monitor.currentWindows(), windows.isEmpty else { safeSince = nil; return }
            let now = ProcessInfo.processInfo.systemUptime
            if safeSince == nil { safeSince = now; return }
            guard now - (safeSince ?? now) >= session.snapshot.config.qianwenGoneStabilityDelay else { return }
        }
        if keyboard.deferredEventCount > 0 {
            guard focusMatches(session.app, session.window, session.element) else {
                let reason = "暂存按键已保留：请回到原输入框以补发，或从菜单丢弃暂存"
                if message != reason { message = reason; onChange?() }
                waitForReplay(reason: "original-input-field")
                return
            }
        }
        if let reason = keyboard.inputDeferralWaitReason {
            waitForReplay(reason: reason)
            return
        }
        guard keyboard.completeInputDeferral() else { return }
        finish()
    }

    private func waitForReplay(reason: String) {
        if replayWaitReason != reason {
            replayWaitReason = reason
            logger.log("voice replay waiting: \(reason) bufferedEvents=\(keyboard.deferredEventCount)")
        }
        // Only after provider completion and a verified ordinary input source.
        // Unknown voice state must not cause automatic input replay or extra toggles.
        guard restoreVerified else { return }
        let time = now()
        if replayWaitingSince == nil { replayWaitingSince = time }
        guard time - (replayWaitingSince ?? time) >= 5 else { return }
        logger.log("voice replay paused: \(reason) bufferedEvents=\(keyboard.deferredEventCount)")
        suspend(reason: "输入法已恢复，暂存未能补发，快捷键已暂停；可回原输入框后启用，或选择「丢弃暂存并恢复快捷键」")
        onRecoveryPaused?()
    }

    private func finish() {
        let restoreTarget = session?.snapshot.restoreInputSourceIdentifier
        if state == .blocked { _ = machine.handle(.recovered) } else { _ = machine.handle(.restoreCompleted) }
        keyboard.setVoiceProvider(nil)
        session = nil
        doubaoTracker = nil
        doubaoStopStartedAt = nil
        keyboard.replayTargetPID = nil
        message = nil
        replayWaitingSince = nil
        replayWaitReason = nil
        restoreStartedAt = nil
        restoreAttempt = nil
        timer?.invalidate()
        timer = nil
        rememberOrdinarySource()
        logger.log("voice session completed safely")
        if let restoreTarget {
            // Keep the existing bounded drift check. Neither this log nor the
            // input source check alone establishes first-key candidate latency.
            startDriftWatch(target: restoreTarget)
        }
        onChange?()
    }

    /// After a verified restore the voice provider can still re-seize the input
    /// source while its overlay finalizes (doubao, observed 2026-09-12: restore
    /// reported safe yet the menu bar showed doubao). Watch briefly and pull the
    /// ordinary source back; never fight the user's own later choice for long.
    private func startDriftWatch(target: String) {
        stopDriftWatch()
        driftWatchTarget = target
        driftWatchRetries = 0
        driftWatchStartedAt = now()
        driftWatchUntil = driftWatchStartedAt + 5
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.driftWatchTick() }
        }
        driftWatchTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func driftWatchTick() {
        guard state == .idle, !suspended, let target = driftWatchTarget, now() < driftWatchUntil else {
            stopDriftWatch()
            return
        }
        guard let current = inputMethods.currentInputSourceIdentity()?.identifier else { return }
        guard VoiceProviderRegistry.isVoiceInputSourceIdentifier(current) else { stopDriftWatch(); return }
        guard driftWatchRetries < 6 else {
            logger.log("voice provider still holds the input source after restore; leaving it for the user")
            stopDriftWatch()
            return
        }
        driftWatchRetries += 1
        // Each fight extends the watch a little, capped overall: a long vendor
        // finalize (observed 2026-09-12) can outlast a fixed window.
        driftWatchUntil = min(driftWatchUntil + 2, driftWatchStartedAt + 15)
        logger.log("voice provider re-seized input source after restore; re-restoring (\(driftWatchRetries))")
        if !inputMethods.selectInputSource(identifier: target) {
            logger.log("drift re-restore could not select the original source")
        }
    }

    private func stopDriftWatch() {
        driftWatchTimer?.invalidate()
        driftWatchTimer = nil
        driftWatchTarget = nil
    }

    /// The menu action explicitly confirms voice has ended and authorizes discarding.
    /// Revalidate windows and the current input source before completing the reset.
    /// Returns whether recovery was accepted; completion reports its final result.
    @discardableResult
    public func recoverByDiscardingInput(completion: @escaping (Bool) -> Void = { _ in }) -> Bool {
        guard !isRecoveringInput else { return false }
        guard state == .blocked || state == .restoringInputMethod, let session else {
            return rejectDiscardRecovery("当前没有需要恢复的异常会话")
        }
        guard !keyboard.isSendingHotkey else {
            return rejectDiscardRecovery("语音快捷键尚未释放，请稍后再恢复")
        }
        let windows = session.snapshot.provider.id == .doubao ? doubaoWindows() : monitor.currentWindows()
        guard let windows else {
            return rejectDiscardRecovery("无法确认语音窗口状态，请稍后再试；暂存仍保留")
        }
        guard windows.isEmpty else {
            return rejectDiscardRecovery("请先结束语音并关闭\(session.snapshot.provider.id.displayName)窗口，再选择恢复；暂存仍保留")
        }
        guard let current = inputMethods.currentInputSourceIdentity()?.identifier,
              !current.isEmpty else {
            return rejectDiscardRecovery("无法确认当前输入法，请手动切回日常输入法后再恢复；暂存仍保留")
        }
        if !VoiceProviderRegistry.isVoiceInputSourceIdentifier(current) {
            completeDiscardRecovery()
            completion(true)
            return true
        }
        guard inputMethods.hasInputSource(identifier: session.snapshot.restoreInputSourceIdentifier) else {
            return rejectDiscardRecovery("原日常输入法当前不可用，请手动选择可用输入法后再恢复")
        }
        restoreAttempt = nil
        inputMethods.cancelPendingOperations()
        keyboard.stop()
        onRecoveryPaused?()
        discardRecoveryCompletion = completion
        restoreVerified = false
        suspended = false
        _ = machine.handle(.recoveryRequested)
        message = "正在恢复日常输入法，完成后将丢弃暂存并重新启用快捷键…"
        logger.log("explicit discard recovery requested; restoring ordinary input source")
        startPolling()
        restore()
        return true
    }

    private func rejectDiscardRecovery(_ reason: String) -> Bool {
        message = reason
        logger.log("explicit discard recovery refused: \(reason)")
        onChange?()
        return false
    }

    private func pollDiscardRecovery() {
        guard let session, let started = restoreStartedAt else { return }
        guard now() - started <= session.snapshot.config.switchWaitTimeout + 2 else {
            block("恢复日常输入法超时，快捷键已暂停；请手动切回日常输入法后再次恢复，暂存仍保留")
            return
        }
        guard restoreVerified else { return }
        let windows = session.snapshot.provider.id == .doubao ? doubaoWindows() : monitor.currentWindows()
        guard let windows, windows.isEmpty,
              let current = inputMethods.currentInputSourceIdentity()?.identifier,
              !current.isEmpty, !VoiceProviderRegistry.isVoiceInputSourceIdentifier(current) else {
            block("恢复时语音窗口或输入法状态发生变化，快捷键已暂停；请确认语音已结束后再次恢复")
            return
        }
        let completion = discardRecoveryCompletion
        discardRecoveryCompletion = nil
        completeDiscardRecovery()
        completion?(true)
    }

    private func completeDiscardRecovery() {
        let discardedCount = keyboard.deferredEventCount
        restoreAttempt = nil
        inputMethods.cancelPendingOperations()
        // Recovery may be requested before the automatic pause. Force the next
        // resume through start() so it samples live keys instead of old bookkeeping.
        suspended = true
        keyboard.stop()
        keyboard.discardInputDeferral()
        finish()
        logger.log("voice session reset by explicit discard: bufferedEvents=\(discardedCount)")
    }

    /// Menu action only: discarding input is an explicit user choice.
    public func discardBufferedInput() {
        keyboard.discardInputDeferral()
        if state != .idle { keyboard.beginInputDeferral() }
        poll()
    }

    /// Normal quit waits for a complete stop/commit/restore, never a half hotkey.
    public func requestFinishForQuit() {
        guard state == .voiceActive, !keyboard.isSendingHotkey, let session else { return }
        if session.snapshot.provider.id == .qianwen {
            guard monitor.canRequestStop else { block("退出前请手动确认千问语音已结束，并切回 RIME"); return }
            beginQianwenStop(alreadyReceivedByProvider: false)
            // Menu actions have no current keyboard callback to finalize this gate.
            keyboard.beginInputDeferral()
        } else {
            keyboard.beginInputDeferral()
            _ = machine.handle(.forcedStop)
            guard keyboard.sendHotkey(session.snapshot.provider.transportHotkey, completion: { [weak self] in self?.restore() }) else {
                block("退出前无法确认语音已结束，请手动切回 RIME")
                return
            }
        }
    }

    public func suspend(reason: String) {
        suspended = true
        if state != .idle { block(reason) }
        inputMethods.cancelPendingOperations()
        keyboard.stop()
    }

    @discardableResult
    public func resume() -> Bool {
        replayWaitingSince = nil
        keyboard.setVoiceProvider(session?.snapshot.provider)
        let started = keyboard.start()
        suspended = !started
        return started
    }

    public func shutdown() {
        suspended = true
        discardRecoveryCompletion = nil
        restoreAttempt = nil
        timer?.invalidate()
        stopDriftWatch()
        monitor.stop()
        doubaoTracker = nil
        doubaoStopStartedAt = nil
        inputMethods.cancelPendingOperations()
        keyboard.stop()
    }
}
