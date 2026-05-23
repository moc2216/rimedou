import AppKit
import ApplicationServices
import Carbon
import DoubaoVoiceBridgeCore

private let rightCommandKeyCode: Int64 = 54
private let leftOptionKeyCode: CGKeyCode = 58
private let deviceRightCommandMask: UInt64 = 0x10
private let doubaoInputMethodName = "豆包输入法"
private let launchAgentLabel = "local.doubao-voice-bridge.keepalive"

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let config = BridgeConfig.loadFromDefaultLocation()
    private let logger = AppLogger()
    private let inputSources = InputSourceController()
    private let optionSender = OptionKeySender()
    private let focusBouncer = FocusBouncer()
    private lazy var launchAgent = LaunchAgentManager(label: launchAgentLabel, logger: logger)
    private var statusItem: NSStatusItem?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var enabled = true
    private var rightCommandDown = false
    private var optionHoldIsDown = false
    private var permissionWindowController: PermissionWindowController?
    private var didCompleteStartupAfterPermissions = false
    private var sessionID = UUID()
    private var machine = BridgeStateMachine()
    private var inputMethodToRestore: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMenu()
        gateStartupOnPermissions()
        logger.log("app launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if optionHoldIsDown {
            optionSender.up()
        }
        restorePreviousInputMethod()
        disableEventTap()
        logger.log("app terminated")
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "豆"

        let menu = NSMenu()
        let enableItem = NSMenuItem(title: "Disable Key Capture", action: #selector(toggleEnabled), keyEquivalent: "")
        enableItem.target = self
        menu.addItem(enableItem)

        let logItem = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        let permissionItem = NSMenuItem(title: "Check Permissions", action: #selector(checkPermissionsFromMenu), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit and Disable Auto Restart", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        enabled.toggle()
        sender.title = enabled ? "Disable Key Capture" : "Enable Key Capture"
        statusItem?.button?.title = enabled ? "豆" : "豆-"
        logger.log(enabled ? "key capture enabled" : "key capture disabled")
        if !enabled {
            releaseOptionIfNeeded()
            restorePreviousInputMethod()
            rightCommandDown = false
            sessionID = UUID()
            machine.handle(.reset)
        }
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(AppLogger.defaultLogURL)
    }

    private func installLaunchAgentIfNeeded() {
        do {
            let shouldRelaunchUnderAgent = try launchAgent.installForCurrentApp()
            if shouldRelaunchUnderAgent {
                logger.log("launch agent installed; terminating manual instance")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.terminate(nil)
                }
            }
        } catch {
            logger.log("failed to install launch agent: \(error)")
        }
    }

    @objc private func checkPermissionsFromMenu() {
        let report = permissionReport()
        if report.isReady {
            showPermissionsReadyAlert()
        } else {
            showPermissionWindow(isStartupGate: false)
        }
    }

    @objc private func quit() {
        do {
            try launchAgent.uninstall()
            logger.log("launch agent disabled by quit")
        } catch {
            logger.log("failed to disable launch agent during quit: \(error)")
        }
        NSApp.terminate(nil)
    }

    private func permissionReport() -> PermissionReport {
        return PermissionReport(
            accessibilityGranted: AXIsProcessTrusted(),
            inputMonitoringGranted: inputMonitoringPermissionIsGranted()
        )
    }

    private func inputMonitoringPermissionIsGranted() -> Bool {
        guard #available(macOS 10.15, *) else {
            return true
        }
        guard CGPreflightListenEventAccess() else {
            return false
        }

        let mask = (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: permissionProbeEventTapCallback,
            userInfo: nil
        ) else {
            return false
        }
        CFMachPortInvalidate(tap)
        return true
    }

    private func gateStartupOnPermissions() {
        let report = permissionReport()
        if report.isReady {
            logger.log("permissions ready")
            completeStartupAfterPermissions()
            return
        }

        let missingNames = report.missingPermissions.map(\.displayName).joined(separator: ", ")
        logger.log("permissions missing: \(missingNames)")
        showPermissionWindow(isStartupGate: true)
    }

    private func completeStartupAfterPermissions() {
        guard !didCompleteStartupAfterPermissions else {
            return
        }
        let report = permissionReport()
        guard report.isReady else {
            let missingNames = report.missingPermissions.map(\.displayName).joined(separator: ", ")
            logger.log("startup blocked by missing permissions: \(missingNames)")
            showPermissionWindow(isStartupGate: true)
            return
        }
        didCompleteStartupAfterPermissions = true
        installLaunchAgentIfNeeded()
        installEventTap()
    }

    private func showPermissionWindow(isStartupGate: Bool) {
        NSApp.setActivationPolicy(.regular)
        if let controller = permissionWindowController {
            controller.isStartupGate = controller.isStartupGate || isStartupGate
            controller.showWindow(nil)
            controller.bringToFront()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let controller = PermissionWindowController(
            isStartupGate: isStartupGate,
            reportProvider: { [weak self] in
                self?.permissionReport()
                    ?? PermissionReport(accessibilityGranted: false, inputMonitoringGranted: false)
            },
            onReady: { [weak self] in
                guard let self else { return }
                self.permissionWindowController = nil
                NSApp.setActivationPolicy(.accessory)
                self.completeStartupAfterPermissions()
            },
            onClose: { [weak self] report, wasStartupGate in
                guard let self else { return }
                self.permissionWindowController = nil
                if wasStartupGate, !report.isReady {
                    self.uninstallLaunchAgent(reason: "permission gate closed with missing permissions")
                }
                NSApp.terminate(nil)
            }
        )
        permissionWindowController = controller
        controller.showWindow(nil)
        controller.bringToFront()
    }

    private func uninstallLaunchAgent(reason: String) {
        do {
            try launchAgent.uninstall()
            logger.log("\(reason); launch agent disabled")
        } catch {
            logger.log("\(reason); failed to disable launch agent: \(error)")
        }
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
            showPermissionWindow(isStartupGate: false)
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
        if actions.contains(.restorePreviousInputMethod) {
            DispatchQueue.main.asyncAfter(deadline: .now() + config.restoreDelay) { [weak self] in
                self?.restorePreviousInputMethod()
            }
        }
    }

    private func startVoiceSession() {
        sessionID = UUID()
        let currentSession = sessionID
        let originalApp = NSWorkspace.shared.frontmostApplication
        let originalWindow = FocusBouncer.focusedWindow(for: originalApp)
        let currentInput = inputSources.currentInputSourceName()
        inputMethodToRestore = currentInput
        logger.log("record original input source: \(currentInput)")
        logger.log("switch to doubao input source: \(doubaoInputMethodName)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            _ = self.inputSources.selectInputSource(namedOrIdentifiedBy: doubaoInputMethodName)
            Thread.sleep(forTimeInterval: self.config.postSwitchSettleDelay)
            let confirmed = self.inputSources.waitUntilActive(
                matches: doubaoInputMethodName,
                timeout: self.config.switchWaitTimeout,
                pollInterval: self.config.switchPollInterval
            )
            self.logger.log(confirmed ? "confirmed doubao input source" : "doubao input source confirmation timed out")

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

    private func restorePreviousInputMethod() {
        guard let inputMethod = inputMethodToRestore else {
            logger.log("skip input method restore: no previous input source recorded")
            return
        }
        inputMethodToRestore = nil
        logger.log("restore previous input method: \(inputMethod)")
        _ = inputSources.selectInputSource(namedOrIdentifiedBy: inputMethod)
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

private let permissionProbeEventTapCallback: CGEventTapCallBack = { _, _, event, _ in
    Unmanaged.passUnretained(event)
}

private final class PermissionWindowController: NSWindowController, NSWindowDelegate {
    var isStartupGate: Bool

    private let reportProvider: () -> PermissionReport
    private let onReady: () -> Void
    private let onClose: (PermissionReport, Bool) -> Void
    private var timer: Timer?
    private var latestReport: PermissionReport
    private var didCloseFromEnable = false
    private var shouldRecoverFocusFromSettings = false

    private let accessibilityStatus = NSTextField(labelWithString: "")
    private let inputMonitoringStatus = NSTextField(labelWithString: "")
    private let accessibilityAction = CallbackButton(title: "Allow")
    private let inputMonitoringAction = CallbackButton(title: "Allow")
    private let enableButton = NSButton(title: "Enable Bridge", target: nil, action: nil)

    init(
        isStartupGate: Bool,
        reportProvider: @escaping () -> PermissionReport,
        onReady: @escaping () -> Void,
        onClose: @escaping (PermissionReport, Bool) -> Void
    ) {
        self.isStartupGate = isStartupGate
        self.reportProvider = reportProvider
        self.onReady = onReady
        self.onClose = onClose
        self.latestReport = reportProvider()

        let contentView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 720, height: 560))
        contentView.material = .hudWindow
        contentView.blendingMode = .behindWindow
        contentView.state = .active
        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DoubaoVoiceBridge Permissions"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentView = contentView

        super.init(window: window)
        window.delegate = self
        buildContent(in: contentView)
        refresh()
        startPolling()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        guard !didCloseFromEnable else {
            return
        }
        onClose(latestReport, isStartupGate)
    }

    private func buildContent(in contentView: NSView) {
        let appIcon = PermissionHeroIconView()
        appIcon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Enable Doubao Voice Bridge")
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.alignment = .center
        title.lineBreakMode = .byWordWrapping

        let message = NSTextField(wrappingLabelWithString: "Doubao Voice Bridge needs these permissions to listen for Right Command and return focus after voice input. They are only used while the bridge is running.")
        message.font = .systemFont(ofSize: 16)
        message.textColor = .secondaryLabelColor
        message.alignment = .center

        let accessibilityRow = permissionRow(
            title: "Accessibility",
            detail: "Allows Doubao Voice Bridge to restore the app you were using after switching input.",
            statusLabel: accessibilityStatus,
            actionButton: accessibilityAction,
            symbolName: "accessibility",
            accentColor: .systemBlue
        ) { [weak self] in
            NSWorkspace.shared.open(PermissionKind.accessibility.settingsURL)
            self?.markSettingsOpened()
            self?.refresh()
        }

        let inputMonitoringRow = permissionRow(
            title: "Input Monitoring",
            detail: "Allows the bridge to detect Right Command as your push-to-talk trigger.",
            statusLabel: inputMonitoringStatus,
            actionButton: inputMonitoringAction,
            symbolName: "keyboard",
            accentColor: .systemTeal
        ) { [weak self] in
            NSWorkspace.shared.open(PermissionKind.inputMonitoring.settingsURL)
            self?.markSettingsOpened()
            self?.refresh()
        }

        enableButton.target = self
        enableButton.action = #selector(enableBridge)
        enableButton.bezelStyle = .rounded
        enableButton.keyEquivalent = "\r"
        enableButton.controlSize = .large

        let footer = NSTextField(labelWithString: "This window checks permission status automatically.")
        footer.font = .systemFont(ofSize: 12)
        footer.textColor = .tertiaryLabelColor
        footer.alignment = .center

        let buttonRow = NSView()
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addSubview(enableButton)
        enableButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [appIcon, title, message, accessibilityRow, inputMonitoringRow, footer, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 68),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -68),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 88),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -34),
            appIcon.widthAnchor.constraint(equalToConstant: 92),
            appIcon.heightAnchor.constraint(equalToConstant: 92),
            title.widthAnchor.constraint(equalTo: stack.widthAnchor),
            message.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.86),
            accessibilityRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            inputMonitoringRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            enableButton.centerXAnchor.constraint(equalTo: buttonRow.centerXAnchor),
            enableButton.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            enableButton.widthAnchor.constraint(equalToConstant: 150),
            buttonRow.heightAnchor.constraint(equalToConstant: 34)
        ])

        stack.setCustomSpacing(22, after: message)
        stack.setCustomSpacing(14, after: accessibilityRow)
        stack.setCustomSpacing(20, after: inputMonitoringRow)
        stack.setCustomSpacing(8, after: footer)
    }

    private func permissionRow(
        title: String,
        detail: String,
        statusLabel: NSTextField,
        actionButton: CallbackButton,
        symbolName: String,
        accentColor: NSColor,
        action: @escaping () -> Void
    ) -> NSView {
        let icon = PermissionSymbolView(symbolName: symbolName, accentColor: accentColor)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)

        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: 14)

        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.alignment = .right

        let openButton = actionButton
        openButton.callback = action
        openButton.bezelStyle = .rounded
        openButton.controlSize = .large

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 5

        let trailingStack = NSStackView(views: [statusLabel, openButton])
        trailingStack.orientation = .horizontal
        trailingStack.alignment = .centerY
        trailingStack.spacing = 14

        let row = NSStackView(views: [icon, textStack, trailingStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 18
        row.translatesAutoresizingMaskIntoConstraints = false

        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        trailingStack.setContentHuggingPriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            statusLabel.widthAnchor.constraint(equalToConstant: 74),
            openButton.widthAnchor.constraint(equalToConstant: 92)
        ])

        let card = PermissionCardView(contentView: row)
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 92)
        ])
        return card
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refresh()
            self.recoverFocusIfSettingsClosed()
        }
    }

    private func refresh() {
        latestReport = reportProvider()
        updateStatus(
            label: accessibilityStatus,
            isGranted: latestReport.accessibilityGranted
        )
        updateStatus(
            label: inputMonitoringStatus,
            isGranted: latestReport.inputMonitoringGranted
        )
        enableButton.isHidden = !latestReport.isReady
        enableButton.isEnabled = latestReport.isReady
    }

    private func markSettingsOpened() {
        shouldRecoverFocusFromSettings = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.recoverFocusIfSettingsClosed()
        }
    }

    private func recoverFocusIfSettingsClosed() {
        guard shouldRecoverFocusFromSettings else {
            return
        }
        let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if bundleIdentifier == "com.apple.SystemSettings" || bundleIdentifier == "com.apple.systempreferences" {
            return
        }
        shouldRecoverFocusFromSettings = false
        bringToFront()
    }

    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func updateStatus(label: NSTextField, isGranted: Bool) {
        label.stringValue = "Done ✓"
        label.textColor = .labelColor
        label.isHidden = !isGranted

        let button = label === accessibilityStatus ? accessibilityAction : inputMonitoringAction
        button.title = "Allow"
        button.isHidden = isGranted
    }

    @objc private func enableBridge() {
        refresh()
        guard latestReport.isReady else {
            return
        }
        didCloseFromEnable = true
        timer?.invalidate()
        close()
        onReady()
    }
}

