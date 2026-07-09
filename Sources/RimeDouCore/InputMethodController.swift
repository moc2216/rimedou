import AppKit
import ApplicationServices
import Carbon
import Foundation

@MainActor
public final class InputMethodController {
    private let logger: RimeDouLogger

    public init(logger: RimeDouLogger) {
        self.logger = logger
    }

    public func currentInputMethod() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return "unknown"
        }
        return propertyString(source, kTISPropertyLocalizedName)
            ?? propertyString(source, kTISPropertyInputSourceID)
            ?? "unknown"
    }

    public func selectInputMethod(namedOrIdentifiedBy value: String) -> Bool {
        guard let source = findInputSource(matching: value) else {
            return false
        }
        return TISSelectInputSource(source) == noErr
    }

    public func restoreInputMethod(
        _ target: String,
        originalApp: NSRunningApplication?,
        originalWindow: AXUIElement?,
        config: RimeDouConfig,
        completion: @escaping () -> Void
    ) {
        let maxAttempts = max(1, Int(ceil(config.switchWaitTimeout / config.switchPollInterval)))
        let logger = self.logger

        func step(attempt: Int) {
            let delay = attempt == 0 ? config.restoreDelay : config.switchPollInterval
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let current = self.currentInputMethod()
                if current == target || current.localizedCaseInsensitiveContains(target) {
                    logger.log("restore: at \(target) (attempt \(attempt + 1)/\(maxAttempts), done)")
                    completion()
                    return
                }
                let ok = self.selectInputMethod(namedOrIdentifiedBy: target)
                self.flushInputContext(originalApp: originalApp, originalWindow: originalWindow, config: config)
                logger.log("restore: select \(target) ok=\(ok) (was \(current), attempt \(attempt + 1)/\(maxAttempts))")
                if attempt + 1 < maxAttempts {
                    step(attempt: attempt + 1)
                } else {
                    completion()
                }
            }
        }
        step(attempt: 0)
    }

    private func flushInputContext(originalApp: NSRunningApplication?, originalWindow: AXUIElement?, config: RimeDouConfig) {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            originalApp?.activate(options: [.activateIgnoringOtherApps])
            return
        }
        finder.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + config.focusBounceBackDelay) { [weak self] in
            originalApp?.activate(options: [.activateIgnoringOtherApps])
            DispatchQueue.main.asyncAfter(deadline: .now() + config.focusBounceSettleDelay) { [weak self] in
                guard let self else { return }
                if let window = originalWindow {
                    let mainResult = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                    let focusedResult = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                    if mainResult != .success {
                        self.logger.log("flushInputContext: set main attribute failed with \(mainResult)")
                    }
                    if focusedResult != .success {
                        self.logger.log("flushInputContext: set focused attribute failed with \(focusedResult)")
                    }
                }
            }
        }
    }

    private func findInputSource(matching value: String) -> TISInputSource? {
        guard let unmanaged = TISCreateInputSourceList(nil, true) else { return nil }
        guard let sources = unmanaged.takeRetainedValue() as? [TISInputSource] else { return nil }
        for source in sources {
            let name = propertyString(source, kTISPropertyLocalizedName)
            let identifier = propertyString(source, kTISPropertyInputSourceID)
            if name == value || identifier == value ||
                name?.localizedCaseInsensitiveContains(value) == true ||
                identifier?.localizedCaseInsensitiveContains(value) == true {
                return source
            }
        }
        return nil
    }

    private func propertyString(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }

    public nonisolated static func isDoubaoInputMethod(_ name: String) -> Bool {
        name.contains("豆包") || name.lowercased().contains("doubao") || name.lowercased().contains("bytedance")
    }

    public static func focusedWindow(for app: NSRunningApplication?) -> AXUIElement? {
        guard let pid = app?.processIdentifier else { return nil }
        let element = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success, let value else { return nil }
        return (value as! AXUIElement)
    }
}
