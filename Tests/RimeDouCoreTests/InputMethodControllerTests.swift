import XCTest
@testable import RimeDouCore

final class InputMethodControllerTests: XCTestCase {
    func testIsDoubaoInputMethod() {
        XCTAssertTrue(InputMethodController.isDoubaoInputMethod("豆包输入法"))
        XCTAssertTrue(InputMethodController.isDoubaoInputMethod("Doubao IME"))
        XCTAssertTrue(InputMethodController.isDoubaoInputMethod("bytedance-ime"))
        XCTAssertFalse(InputMethodController.isDoubaoInputMethod("Squirrel"))
    }
}
