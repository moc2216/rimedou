import XCTest
@testable import RimeDouCore

final class CompletionStateTests: XCTestCase {
    func testQianwenStopAtMostOnceAndNoEarlyRestore() {
        var machine = VoiceStateMachine()
        _ = machine.handle(.triggerTap)
        XCTAssertEqual(machine.handle(.explicitStopRequested), [.stopVoice])
        XCTAssertEqual(machine.state, .waitingForProviderCompletion)
        for event: VoiceEvent in [.triggerTap, .explicitStopRequested, .externalVoiceEnd, .forcedStop] {
            XCTAssertEqual(machine.handle(event), [])
        }
        XCTAssertEqual(machine.handle(.providerCompletion), [.restoreInputMethod])
        XCTAssertEqual(machine.handle(.providerCompletion), [])
    }

    func testPhysicalProviderStopDoesNotSendAnotherToggle() {
        var machine = VoiceStateMachine(state: .voiceActive)
        XCTAssertEqual(machine.handle(.explicitStopObserved), [])
        XCTAssertEqual(machine.state, .waitingForProviderCompletion)
    }

    func testFailureBlocksEveryPhaseWithoutSendingToggle() {
        for state: VoiceState in [.voiceActive, .waitingForProviderCompletion, .restoringInputMethod] {
            var machine = VoiceStateMachine(state: state)
            XCTAssertEqual(machine.handle(.failed), [])
            XCTAssertEqual(machine.state, .blocked)
            XCTAssertEqual(machine.handle(.triggerTap), [])
            XCTAssertEqual(machine.handle(.forcedStop), [])
            _ = machine.handle(.recovered)
            XCTAssertEqual(machine.state, .idle)
        }
    }
}
