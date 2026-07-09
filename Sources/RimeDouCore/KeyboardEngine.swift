import AppKit
import ApplicationServices
import Carbon
import Foundation

public enum KeyboardEvent: Equatable, Sendable {
    case keyDown(keyCode: Int64, timestamp: TimeInterval)
    case keyUp(keyCode: Int64, timestamp: TimeInterval)
    case flagsChanged(rawFlags: UInt64, timestamp: TimeInterval)
}

public enum TriggerDetectionResult: Equatable, Sendable {
    case triggerDown
    case triggerTap
    case cancelled(TriggerCancellationReason)
    case ignored
}

public enum TriggerCancellationReason: Equatable, Sendable {
    case heldTooLong
    case otherKeyPressed
}

public final class TriggerDetector: @unchecked Sendable {
    private let triggerHotkey: Hotkey
    private let tapMaxDuration: TimeInterval
    private let logger: RimeDouLogger
    private var triggerDownAt: TimeInterval?
    private var otherKeyPressed = false

    public init(triggerHotkey: Hotkey, tapMaxDuration: TimeInterval, logger: RimeDouLogger) {
        self.triggerHotkey = triggerHotkey
        self.tapMaxDuration = tapMaxDuration
        self.logger = logger
    }

    public func process(event: KeyboardEvent) -> TriggerDetectionResult {
        switch event {
        case .keyDown(let keyCode, let timestamp):
            if isTriggerKeyCode(keyCode) {
                triggerDownAt = timestamp
                otherKeyPressed = false
                return .triggerDown
            } else {
                if triggerDownAt != nil {
                    otherKeyPressed = true
                    return .cancelled(.otherKeyPressed)
                }
                return .ignored
            }
        case .keyUp(let keyCode, let timestamp):
            guard isTriggerKeyCode(keyCode), let downAt = triggerDownAt else {
                return .ignored
            }
            triggerDownAt = nil
            if otherKeyPressed {
                return .cancelled(.otherKeyPressed)
            }
            let duration = timestamp - downAt
            if duration > tapMaxDuration {
                return .cancelled(.heldTooLong)
            }
            return .triggerTap
        case .flagsChanged:
            return .ignored
        }
    }

    private func isTriggerKeyCode(_ keyCode: Int64) -> Bool {
        triggerHotkey.keys.flatMap(\.keyCodes).contains(Int(keyCode))
    }
}

public protocol KeyboardEngineDelegate: AnyObject {
    func keyboardEngineDidDetectTriggerTap(_ engine: KeyboardEngine)
    func keyboardEngineDidDetectExternalVoiceEnd(_ engine: KeyboardEngine)
}

public final class KeyboardEngine: @unchecked Sendable {
    private let config: RimeDouConfig
    private let logger: RimeDouLogger
    private let triggerDetector: TriggerDetector
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activeKeyCodes = Set<Int64>()
    private var voiceStartedAt: Date?
    public weak var delegate: KeyboardEngineDelegate?

    public init(config: RimeDouConfig, logger: RimeDouLogger) {
        self.config = config
        self.logger = logger
        self.triggerDetector = TriggerDetector(
            triggerHotkey: config.triggerHotkey,
            tapMaxDuration: config.tapMaxDuration,
            logger: logger
        )
    }

    public func start() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: keyboardEngineEventTapCallback,
            userInfo: refcon
        ) else {
            logger.log("failed to create event tap")
            return false
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.log("keyboard engine started")
        return true
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        logger.log("keyboard engine stopped")
    }

    public func sendVoiceHotkey() {
        let synthesizer = HotkeySynthesizer(hotkey: config.voiceHotkey)
        synthesizer.tap(duration: config.tapDuration, logger: logger)
    }

    public func markVoiceStarted(at date: Date) {
        voiceStartedAt = date
    }

    public func resetVoiceStartTime() {
        voiceStartedAt = nil
    }

    fileprivate func handleKeyboardEvent(_ event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let timestamp = Date().timeIntervalSince1970

        if type == .keyDown {
            activeKeyCodes.insert(keyCode)
        } else if type == .keyUp {
            activeKeyCodes.remove(keyCode)
        }

        let keyboardEvent: KeyboardEvent
        switch type {
        case .keyDown:
            keyboardEvent = .keyDown(keyCode: keyCode, timestamp: timestamp)
        case .keyUp:
            keyboardEvent = .keyUp(keyCode: keyCode, timestamp: timestamp)
        case .flagsChanged:
            keyboardEvent = .flagsChanged(rawFlags: event.flags.rawValue, timestamp: timestamp)
        default:
            return Unmanaged.passUnretained(event)
        }

        let result = triggerDetector.process(event: keyboardEvent)
        switch result {
        case .triggerTap:
            logger.log("trigger tap detected")
            delegate?.keyboardEngineDidDetectTriggerTap(self)
        case .cancelled(let reason):
            logger.log("trigger cancelled: \(reason)")
        case .triggerDown, .ignored:
            break
        }

        // Detect external voice end: any non-trigger key event while voice is active,
        // after a 0.5s silence window to ignore synthetic key noise.
        if let startedAt = voiceStartedAt,
           Date().timeIntervalSince(startedAt) > 0.5,
           !isVoiceHotkeyEvent(keyCode),
           !isTriggerKeyCode(keyCode),
           (type == .keyDown || type == .flagsChanged) {
            logger.log("external voice end detected")
            delegate?.keyboardEngineDidDetectExternalVoiceEnd(self)
        }

        return shouldSwallowTriggerEvent() && isTriggerKeyCode(keyCode) ? nil : Unmanaged.passUnretained(event)
    }

    private func isTriggerKeyCode(_ keyCode: Int64) -> Bool {
        config.triggerHotkey.keys.flatMap(\.keyCodes).contains(Int(keyCode))
    }

    private func isVoiceHotkeyEvent(_ keyCode: Int64) -> Bool {
        config.voiceHotkey.keys.flatMap(\.keyCodes).contains(Int(keyCode))
    }

    private func shouldSwallowTriggerEvent() -> Bool {
        // Swallow non-modifier trigger keys so they don't leak into the active app.
        !config.triggerHotkey.keys.allSatisfy(\.isModifier)
    }

    fileprivate func reenableEventTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.log("event tap re-enabled after system disable")
    }
}

