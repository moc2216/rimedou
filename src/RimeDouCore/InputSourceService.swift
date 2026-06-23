import Carbon
import Foundation

public protocol InputSourceSelecting {
    func selectInputSource(id: String) throws
    func currentInputSourceId() throws -> String
}

public enum InputSourceError: Error, CustomStringConvertible, Equatable {
    case sourceNotFound(String)
    case sourceNotSelectable(String)
    case currentSourceUnavailable
    case selectionFailed(String, Int32)

    public var description: String {
        switch self {
        case .sourceNotFound(let id):
            return "Input source not found: \(id)"
        case .sourceNotSelectable(let id):
            return "Input source is installed but not enabled/selectable: \(id)"
        case .currentSourceUnavailable:
            return "Current input source is unavailable"
        case .selectionFailed(let id, let status):
            return "Failed to select input source: \(id), status: \(status)"
        }
    }
}

public struct InputSourceService: InputSourceSelecting {
    public init() {}

    public func containsInputSource(id: String) -> Bool {
        inputSource(for: id, includeAllInstalled: true) != nil
    }

    public func containsSelectableInputSource(id: String) -> Bool {
        inputSource(for: id, includeAllInstalled: false) != nil
    }

    public func allInputSourceIds() -> [String] {
        allInputSources(includeAllInstalled: true).compactMap { inputSourceId(from: $0) }
    }

    public func allSelectableInputSourceIds() -> [String] {
        allInputSources(includeAllInstalled: false).compactMap { inputSourceId(from: $0) }
    }

    public func descriptors(matching text: String? = nil) -> [InputSourceDescriptor] {
        allInputSources(includeAllInstalled: true)
            .compactMap { descriptor(from: $0) }
            .filter { descriptor in
                guard let text, !text.isEmpty else {
                    return true
                }

                return descriptor.id.contains(text)
                    || descriptor.bundleId.contains(text)
                    || descriptor.localizedName.contains(text)
            }
    }

    public func requireInputSource(id: String) throws {
        guard containsInputSource(id: id) else {
            throw InputSourceError.sourceNotFound(id)
        }
    }

    public func currentInputSourceId() throws -> String {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let id = inputSourceId(from: currentSource) else {
            throw InputSourceError.currentSourceUnavailable
        }

        return id
    }

    public func selectInputSource(id: String) throws {
        guard containsInputSource(id: id) else {
            throw InputSourceError.sourceNotFound(id)
        }

        guard let source = inputSource(for: id, includeAllInstalled: false) else {
            throw InputSourceError.sourceNotSelectable(id)
        }

        let status = TISSelectInputSource(source)
        guard status == noErr else {
            throw InputSourceError.selectionFailed(id, status)
        }
    }

    private func inputSource(for id: String, includeAllInstalled: Bool) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let unmanagedSources = TISCreateInputSourceList(filter, includeAllInstalled) else {
            return nil
        }

        let sources = unmanagedSources.takeRetainedValue() as NSArray
        return sources.firstObject as! TISInputSource?
    }

    private func allInputSources(includeAllInstalled: Bool) -> [TISInputSource] {
        guard let unmanagedSources = TISCreateInputSourceList(nil, includeAllInstalled) else {
            return []
        }

        let sources = unmanagedSources.takeRetainedValue() as NSArray
        return sources.compactMap { $0 as! TISInputSource? }
    }

    private func inputSourceId(from source: TISInputSource) -> String? {
        guard let rawValue = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }

        return Unmanaged<CFString>.fromOpaque(rawValue).takeUnretainedValue() as String
    }

    private func descriptor(from source: TISInputSource) -> InputSourceDescriptor? {
        guard let id = inputSourceId(from: source) else {
            return nil
        }

        return InputSourceDescriptor(
            id: id,
            localizedName: stringProperty(source, kTISPropertyLocalizedName),
            bundleId: stringProperty(source, kTISPropertyBundleID),
            category: stringProperty(source, kTISPropertyInputSourceCategory),
            sourceType: stringProperty(source, kTISPropertyInputSourceType),
            isEnabled: boolProperty(source, kTISPropertyInputSourceIsEnabled),
            isSelected: boolProperty(source, kTISPropertyInputSourceIsSelected),
            isEnableCapable: boolProperty(source, kTISPropertyInputSourceIsEnableCapable),
            isSelectCapable: boolProperty(source, kTISPropertyInputSourceIsSelectCapable)
        )
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String {
        guard let rawValue = TISGetInputSourceProperty(source, key) else {
            return ""
        }

        return Unmanaged<CFString>.fromOpaque(rawValue).takeUnretainedValue() as String
    }

    private func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let rawValue = TISGetInputSourceProperty(source, key) else {
            return false
        }

        let value = Unmanaged<CFBoolean>.fromOpaque(rawValue).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }
}

public struct InputSourceDescriptor: Equatable {
    public let id: String
    public let localizedName: String
    public let bundleId: String
    public let category: String
    public let sourceType: String
    public let isEnabled: Bool
    public let isSelected: Bool
    public let isEnableCapable: Bool
    public let isSelectCapable: Bool
}
