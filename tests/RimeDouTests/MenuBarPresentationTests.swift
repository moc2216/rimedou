import RimeDouCore

enum MenuBarPresentationTests {
    static func run() {
        testRunningStatus()
        testPausedStatus()
        testExternalVoiceToolStatus()
        testDoubaoVoiceStatus()
    }

    private static func testRunningStatus() {
        let presentation = MenuBarPresentation(isPaused: false, switchState: .idle, isExternalVoiceToolRunning: false)

        TestExpect.equal(presentation.statusTitle, "状态：运行中", "idle menu status should show running")
        TestExpect.equal(presentation.toggleTitle, "暂停", "running menu toggle should pause")
    }

    private static func testPausedStatus() {
        let presentation = MenuBarPresentation(isPaused: true, switchState: .idle, isExternalVoiceToolRunning: false)

        TestExpect.equal(presentation.statusTitle, "状态：已暂停", "paused menu status should show paused")
        TestExpect.equal(presentation.toggleTitle, "启用", "paused menu toggle should enable")
    }

    private static func testExternalVoiceToolStatus() {
        let presentation = MenuBarPresentation(isPaused: false, switchState: .suspended, isExternalVoiceToolRunning: true)

        TestExpect.equal(presentation.statusTitle, "状态：Type4Me 运行中，已让渡", "external voice tool menu status should show handoff")
        TestExpect.equal(presentation.toggleTitle, "暂停", "handoff menu toggle should still allow pause")
    }

    private static func testDoubaoVoiceStatus() {
        let presentation = MenuBarPresentation(isPaused: false, switchState: .doubaoVoiceActive, isExternalVoiceToolRunning: false)

        TestExpect.equal(presentation.statusTitle, "状态：豆包语音中", "doubao voice menu status should show voice active")
    }
}
