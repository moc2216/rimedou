import ApplicationServices
import XCTest
@testable import RimeDouCore

final class InputMethodControllerTests: XCTestCase {
    func testFieldIdentityFallsBackToWindowWhenElementWasNeverCaptured() {
        // Live evidence 2026-09-12: some frontmost apps answer AXFocusedUIElement with
        // kAXErrorNoValue while AXFocusedWindow works. A missing capture must not turn
        // into an unsatisfiable replay wait.
        XCTAssertTrue(
            InputMethodController.elementIdentityMatches(nil) { AXUIElementCreateSystemWide() },
            "an uncaptured field must let a window-matched destination replay"
        )
        XCTAssertTrue(
            InputMethodController.elementIdentityMatches(nil) { nil },
            "an uncaptured field must not require a focused element to exist either"
        )
    }

    func testFieldIdentityStillGuardsCapturedElements() {
        let captured = AXUIElementCreateSystemWide()
        XCTAssertTrue(InputMethodController.elementIdentityMatches(captured) { captured })
        XCTAssertFalse(
            InputMethodController.elementIdentityMatches(captured) { nil },
            "a captured field with no current focused element must keep waiting"
        )
        XCTAssertFalse(InputMethodController.elementIdentityMatches(captured) { AXUIElementCreateApplication(1) })
    }

    func testIsDoubaoInputMethod() {
        XCTAssertTrue(InputMethodController.isDoubaoInputMethod("豆包输入法"))
        XCTAssertTrue(InputMethodController.isDoubaoInputMethod("Doubao IME"))
        XCTAssertTrue(InputMethodController.isDoubaoInputMethod("bytedance-ime"))
        XCTAssertFalse(InputMethodController.isDoubaoInputMethod("Squirrel"))
    }

    func testStartupWarmupTemporarilySelectsDoubaoThenRestoresOriginalInputMethod() {
        let plan = StartupInputMethodWarmupPlan.make(currentInputMethod: "Squirrel - Simplified")

        XCTAssertEqual(
            plan?.selectionTargets,
            ["com.bytedance.inputmethod.doubaoime.pinyin", "Squirrel - Simplified"]
        )
    }

    func testStartupWarmupKeepsDoubaoSelectedWhenItWasAlreadyCurrent() {
        let plan = StartupInputMethodWarmupPlan.make(currentInputMethod: "豆包输入法")

        XCTAssertEqual(
            plan?.selectionTargets,
            ["com.bytedance.inputmethod.doubaoime.pinyin"]
        )
    }

    func testStartupWarmupDoesNotRiskLosingAnUnknownOriginalInputMethod() {
        XCTAssertNil(StartupInputMethodWarmupPlan.make(currentInputMethod: "unknown"))
    }

    func testLocalizedDoubaoNameMatchesItsInputSourceIdentifier() {
        XCTAssertTrue(
            InputMethodController.inputMethod(
                "豆包输入法",
                matches: "com.bytedance.inputmethod.doubaoime.pinyin"
            )
        )
    }
}
