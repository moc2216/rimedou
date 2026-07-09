import XCTest
@testable import RimeDouCore

final class LoggerTests: XCTestCase {
    func testLoggerWritesMessageToFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logURL = tempDir.appendingPathComponent("app.log")
        let logger = RimeDouLogger(url: logURL)
        logger.log("hello rimedou")

        // Allow async write to complete
        Thread.sleep(forTimeInterval: 0.1)

        let content = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(content.contains("hello rimedou"), "logged content was: \(content)")
    }
}
