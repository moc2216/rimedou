import CoreGraphics
import Foundation

public enum HotkeyMonitorError: Error, CustomStringConvertible, Equatable {
    case inputMonitoringPermissionMissing
    case eventTapCreationFailed

    public var description: String {
        switch self {
        case .inputMonitoringPermissionMissing:
            return "Input monitoring permission is missing"
        case .eventTapCreationFailed:
            return "Failed to create keyboard event tap"
        }
    }
}

public final class HotkeyMonitor {
    public typealias EventHandler = @Sendable (SwitchEvent) -> Void
    public typealias EventDelayProvider = @Sendable (SwitchEvent) -> TimeInterval

    public static let defaultHotkeyDispatchDelaySeconds = 0.08

    private var parser = HotkeyEventParser()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let eventHandler: EventHandler
    private let eventDelayProvider: EventDelayProvider

    public init(
        eventDelayProvider: @escaping EventDelayProvider = { _ in HotkeyMonitor.defaultHotkeyDispatchDelaySeconds },
        eventHandler: @escaping EventHandler
    ) {
        self.eventDelayProvider = eventDelayProvider
        self.eventHandler = eventHandler
    }

    public static func hasInputMonitoringPermission() -> Bool {
        CGPreflightListenEventAccess()
    }

    public static func requestInputMonitoringPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    public func start() throws {
        guard Self.hasInputMonitoringPermission() else {
            throw HotkeyMonitorError.inputMonitoringPermissionMissing
        }

        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: HotkeyMonitor.eventTapCallback,
            userInfo: context
        ) else {
            throw HotkeyMonitorError.eventTapCreationFailed
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            throw HotkeyMonitorError.eventTapCreationFailed
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource

        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    public func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, _, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        return monitor.handle(event: event)
    }

    private func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isControlDown = event.flags.contains(.maskControl)
        let isSynthetic = event.getIntegerValueField(.eventSourceUserData) == SyntheticEventTag.rightControl

        guard let result = parser.parseModifierChangeResult(
            keyCode: keyCode,
            isControlDown: isControlDown,
            isSynthetic: isSynthetic
        ) else {
            return Unmanaged.passUnretained(event)
        }

        if let switchEvent = result.event {
            dispatch(switchEvent)
        }

        return Unmanaged.passUnretained(event)
    }

    private func dispatch(_ switchEvent: SwitchEvent) {
        DispatchQueue.main.asyncAfter(deadline: .now() + eventDelayProvider(switchEvent)) { [eventHandler] in
            eventHandler(switchEvent)
        }
    }
}
