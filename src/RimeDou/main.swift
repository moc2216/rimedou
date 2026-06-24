import RimeDouCore
import AppKit
import CoreFoundation
import Foundation

@main
@MainActor
struct RimeDouApp {
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()

        do {
            if arguments.isEmpty && isRunningFromAppBundle() {
                runAppBundle()
                return
            }

            if arguments.contains("--check-input-sources") {
                try checkInputSources()
                return
            }

            if arguments.contains("--check-external-voice-tool") {
                try checkExternalVoiceTool()
                return
            }

            if arguments.contains("--check-hotkey-permission") {
                checkHotkeyPermission()
                return
            }

            if arguments.contains("--check-voice-control-permission") {
                checkVoiceControlPermission()
                return
            }

            if arguments.contains("--request-permissions") {
                requestPermissions()
                return
            }

            if arguments.contains("--listen-hotkeys-once") {
                try listenHotkeysOnce()
                return
            }

            if arguments.contains("--verify-input-source-switch") {
                try verifyInputSourceSwitch()
                return
            }

            if let dumpIndex = arguments.firstIndex(of: "--dump-input-sources") {
                let nextIndex = arguments.index(after: dumpIndex)
                let filter = nextIndex < arguments.endIndex ? String(arguments[nextIndex]) : nil
                dumpInputSources(filter: filter)
                return
            }

            if let selectIndex = arguments.firstIndex(of: "--try-select-input-source") {
                let nextIndex = arguments.index(after: selectIndex)
                guard nextIndex < arguments.endIndex else {
                    print("Missing input source id")
                    return
                }

                try trySelectInputSource(id: String(arguments[nextIndex]))
                return
            }

            if let setIndex = arguments.firstIndex(of: "--set-input-source") {
                let nextIndex = arguments.index(after: setIndex)
                guard nextIndex < arguments.endIndex else {
                    print("Missing input source id")
                    return
                }

                try setInputSource(id: String(arguments[nextIndex]))
                return
            }

            if arguments.contains("--run") {
                try AppRunner().run()
                return
            }

            print("""
            rimedou: 用法
              --run                            运行菜单栏工具
              --check-input-sources            检查输入源
              --check-external-voice-tool      检查外部语音工具
              --check-hotkey-permission        检查输入监听权限
              --check-voice-control-permission 检查辅助功能权限
              --listen-hotkeys-once            监听一次触发键
              --set-input-source <id>          切换输入源
            详细说明见 README
            """)
        } catch {
            print("rimedou error: \(error)")
        }
    }

    private static func isRunningFromAppBundle() -> Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    private static func bundledConfigPath() -> String {
        if let resourcePath = Bundle.main.resourcePath {
            return "\(resourcePath)/default.json"
        }

        return "config/default.json"
    }

    private static func runAppBundle() {
        let app = NSApplication.shared
        let delegate = AppDelegate(configPath: bundledConfigPath())
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }

    private static func checkInputSources() throws {
        let config = try ConfigStore().load(path: "config/default.json")
        let service = InputSourceService()

        print("primaryInputSourceId=\(config.primaryInputSourceId) exists=\(service.containsInputSource(id: config.primaryInputSourceId)) selectable=\(service.containsSelectableInputSource(id: config.primaryInputSourceId))")
        print("doubaoInputSourceId=\(config.doubaoInputSourceId) exists=\(service.containsInputSource(id: config.doubaoInputSourceId)) selectable=\(service.containsSelectableInputSource(id: config.doubaoInputSourceId))")
        print("currentInputSourceId=\(try service.currentInputSourceId())")
    }

    private static func checkExternalVoiceTool() throws {
        let config = try ConfigStore().load(path: "config/default.json")
        let monitor = VoiceToolMonitor(config: config)

        print("externalVoiceAppPath=\(config.externalVoiceAppPath)")
        print("externalVoiceBundleId=\(config.externalVoiceBundleId)")
        print("externalVoiceToolRunning=\(monitor.isExternalVoiceToolRunning())")

        for warning in monitor.configurationWarnings() {
            print("warning=\(warning)")
        }
    }

    private static func checkHotkeyPermission() {
        print("inputMonitoringPermission=\(HotkeyMonitor.hasInputMonitoringPermission())")
    }

    private static func checkVoiceControlPermission() {
        print("accessibilityPermission=\(RightControlKeyEventPoster.hasAccessibilityPermission())")
    }

    private static func requestPermissions() {
        AppRunner.requestRequiredPermissionsIfNeeded()
        print("inputMonitoringPermission=\(HotkeyMonitor.hasInputMonitoringPermission())")
        print("accessibilityPermission=\(RightControlKeyEventPoster.hasAccessibilityPermission())")
    }

    private static func listenHotkeysOnce() throws {
        let config = try ConfigStore().load(path: "config/default.json")
        let monitor = HotkeyMonitor(triggerKey: config.triggerKey) { event in
            print("hotkeyEvent=\(event)")
            CFRunLoopStop(CFRunLoopGetCurrent())
        }

        try monitor.start()
        print("listeningForHotkey=true")
        CFRunLoopRunInMode(.defaultMode, 10, false)
        monitor.stop()
        print("listeningForHotkey=false")
    }

    private static func verifyInputSourceSwitch() throws {
        let config = try ConfigStore().load(path: "config/default.json")
        let service = InputSourceService()
        let originalInputSourceId = try service.currentInputSourceId()

        defer {
            try? service.selectInputSource(id: originalInputSourceId)
        }

        try service.requireInputSource(id: config.doubaoInputSourceId)
        try service.requireInputSource(id: config.primaryInputSourceId)

        try service.selectInputSource(id: config.doubaoInputSourceId)
        print("selectedDoubaoInputSourceId=\(try service.currentInputSourceId())")

        try service.selectInputSource(id: config.primaryInputSourceId)
        print("selectedPrimaryInputSourceId=\(try service.currentInputSourceId())")

        try service.selectInputSource(id: originalInputSourceId)
        print("restoredInputSourceId=\(try service.currentInputSourceId())")
    }

    private static func dumpInputSources(filter: String?) {
        let service = InputSourceService()

        for descriptor in service.descriptors(matching: filter) {
            print("id=\(descriptor.id)")
            print("  name=\(descriptor.localizedName)")
            print("  bundleId=\(descriptor.bundleId)")
            print("  category=\(descriptor.category)")
            print("  sourceType=\(descriptor.sourceType)")
            print("  enabled=\(descriptor.isEnabled) selected=\(descriptor.isSelected) enableCapable=\(descriptor.isEnableCapable) selectCapable=\(descriptor.isSelectCapable)")
        }
    }

    private static func trySelectInputSource(id: String) throws {
        let service = InputSourceService()
        let originalInputSourceId = try service.currentInputSourceId()

        defer {
            try? service.selectInputSource(id: originalInputSourceId)
        }

        try service.selectInputSource(id: id)
        print("selectedInputSourceId=\(try service.currentInputSourceId())")

        try service.selectInputSource(id: originalInputSourceId)
        print("restoredInputSourceId=\(try service.currentInputSourceId())")
    }

    private static func setInputSource(id: String) throws {
        let service = InputSourceService()

        try service.selectInputSource(id: id)
        print("selectedInputSourceId=\(try service.currentInputSourceId())")
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configPath: String
    private var runner: AppRunner?
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "状态：启动中", action: nil, keyEquivalent: "")
    private let toggleMenuItem = NSMenuItem(title: "暂停", action: #selector(togglePause), keyEquivalent: "")
    private let restorePrimaryMenuItem = NSMenuItem(title: "恢复鼠须管", action: #selector(restorePrimaryInput), keyEquivalent: "")
    private let quitMenuItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")

    init(configPath: String) {
        self.configPath = configPath
        super.init()
        configureStatusMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        let runner = AppRunner(configPath: configPath)
        self.runner = runner

        do {
            try runner.run(shouldStartRunLoop: false)
            updateStatusMenu()
        } catch {
            print("rimedou error: \(error)")
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runner?.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "豆"
        item.button?.toolTip = "豆包语音切换"
        item.menu = statusMenu
        statusItem = item
    }

    private func configureStatusMenu() {
        statusMenu.delegate = self
        statusMenu.addItem(statusMenuItem)
        statusMenu.addItem(.separator())

        toggleMenuItem.target = self
        statusMenu.addItem(toggleMenuItem)

        restorePrimaryMenuItem.target = self
        statusMenu.addItem(restorePrimaryMenuItem)

        statusMenu.addItem(.separator())

        quitMenuItem.target = self
        statusMenu.addItem(quitMenuItem)
    }

    private func updateStatusMenu() {
        guard let runner else {
            statusMenuItem.title = "状态：未启动"
            toggleMenuItem.isEnabled = false
            restorePrimaryMenuItem.isEnabled = false
            return
        }

        let presentation = runner.menuPresentation()
        statusMenuItem.title = presentation.statusTitle
        toggleMenuItem.title = presentation.toggleTitle
        toggleMenuItem.isEnabled = true
        restorePrimaryMenuItem.isEnabled = true
    }

    @objc private func togglePause() {
        do {
            try runner?.togglePause()
        } catch {
            print("rimedou toggle error: \(error)")
        }

        updateStatusMenu()
    }

    @objc private func restorePrimaryInput() {
        _ = runner?.restorePrimaryInputNow()
        updateStatusMenu()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            self.updateStatusMenu()
        }
    }
}
