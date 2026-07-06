/**
 * [INPUT]: 依赖 XCTest 的断言能力，依赖 DoubaoVoiceBridgeCore 的 BridgeStateMachine
 * [OUTPUT]: 对外提供全局唤起 toggle 状态机的行为回归测试
 * [POS]: Tests/DoubaoVoiceBridgeCoreTests 的核心状态测试，约束点按生命周期与恢复动作
 * [PROTOCOL]: 变更时更新此头部，然后检查 codex.md
 */
import XCTest
@testable import DoubaoVoiceBridgeCore

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
