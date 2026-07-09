import AppKit
import RimeDouCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let config = RimeDouConfig.loadFromDefaultLocation()
    private let logger = RimeDouLogger()
    private var stateMachine = VoiceStateMachine()
    private lazy var keyboardEngine = KeyboardEngine(config: config, logger: logger)
    private lazy var inputMethodController = InputMethodController(logger: logger)
    private var statusItem: NSStatusItem?
    private var permissionWindow: PermissionsWindowController?
    private var currentSessionID = UUID()
    private var originalInputMethod: String?
    private var originalApp: NSRunningApplication?
    private var originalWindow: AXUIElement?
    private var enabled = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMenu()
        checkPermissions()
        logger.log("rimedou launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardEngine.stop()
        if let target = originalInputMethod {
            _ = inputMethodController.selectInputMethod(namedOrIdentifiedBy: target)
        }
        logger.log("rimedou terminated")
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "豆"
        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: "Disable Key Capture", action: #selector(toggleEnabled), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "")
        menu.addItem(withTitle: "Open Config", action: #selector(openConfig), keyEquivalent: "")
        menu.addItem(withTitle: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "")
        menu.addItem(withTitle: "Check Permissions", action: #selector(checkPermissionsFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        updateMenuItems()
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        enabled.toggle()
        updateMenuItems()
        logger.log(enabled ? "key capture enabled" : "key capture disabled")
        if !enabled {
            resetState()
        }
    }

    private func updateMenuItems() {
        guard let menu = statusItem?.menu else { return }
        menu.item(at: 0)?.title = enabled ? "Disable Key Capture" : "Enable Key Capture"
        statusItem?.button?.title = enabled ? "豆" : "豆-"
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(RimeDouLogger.defaultLogURL)
    }

    @objc private func openConfig() {
        _ = RimeDouConfig.loadFromDefaultLocation()
        NSWorkspace.shared.activateFileViewerSelecting([RimeDouConfig.defaultUserConfigURL])
    }

    @objc private func reloadConfig() {
        resetState()
        logger.log("config reload requested")
    }

    @objc private func checkPermissionsFromMenu() {
        showPermissionWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func checkPermissions() {
        let report = currentPermissionReport()
        if report.isReady {
            startKeyboardEngine()
        } else {
            showPermissionWindow()
        }
    }

    private func currentPermissionReport() -> PermissionReport {
        PermissionReport(
            accessibilityGranted: AXIsProcessTrusted(),
            inputMonitoringGranted: inputMonitoringPermissionIsGranted()
        )
    }

    private func inputMonitoringPermissionIsGranted() -> Bool {
        guard #available(macOS 10.15, *) else { return true }
        guard CGPreflightListenEventAccess() else { return false }
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else {
            return false
        }
        CFMachPortInvalidate(tap)
        return true
    }

    private func showPermissionWindow() {
        if let window = permissionWindow {
            window.bringToFront()
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let window = PermissionsWindowController(
            reportProvider: { [weak self] in
                self?.currentPermissionReport() ?? PermissionReport(accessibilityGranted: false, inputMonitoringGranted: false)
            },
            onClose: { [weak self] in
                self?.permissionWindow = nil
                NSApp.setActivationPolicy(.accessory)
            }
        )
        window.delegate = self
        permissionWindow = window
        window.showWindow(nil)
        window.bringToFront()
    }

    private func startKeyboardEngine() {
        keyboardEngine.delegate = self
        guard keyboardEngine.start() else {
            logger.log("failed to start keyboard engine")
            return
        }
        logger.log("keyboard engine started")
    }

    private func resetState() {
        stateMachine.handle(.reset)
        keyboardEngine.resetVoiceStartTime()
        originalInputMethod = nil
        originalApp = nil
        originalWindow = nil
        currentSessionID = UUID()
    }
}

extension AppDelegate: PermissionsWindowControllerDelegate {
    func permissionsWindowControllerDidBecomeReady(_ controller: PermissionsWindowController) {
        permissionWindow = nil
        NSApp.setActivationPolicy(.accessory)
        startKeyboardEngine()
    }
}

extension AppDelegate: KeyboardEngineDelegate {
    func keyboardEngineDidDetectTriggerTap(_ engine: KeyboardEngine) {
        guard enabled else { return }
        let actions = stateMachine.handle(.triggerTap)
        for action in actions {
            apply(action)
        }
    }

    func keyboardEngineDidDetectExternalVoiceEnd(_ engine: KeyboardEngine) {
        guard enabled else { return }
        let actions = stateMachine.handle(.externalVoiceEnd)
        for action in actions {
            apply(action)
        }
    }

    private func apply(_ action: VoiceAction) {
        switch action {
        case .startVoiceSession:
            startVoiceSession()
        case .stopVoice:
            keyboardEngine.sendVoiceHotkey()
        case .restoreInputMethod:
            restoreInputMethod()
        }
    }

    private func startVoiceSession() {
        currentSessionID = UUID()
        keyboardEngine.markVoiceStarted(at: Date())
        let current = inputMethodController.currentInputMethod()
        if InputMethodController.isDoubaoInputMethod(current) {
            originalInputMethod = "Squirrel"
            logger.log("current is doubao; restore target -> Squirrel")
        } else {
            originalInputMethod = current
            logger.log("record original input method: \(current)")
        }
        originalApp = NSWorkspace.shared.frontmostApplication
        originalWindow = InputMethodController.focusedWindow(for: originalApp)
        keyboardEngine.sendVoiceHotkey()
    }

    private func restoreInputMethod() {
        guard let target = originalInputMethod else { return }
        let session = currentSessionID
        inputMethodController.restoreInputMethod(
            target,
            originalApp: originalApp,
            originalWindow: originalWindow,
            config: config
        ) { [weak self] in
            guard let self, self.currentSessionID == session else { return }
            self.originalInputMethod = nil
            self.originalApp = nil
            self.originalWindow = nil
        }
    }
}
