import XCTest
@testable import RimeDouCore

final class StateMachineTests: XCTestCase {
    func testExplicitRecoveryCanRestartBlockedOrInterruptedRestore() {
        for state in [VoiceState.blocked, .restoringInputMethod] {
            var machine = VoiceStateMachine(state: state)
            XCTAssertEqual(machine.handle(.recoveryRequested), [.restoreInputMethod])
            XCTAssertEqual(machine.state, .restoringInputMethod)
            _ = machine.handle(.restoreCompleted)
            XCTAssertEqual(machine.state, .idle)
        }
    }

    func testExplicitRecoveryDoesNotInterruptActiveOrCompletingVoice() {
        for state in [VoiceState.idle, .voiceActive, .waitingForProviderCompletion] {
            var machine = VoiceStateMachine(state: state)
            XCTAssertEqual(machine.handle(.recoveryRequested), [])
            XCTAssertEqual(machine.state, state)
        }
    }

    func testTapFromIdleStartsVoice() {
        var machine = VoiceStateMachine()
        let actions = machine.handle(.triggerTap)
        XCTAssertEqual(actions, [.startVoiceSession])
        XCTAssertEqual(machine.state, .voiceActive)
    }

    func testTapWhileActiveRestoresWithoutResendingVoiceHotkey() {
        var machine = VoiceStateMachine()
        _ = machine.handle(.triggerTap)
        let actions = machine.handle(.triggerTap)
        XCTAssertEqual(actions, [.restoreInputMethod])
        XCTAssertEqual(machine.state, .restoringInputMethod)
    }

    func testExternalVoiceEndRestoresWithoutResendingVoiceHotkey() {
        var machine = VoiceStateMachine()
        _ = machine.handle(.triggerTap)
        let actions = machine.handle(.externalVoiceEnd)
        XCTAssertEqual(actions, [.restoreInputMethod])
        XCTAssertEqual(machine.state, .restoringInputMethod)
    }

    func testForcedStopStillSendsVoiceHotkeyBeforeRestoring() {
        var machine = VoiceStateMachine()
        _ = machine.handle(.triggerTap)

        XCTAssertEqual(machine.handle(.forcedStop), [.stopVoice, .restoreInputMethod])
        XCTAssertEqual(machine.state, .restoringInputMethod)
    }

    func testTapWhileRestoringDoesNotStartAnotherSession() {
        var machine = VoiceStateMachine()
        _ = machine.handle(.triggerTap)
        _ = machine.handle(.externalVoiceEnd)

        XCTAssertEqual(machine.handle(.triggerTap), [])
        XCTAssertEqual(machine.state, .restoringInputMethod)
    }

    func testRestoreCompletionReturnsToIdle() {
        var machine = VoiceStateMachine()
        _ = machine.handle(.triggerTap)
        _ = machine.handle(.externalVoiceEnd)

        XCTAssertEqual(machine.handle(.restoreCompleted), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testPunctuationAfterRestoreCannotSendAnotherVoiceHotkey() {
        var machine = VoiceStateMachine()
        _ = machine.handle(.triggerTap)
        _ = machine.handle(.externalVoiceEnd)
        _ = machine.handle(.restoreCompleted)

        XCTAssertEqual(machine.handle(.externalVoiceEnd), [])
        XCTAssertEqual(machine.state, .idle)
    }
}
