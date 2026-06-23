public enum HotkeyKeyCode {
    public static let leftControl: Int64 = 59
    public static let rightControl: Int64 = 62
}

public struct HotkeyParseResult: Equatable {
    public let event: SwitchEvent?

    public init(event: SwitchEvent?) {
        self.event = event
    }
}

public struct HotkeyEventParser {
    private var pressedControlKeyCodes: Set<Int64> = []

    public init() {}

    public mutating func parseModifierChange(
        keyCode: Int64,
        isControlDown: Bool,
        isSynthetic: Bool = false
    ) -> SwitchEvent? {
        parseModifierChangeResult(
            keyCode: keyCode,
            isControlDown: isControlDown,
            isSynthetic: isSynthetic
        )?.event
    }

    public mutating func parseModifierChangeResult(
        keyCode: Int64,
        isControlDown: Bool,
        isSynthetic: Bool = false
    ) -> HotkeyParseResult? {
        if isSynthetic {
            return nil
        }

        guard keyCode == HotkeyKeyCode.leftControl || keyCode == HotkeyKeyCode.rightControl else {
            return nil
        }

        if isControlDown && !pressedControlKeyCodes.contains(keyCode) {
            pressedControlKeyCodes.insert(keyCode)
            let event: SwitchEvent = keyCode == HotkeyKeyCode.rightControl ? .rightControlPressed : .leftControlPressed
            return HotkeyParseResult(event: event)
        }

        if !isControlDown {
            pressedControlKeyCodes.remove(keyCode)
            return HotkeyParseResult(event: nil)
        }

        return HotkeyParseResult(event: nil)
    }
}
