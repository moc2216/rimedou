import XCTest
@testable import DoubaoVoiceBridgeCore

final class BridgeStateMachineTests: XCTestCase {
    func testTriggerDownWaitsForHoldThresholdBeforeStartingVoiceSession() {
        var machine = BridgeStateMachine()

        let downActions = machine.handle(.rightCommandDown)
        let thresholdActions = machine.handle(.triggerHoldThresholdPassed)

        XCTAssertEqual(downActions, [])
        XCTAssertEqual(thresholdActions, [.startVoiceSession])
        XCTAssertEqual(machine.state, .preparingVoice)
    }

    func testTriggerUpBeforeHoldThresholdDoesNotStartVoiceSession() {
        var machine = BridgeStateMachine()

        let downActions = machine.handle(.rightCommandDown)
        let upActions = machine.handle(.rightCommandUp)

        XCTAssertEqual(downActions, [])
        XCTAssertEqual(upActions, [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testRightCommandUpBeforeOptionHoldCancelsPendingVoiceTrigger() {
        var machine = BridgeStateMachine()

        _ = machine.handle(.rightCommandDown)
        let downActions = machine.handle(.triggerHoldThresholdPassed)
        let upActions = machine.handle(.rightCommandUp)

        XCTAssertEqual(downActions, [.startVoiceSession])
        XCTAssertEqual(upActions, [.cancelPendingOptionHold, .restorePreviousInputMethod])
        XCTAssertEqual(machine.state, .idle)
    }

    func testRightCommandUpWhileHoldingOptionReleasesOptionThenRestoresInputMethod() {
        var machine = BridgeStateMachine()

        _ = machine.handle(.rightCommandDown)
        _ = machine.handle(.triggerHoldThresholdPassed)
        _ = machine.handle(.optionHoldStarted)
        let actions = machine.handle(.rightCommandUp)

        XCTAssertEqual(actions, [.releaseOptionHold, .restorePreviousInputMethod])
        XCTAssertEqual(machine.state, .idle)
    }
}
