import ApplicationServices
import CoreGraphics
import Foundation

public protocol KeyEventPosting: AnyObject {
    func postRightControlTap() -> Bool
}

public protocol VoiceHotkeyDelaying: AnyObject {
    func waitBeforeStartingVoice()
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

    private func postConfiguredHotkey() -> Bool {
        switch voiceHotkey {
        case .rightControl:
            return keyEventPoster.postRightControlTap()
        }
    }
}

public final class DefaultVoiceHotkeyDelay: VoiceHotkeyDelaying {
    private let startDelaySeconds: TimeInterval

    public init(startDelaySeconds: TimeInterval = 0.18) {
        self.startDelaySeconds = startDelaySeconds
    }

    public func waitBeforeStartingVoice() {
        Thread.sleep(forTimeInterval: startDelaySeconds)
    }
}

public final class RightControlKeyEventPoster: KeyEventPosting {
    /// 合成按键 keyDown→keyUp 之间的停留。豆包会把“零停留瞬按”判为快速双击而弹
    /// “语音唤起方式调整”；这里模拟一次有停留的慢按来规避。可按真机表现微调。
    private static let synthesizedTapDwellSeconds: TimeInterval = 0.1

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

    private func postKeyTap(virtualKey: CGKeyCode, flags: CGEventFlags, tag: Int64) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true) else {
            return false
        }

        keyDown.flags = flags
        markSynthetic(keyDown, tag: tag)
        keyDown.post(tap: .cghidEventTap)

        // 在 keyDown 与 keyUp 之间留出停留，模拟一次“慢按”，避免豆包把零停留的
        // 瞬按判定为快速双击而弹“语音唤起方式调整”。keyUp 在停留之后再创建，
        // 使其时间戳真正晚于 keyDown。
        Thread.sleep(forTimeInterval: Self.synthesizedTapDwellSeconds)

        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
            return false
        }

        keyUp.flags = []
        markSynthetic(keyUp, tag: tag)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func markSynthetic(_ event: CGEvent, tag: Int64) {
        event.setIntegerValueField(.eventSourceUserData, value: tag)
    }
}

public enum SyntheticEventTag {
    public static let rightControl: Int64 = 0x52435452
}
