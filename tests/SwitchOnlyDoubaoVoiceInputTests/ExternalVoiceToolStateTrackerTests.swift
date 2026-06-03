import SwitchOnlyDoubaoVoiceInputCore

enum ExternalVoiceToolStateTrackerTests {
    static func run() {
        testStartedEventWhenToolBecomesRunning()
        testStoppedEventWhenToolStopsRunning()
        testNoEventWhenStateDoesNotChange()
    }

    private static func testStartedEventWhenToolBecomesRunning() {
        var tracker = ExternalVoiceToolStateTracker(initiallyRunning: false)

        let event = tracker.update(isRunning: true)

        TestExpect.equal(event, .externalVoiceToolStarted, "external voice tool start should emit started event")
    }

    private static func testStoppedEventWhenToolStopsRunning() {
        var tracker = ExternalVoiceToolStateTracker(initiallyRunning: true)

        let event = tracker.update(isRunning: false)

        TestExpect.equal(event, .externalVoiceToolStopped, "external voice tool stop should emit stopped event")
    }

    private static func testNoEventWhenStateDoesNotChange() {
        var tracker = ExternalVoiceToolStateTracker(initiallyRunning: false)

        let event = tracker.update(isRunning: false)

        TestExpect.isNil(event, "unchanged external voice tool state should not emit event")
    }
}
