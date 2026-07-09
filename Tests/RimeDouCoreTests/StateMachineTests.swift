import XCTest
@testable import RimeDouCore

final class StateMachineTests: XCTestCase {
    func testTapFromIdleStartsVoice() {
        var machine = VoiceStateMachine()
        let actions = machine.handle(.triggerTap)
        XCTAssertEqual(actions, [.startVoiceSession])
        XCTAssertEqual(machine.state, .voiceActive)
    }

    func testTapWhileActiveStopsVoiceAndRestores() {
        var machine = VoiceStateMachine()
        _ = machine.handle(.triggerTap)
        let actions = machine.handle(.triggerTap)
        XCTAssertEqual(actions, [.stopVoice, .restoreInputMethod])
        XCTAssertEqual(machine.state, .idle)
    }

    func testExternalVoiceEndRestoresWithoutStopping() {
        var machine = VoiceStateMachine()
        _ = machine.handle(.triggerTap)
        let actions = machine.handle(.externalVoiceEnd)
        XCTAssertEqual(actions, [.restoreInputMethod])
        XCTAssertEqual(machine.state, .idle)
    }

    func testResetReturnsToIdle() {
        var machine = VoiceStateMachine()
        _ = machine.handle(.triggerTap)
        _ = machine.handle(.reset)
        XCTAssertEqual(machine.state, .idle)
    }
}
