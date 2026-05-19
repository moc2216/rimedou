import XCTest
@testable import DoubaoVoiceBridgeCore

final class BridgeStateMachineTests: XCTestCase {
    func testRightCommandUpBeforeOptionHoldCancelsPendingVoiceTrigger() {
        var machine = BridgeStateMachine()

        let downActions = machine.handle(.rightCommandDown)
        let upActions = machine.handle(.rightCommandUp)

        XCTAssertEqual(downActions, [.startVoiceSession])
        XCTAssertEqual(upActions, [.cancelPendingOptionHold, .restoreUserInputMethod])
        XCTAssertEqual(machine.state, .idle)
    }

    func testRightCommandUpWhileHoldingOptionReleasesOptionThenRestoresInputMethod() {
        var machine = BridgeStateMachine()

        _ = machine.handle(.rightCommandDown)
        _ = machine.handle(.optionHoldStarted)
        let actions = machine.handle(.rightCommandUp)

        XCTAssertEqual(actions, [.releaseOptionHold, .restoreUserInputMethod])
        XCTAssertEqual(machine.state, .idle)
    }
}
