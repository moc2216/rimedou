import AppKit
import ApplicationServices
import Carbon
import DoubaoVoiceBridgeCore
import ServiceManagement

private let rightCommandKeyCode: Int64 = 54
private let leftOptionKeyCode: CGKeyCode = 58
private let deviceRightCommandMask: UInt64 = 0x10

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let config = BridgeConfig.loadFromDefaultLocation()
    private let logger = AppLogger()
    private let inputSources = InputSourceController()
    private let optionSender = OptionKeySender()
    private let focusBouncer = FocusBouncer()
    private var statusItem: NSStatusItem?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var enabled = true
    private var rightCommandDown = false
    private var optionHoldIsDown = false
    private var permissionAlertVisible = false
    private var permissionAlertPending = false
    private var sessionID = UUID()
    private var machine = BridgeStateMachine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMenu()
        syncLaunchAtLogin()
        checkPermissionsAndShowAlertIfNeeded()
        warnIfHammerspoonIsRunning()
        installEventTap()
        normalizeStartupInputMethod()
        logger.log("app launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if optionHoldIsDown {
            optionSender.up()
        }
        disableEventTap()
        logger.log("app terminated")
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "豆"

        let menu = NSMenu()
        let enableItem = NSMenuItem(title: "Disable", action: #selector(toggleEnabled), keyEquivalent: "")
        enableItem.target = self
        menu.addItem(enableItem)

        let logItem = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        let permissionItem = NSMenuItem(title: "Check Permissions", action: #selector(checkPermissionsFromMenu), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        enabled.toggle()
        sender.title = enabled ? "Disable" : "Enable"
        statusItem?.button?.title = enabled ? "豆" : "豆-"
        logger.log(enabled ? "bridge enabled" : "bridge disabled")
        if !enabled {
            releaseOptionIfNeeded()
            restoreUserInputMethod()
            machine.handle(.reset)
        }
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(AppLogger.defaultLogURL)
    }

    private func syncLaunchAtLogin() {
        guard #available(macOS 13.0, *) else {
            return
        }

        let service = SMAppService.mainApp
        do {
            if config.launchAtLogin {
                if service.status != .enabled {
                    try service.register()
                    logger.log("launch at login enabled")
                }
            } else if service.status != .notRegistered {
                try service.unregister()
                logger.log("launch at login disabled")
            }
        } catch {
            logger.log("failed to sync launch at login: \(error)")
        }
    }

    @objc private func checkPermissionsFromMenu() {
        checkPermissionsAndShowAlertIfNeeded(forceReadyAlert: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func permissionReport(promptForAccessibility: Bool) -> PermissionReport {
        let accessibilityGranted: Bool
        if promptForAccessibility {
            let promptKey = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
            accessibilityGranted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        } else {
            accessibilityGranted = AXIsProcessTrusted()
        }

        let inputMonitoringGranted: Bool
        if #available(macOS 10.15, *) {
            inputMonitoringGranted = CGPreflightListenEventAccess()
        } else {
            inputMonitoringGranted = true
        }

        return PermissionReport(
            accessibilityGranted: accessibilityGranted,
            inputMonitoringGranted: inputMonitoringGranted
        )
    }

    private func checkPermissionsAndShowAlertIfNeeded(forceReadyAlert: Bool = false) {
        let report = permissionReport(promptForAccessibility: true)
        if report.isReady {
            logger.log("permissions ready")
            if forceReadyAlert {
                showPermissionsReadyAlert()
            }
            return
        }

        let missingNames = report.missingPermissions.map(\.displayName).joined(separator: ", ")
        logger.log("permissions missing: \(missingNames)")
        guard !permissionAlertVisible, !permissionAlertPending else {
            return
        }
        permissionAlertPending = true
        DispatchQueue.main.async { [weak self] in
            self?.showMissingPermissionsAlert(report)
        }
    }

    private func showMissingPermissionsAlert(_ report: PermissionReport) {
        guard !permissionAlertVisible else {
            return
        }
        permissionAlertPending = false
        permissionAlertVisible = true
        defer { permissionAlertVisible = false }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "DoubaoVoiceBridge needs permissions"
        alert.informativeText = "\(report.message)\n\nAfter enabling permissions, quit and reopen DoubaoVoiceBridge."

        let missing = report.missingPermissions
        if missing.contains(.accessibility) {
            alert.addButton(withTitle: "Open Accessibility")
        }
        if missing.contains(.inputMonitoring) {
            alert.addButton(withTitle: "Open Input Monitoring")
        }
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        let clickedIndex = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard clickedIndex >= 0, clickedIndex < missing.count else {
            return
        }
        NSWorkspace.shared.open(missing[clickedIndex].settingsURL)
    }

    private func showPermissionsReadyAlert() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "DoubaoVoiceBridge permissions are ready"
        alert.informativeText = "Right Command can now be used as push-to-talk."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func warnIfHammerspoonIsRunning() {
        let hammerspoonApps = NSRunningApplication.runningApplications(withBundleIdentifier: "org.hammerspoon.Hammerspoon")
        guard !hammerspoonApps.isEmpty else {
            return
        }

        logger.log("hammerspoon is running; old right command event tap may conflict")
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Hammerspoon is still running"
            alert.informativeText = "If your old Right Command script is loaded, it may intercept the key before DoubaoVoiceBridge can handle it. Quit Hammerspoon or disable the old rightcmd watcher before testing this app."
            alert.addButton(withTitle: "Quit Hammerspoon")
            alert.addButton(withTitle: "Keep Running")

            if alert.runModal() == .alertFirstButtonReturn {
                hammerspoonApps.forEach { $0.terminate() }
            }
        }
    }

    private func installEventTap() {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            logger.log("failed to create event tap; grant Input Monitoring and Accessibility")
            checkPermissionsAndShowAlertIfNeeded()
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.log("event tap installed")
    }

    private func disableEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    fileprivate func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard enabled else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == rightCommandKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let isDown = (event.flags.rawValue & deviceRightCommandMask) != 0
        logger.log(
            "rightcmd flagsChanged: physicalDown=\(isDown) internalDown=\(rightCommandDown) rawFlags=0x\(String(event.flags.rawValue, radix: 16))"
        )
        if isDown, !rightCommandDown {
            rightCommandDown = true
            handleRightCommandDown()
        } else if !isDown, rightCommandDown {
            rightCommandDown = false
            handleRightCommandUp()
        }

        return nil
    }

    private func handleRightCommandDown() {
        logger.log("right command down")
        let actions = machine.handle(.rightCommandDown)
        if actions.contains(.startVoiceSession) {
            startVoiceSession()
        }
    }

    private func handleRightCommandUp() {
        logger.log("right command up")
        let actions = machine.handle(.rightCommandUp)
        if actions.contains(.cancelPendingOptionHold) {
            sessionID = UUID()
            logger.log("cancel pending option hold")
        }
        if actions.contains(.releaseOptionHold) {
            releaseOptionIfNeeded()
        }
        if actions.contains(.restoreUserInputMethod) {
            DispatchQueue.main.asyncAfter(deadline: .now() + config.restoreDelay) { [weak self] in
                self?.restoreUserInputMethod()
            }
        }
    }

    private func startVoiceSession() {
        sessionID = UUID()
        let currentSession = sessionID
        let originalApp = NSWorkspace.shared.frontmostApplication
        let originalWindow = FocusBouncer.focusedWindow(for: originalApp)
        let currentInput = inputSources.currentInputSourceName()
        logger.log("record original input source: \(currentInput)")
        logger.log("switch to target input source: \(config.targetInputMethod)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            _ = self.inputSources.selectInputSource(namedOrIdentifiedBy: self.config.targetInputMethod)
            Thread.sleep(forTimeInterval: self.config.postSwitchSettleDelay)
            let confirmed = self.inputSources.waitUntilActive(
                matches: self.config.targetInputMethod,
                timeout: self.config.switchWaitTimeout,
                pollInterval: self.config.switchPollInterval
            )
            self.logger.log(confirmed ? "confirmed target input source" : "target input source confirmation timed out")

            DispatchQueue.main.async {
                guard self.sessionID == currentSession, self.rightCommandDown else { return }
                self.logger.log("start app focus bounce")
                self.focusBouncer.bounce(
                    originalApp: originalApp,
                    originalWindow: originalWindow,
                    backDelay: self.config.focusBounceBackDelay,
                    settleDelay: self.config.focusBounceSettleDelay
                ) { [weak self] in
                    self?.startOptionWarmupIfCurrent(currentSession)
                }
            }
        }
    }

    private func startOptionWarmupIfCurrent(_ currentSession: UUID) {
        guard sessionID == currentSession, rightCommandDown else {
            return
        }
        logger.log("left option warmup down/up")
        optionSender.down()
        DispatchQueue.main.asyncAfter(deadline: .now() + config.optionWarmupTapDuration) { [weak self] in
            guard let self else { return }
            self.optionSender.up()
            DispatchQueue.main.asyncAfter(deadline: .now() + self.config.optionWarmupToHoldDelay) { [weak self] in
                guard let self, self.sessionID == currentSession, self.rightCommandDown else { return }
                self.logger.log("left option formal hold down")
                self.optionSender.down()
                self.optionHoldIsDown = true
                self.machine.handle(.optionHoldStarted)
            }
        }
    }

    private func releaseOptionIfNeeded() {
        guard optionHoldIsDown else {
            return
        }
        optionSender.up()
        optionHoldIsDown = false
        logger.log("left option release")
    }

    private func restoreUserInputMethod() {
        logger.log("restore input method: \(config.userInputMethod)")
        _ = inputSources.selectInputSource(namedOrIdentifiedBy: config.userInputMethod)
    }

    private func normalizeStartupInputMethod() {
        if inputSources.currentInputSourceName().contains(config.targetInputMethod) {
            restoreUserInputMethod()
        }
    }
}

