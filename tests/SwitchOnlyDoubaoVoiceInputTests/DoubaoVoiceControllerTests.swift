import SwitchOnlyDoubaoVoiceInputCore

enum DoubaoVoiceControllerTests {
    static func run() {
        testStartVoiceInputPostsRightControlTap()
        testStartVoiceInputWaitsBeforePostingHotkey()
        testStopVoiceInputPostsRightControlTap()
        testStopVoiceInputWaitsAfterPostingHotkey()
        testDismissAdjustmentPopupPostsEscapeTap()
        testConfiguredRightControlHotkeyPostsRightControlTap()
        testPostFailureReturnsFalse()
        testSyntheticRightControlEventIsIgnoredByParser()
    }

    private static func testStartVoiceInputPostsRightControlTap() {
        let poster = FakeKeyEventPoster()
        let controller = DoubaoVoiceController(keyEventPoster: poster)

        let result = controller.startVoiceInput()

        TestExpect.isTrue(result, "start voice input should return true when posting succeeds")
        TestExpect.equal(poster.actions, [.rightControlTap], "start voice input should post right Ctrl tap")
    }

    private static func testStartVoiceInputWaitsBeforePostingHotkey() {
        let recorder = ActionRecorder()
        let poster = FakeKeyEventPoster(recorder: recorder)
        let delay = FakeVoiceHotkeyDelay(recorder: recorder)
        let controller = DoubaoVoiceController(keyEventPoster: poster, delay: delay)

        let result = controller.startVoiceInput()

        TestExpect.isTrue(result, "start voice input should return true when posting succeeds")
        TestExpect.equal(recorder.actions, [.waitBeforeStart, .rightControlTap], "start voice input should wait before posting hotkey")
    }

    private static func testStopVoiceInputPostsRightControlTap() {
        let poster = FakeKeyEventPoster()
        let controller = DoubaoVoiceController(keyEventPoster: poster)

        let result = controller.stopVoiceInputIfPossible()

        TestExpect.isTrue(result, "stop voice input should return true when posting succeeds")
        TestExpect.equal(poster.actions, [.rightControlTap], "stop voice input should post right Ctrl tap")
    }

    private static func testStopVoiceInputWaitsAfterPostingHotkey() {
        let recorder = ActionRecorder()
        let poster = FakeKeyEventPoster(recorder: recorder)
        let delay = FakeVoiceHotkeyDelay(recorder: recorder)
        let controller = DoubaoVoiceController(keyEventPoster: poster, delay: delay)

        let result = controller.stopVoiceInputIfPossible()

        TestExpect.isTrue(result, "stop voice input should return true when posting succeeds")
        TestExpect.equal(recorder.actions, [.rightControlTap, .waitAfterStop], "stop voice input should wait after posting hotkey")
    }

    private static func testConfiguredRightControlHotkeyPostsRightControlTap() {
        let poster = FakeKeyEventPoster()
        let controller = DoubaoVoiceController(voiceHotkey: .rightControl, keyEventPoster: poster)

        let result = controller.startVoiceInput()

        TestExpect.isTrue(result, "configured right Ctrl hotkey should post successfully")
        TestExpect.equal(poster.actions, [.rightControlTap], "configured right Ctrl should post right Ctrl tap")
    }

    private static func testDismissAdjustmentPopupPostsEscapeTap() {
        let poster = FakeKeyEventPoster()
        let controller = DoubaoVoiceController(keyEventPoster: poster)

        let result = controller.dismissAdjustmentPopupIfPossible()

        TestExpect.isTrue(result, "dismiss popup should return true when posting succeeds")
        TestExpect.equal(poster.actions, [.escapeTap], "dismiss popup should post escape tap")
    }

    private static func testPostFailureReturnsFalse() {
        let poster = FakeKeyEventPoster()
        poster.shouldSucceed = false
        let controller = DoubaoVoiceController(keyEventPoster: poster)

        let result = controller.startVoiceInput()

        TestExpect.isTrue(!result, "start voice input should return false when posting fails")
    }

    private static func testSyntheticRightControlEventIsIgnoredByParser() {
        var parser = HotkeyEventParser()

        let event = parser.parseModifierChange(
            keyCode: HotkeyKeyCode.rightControl,
            isControlDown: true,
            isSynthetic: true
        )

        TestExpect.isNil(event, "synthetic right Ctrl should be ignored")
    }
}

private final class FakeKeyEventPoster: KeyEventPosting {
    var actions: [DoubaoVoiceTestAction] { recorder.actions }
    var shouldSucceed = true
    private let recorder: ActionRecorder

    init(recorder: ActionRecorder = ActionRecorder()) {
        self.recorder = recorder
    }

    func postRightControlTap() -> Bool {
        recorder.actions.append(.rightControlTap)
        return shouldSucceed
    }

    func postEscapeTap() -> Bool {
        recorder.actions.append(.escapeTap)
        return shouldSucceed
    }
}

private enum DoubaoVoiceTestAction: Equatable {
    case waitBeforeStart
    case waitAfterStop
    case rightControlTap
    case escapeTap
}

private final class ActionRecorder {
    var actions: [DoubaoVoiceTestAction] = []
}

private final class FakeVoiceHotkeyDelay: VoiceHotkeyDelaying {
    private let recorder: ActionRecorder

    init(recorder: ActionRecorder) {
        self.recorder = recorder
    }

    func waitBeforeStartingVoice() {
        recorder.actions.append(.waitBeforeStart)
    }

    func waitAfterStoppingVoice() {
        recorder.actions.append(.waitAfterStop)
    }
}
