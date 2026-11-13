import ApplicationServices
import XCTest
@testable import RimeDouCore

final class RestoreAndSenderTests: XCTestCase {
    @MainActor func testFailedRestoreIsNeverReportedAsSuccess() async {
        var selections = 0
        let restorer = InputSourceRestorer(current: { VoiceProviderRegistry.qianwenInputSourceIdentifier }, select: { _ in selections += 1; return false }, settleFocus: {}, sleep: { _ in })
        let result = await restorer.restore(target: "rime", config: .default, initialDelay: 0)
        XCTAssertEqual(result, .failed)
        XCTAssertGreaterThan(selections, 0)
    }

    @MainActor func testUserOrdinarySelectionIsRespectedWithoutSelectingOldTarget() async {
        var selections = 0
        let restorer = InputSourceRestorer(current: { "com.apple.keylayout.ABC" }, select: { _ in selections += 1; return true }, settleFocus: {}, sleep: { _ in })
        let result = await restorer.restore(target: "rime", config: .default, initialDelay: 0)
        XCTAssertEqual(result, .safe("com.apple.keylayout.ABC"))
        XCTAssertEqual(selections, 0)
    }

    @MainActor func testSourceVerifiedAfterFocusSettlesBeforeSuccess() async {
        var current = VoiceProviderRegistry.doubaoInputSourceIdentifier
        let restorer = InputSourceRestorer(current: { current }, select: { value in current = value; return true }, settleFocus: { current = VoiceProviderRegistry.qianwenInputSourceIdentifier }, sleep: { _ in })
        let result = await restorer.restore(target: "rime", config: .default, initialDelay: 0)
        XCTAssertEqual(result, .failed)
    }

    @MainActor func testHotkeySenderRejectsOverlappingTapsAndReleasesAllOnCancel() {
        var events: [CGEvent] = []
        let sender = HotkeySender(marker: 1234, postEvent: { events.append($0) })
        let key = Hotkey(keys: [.rightOption])
        XCTAssertTrue(sender.tap(key, duration: 10, completion: {}))
        XCTAssertFalse(sender.tap(key, duration: 10, completion: {}))
        sender.releaseAll()
        XCTAssertFalse(sender.isSending)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.last?.flags, [])
        XCTAssertTrue(events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == 1234 })
    }
}
