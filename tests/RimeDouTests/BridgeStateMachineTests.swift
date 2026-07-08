import XCTest
@testable import RimeDouCore

final class BridgeStateMachineTests: XCTestCase {
    func testTapFromIdleStartsVoice() {
        var machine = BridgeStateMachine()

        let actions = machine.handle(.triggerTap)

        XCTAssertEqual(actions, [.startVoiceSession])
        XCTAssertEqual(machine.state, .voiceActive)
    }

    func testTapWhileActiveStopsVoiceAndRestores() {
        var machine = BridgeStateMachine()

        _ = machine.handle(.triggerTap)
        let actions = machine.handle(.triggerTap)

        XCTAssertEqual(actions, [.stopVoice, .restorePreviousInputMethod])
        XCTAssertEqual(machine.state, .idle)
    }

    func testExternalVoiceEndRestoresWithoutStopping() {
        var machine = BridgeStateMachine()

        _ = machine.handle(.triggerTap)
        let actions = machine.handle(.externalVoiceEnd)

        XCTAssertEqual(actions, [.restorePreviousInputMethod])
        XCTAssertEqual(machine.state, .idle)
    }

    func testResetReturnsToIdle() {
        var machine = BridgeStateMachine()

        _ = machine.handle(.triggerTap)
        _ = machine.handle(.reset)

        XCTAssertEqual(machine.state, .idle)
    }
}
