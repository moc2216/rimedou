import SwitchOnlyDoubaoVoiceInputCore

enum HotkeyTests {
    static func run() {
        testRightControlPressProducesRightControlEvent()
        testLeftControlPressProducesLeftControlEvent()
        testOtherKeyProducesNoEvent()
        testRightControlReleaseDoesNotRepeatEvent()
    }

    private static func testRightControlPressProducesRightControlEvent() {
        var parser = HotkeyEventParser()

        let event = parser.parseModifierChange(keyCode: HotkeyKeyCode.rightControl, isControlDown: true)

        TestExpect.equal(event, .rightControlPressed, "right Ctrl press should produce right control event")
    }

    private static func testLeftControlPressProducesLeftControlEvent() {
        var parser = HotkeyEventParser()

        let event = parser.parseModifierChange(keyCode: HotkeyKeyCode.leftControl, isControlDown: true)

        TestExpect.equal(event, .leftControlPressed, "left Ctrl press should produce left control event")
    }

    private static func testOtherKeyProducesNoEvent() {
        var parser = HotkeyEventParser()

        let event = parser.parseModifierChange(keyCode: 0, isControlDown: true)

        TestExpect.isNil(event, "non-control key should produce no event")
    }

    private static func testRightControlReleaseDoesNotRepeatEvent() {
        var parser = HotkeyEventParser()

        _ = parser.parseModifierChange(keyCode: HotkeyKeyCode.rightControl, isControlDown: true)
        let event = parser.parseModifierChange(keyCode: HotkeyKeyCode.rightControl, isControlDown: false)

        TestExpect.isNil(event, "right Ctrl release should not repeat event")
    }
}
