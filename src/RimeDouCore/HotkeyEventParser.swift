public enum HotkeyKeyCode {
    public static let leftControl: Int64 = 59
    public static let rightControl: Int64 = 62
    public static let rightCommand: Int64 = 54
}

public struct HotkeyEventParser {
    private let triggerKeyCode: Int64
    private var triggerKeyDown = false

    public init(triggerKeyCode: Int64) {
        self.triggerKeyCode = triggerKeyCode
    }

    public mutating func parse(keyCode: Int64, isTriggerDown: Bool, isSynthetic: Bool = false, isVoiceActive: Bool = false, isKeyDownEvent: Bool = false) -> SwitchEvent? {
        if isSynthetic {
            return nil
        }

        // 语音激活期间，任意常规按键（keyDown）都视为“结束语音”。
        // 豆包原生会在该按键时自行停止语音，工具只需切回主输入法。
        if isKeyDownEvent && isVoiceActive {
            return .anyKeyPressed
        }

        guard keyCode == triggerKeyCode else {
            return nil
        }

        if isTriggerDown && !triggerKeyDown {
            triggerKeyDown = true
            return .triggerKeyPressed
        }

        if !isTriggerDown {
            triggerKeyDown = false
        }

        return nil
    }
}
