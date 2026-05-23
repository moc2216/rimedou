import XCTest
@testable import DoubaoVoiceBridgeCore

final class LaunchAgentPlistTests: XCTestCase {
    func testKeepAliveAgentPlistUsesExecutableAndInteractiveAquaSession() throws {
        let executableURL = URL(fileURLWithPath: "/Applications/DoubaoVoiceBridge.app/Contents/MacOS/DoubaoVoiceBridge")
        let logDirectoryURL = URL(fileURLWithPath: "/Users/tester/Library/Logs/DoubaoVoiceBridge")

        let plist = LaunchAgentPlist(
            label: "local.doubao-voice-bridge.keepalive",
            executableURL: executableURL,
            logDirectoryURL: logDirectoryURL
        )

        let data = try plist.data()
        let object = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        XCTAssertEqual(object["Label"] as? String, "local.doubao-voice-bridge.keepalive")
        XCTAssertEqual(object["ProgramArguments"] as? [String], [executableURL.path])
        XCTAssertEqual(object["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(object["KeepAlive"] as? Bool, true)
        XCTAssertEqual(object["LimitLoadToSessionType"] as? String, "Aqua")
        XCTAssertEqual(object["ProcessType"] as? String, "Interactive")
        XCTAssertEqual(object["StandardOutPath"] as? String, logDirectoryURL.appendingPathComponent("launch-agent.out.log").path)
        XCTAssertEqual(object["StandardErrorPath"] as? String, logDirectoryURL.appendingPathComponent("launch-agent.err.log").path)
    }
}
