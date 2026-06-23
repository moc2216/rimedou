import ApplicationServices
import CoreGraphics
import Foundation

public protocol KeyEventPosting: AnyObject {
    func postRightControlTap() -> Bool
    func postEscapeTap() -> Bool
}

public protocol VoiceHotkeyDelaying: AnyObject {
    func waitBeforeStartingVoice()
    func waitAfterStoppingVoice()
}

public struct DoubaoVoiceController {
    private let voiceHotkey: DoubaoVoiceHotkey
    private let keyEventPoster: KeyEventPosting
    private let delay: VoiceHotkeyDelaying

    public init(
        voiceHotkey: DoubaoVoiceHotkey = .rightControl,
        keyEventPoster: KeyEventPosting = RightControlKeyEventPoster(),
        delay: VoiceHotkeyDelaying = DefaultVoiceHotkeyDelay()
    ) {
        self.voiceHotkey = voiceHotkey
        self.keyEventPoster = keyEventPoster
        self.delay = delay
    }

    public func startVoiceInput() -> Bool {
        delay.waitBeforeStartingVoice()
        return postConfiguredHotkey()
    }

    public func stopVoiceInputIfPossible() -> Bool {
        let result = postConfiguredHotkey()
        delay.waitAfterStoppingVoice()
        return result
    }

    public func dismissAdjustmentPopupIfPossible() -> Bool {
        delay.waitAfterStoppingVoice()
        return keyEventPoster.postEscapeTap()
    }

    private func postConfiguredHotkey() -> Bool {
        switch voiceHotkey {
        case .rightControl:
            return keyEventPoster.postRightControlTap()
        }
    }
}

public final class DefaultVoiceHotkeyDelay: VoiceHotkeyDelaying {
    private let startDelaySeconds: TimeInterval
    private let stopDelaySeconds: TimeInterval

    public init(startDelaySeconds: TimeInterval = 0.18, stopDelaySeconds: TimeInterval = 0.15) {
        self.startDelaySeconds = startDelaySeconds
        self.stopDelaySeconds = stopDelaySeconds
    }

    public func waitBeforeStartingVoice() {
        Thread.sleep(forTimeInterval: startDelaySeconds)
    }

    public func waitAfterStoppingVoice() {
        Thread.sleep(forTimeInterval: stopDelaySeconds)
    }
}

public final class RightControlKeyEventPoster: KeyEventPosting {
    public init() {}

    public static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    public static func requestAccessibilityPermission() -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }

    public func postRightControlTap() -> Bool {
        guard Self.hasAccessibilityPermission() else {
            return false
        }

        return postKeyTap(virtualKey: CGKeyCode(HotkeyKeyCode.rightControl), flags: .maskControl, tag: SyntheticEventTag.rightControl)
    }

    public func postEscapeTap() -> Bool {
        guard Self.hasAccessibilityPermission() else {
            return false
        }

        return postKeyTap(virtualKey: 53, flags: [], tag: SyntheticEventTag.escape)
    }

    private func postKeyTap(virtualKey: CGKeyCode, flags: CGEventFlags, tag: Int64) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
            return false
        }

        keyDown.flags = flags
        keyUp.flags = []
        markSynthetic(keyDown, tag: tag)
        markSynthetic(keyUp, tag: tag)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func markSynthetic(_ event: CGEvent, tag: Int64) {
        event.setIntegerValueField(.eventSourceUserData, value: tag)
    }
}

public enum SyntheticEventTag {
    public static let rightControl: Int64 = 0x52435452
    public static let escape: Int64 = 0x45534350
}
