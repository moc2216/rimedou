import AppKit
import RimeDouCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let selectionKey = "selectedVoiceProvider"
    private let logger: RimeDouLogger
    private var config: RimeDouConfig
    private var keyboardEngine: KeyboardEngine
    private let inputMethods: InputMethodController
    private var coordinator: VoiceSessionCoordinator!
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var providerItems: [VoiceProviderID: NSMenuItem] = [:]
    private var toggleItem: NSMenuItem?
    private var reloadItem: NSMenuItem?
    private var discardItem: NSMenuItem?
    private var emergencyQuitItem: NSMenuItem?
    private var permissionWindow: PermissionsWindowController?
    private var selectedProvider: VoiceProviderID?
    private var installedProviders = Set<VoiceProviderID>()
    private var configProviders = Set<VoiceProviderID>()
    private var enabled = true
    private var capturing = false
    private var warmingUp = false
    private var didWarmUpDoubao = false
    private var initializationMessage: String?
    private var sleeping = false
    private var terminationRequested = false
    private var healthTimer: Timer?

    override init() {
        let logger = RimeDouLogger()
        self.logger = logger
        let inputs = InputMethodController(logger: logger)
        inputMethods = inputs
        let providers = VoiceProviderRegistry.installedProviders { inputs.hasInputSource(identifier: $0) }
        installedProviders = providers
        configProviders = providers
        config = RimeDouConfig.loadFromDefaultLocation(installedProviders: providers, onWarning: { [logger] in logger.log($0) })
        keyboardEngine = KeyboardEngine(config: config, logger: logger,
                                         postEventToPID: { $0.postToPid($1) })
        super.init()
        connectCoordinator()
    }

    private func connectCoordinator() {
        coordinator = VoiceSessionCoordinator(keyboard: keyboardEngine, inputMethods: inputMethods, logger: logger)
        coordinator.onChange = { [weak self] in self?.stateChanged() }
        coordinator.onIdleTrigger = { [weak self] in self?.startSelectedProvider() }
        coordinator.onRecoveryPaused = { [weak self] in
            self?.enabled = false
            self?.capturing = false
            self?.stateChanged()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMenu()
        refreshProviders()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkRuntimeHealth() }
        }
        if currentPermissionReport().isReady { prepareCapture() } else { showPermissionWindow() }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
        logger.log("rimedou v3 launched (build \(build))")
    }

    private func installMenu() {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        func add(_ title: String, _ action: Selector?, _ key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
            return item
        }
        statusMenuItem = add("语音来源", nil)
        statusMenuItem?.isEnabled = false
        providerItems[.doubao] = add("豆包", #selector(selectDoubao))
        providerItems[.qianwen] = add("千问", #selector(selectQianwen))
        menu.addItem(.separator())
        toggleItem = add("暂停快捷键", #selector(toggleEnabled))
        _ = add("打开日志", #selector(openLog))
        _ = add("打开配置", #selector(openConfig))
        reloadItem = add("重新加载配置", #selector(reloadConfig))
        _ = add("检查权限", #selector(checkPermissionsFromMenu))
        discardItem = add("确认语音已结束，丢弃暂存并恢复快捷键", #selector(recoverInput))
        emergencyQuitItem = add("确认语音已结束，丢弃暂存并退出", #selector(emergencyQuit))
        menu.addItem(.separator())
        _ = add("退出", #selector(quit), "q")
        status.menu = menu
        statusItem = status
        updateMenuItems()
    }

    func menuWillOpen(_ menu: NSMenu) { refreshProviders(); updateMenuItems() }

    private func refreshProviders() {
        installedProviders = VoiceProviderRegistry.installedProviders { inputMethods.hasInputSource(identifier: $0) }
        // Re-read the original JSON, not the already-sanitized configuration:
        // adding/removing a provider can create or remove a hotkey conflict.
        if installedProviders != configProviders, settingsAvailable {
            reloadConfig()
            return
        }
        if selectedProvider == nil {
            let saved = UserDefaults.standard.string(forKey: Self.selectionKey).flatMap(VoiceProviderID.init(rawValue:))
            // Prefer installed Qianwen even if it still needs a transport configured,
            // so a Qianwen-only installation can show a useful setup status.
            selectedProvider = VoiceProviderSelectionResolver.resolve(saved: saved, usableProviders: installedProviders)
        }
        updateMenuItems()
    }

    private var settingsAvailable: Bool { coordinator.state == .idle && !warmingUp && keyboardEngine.canReconfigure }
    private var sourceSelectionAvailable: Bool { !warmingUp && coordinator.canSelectProvider }

    private func updateMenuItems() {
        for provider in VoiceProviderID.allCases {
            let installed = installedProviders.contains(provider)
            let configured = VoiceProviderRegistry.definition(for: provider, config: config) != nil
            providerItems[provider]?.title = provider.displayName + (!installed ? "（未安装或未启用）" : !configured ? "（请先配置语音快捷键）" : "")
            providerItems[provider]?.state = selectedProvider == provider ? .on : .off
            providerItems[provider]?.isEnabled = sourceSelectionAvailable && installed
        }
        toggleItem?.title = enabled ? "暂停快捷键" : "启用快捷键"
        toggleItem?.isEnabled = !coordinator.isRecoveringInput && (settingsAvailable || coordinator.state == .blocked || coordinator.state == .restoringInputMethod)
        reloadItem?.isEnabled = settingsAvailable
        discardItem?.isHidden = coordinator.state != .blocked && keyboardEngine.deferredEventCount == 0
        discardItem?.isEnabled = !coordinator.isRecoveringInput && (coordinator.state == .blocked || coordinator.state == .restoringInputMethod)
        emergencyQuitItem?.isHidden = coordinator.state != .blocked
        emergencyQuitItem?.isEnabled = coordinator.state == .blocked
        let label: String
        if let message = coordinator.message ?? initializationMessage { label = message }
        else if warmingUp { label = "正在初始化豆包语音快捷键…" }
        else if !enabled { label = "快捷键已暂停" }
        else {
            switch coordinator.state {
            case .voiceActive: label = "语音输入中"
            case .waitingForProviderCompletion: label = "等待\(coordinator.sessionProvider?.displayName ?? "语音")文字上屏，按键已暂存…"
            case .restoringInputMethod: label = "正在恢复输入法，请松开按键…"
            case .blocked: label = "请确认语音已结束，并手动切回 RIME"
            case .idle:
                if let selectedProvider {
                    if !installedProviders.contains(selectedProvider) { label = "所选来源当前不可用" }
                    else if VoiceProviderRegistry.definition(for: selectedProvider, config: config) == nil { label = "请在配置中填写与千问设置一致的语音快捷键" }
                    else { label = "语音来源" }
                } else { label = "未检测到可用语音输入法" }
            }
        }
        statusMenuItem?.title = label
        let glyph = (coordinator.sessionProvider ?? selectedProvider)?.statusGlyph ?? "—"
        let suffix = coordinator.state == .blocked ? "!" : !enabled ? "-" : coordinator.state != .idle || warmingUp ? "…" : ""
        statusItem?.button?.title = glyph + suffix
        statusItem?.button?.toolTip = label
    }

    @objc private func selectDoubao() { select(.doubao) }
    @objc private func selectQianwen() { select(.qianwen) }
    private func select(_ provider: VoiceProviderID) {
        guard sourceSelectionAvailable, installedProviders.contains(provider) else { return }
        selectedProvider = provider
        initializationMessage = nil
        UserDefaults.standard.set(provider.rawValue, forKey: Self.selectionKey)
        if enabled { prepareCapture() }
        updateMenuItems()
    }

    private func startSelectedProvider() {
        guard enabled, capturing, !warmingUp, !sleeping, !terminationRequested else { return }
        refreshProviders()
        guard enabled, capturing, !warmingUp, !sleeping, !terminationRequested else { return }
        guard installedProviders == configProviders else {
            initializationMessage = "输入法列表已变化，请松开按键后重新加载配置"
            updateMenuItems()
            return
        }
        guard let selectedProvider, installedProviders.contains(selectedProvider),
              let definition = VoiceProviderRegistry.definition(for: selectedProvider, config: config) else {
            NSSound.beep(); return
        }
        // A refused start that already explains itself in the menu stays silent;
        // only truly unexplained refusals also beep.
        if !coordinator.start(provider: definition, config: config), coordinator.message == nil {
            NSSound.beep()
        }
    }

    private func prepareCapture() {
        guard enabled, !sleeping, !warmingUp, currentPermissionReport().isReady else { return }
        if coordinator.state == .idle, selectedProvider == .doubao, installedProviders.contains(.doubao), !didWarmUpDoubao,
           let original = inputMethods.currentInputSourceIdentity()?.identifier,
           !VoiceProviderRegistry.isVoiceInputSourceIdentifier(original) {
            warmingUp = true
            coordinator.rememberOrdinarySource()
            inputMethods.warmUpDoubaoInputMethod(config: config) { [weak self] success in
                guard let self else { return }
                self.warmingUp = false
                self.didWarmUpDoubao = success
                if !success, self.inputMethods.currentInputSourceIdentity().map({ VoiceProviderRegistry.isVoiceInputSourceIdentifier($0.identifier) }) ?? true {
                    self.initializationMessage = "初始化后未能恢复输入法，请手动切回 RIME 后重新启用快捷键"
                    self.enabled = false
                    self.capturing = false
                }
                if self.enabled, !self.sleeping { self.capturing = self.coordinator.resume() }
                self.stateChanged()
            }
        } else { capturing = coordinator.resume() }
        updateMenuItems()
    }

    @objc private func toggleEnabled() {
        // Recovery must always let the user pause the listener by mouse.
        // The coordinator retains buffered input while suspended.
        guard settingsAvailable || coordinator.state == .blocked || coordinator.state == .restoringInputMethod else { return }
        enabled.toggle()
        if enabled {
            initializationMessage = nil
            if currentPermissionReport().isReady { prepareCapture() } else { showPermissionWindow() }
        } else { coordinator.suspend(reason: "快捷键已暂停"); capturing = false }
        updateMenuItems()
    }

    @objc private func reloadConfig() {
        guard settingsAvailable else { return }
        coordinator.shutdown()
        initializationMessage = nil
        installedProviders = VoiceProviderRegistry.installedProviders { inputMethods.hasInputSource(identifier: $0) }
        configProviders = installedProviders
        config = RimeDouConfig.loadFromDefaultLocation(installedProviders: installedProviders, onWarning: { [logger] in logger.log($0) })
        keyboardEngine = KeyboardEngine(config: config, logger: logger,
                                         postEventToPID: { $0.postToPid($1) })
        connectCoordinator()
        capturing = false
        refreshProviders()
        if enabled { prepareCapture() }
    }

    @objc private func openLog() { NSWorkspace.shared.open(RimeDouLogger.defaultLogURL) }
    @objc private func openConfig() { NSWorkspace.shared.activateFileViewerSelecting([RimeDouConfig.defaultUserConfigURL]) }
    @objc private func checkPermissionsFromMenu() { refreshProviders(); showPermissionWindow() }
    @objc private func recoverInput() {
        guard !warmingUp, !sleeping else { return }
        let accepted = coordinator.recoverByDiscardingInput { [weak self] success in
            guard let self else { return }
            if success {
                self.enabled = true
                self.initializationMessage = nil
                if self.currentPermissionReport().isReady { self.prepareCapture() } else { self.showPermissionWindow() }
                self.updateMenuItems()
            } else { self.showRecoveryFailure() }
        }
        if !accepted { showRecoveryFailure() }
    }

    private func showRecoveryFailure() {
        updateMenuItems()
        let alert = NSAlert()
        alert.messageText = "快捷键恢复尚未完成"
        alert.informativeText = coordinator.message ?? "请查看菜单状态并确认语音已结束后再次恢复"
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func emergencyQuit() {
        // This explicitly labelled menu action is the user's choice to discard.
        coordinator.discardBufferedInput()
        coordinator.shutdown()
        terminationRequested = false
        allowEmergencyTermination = true
        NSApp.terminate(nil)
    }
    private var allowEmergencyTermination = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowEmergencyTermination || (coordinator.state == .idle && !warmingUp && !keyboardEngine.isSendingHotkey) { return .terminateNow }
        guard coordinator.state != .blocked else { NSSound.beep(); return .terminateCancel }
        terminationRequested = true
        DispatchQueue.main.async { [weak self] in
            self?.coordinator.requestFinishForQuit()
            self?.stateChanged()
        }
        return .terminateLater
    }

    private func stateChanged() {
        updateMenuItems()
        guard terminationRequested else { return }
        if coordinator.state == .idle, !warmingUp, !keyboardEngine.isSendingHotkey {
            terminationRequested = false
            NSApp.reply(toApplicationShouldTerminate: true)
        } else if coordinator.state == .blocked {
            terminationRequested = false
            NSApp.reply(toApplicationShouldTerminate: false)
        }
    }

    private func checkRuntimeHealth() {
        guard !sleeping else { return }
        if capturing, (!AXIsProcessTrusted() || !CGPreflightListenEventAccess()) {
            coordinator.suspend(reason: "权限已撤销：请恢复权限，并确认语音已结束后切回 RIME")
            capturing = false
            enabled = false
            updateMenuItems()
        }
        if terminationRequested, coordinator.state == .voiceActive { coordinator.requestFinishForQuit() }
    }

    @objc private func willSleep() {
        sleeping = true
        warmingUp = false
        didWarmUpDoubao = false
        coordinator.suspend(reason: "睡眠打断了语音：请确认语音已结束，并手动切回 RIME")
        capturing = false
    }

    @objc private func didWake() {
        sleeping = false
        refreshProviders()
        if enabled { prepareCapture() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        healthTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        coordinator.shutdown()
        logger.log("rimedou terminated")
    }
    private func currentPermissionReport() -> PermissionReport {
        PermissionReport(
            accessibilityGranted: AXIsProcessTrusted(),
            inputMonitoringGranted: inputMonitoringPermissionIsGranted()
        )
    }

    private func inputMonitoringPermissionIsGranted() -> Bool {
        guard CGPreflightListenEventAccess() else { return false }
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        // Probe the same tap layer the engine actually uses, so the check reflects
        // what starting the engine will really require.
        guard let tap = CGEvent.tapCreate(
            tap: KeyboardEngine.eventTapLocation,
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

}

extension AppDelegate: PermissionsWindowControllerDelegate {
    func permissionsWindowControllerDidBecomeReady(_ controller: PermissionsWindowController) {
        permissionWindow = nil
        NSApp.setActivationPolicy(.accessory)
        enabled = true
        prepareCapture()
    }
}
