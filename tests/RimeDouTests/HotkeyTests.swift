import RimeDouCore

enum HotkeyTests {
    static func run() {
        testRightCommandPressProducesTriggerEvent()
        testRightCommandReleaseDoesNotRepeatEvent()
        testRightControlIsIgnoredWhenTriggerIsRightCommand()
        testOtherKeyProducesNoEvent()
        testSyntheticEventIsIgnored()
        testAnyKeyDownStopsVoiceWhenActive()
        testAnyKeyDownDoesNothingWhenIdle()
        testAnyKeyDownIgnoredWhenSynthetic()
    }

    private static func testRightCommandPressProducesTriggerEvent() {
        var parser = HotkeyEventParser(triggerKeyCode: HotkeyKeyCode.rightCommand)

        let event = parser.parse(keyCode: HotkeyKeyCode.rightCommand, isTriggerDown: true)

        TestExpect.equal(event, .triggerKeyPressed, "right Cmd press should produce trigger event")
    }

    private static func testRightCommandReleaseDoesNotRepeatEvent() {
        var parser = HotkeyEventParser(triggerKeyCode: HotkeyKeyCode.rightCommand)

        _ = parser.parse(keyCode: HotkeyKeyCode.rightCommand, isTriggerDown: true)
        let event = parser.parse(keyCode: HotkeyKeyCode.rightCommand, isTriggerDown: false)

        TestExpect.isNil(event, "right Cmd release should not repeat event")
    }

    private static func testRightControlIsIgnoredWhenTriggerIsRightCommand() {
        var parser = HotkeyEventParser(triggerKeyCode: HotkeyKeyCode.rightCommand)

        let event = parser.parse(keyCode: HotkeyKeyCode.rightControl, isTriggerDown: true)

        TestExpect.isNil(event, "right Ctrl should be ignored when trigger is right Cmd (no collision)")
    }

    private static func testOtherKeyProducesNoEvent() {
        var parser = HotkeyEventParser(triggerKeyCode: HotkeyKeyCode.rightCommand)

        let event = parser.parse(keyCode: 0, isTriggerDown: true)

        TestExpect.isNil(event, "non-trigger key should produce no event")
    }

    private static func testSyntheticEventIsIgnored() {
        var parser = HotkeyEventParser(triggerKeyCode: HotkeyKeyCode.rightCommand)

        let event = parser.parse(keyCode: HotkeyKeyCode.rightCommand, isTriggerDown: true, isSynthetic: true)

        TestExpect.isNil(event, "synthetic event should be ignored")
    }

    // 空格键码 = 49，代表“任意常规按键”。
    private static func testAnyKeyDownStopsVoiceWhenActive() {
        var parser = HotkeyEventParser(triggerKeyCode: HotkeyKeyCode.rightCommand)

        let event = parser.parse(keyCode: 49, isTriggerDown: false, isVoiceActive: true, isKeyDownEvent: true)

        TestExpect.equal(event, .anyKeyPressed, "any keyDown while voice active should produce anyKeyPressed")
    }

    private static func testAnyKeyDownDoesNothingWhenIdle() {
        var parser = HotkeyEventParser(triggerKeyCode: HotkeyKeyCode.rightCommand)

        let event = parser.parse(keyCode: 49, isTriggerDown: false, isVoiceActive: false, isKeyDownEvent: true)

        TestExpect.isNil(event, "any keyDown while idle should produce no event")
    }

    private static func testAnyKeyDownIgnoredWhenSynthetic() {
        var parser = HotkeyEventParser(triggerKeyCode: HotkeyKeyCode.rightCommand)

        let event = parser.parse(keyCode: 49, isTriggerDown: false, isSynthetic: true, isVoiceActive: true, isKeyDownEvent: true)

        TestExpect.isNil(event, "synthetic keyDown should be ignored")
    }
}
