import AppKit
import CoreGraphics

/// Window visibility only; no titles, accessibility text, or voice content.
@MainActor
public enum DoubaoWindowQuery {
    public static func visibleWindowIDs() -> Set<Int>? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let owners = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.bytedance.inputmethod.doubaoime").map { Int($0.processIdentifier) })
        return Set(list.compactMap { item in
            guard let owner = item[kCGWindowOwnerPID as String] as? Int, owners.contains(owner),
                  let bounds = item[kCGWindowBounds as String] as? [String: Any],
                  (bounds["Width"] as? NSNumber)?.doubleValue ?? 0 > 0,
                  (bounds["Height"] as? NSNumber)?.doubleValue ?? 0 > 0 else { return nil }
            return item[kCGWindowNumber as String] as? Int
        })
    }
}
