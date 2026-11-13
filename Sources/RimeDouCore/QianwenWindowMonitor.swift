import AppKit
import CoreGraphics
import Foundation

public enum ProviderWindowIssue: Equatable, Sendable {
    case startNotObserved
    case windowDisappearedBeforeStop
    case completionTimedOut

    public var message: String {
        switch self {
        case .startNotObserved: return "未能确认千问启动：请核对千问快捷键与短按设置"
        case .windowDisappearedBeforeStop: return "千问窗口在停止指令前消失：请确认语音状态并切回 RIME"
        case .completionTimedOut: return "千问处理超时：请先确认语音已结束，再手动切回 RIME"
        }
    }
}

@MainActor
public protocol ProviderWindowMonitoring: AnyObject {
    var hasObservedVoiceWindow: Bool { get }
    var canRequestStop: Bool { get }
    func currentWindows() -> Set<Int>?
    func startTracking(onIssue: @escaping (ProviderWindowIssue) -> Void) -> Bool
    func beginWaitingForGone(timeout: TimeInterval, goneStabilityDelay: TimeInterval, onCompletion: @escaping () -> Void)
    func stop()
}

/// Only window IDs and owning process bundle IDs are used. No titles/text/clipboard.
@MainActor
public final class QianwenWindowMonitor: ProviderWindowMonitoring {
    public init() {}

    private var timer: Timer?
    private var tracker = ProviderWindowLifecycleTracker()
    private var startedAt: TimeInterval = 0
    private var missingSince: TimeInterval?
    private var timeout: TimeInterval = 60
    private var stability: TimeInterval = 0.15
    private var completion: (() -> Void)?
    private var issue: ((ProviderWindowIssue) -> Void)?

    public func currentWindows() -> Set<Int>? { Self.visibleWindowIDs() }

    public var hasObservedVoiceWindow: Bool { tracker.didObserveProviderWindow }

    public var canRequestStop: Bool {
        guard hasObservedVoiceWindow, let current = Self.visibleWindowIDs() else { return false }
        return !current.intersection(tracker.tracked).isEmpty
    }

    @discardableResult
    public func startTracking(onIssue: @escaping (ProviderWindowIssue) -> Void) -> Bool {
        stop()
        guard let baseline = Self.visibleWindowIDs(), baseline.isEmpty else { return false }
        tracker = ProviderWindowLifecycleTracker(baseline: baseline)
        issue = onIssue
        startedAt = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        return true
    }

    public func beginWaitingForGone(timeout: TimeInterval, goneStabilityDelay: TimeInterval,
                                     onCompletion: @escaping () -> Void) {
        self.timeout = timeout
        stability = goneStabilityDelay
        completion = onCompletion
        missingSince = nil
        tracker.beginWaiting(at: ProcessInfo.processInfo.systemUptime)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        tracker = ProviderWindowLifecycleTracker()
        missingSince = nil
        completion = nil
        issue = nil
    }

    private func poll() {
        let now = ProcessInfo.processInfo.systemUptime
        let current = Self.visibleWindowIDs()
        let result = tracker.observe(current: current, now: now,
                                     completionTimeout: timeout, goneStabilityDelay: stability)
        if tracker.waitingStartedAt != nil {
            switch result {
            case .none: break
            case .completed:
                let callback = completion
                stop()
                callback?()
            case .timedOut:
                report(.completionTimedOut)
            }
        } else if !tracker.didObserveProviderWindow {
            if now - startedAt >= 3 {
                report(.startNotObserved)
            }
        } else if let current, current.intersection(tracker.tracked).isEmpty {
            if let missingSince, now - missingSince >= stability {
                report(.windowDisappearedBeforeStop)
            } else if missingSince == nil { missingSince = now }
        } else {
            missingSince = nil
        }
    }

    private func report(_ issue: ProviderWindowIssue) {
        let callback = self.issue
        stop()
        callback?(issue)
    }

    /// nil means the system query failed, never a successful empty observation.
    public static func visibleWindowIDs() -> Set<Int>? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        var owners: [pid_t: Bool] = [:]
        return Set(list.compactMap { item in
            guard let owner = item[kCGWindowOwnerPID as String] as? Int else { return nil }
            let pid = pid_t(owner)
            let isQianwen = owners[pid] ?? (NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == VoiceProviderRegistry.qianwenServiceBundleIdentifier)
            owners[pid] = isQianwen
            guard isQianwen else { return nil }
            return item[kCGWindowNumber as String] as? Int
        })
    }
}
