import CoreFoundation
import Foundation

@MainActor
public final class AppRunner {
    private let configPath: String
    private let configStore: ConfigStore
    private let inputSourceService: InputSourceService
    private var hotkeyMonitor: HotkeyMonitor?
    private var coordinator: SwitchCoordinator?
    private var switchServices: SystemSwitchServices?
    private var voiceToolMonitor: VoiceToolMonitor?
    private var voiceToolStateTracker: ExternalVoiceToolStateTracker?
    private var voiceToolPollTimer: Timer?
    private var primaryInputGuardTimer: Timer?
    private var isPaused = false
    private let hotkeyRuntimeState = HotkeyRuntimeState()

    public init(
        configPath: String = "config/default.json",
        configStore: ConfigStore = ConfigStore(),
        inputSourceService: InputSourceService = InputSourceService()
    ) {
        self.configPath = configPath
        self.configStore = configStore
        self.inputSourceService = inputSourceService
    }

    public func run(shouldStartRunLoop: Bool = true) throws {
        let config = try configStore.load(path: configPath)
        let voiceToolMonitor = VoiceToolMonitor(config: config)
        self.voiceToolMonitor = voiceToolMonitor

        print("configLoaded=true")
        for warning in voiceToolMonitor.configurationWarnings() {
            print("warning=\(warning)")
        }

        try inputSourceService.requireInputSource(id: config.primaryInputSourceId)
        try inputSourceService.requireInputSource(id: config.doubaoInputSourceId)
        print("primaryInputSourceSelectable=\(inputSourceService.containsSelectableInputSource(id: config.primaryInputSourceId))")
        print("doubaoInputSourceSelectable=\(inputSourceService.containsSelectableInputSource(id: config.doubaoInputSourceId))")
        requestRequiredPermissionsIfNeeded()
        print("inputMonitoringPermission=\(HotkeyMonitor.hasInputMonitoringPermission())")
        print("accessibilityPermission=\(RightControlKeyEventPoster.hasAccessibilityPermission())")
        print("externalVoiceToolRunning=\(voiceToolMonitor.isExternalVoiceToolRunning())")

        let services = SystemSwitchServices(config: config, inputSourceService: inputSourceService)
        switchServices = services
        var coordinator = SwitchCoordinator(services: services)

        let externalVoiceToolRunning = voiceToolMonitor.isExternalVoiceToolRunning()
        voiceToolStateTracker = ExternalVoiceToolStateTracker(initiallyRunning: externalVoiceToolRunning)

        if externalVoiceToolRunning {
            coordinator.handle(.externalVoiceToolStarted)
        }

        self.coordinator = coordinator

        try startHotkeyMonitor()
        startVoiceToolPolling()
        startPrimaryInputGuard()

        print("appRunnerStarted=true")
        if shouldStartRunLoop {
            CFRunLoopRun()
        }
    }

    public func stop() {
        voiceToolPollTimer?.invalidate()
        voiceToolPollTimer = nil
        primaryInputGuardTimer?.invalidate()
        primaryInputGuardTimer = nil
        hotkeyMonitor?.stop()
        hotkeyMonitor = nil
        restorePrimaryInputIfNeeded()
    }

    public func pause() {
        isPaused = true
        voiceToolPollTimer?.invalidate()
        voiceToolPollTimer = nil
        primaryInputGuardTimer?.invalidate()
        primaryInputGuardTimer = nil
        hotkeyMonitor?.stop()
        hotkeyMonitor = nil
        restorePrimaryInputIfNeeded()
        hotkeyRuntimeState.setDoubaoVoiceActive(false)
        print("appPaused=true")
    }

    public func resume() throws {
        guard isPaused else {
            return
        }

        isPaused = false
        try startHotkeyMonitor()
        startVoiceToolPolling()
        startPrimaryInputGuard()
        print("appPaused=false")
    }

    public func togglePause() throws {
        if isPaused {
            try resume()
        } else {
            pause()
        }
    }

    public func restorePrimaryInputNow() -> Bool {
        switchServices?.restorePrimaryInputSourceIfNeeded() == true
    }

