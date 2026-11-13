import XCTest
@testable import RimeDouCore

final class WindowLifecycleTests: XCTestCase {
    private func sample(_ tracker: inout ProviderWindowLifecycleTracker, _ windows: Set<Int>?, _ now: TimeInterval) -> ProviderWindowCompletionEvent {
        tracker.observe(current: windows, now: now, completionTimeout: 60, goneStabilityDelay: 0.15)
    }

    func testNeverObservedOrBaselineOnlyCannotComplete() {
        var tracker = ProviderWindowLifecycleTracker(baseline: [1])
        tracker.beginWaiting(at: 0)
        XCTAssertEqual(sample(&tracker, [1], 1), .none)
        XCTAssertEqual(sample(&tracker, [], 2), .none)
        XCTAssertEqual(sample(&tracker, [], 60), .timedOut)
    }

    func testCompletionRequiresStopAndStableGone() {
        var tracker = ProviderWindowLifecycleTracker()
        XCTAssertEqual(sample(&tracker, [2], 0), .none)
        XCTAssertEqual(sample(&tracker, [], 10), .none)
        tracker.beginWaiting(at: 11)
        XCTAssertEqual(sample(&tracker, [], 11), .none)
        XCTAssertEqual(sample(&tracker, [], 11.1), .none)
        XCTAssertEqual(sample(&tracker, [], 11.16), .completed)
    }

    func testReappearingOrReplacementWindowResetsGoneCountdown() {
        var tracker = ProviderWindowLifecycleTracker(baseline: [1])
        _ = sample(&tracker, [1, 2], 0)
        tracker.beginWaiting(at: 1)
        _ = sample(&tracker, [1], 2)
        XCTAssertEqual(sample(&tracker, [1, 3], 2.1), .none)
        XCTAssertEqual(sample(&tracker, [1, 3], 10), .none)
        _ = sample(&tracker, [1], 11)
        XCTAssertEqual(sample(&tracker, [1], 11.2), .completed)
    }

    func testFailedWindowReadIsNotEmptyWindowList() {
        var tracker = ProviderWindowLifecycleTracker()
        _ = sample(&tracker, [1], 0)
        tracker.beginWaiting(at: 1)
        _ = sample(&tracker, [], 2)
        XCTAssertEqual(sample(&tracker, nil, 2.2), .none)
        XCTAssertEqual(sample(&tracker, [], 2.3), .none)
        XCTAssertEqual(sample(&tracker, [], 2.5), .completed)
    }

    func testTimeoutDoesNotBecomeCompletionOnLatePoll() {
        var tracker = ProviderWindowLifecycleTracker()
        _ = sample(&tracker, [1], 0)
        tracker.beginWaiting(at: 1)
        _ = sample(&tracker, [], 2)
        XCTAssertEqual(sample(&tracker, [], 62), .timedOut)
    }
}
