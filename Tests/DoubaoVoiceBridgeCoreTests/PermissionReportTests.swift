import XCTest
@testable import DoubaoVoiceBridgeCore

final class PermissionReportTests: XCTestCase {
    func testReportIsReadyWhenAllRequiredPermissionsAreGranted() {
        let report = PermissionReport(accessibilityGranted: true, inputMonitoringGranted: true)

        XCTAssertTrue(report.isReady)
        XCTAssertEqual(report.missingPermissions, [])
    }

    func testReportListsMissingPermissionsInUserFacingOrder() {
        let report = PermissionReport(accessibilityGranted: false, inputMonitoringGranted: false)

        XCTAssertFalse(report.isReady)
        XCTAssertEqual(report.missingPermissions, [.accessibility, .inputMonitoring])
        XCTAssertEqual(report.message, "DoubaoVoiceBridge needs Accessibility and Input Monitoring permissions before Right Command can trigger voice input.")
    }

    func testSettingsURLsPointAtMatchingPrivacyPanes() {
        XCTAssertEqual(PermissionKind.accessibility.settingsURL.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        XCTAssertEqual(PermissionKind.inputMonitoring.settingsURL.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }
}