@main
enum DoubaoVoiceBridgeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        _ = delegate
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard type == .flagsChanged, let refcon else {
        return Unmanaged.passUnretained(event)
    }
    let app = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
    return app.handleFlagsChanged(event)
}

private final class OptionKeySender {
    private let source = CGEventSource(stateID: .hidSystemState)

    func down() {
        post(down: true)
    }

    func up() {
        post(down: false)
    }

    private func post(down: Bool) {
        let event = CGEvent(keyboardEventSource: source, virtualKey: leftOptionKeyCode, keyDown: down)
        event?.flags = down ? .maskAlternate : []
        event?.post(tap: .cghidEventTap)
    }
}

private final class FocusBouncer {
    func bounce(
        originalApp: NSRunningApplication?,
        originalWindow: AXUIElement?,
        backDelay: TimeInterval,
        settleDelay: TimeInterval,
        completion: @escaping () -> Void
    ) {
        activateNeutralApp(excluding: originalApp)
        DispatchQueue.main.asyncAfter(deadline: .now() + backDelay) {
            originalApp?.activate(options: [.activateIgnoringOtherApps])
            if let originalWindow {
                AXUIElementSetAttributeValue(originalWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(originalWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: completion)
        }
    }

    static func focusedWindow(for app: NSRunningApplication?) -> AXUIElement? {
        guard let pid = app?.processIdentifier else {
            return nil
        }
        let element = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success, let value else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func activateNeutralApp(excluding originalApp: NSRunningApplication?) {
        if originalApp?.bundleIdentifier != Bundle.main.bundleIdentifier {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
            return
        }

        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            finder.activate(options: [.activateIgnoringOtherApps])
            return
        }

        if let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
            NSWorkspace.shared.openApplication(at: finderURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