private let keyboardEngineEventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<KeyboardEngine>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        engine.reenableEventTap()
        return Unmanaged.passUnretained(event)
    }
    guard [.flagsChanged, .keyDown, .keyUp].contains(type) else {
        return Unmanaged.passUnretained(event)
    }
    return engine.handleKeyboardEvent(event, type: type)
}

// MARK: - Hotkey Synthesis

final class HotkeySynthesizer: @unchecked Sendable {
    private let hotkey: Hotkey
    private let source = CGEventSource(stateID: .hidSystemState)

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    func tap(duration: TimeInterval, logger: RimeDouLogger) {
        for key in hotkey.keys where key.isModifier {
            postModifier(key: key, down: true)
        }
        for key in hotkey.keys where !key.isModifier {
            postKey(key: key, down: true)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            for key in self.hotkey.keys.reversed() where !key.isModifier {
                self.postKey(key: key, down: false)
            }
            for key in self.hotkey.keys.reversed() where key.isModifier {
                self.postModifier(key: key, down: false)
            }
            logger.log("voice hotkey tap completed")
        }
    }

    private func postModifier(key: Key, down: Bool) {
        guard let keyCode = key.keyCodes.first else { return }
        let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down)
        event?.flags = down ? flags(for: hotkey) : remainingFlags(excluding: key)
        event?.post(tap: .cghidEventTap)
    }

    private func postKey(key: Key, down: Bool) {
        guard let keyCode = key.keyCodes.first else { return }
        let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down)
        event?.flags = flags(for: hotkey)
        event?.post(tap: .cghidEventTap)
    }
}

// MARK: - Key code and flag helpers (defined on Key)

extension Key {
    public var keyCodes: [Int] {
        switch self {
        case .leftShift: return [56]
        case .rightShift: return [60]
        case .shift: return [56, 60]
        case .leftControl: return [59]
        case .rightControl: return [62]
        case .control: return [59, 62]
        case .leftOption: return [58]
        case .rightOption: return [61]
        case .option: return [58, 61]
        case .leftCommand: return [55]
        case .rightCommand: return [54]
        case .command: return [55, 54]
        case .tab: return [48]
        case .space: return [49]
        case .character(let character): return characterKeyCodes[character].map { [$0] } ?? []
        }
    }
}

private let characterKeyCodes: [String: Int] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
    "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
    "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
    "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
    "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
    "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
    "n": 45, "m": 46, ".": 47, "`": 50
]

private let leftShiftMask: UInt64 = 0x2
private let rightShiftMask: UInt64 = 0x4
private let leftControlMask: UInt64 = 0x1
private let rightControlMask: UInt64 = 0x2000
private let leftOptionMask: UInt64 = 0x20
private let rightOptionMask: UInt64 = 0x40
private let leftCommandMask: UInt64 = 0x8
private let rightCommandMask: UInt64 = 0x10

private func modifierIsDown(_ key: Key, flags: CGEventFlags) -> Bool {
    switch key {
    case .leftShift: return (flags.rawValue & leftShiftMask) != 0
    case .rightShift: return (flags.rawValue & rightShiftMask) != 0
    case .shift: return flags.contains(.maskShift)
    case .leftControl: return (flags.rawValue & leftControlMask) != 0
    case .rightControl: return (flags.rawValue & rightControlMask) != 0
    case .control: return flags.contains(.maskControl)
    case .leftOption: return (flags.rawValue & leftOptionMask) != 0
    case .rightOption: return (flags.rawValue & rightOptionMask) != 0
    case .option: return flags.contains(.maskAlternate)
    case .leftCommand: return (flags.rawValue & leftCommandMask) != 0
    case .rightCommand: return (flags.rawValue & rightCommandMask) != 0
    case .command: return flags.contains(.maskCommand)
    case .tab, .space, .character: return false
    }
}

private func flags(for hotkey: Hotkey) -> CGEventFlags {
    hotkey.keys.reduce(CGEventFlags()) { result, key in
        var result = result
        switch key {
        case .leftShift, .rightShift, .shift: result.insert(.maskShift)
        case .leftControl, .rightControl, .control: result.insert(.maskControl)
        case .leftOption, .rightOption, .option: result.insert(.maskAlternate)
        case .leftCommand, .rightCommand, .command: result.insert(.maskCommand)
        case .tab, .space, .character: break
        }
        return result
    }
}

private func remainingFlags(excluding excludedKey: Key) -> CGEventFlags {
    excludedKey.keyCodes.first.map { _ in CGEventFlags() } ?? CGEventFlags()
}
