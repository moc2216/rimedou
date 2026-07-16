import XCTest
@testable import RimeDouCore

final class InputMethodControllerTests: XCTestCase {
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
