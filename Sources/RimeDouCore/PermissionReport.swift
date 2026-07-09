import Foundation

public enum PermissionKind: CaseIterable, Equatable, Sendable {
    case accessibility
    case inputMonitoring

    public var displayName: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        }
    }

    public var settingsURL: URL {
        switch self {
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .inputMonitoring:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        }
    }
}

public struct PermissionReport: Equatable, Sendable {
    public var accessibilityGranted: Bool
    public var inputMonitoringGranted: Bool

    public init(accessibilityGranted: Bool, inputMonitoringGranted: Bool) {
        self.accessibilityGranted = accessibilityGranted
        self.inputMonitoringGranted = inputMonitoringGranted
    }

    public var isReady: Bool {
        missingPermissions.isEmpty
    }

    public var missingPermissions: [PermissionKind] {
        var permissions: [PermissionKind] = []
        if !accessibilityGranted { permissions.append(.accessibility) }
        if !inputMonitoringGranted { permissions.append(.inputMonitoring) }
        return permissions
    }

    public var message: String {
        let names = missingPermissions.map(\.displayName)
        let joined: String
        switch names.count {
        case 0: joined = "no"
        case 1: joined = names[0]
        case 2: joined = "\(names[0]) and \(names[1])"
        default: joined = names.dropLast().joined(separator: ", ") + ", and \(names.last!)"
        }
        return "rimedou needs \(joined) permissions before the trigger hotkey can start voice input."
    }
}
