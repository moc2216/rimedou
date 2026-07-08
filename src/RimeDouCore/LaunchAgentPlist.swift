import Foundation

public struct LaunchAgentPlist: Equatable, Sendable {
    public let label: String
    public let executableURL: URL
    public let logDirectoryURL: URL

    public init(label: String, executableURL: URL, logDirectoryURL: URL) {
        self.label = label
        self.executableURL = executableURL
        self.logDirectoryURL = logDirectoryURL
    }

    public func data() throws -> Data {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executableURL.path],
            "RunAtLoad": true,
            "KeepAlive": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
            "StandardOutPath": logDirectoryURL.appendingPathComponent("launch-agent.out.log").path,
            "StandardErrorPath": logDirectoryURL.appendingPathComponent("launch-agent.err.log").path
        ]

        return try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
    }
}
