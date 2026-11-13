import AppKit
import ApplicationServices
import Carbon
import Foundation

public struct InputSourceIdentity: Equatable, Sendable {
    public let identifier: String
    public let localizedName: String
    public let bundleIdentifier: String?
}

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
public protocol InputSourceControlling: AnyObject {
    func currentInputSourceIdentity() -> InputSourceIdentity?
    func hasInputSource(identifier: String) -> Bool
    @discardableResult func selectInputSource(identifier: String) -> Bool
    func cancelPendingOperations()
    func restoreInputSource(identifier: String, originalApp: NSRunningApplication?, originalWindow: AXUIElement?,
                            config: RimeDouConfig, initialDelay: TimeInterval?, completion: @escaping (InputSourceRestoreResult) -> Void)
}

@MainActor
public final class InputMethodController: InputSourceControlling {
    private let logger: RimeDouLogger
    private var operation: Task<Void, Never>?

    public init(logger: RimeDouLogger) {
        self.logger = logger
    }

    public func currentInputSourceIdentity() -> InputSourceIdentity? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let identifier = propertyString(source, kTISPropertyInputSourceID) else { return nil }
        return InputSourceIdentity(identifier: identifier,
                                   localizedName: propertyString(source, kTISPropertyLocalizedName) ?? identifier,
                                   bundleIdentifier: propertyString(source, kTISPropertyBundleID))
    }

    public func hasInputSource(identifier: String) -> Bool { findInputSource(identifier: identifier) != nil }

    public func selectInputSource(identifier: String) -> Bool {
        guard let source = findInputSource(identifier: identifier) else { return false }
        return TISSelectInputSource(source) == noErr
    }

    public func cancelPendingOperations() { operation?.cancel(); operation = nil }

    public func warmUpDoubaoInputMethod(config: RimeDouConfig, settleDelay: TimeInterval = 0.8,
                                        completion: @escaping (Bool) -> Void) {
        cancelPendingOperations()
        guard let original = currentInputSourceIdentity()?.identifier,
              selectInputSource(identifier: VoiceProviderRegistry.doubaoInputSourceIdentifier) else {
            completion(false)
            return
        }
        operation = Task { [weak self] in
            guard let self else { return }
            let doubao = VoiceProviderRegistry.doubaoInputSourceIdentifier
            defer {
                // Cancelling startup during sleep must not strand the user in Doubao.
                if Task.isCancelled, original != doubao,
                   self.currentInputSourceIdentity()?.identifier == doubao {
                    _ = self.selectInputSource(identifier: original)
                }
            }
            let attempts = max(1, Int(ceil(config.switchWaitTimeout / config.switchPollInterval)))
            for _ in 0..<attempts {
                if self.currentInputSourceIdentity()?.identifier == doubao { break }
                do { try await Task.sleep(for: .seconds(config.switchPollInterval)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            guard self.currentInputSourceIdentity()?.identifier == doubao else { completion(false); return }
            do { try await Task.sleep(for: .seconds(settleDelay)) } catch { return }
            // A user-selected ordinary source takes precedence during warm-up too.
            if let current = self.currentInputSourceIdentity()?.identifier, current != doubao {
                completion(!VoiceProviderRegistry.isVoiceInputSourceIdentifier(current))
                return
            }
            if original == doubao { completion(true); return }
            let restorer = InputSourceRestorer(current: { self.currentInputSourceIdentity()?.identifier },
                                              select: { self.selectInputSource(identifier: $0) }, settleFocus: {})
            let result = await restorer.restore(target: original, config: config, initialDelay: 0)
            guard !Task.isCancelled else { return }
            if case .safe = result { completion(true) } else { completion(false) }
        }
    }

    public func restoreInputSource(identifier target: String, originalApp: NSRunningApplication?,
                                   originalWindow: AXUIElement?, config: RimeDouConfig,
                                   initialDelay: TimeInterval? = nil,
                                   completion: @escaping (InputSourceRestoreResult) -> Void) {
        cancelPendingOperations()
        let startedAt = CFAbsoluteTimeGetCurrent()
        logger.log("input source restore started: \(target)")
        operation = Task { [weak self] in
            guard let self else { return }
            let restorer = InputSourceRestorer(
                current: { self.currentInputSourceIdentity()?.identifier },
                select: { self.selectInputSource(identifier: $0) },
                settleFocus: {
                    await self.settleOriginalFocus(app: originalApp, window: originalWindow, config: config)
                }
            )
            let result = await restorer.restore(target: target, config: config, initialDelay: initialDelay ?? config.restoreDelay)
            // A restore task once vanished silently (2026-09-12); lifecycle logs make
            // the next occurrence attributable. Elapsed time only, no content.
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
            guard !Task.isCancelled else {
                self.logger.log("input source restore cancelled after \(elapsed)ms")
                return
            }
            self.logger.log("input source restore result: \(result) in \(elapsed)ms")
            completion(result)
        }
    }

    private func settleOriginalFocus(app: NSRunningApplication?, window: AXUIElement?, config: RimeDouConfig) async {
        do { try await Task.sleep(for: .seconds(config.focusBounceBackDelay)) } catch { return }
        // Check at the moment of each effect, not before a delayed callback.
        guard Self.focusStillMatches(app: app, window: window), !Task.isCancelled else { return }
        app?.activate(options: [])
        do { try await Task.sleep(for: .seconds(config.focusBounceSettleDelay)) } catch { return }
        guard Self.focusStillMatches(app: app, window: window), !Task.isCancelled else { return }
        if let window {
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
    }

    public static func focusStillMatches(app: NSRunningApplication?, window: AXUIElement?) -> Bool {
        guard let app, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return false }
        guard let window else { return false }
        guard let focused = focusedWindow(for: app) else { return false }
        return CFEqual(window, focused)
    }

    private func findInputSource(identifier: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
        guard let unmanaged = TISCreateInputSourceList(filter, false),
              let sources = unmanaged.takeRetainedValue() as? [TISInputSource] else { return nil }
        return sources.first { propertyString($0, kTISPropertyInputSourceID) == identifier }
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

    public static func focusedElement(for app: NSRunningApplication?) -> AXUIElement? {
        focusedElementCapture(for: app).element
    }

    /// `axError` is a diagnostic code only; it never carries content.
    public static func focusedElementCapture(for app: NSRunningApplication?) -> (element: AXUIElement?, axError: AXError?) {
        guard let pid = app?.processIdentifier else { return (nil, nil) }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &value)
        guard result == .success, let value else { return (nil, result == .success ? nil : result) }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return (nil, nil) }
        return ((value as! AXUIElement), nil)
    }

    /// Replay-destination policy for the focused text field. Some apps answer
    /// AXFocusedUIElement with kAXErrorNoValue while AXFocusedWindow works
    /// (live probe 2026-09-12), so an uncaptured field falls back to the captured
    /// window identity instead of becoming an unsatisfiable replay wait.
    public nonisolated static func elementIdentityMatches(_ captured: AXUIElement?, fetchCurrent: () -> AXUIElement?) -> Bool {
        guard let captured else { return true }
        guard let current = fetchCurrent() else { return false }
        return CFEqual(captured, current)
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
