import Foundation

public final class RimeDouLogger: @unchecked Sendable {
    private let url: URL
    private let maxFileSize: UInt64
    private let queue = DispatchQueue(label: "com.moc2216.rimedou.logger")
    private let formatter: ISO8601DateFormatter

    public init(url: URL, maxFileSize: UInt64 = 1_048_576) {
        self.url = url
        self.maxFileSize = max(1, maxFileSize)
        self.formatter = ISO8601DateFormatter()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    public convenience init() {
        self.init(url: Self.defaultLogURL)
    }

    public static var defaultLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/rimedou/app.log")
    }

    public func log(_ message: String) {
        queue.async { [self] in
            let line = "\(formatter.string(from: Date())) \(message)\n"
            let data = Data(line.utf8)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let currentSize = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
            if currentSize + UInt64(data.count) > maxFileSize {
                try? data.write(to: url, options: .atomic)
                return
            }
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
