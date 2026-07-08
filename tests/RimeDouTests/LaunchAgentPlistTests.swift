import XCTest
@testable import RimeDouCore

final class LaunchAgentPlistTests: XCTestCase {
    func testKeepAliveAgentPlistUsesExecutableAndInteractiveAquaSession() throws {
        let executableURL = URL(fileURLWithPath: "/Applications/RimeDou.app/Contents/MacOS/RimeDou")
        let logDirectoryURL = URL(fileURLWithPath: "/Users/tester/Library/Logs/RimeDou")

        let plist = LaunchAgentPlist(
            label: "com.moc2216.rimedou.keepalive",
            executableURL: executableURL,
            logDirectoryURL: logDirectoryURL
        )

        let data = try plist.data()
        let object = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        XCTAssertEqual(object["Label"] as? String, "com.moc2216.rimedou.keepalive")
        XCTAssertEqual(object["ProgramArguments"] as? [String], [executableURL.path])
        XCTAssertEqual(object["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(object["KeepAlive"] as? Bool, true)
        XCTAssertEqual(object["LimitLoadToSessionType"] as? String, "Aqua")
        XCTAssertEqual(object["ProcessType"] as? String, "Interactive")
        XCTAssertEqual(object["StandardOutPath"] as? String, logDirectoryURL.appendingPathComponent("launch-agent.out.log").path)
        XCTAssertEqual(object["StandardErrorPath"] as? String, logDirectoryURL.appendingPathComponent("launch-agent.err.log").path)
    }
}
