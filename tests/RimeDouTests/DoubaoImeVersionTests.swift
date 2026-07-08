import XCTest
@testable import RimeDouCore

final class DoubaoImeVersionTests: XCTestCase {
    func testVersionsBeforeZeroNineTwoUseLegacyHoldTrigger() {
        XCTAssertEqual(DoubaoImeVoiceStrategy.resolve(versionString: "0.9.1"), .holdHotkey)
        XCTAssertEqual(DoubaoImeVoiceStrategy.resolve(versionString: "0.8.9"), .holdHotkey)
    }

    func testZeroNineTwoAndLaterUseTapTrigger() {
        XCTAssertEqual(DoubaoImeVoiceStrategy.resolve(versionString: "0.9.2"), .tapHotkey)
        XCTAssertEqual(DoubaoImeVoiceStrategy.resolve(versionString: "0.10.0"), .tapHotkey)
        XCTAssertEqual(DoubaoImeVoiceStrategy.resolve(versionString: "1.0.0"), .tapHotkey)
    }

    func testUnknownVersionFallsBackToLegacyHoldTrigger() {
        XCTAssertEqual(DoubaoImeVoiceStrategy.resolve(versionString: nil), .holdHotkey)
        XCTAssertEqual(DoubaoImeVoiceStrategy.resolve(versionString: "bad-version"), .holdHotkey)
    }

    func testDetectorReadsFirstExistingDoubaoBundleVersion() throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let missingBundle = tempDirectory.appendingPathComponent("Missing.app", isDirectory: true)
        let bundle = tempDirectory.appendingPathComponent("DoubaoIme.app", isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        try fileManager.createDirectory(at: contents, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleShortVersionString</key>
            <string>0.9.2</string>
        </dict>
        </plist>
        """.data(using: .utf8)!.write(to: contents.appendingPathComponent("Info.plist"))

        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }

        let detector = DoubaoImeVersionDetector(bundleURLs: [missingBundle, bundle])

        XCTAssertEqual(detector.installedVersionString(), "0.9.2")
        XCTAssertEqual(detector.voiceStrategy(), .tapHotkey)
    }
}
