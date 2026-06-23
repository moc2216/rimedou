import RimeDouCore

enum RightControlRapidRepeatGuardTests {
    static func run() {
        testFirstPressIsAccepted()
        testRapidSecondPressIsSuppressed()
        testLaterPressIsAccepted()
    }

    private static func testFirstPressIsAccepted() {
        var guardState = RightControlRapidRepeatGuard(minimumIntervalSeconds: 1.0)

        let shouldSuppress = guardState.shouldSuppressPress(at: 10)

        TestExpect.isTrue(!shouldSuppress, "first right Ctrl press should be accepted")
    }

    private static func testRapidSecondPressIsSuppressed() {
        var guardState = RightControlRapidRepeatGuard(minimumIntervalSeconds: 1.0)

        _ = guardState.shouldSuppressPress(at: 10)
        let shouldSuppress = guardState.shouldSuppressPress(at: 10.4)

        TestExpect.isTrue(shouldSuppress, "rapid second right Ctrl press should be suppressed")
    }

    private static func testLaterPressIsAccepted() {
        var guardState = RightControlRapidRepeatGuard(minimumIntervalSeconds: 1.0)

        _ = guardState.shouldSuppressPress(at: 10)
        let shouldSuppress = guardState.shouldSuppressPress(at: 11.2)

        TestExpect.isTrue(!shouldSuppress, "right Ctrl press after debounce interval should be accepted")
    }
}
