import Foundation

public final class AppLogger: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "RimeDou.AppLogger")
    private let formatter: ISO8601DateFormatter

    public init(url: URL = AppLogger.defaultLogURL) {
        self.url = url
        self.formatter = ISO8601DateFormatter()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    public static var defaultLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/RimeDou/app.log")
    }

    public func log(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async { [url] in
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: Data(line.utf8))
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
