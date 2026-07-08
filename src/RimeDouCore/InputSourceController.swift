import Carbon
import Foundation

public final class InputSourceController: @unchecked Sendable {
    public init() {}

    public func currentInputSourceName() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return "unknown"
        }
        return propertyString(source, kTISPropertyLocalizedName) ??
            propertyString(source, kTISPropertyInputSourceID) ??
            "unknown"
    }

    public func selectInputSource(namedOrIdentifiedBy value: String) -> Bool {
        guard let source = findInputSource(matching: value) else {
            return false
        }
        return TISSelectInputSource(source) == noErr
    }

    public func waitUntilActive(
        matches value: String,
        timeout: TimeInterval,
        pollInterval: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            // TISCopyCurrentKeyboardInputSource must be called from the main thread.
            let current = DispatchQueue.main.sync { currentInputSourceName() }
            if current == value || current.localizedCaseInsensitiveContains(value) {
                return true
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return false
    }

    private func findInputSource(matching value: String) -> TISInputSource? {
        guard let unmanaged = TISCreateInputSourceList(nil, true) else {
            return nil
        }
        let sources = unmanaged.takeRetainedValue() as NSArray
        for item in sources {
            guard let source = item as! TISInputSource? else { continue }
            let name = propertyString(source, kTISPropertyLocalizedName)
            let identifier = propertyString(source, kTISPropertyInputSourceID)
            if name == value || identifier == value ||
                name?.localizedCaseInsensitiveContains(value) == true ||
                identifier?.localizedCaseInsensitiveContains(value) == true {
                return source
            }
        }
        return nil
    }

    private func propertyString(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let value = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }
}
