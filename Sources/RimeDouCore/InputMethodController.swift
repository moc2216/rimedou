import AppKit
import ApplicationServices
import Carbon
import Foundation

public struct StartupInputMethodWarmupPlan: Equatable, Sendable {
    public static let doubaoInputSourceIdentifier = "com.bytedance.inputmethod.doubaoime.pinyin"

    public let selectionTargets: [String]

    public static func make(currentInputMethod: String) -> StartupInputMethodWarmupPlan? {
        let current = currentInputMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty, current.lowercased() != "unknown" else { return nil }
        if InputMethodController.isDoubaoInputMethod(current) {
            return StartupInputMethodWarmupPlan(selectionTargets: [doubaoInputSourceIdentifier])
        }
        return StartupInputMethodWarmupPlan(
            selectionTargets: [doubaoInputSourceIdentifier, current]
        )
    }
}

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

    public func warmUpDoubaoInputMethod(
        config: RimeDouConfig,
        settleDelay: TimeInterval = 0.8,
        completion: @escaping (Bool) -> Void
    ) {
        let current = currentInputMethod()
        guard let plan = StartupInputMethodWarmupPlan.make(currentInputMethod: current),
              let doubao = plan.selectionTargets.first else {
            logger.log("startup warmup skipped: original input method is unknown")
            completion(false)
            return
        }

        logger.log("startup warmup: activate doubao (original: \(current))")
        guard selectInputMethod(namedOrIdentifiedBy: doubao) else {
            logger.log("startup warmup failed: cannot select doubao")
            completion(false)
            return
        }

        waitUntilInputMethodIsActive(
            doubao,
            pollInterval: config.switchPollInterval,
            timeout: config.switchWaitTimeout
        ) { [weak self] doubaoIsActive in
            guard let self else { return }
            guard doubaoIsActive else {
                self.logger.log("startup warmup failed: doubao did not become active")
                completion(false)
                return
            }

            self.logger.log("startup warmup: doubao active; waiting for shortcut initialization")
            DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) { [weak self] in
                guard let self else { return }
                guard plan.selectionTargets.count > 1 else {
                    self.logger.log("startup warmup completed: doubao was already the original input method")
                    completion(true)
                    return
                }

                let original = plan.selectionTargets[1]
                guard self.selectInputMethod(namedOrIdentifiedBy: original) else {
                    self.logger.log("startup warmup failed: cannot restore \(original)")
                    completion(false)
                    return
                }
                self.waitUntilInputMethodIsActive(
                    original,
                    pollInterval: config.switchPollInterval,
                    timeout: config.switchWaitTimeout
                ) { [weak self] restored in
                    self?.logger.log(
                        restored
                            ? "startup warmup completed: restored \(original)"
                            : "startup warmup failed: \(original) did not become active"
                    )
                    completion(restored)
                }
            }
        }
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
                if InputMethodController.inputMethod(current, matches: target) {
                    logger.log("restore: at \(target) (attempt \(attempt + 1)/\(maxAttempts), done)")
                    completion()
                    return
                }
                let ok = self.selectInputMethod(namedOrIdentifiedBy: target)
                self.restoreOriginalFocus(originalApp: originalApp, originalWindow: originalWindow, config: config)
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

    private func restoreOriginalFocus(
        originalApp: NSRunningApplication?,
        originalWindow: AXUIElement?,
        config: RimeDouConfig
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + config.focusBounceBackDelay) { [weak self] in
            originalApp?.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + config.focusBounceSettleDelay) { [weak self] in
                guard let self else { return }
                if let window = originalWindow {
                    let mainResult = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                    let focusedResult = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                    if mainResult != .success {
                        self.logger.log("restoreOriginalFocus: set main attribute failed with \(mainResult)")
                    }
                    if focusedResult != .success {
                        self.logger.log("restoreOriginalFocus: set focused attribute failed with \(focusedResult)")
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

    private func waitUntilInputMethodIsActive(
        _ target: String,
        pollInterval: TimeInterval,
        timeout: TimeInterval,
        completion: @escaping (Bool) -> Void
    ) {
        let maxAttempts = max(1, Int(ceil(timeout / pollInterval)))

        func step(attempt: Int) {
            let current = self.currentInputMethod()
            if InputMethodController.inputMethod(current, matches: target) {
                completion(true)
                return
            }
            guard attempt + 1 < maxAttempts else {
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) {
                step(attempt: attempt + 1)
            }
        }

        step(attempt: 0)
    }

    private func propertyString(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }

    public nonisolated static func isDoubaoInputMethod(_ name: String) -> Bool {
        name.contains("豆包") || name.lowercased().contains("doubao") || name.lowercased().contains("bytedance")
    }

    public nonisolated static func inputMethod(_ current: String, matches target: String) -> Bool {
        if isDoubaoInputMethod(current), isDoubaoInputMethod(target) {
            return true
        }
        return current.caseInsensitiveCompare(target) == .orderedSame ||
            current.localizedCaseInsensitiveContains(target) ||
            target.localizedCaseInsensitiveContains(current)
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