private final class PermissionHeroIconView: NSView {
    private let appIcon: NSImage? = {
        if let image = NSImage(named: "AppIcon") {
            return image
        }
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: iconURL) {
            return image
        }
        return nil
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 14
        layer?.shadowOffset = NSSize(width: 0, height: 8)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let appIcon else {
            return
        }

        appIcon.draw(
            in: bounds.insetBy(dx: 2, dy: 2),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}

private final class PermissionSymbolView: NSView {
    private let symbolName: String
    private let accentColor: NSColor

    init(symbolName: String, accentColor: NSColor) {
        self.symbolName = symbolName
        self.accentColor = accentColor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            image.isTemplate = true
            accentColor.set()
            image.draw(
                in: bounds.insetBy(dx: 14, dy: 14),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        }
    }
}

private final class PermissionCardView: NSView {
    init(contentView: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.78).cgColor
        layer?.cornerRadius = 24
        layer?.cornerCurve = .continuous
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 14
        layer?.shadowOffset = NSSize(width: 0, height: 5)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            contentView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class CallbackButton: NSButton {
    var callback: () -> Void

    init(title: String, action: @escaping () -> Void = {}) {
        self.callback = action
        super.init(frame: .zero)
        self.title = title
        self.target = self
        self.action = #selector(runCallback)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runCallback() {
        callback()
    }
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

private final class LaunchAgentManager {
    private let label: String
    private let logger: AppLogger
    private let fileManager: FileManager

    init(label: String, logger: AppLogger, fileManager: FileManager = .default) {
        self.label = label
        self.logger = logger
        self.fileManager = fileManager
    }

    func installForCurrentApp() throws -> Bool {
        guard let executableURL = Bundle.main.executableURL else {
            throw LaunchAgentError.missingExecutableURL
        }

        let plistURL = Self.plistURL(label: label)
        let logDirectoryURL = AppLogger.defaultLogURL.deletingLastPathComponent()
        let plist = LaunchAgentPlist(
            label: label,
            executableURL: executableURL,
            logDirectoryURL: logDirectoryURL
        )
        let data = try plist.data()

        try fileManager.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)

        let existingData = try? Data(contentsOf: plistURL)
        let plistChanged = existingData != data
        if plistChanged {
            try data.write(to: plistURL, options: .atomic)
            logger.log("launch agent plist written: \(plistURL.path)")
        }

        let runningUnderLaunchAgent = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == label
        let isLoaded = launchctlPrint()

        if isLoaded, plistChanged, !runningUnderLaunchAgent {
            _ = runLaunchctl(arguments: ["bootout", "gui/\(getuid())/\(label)"])
        }

        if !isLoaded || (plistChanged && !runningUnderLaunchAgent) {
            try runLaunchctlOrThrow(arguments: ["bootstrap", "gui/\(getuid())", plistURL.path])
            try runLaunchctlOrThrow(arguments: ["enable", "gui/\(getuid())/\(label)"])
            logger.log("launch agent bootstrapped")
            return !runningUnderLaunchAgent
        }

        try runLaunchctlOrThrow(arguments: ["enable", "gui/\(getuid())/\(label)"])
        logger.log("launch agent already active")
        return !runningUnderLaunchAgent
    }

    func uninstall() throws {
        let plistURL = Self.plistURL(label: label)
        if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
        }
        if launchctlPrint() {
            _ = runLaunchctl(arguments: ["bootout", "gui/\(getuid())/\(label)"])
        }
    }

    var isInstalled: Bool {
        let plistURL = Self.plistURL(label: label)
        return fileManager.fileExists(atPath: plistURL.path) || launchctlPrint()
    }

    private func launchctlPrint() -> Bool {
        runLaunchctl(arguments: ["print", "gui/\(getuid())/\(label)"]).status == 0
    }

    private func runLaunchctlOrThrow(arguments: [String]) throws {
        let result = runLaunchctl(arguments: arguments)
        guard result.status == 0 else {
            throw LaunchAgentError.launchctlFailed(arguments: arguments, output: result.output)
        }
    }

    private func runLaunchctl(arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (1, "\(error)")
        }
    }

    private static func plistURL(label: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
}

private enum LaunchAgentError: Error, CustomStringConvertible {
    case missingExecutableURL
    case launchctlFailed(arguments: [String], output: String)

    var description: String {
        switch self {
        case .missingExecutableURL:
            return "missing Bundle.main.executableURL"
        case .launchctlFailed(let arguments, let output):
            return "launchctl \(arguments.joined(separator: " ")) failed: \(output)"
        }
    }
}
