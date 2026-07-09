import XCTest
@testable import RimeDouCore

final class PermissionReportTests: XCTestCase {
    func testReportIsReadyWhenBothGranted() {
        let report = PermissionReport(accessibilityGranted: true, inputMonitoringGranted: true)
        XCTAssertTrue(report.isReady)
        XCTAssertEqual(report.missingPermissions, [])
    }

    func testReportMissingAccessibility() {
        let report = PermissionReport(accessibilityGranted: false, inputMonitoringGranted: true)
        XCTAssertFalse(report.isReady)
        XCTAssertEqual(report.missingPermissions, [.accessibility])
    }

    func testReportMessage() {
        let report = PermissionReport(accessibilityGranted: false, inputMonitoringGranted: false)
        XCTAssertTrue(report.message.contains("Accessibility"))
        XCTAssertTrue(report.message.contains("Input Monitoring"))
    }
}