    public func menuPresentation() -> MenuBarPresentation {
        MenuBarPresentation(
            isPaused: isPaused,
            switchState: coordinator?.state,
            isExternalVoiceToolRunning: voiceToolMonitor?.isExternalVoiceToolRunning() == true
        )
    }

    public static func requestRequiredPermissionsIfNeeded() {
        if !HotkeyMonitor.hasInputMonitoringPermission() {
            print("requestingInputMonitoringPermission=true")
            _ = HotkeyMonitor.requestInputMonitoringPermission()
        }

        if !RightControlKeyEventPoster.hasAccessibilityPermission() {
            print("requestingAccessibilityPermission=true")
            _ = RightControlKeyEventPoster.requestAccessibilityPermission()
        }
    }

    private func requestRequiredPermissionsIfNeeded() {
        Self.requestRequiredPermissionsIfNeeded()
    }

    private func startVoiceToolPolling() {
        guard voiceToolPollTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollVoiceToolState()
            }
        }

        voiceToolPollTimer = timer
        RunLoop.current.add(timer, forMode: .common)
    }

    private func startPrimaryInputGuard() {
        guard primaryInputGuardTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.restorePrimaryInputWhenIdle()
            }
        }

        primaryInputGuardTimer = timer
        RunLoop.current.add(timer, forMode: .common)
    }

    private func startHotkeyMonitor() throws {
        guard hotkeyMonitor == nil else {
            return
        }

        let monitor = HotkeyMonitor(
            eventDelayProvider: { [weak self] event in
                guard event == .rightControlPressed else {
                    return HotkeyMonitor.defaultHotkeyDispatchDelaySeconds
                }

                return self?.hotkeyRuntimeState.shouldHandleRightControlImmediately() == true
                    ? 0
                    : HotkeyMonitor.defaultHotkeyDispatchDelaySeconds
            },
            eventHandler: { [weak self] event in
                Task { @MainActor in
                    self?.handleHotkey(event)
                }
            }
        )

        try monitor.start()
        hotkeyMonitor = monitor
    }

    private func pollVoiceToolState() {
        guard let voiceToolMonitor, var voiceToolStateTracker else {
            return
        }

        if let event = voiceToolStateTracker.update(isRunning: voiceToolMonitor.isExternalVoiceToolRunning()) {
            self.voiceToolStateTracker = voiceToolStateTracker
            handleHotkey(event)
            return
        }

        self.voiceToolStateTracker = voiceToolStateTracker
    }

    private func handleHotkey(_ event: SwitchEvent) {
        guard !isPaused else {
            return
        }

        guard var coordinator else {
            return
        }

        let previousState = coordinator.state
        coordinator.handle(event)
        self.coordinator = coordinator
        hotkeyRuntimeState.setDoubaoVoiceActive(coordinator.state == .doubaoVoiceActive)
        print("switchEvent=\(event) state=\(previousState)->\(coordinator.state)")
    }

    private func restorePrimaryInputWhenIdle() {
        guard coordinator?.state == .idle else {
            return
        }

        guard voiceToolMonitor?.isExternalVoiceToolRunning() == false else {
            return
        }

        if switchServices?.restorePrimaryInputSourceIfNeeded() == true {
            return
        }

        print("idlePrimaryInputGuardRestored=false")
    }

    private func restorePrimaryInputIfNeeded() {
        guard coordinator?.state == .doubaoVoiceActive else {
            return
        }

        if switchServices?.switchToPrimary() == true {
            print("restoredPrimaryInputOnStop=true")
        } else {
            print("restoredPrimaryInputOnStop=false")
        }
    }
}

private final class HotkeyRuntimeState: @unchecked Sendable {
    private let lock = NSLock()
    private var isDoubaoVoiceActive = false

    func setDoubaoVoiceActive(_ value: Bool) {
        lock.lock()
        isDoubaoVoiceActive = value
        lock.unlock()
    }

    func shouldHandleRightControlImmediately() -> Bool {
        lock.lock()
        let value = isDoubaoVoiceActive
        lock.unlock()
        return value
    }
}
