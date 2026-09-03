import ApplicationServices
import Foundation

public enum KeyboardEvent: Equatable, Sendable {
    case keyDown(keyCode: Int64, rawFlags: UInt64, timestamp: TimeInterval)
    case keyUp(keyCode: Int64, rawFlags: UInt64, timestamp: TimeInterval)
    case flagsChanged(keyCode: Int64, rawFlags: UInt64, timestamp: TimeInterval)

    public static func keyDown(keyCode: Int64, timestamp: TimeInterval) -> KeyboardEvent {
        .keyDown(keyCode: keyCode, rawFlags: 0, timestamp: timestamp)
    }

    public static func keyUp(keyCode: Int64, timestamp: TimeInterval) -> KeyboardEvent {
        .keyUp(keyCode: keyCode, rawFlags: 0, timestamp: timestamp)
    }
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

struct DeferredEventBuffer<Event> {
    private(set) var isActive = false
    private var events: [Event] = []

    mutating func begin() {
        guard !isActive else { return }
        isActive = true
        events.removeAll(keepingCapacity: true)
    }

    @discardableResult
    mutating func append(_ event: Event) -> Bool {
        guard isActive else { return false }
        events.append(event)
        return true
    }

    mutating func drain() -> [Event] {
        let drained = events
        events.removeAll(keepingCapacity: true)
        isActive = false
        return drained
    }
}

public final class TriggerDetector {
    private let triggerHotkey: Hotkey
    private let tapMaxDuration: TimeInterval
    private var activeTriggerKeyCode: Int64?
    private var triggerDownAt: TimeInterval?
    private var otherKeyPressed = false

    public init(triggerHotkey: Hotkey, tapMaxDuration: TimeInterval) {
        self.triggerHotkey = triggerHotkey
        self.tapMaxDuration = tapMaxDuration
    }

    public func process(event: KeyboardEvent) -> TriggerDetectionResult {
        if hasNonModifierActivationKey {
            return processCombination(event: event)
        }

        switch event {
        case .keyDown(let keyCode, _, let timestamp):
            if isTriggerKeyCode(keyCode) {
                return beginTrigger(keyCode: keyCode, timestamp: timestamp)
            }
            return cancelActiveTrigger()
        case .keyUp(let keyCode, _, let timestamp):
            guard isTriggerKeyCode(keyCode) else { return .ignored }
            return finishTrigger(keyCode: keyCode, timestamp: timestamp)
        case .flagsChanged(let keyCode, let rawFlags, let timestamp):
            guard isTriggerKeyCode(keyCode) else {
                return cancelActiveTrigger()
            }
            if activeTriggerKeyCode == keyCode {
                return finishTrigger(keyCode: keyCode, timestamp: timestamp)
            }
            guard modifierIsPressed(keyCode: keyCode, rawFlags: rawFlags) else { return .ignored }
            return beginTrigger(keyCode: keyCode, timestamp: timestamp)
        }
    }

    private func processCombination(event: KeyboardEvent) -> TriggerDetectionResult {
        switch event {
        case .keyDown(let keyCode, let rawFlags, let timestamp):
            guard isActivationKeyCode(keyCode), modifierFlagsMatch(rawFlags) else {
                return cancelActiveTrigger()
            }
            return beginTrigger(keyCode: keyCode, timestamp: timestamp)
        case .keyUp(let keyCode, _, let timestamp):
            guard isActivationKeyCode(keyCode) else { return .ignored }
            return finishTrigger(keyCode: keyCode, timestamp: timestamp)
        case .flagsChanged(_, let rawFlags, _):
            guard activeTriggerKeyCode != nil else { return .ignored }
            return modifierFlagsMatch(rawFlags) ? .ignored : cancelActiveTrigger()
        }
    }

    func reset() {
        activeTriggerKeyCode = nil
        triggerDownAt = nil
        otherKeyPressed = false
    }

    func shouldSwallowEvent(keyCode: Int64, after result: TriggerDetectionResult) -> Bool {
        result != .ignored && isActivationKeyCode(keyCode)
    }

    private func beginTrigger(keyCode: Int64, timestamp: TimeInterval) -> TriggerDetectionResult {
        guard activeTriggerKeyCode == nil else {
            guard activeTriggerKeyCode != keyCode else { return .ignored }
            otherKeyPressed = true
            return .cancelled(.otherKeyPressed)
        }
        activeTriggerKeyCode = keyCode
        triggerDownAt = timestamp
        otherKeyPressed = false
        return .triggerDown
    }

    private func finishTrigger(keyCode: Int64, timestamp: TimeInterval) -> TriggerDetectionResult {
        guard activeTriggerKeyCode == keyCode, let downAt = triggerDownAt else { return .ignored }
        activeTriggerKeyCode = nil
        triggerDownAt = nil
        defer { otherKeyPressed = false }
        if otherKeyPressed {
            return .cancelled(.otherKeyPressed)
        }
        if timestamp - downAt > tapMaxDuration {
            return .cancelled(.heldTooLong)
        }
        return .triggerTap
    }

    private func cancelActiveTrigger() -> TriggerDetectionResult {
        guard activeTriggerKeyCode != nil else { return .ignored }
        otherKeyPressed = true
        return .cancelled(.otherKeyPressed)
    }

    private func modifierIsPressed(keyCode: Int64, rawFlags: UInt64) -> Bool {
        let matchingKeys = triggerHotkey.keys.filter {
            $0.isModifier && $0.keyCodes.contains(Int(keyCode))
        }
        let expectedFlags = flags(for: Hotkey(keys: matchingKeys)).rawValue
        return expectedFlags != 0 && rawFlags & expectedFlags != 0
    }

    private func isTriggerKeyCode(_ keyCode: Int64) -> Bool {
        triggerHotkey.keys.flatMap(\.keyCodes).contains(Int(keyCode))
    }

    private var hasNonModifierActivationKey: Bool {
        !triggerHotkey.isModifierOnly
    }

    private func isActivationKeyCode(_ keyCode: Int64) -> Bool {
        triggerHotkey.keys
            .filter { !$0.isModifier }
            .flatMap(\.keyCodes)
            .contains(Int(keyCode))
    }

    private func modifierFlagsMatch(_ rawFlags: UInt64) -> Bool {
        let expected = flags(for: Hotkey(keys: triggerHotkey.keys.filter(\.isModifier)))
        guard !expected.isEmpty else { return true }
        let relevant: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        return CGEventFlags(rawValue: rawFlags).intersection(relevant) == expected
    }
}

/// Aggregates one or more trigger hotkeys so any of them can start or end a voice
/// session, while each keeps its own single-key / combination timing rules.
struct TriggerDetectorGroup {
    private let detectors: [TriggerDetector]

    init(hotkeys: [Hotkey], tapMaxDuration: TimeInterval) {
        precondition(!hotkeys.isEmpty, "at least one trigger hotkey is required")
        self.detectors = hotkeys.map { TriggerDetector(triggerHotkey: $0, tapMaxDuration: tapMaxDuration) }
    }

    /// Processes the event through every detector; result order matches hotkey order.
    /// When any detector fires a tap, all detectors reset so another armed trigger
    /// cannot fire a second tap on its own release.
    func process(event: KeyboardEvent) -> [TriggerDetectionResult] {
        let results = detectors.map { $0.process(event: event) }
        if results.contains(.triggerTap) {
            reset()
        }
        return results
    }

    func reset() {
        detectors.forEach { $0.reset() }
    }

    func shouldSwallowEvent(keyCode: Int64, after results: [TriggerDetectionResult]) -> Bool {
        zip(detectors, results).contains { detector, result in
            detector.shouldSwallowEvent(keyCode: keyCode, after: result)
        }
    }
}

public protocol KeyboardEngineDelegate: AnyObject {
    @MainActor func keyboardEngineDidDetectTriggerTap(_ engine: KeyboardEngine)
    @MainActor func keyboardEngineDidDetectExternalVoiceEnd(_ engine: KeyboardEngine)
}

/// Manages the CGEvent tap lifecycle, trigger detection, and synthetic hotkey posting.
///
/// - Important: The owner must call `stop()` on the main actor before releasing the last
///   reference. `KeyboardEngine` does not stop its event tap automatically in `deinit`,
///   because `deinit` may run on a non-main thread and touching `CFRunLoop`/`CFMachPort`
///   state off the main actor is unsafe.
@MainActor
public final class KeyboardEngine {
    public nonisolated static let eventTapLocation: CGEventTapLocation = .cgSessionEventTap

    /// Key events arriving within this window after voice start are ignored for
    /// external voice end detection, so synthetic key noise does not end the session.
    private static let externalEndSilenceWindow: TimeInterval = 0.5

    private let config: RimeDouConfig
    private let logger: RimeDouLogger
    private let triggerDetectorGroup: TriggerDetectorGroup
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var voiceStartedUptime: TimeInterval?
    private var deferredEvents = DeferredEventBuffer<CGEvent>()
    public weak var delegate: KeyboardEngineDelegate?

    public init(config: RimeDouConfig, logger: RimeDouLogger) {
        self.config = config
        self.logger = logger
        var triggerHotkeys = [config.triggerHotkey]
        if let secondary = config.triggerHotkey2 {
            triggerHotkeys.append(secondary)
        }
        self.triggerDetectorGroup = TriggerDetectorGroup(
            hotkeys: triggerHotkeys,
            tapMaxDuration: config.tapMaxDuration
        )
    }

    public func start() -> Bool {
        guard eventTap == nil else {
            logger.log("keyboard engine already started")
            return true
        }
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: Self.eventTapLocation,
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
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            eventTap = nil
            logger.log("failed to create run loop source for event tap")
            return false
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.log("keyboard engine started")
        return true
    }

    public func stop() {
        triggerDetectorGroup.reset()
        voiceStartedUptime = nil
        completeInputDeferral()
        guard eventTap != nil || runLoopSource != nil else { return }
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

    public func markVoiceStarted() {
        voiceStartedUptime = ProcessInfo.processInfo.systemUptime
    }

    public func resetVoiceStartTime() {
        voiceStartedUptime = nil
    }

    public func beginInputDeferral() {
        let wasActive = deferredEvents.isActive
        deferredEvents.begin()
        if !wasActive {
            logger.log("input deferral started")
        }
    }

    public func completeInputDeferral() {
        let events = deferredEvents.drain()
        guard !events.isEmpty else { return }
        logger.log("input deferral completed: events=\(events.count)")
        for event in events {
            event.post(tap: .cghidEventTap)
        }
    }

    fileprivate func handleKeyboardEvent(_ event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let timestamp = ProcessInfo.processInfo.systemUptime

        let keyboardEvent: KeyboardEvent
        switch type {
        case .keyDown:
            keyboardEvent = .keyDown(
                keyCode: keyCode,
                rawFlags: event.flags.rawValue,
                timestamp: timestamp
            )
        case .keyUp:
            keyboardEvent = .keyUp(
                keyCode: keyCode,
                rawFlags: event.flags.rawValue,
                timestamp: timestamp
            )
        case .flagsChanged:
            keyboardEvent = .flagsChanged(
                keyCode: keyCode,
                rawFlags: event.flags.rawValue,
                timestamp: timestamp
            )
        default:
            return Unmanaged.passUnretained(event)
        }

        let results = triggerDetectorGroup.process(event: keyboardEvent)
        for result in results {
            switch result {
            case .triggerTap:
                logger.log("trigger tap detected")
                delegate?.keyboardEngineDidDetectTriggerTap(self)
            case .cancelled(let reason):
                logger.log("trigger cancelled: \(reason)")
            case .triggerDown, .ignored:
                break
            }
        }

        // Detect external voice end: any non-trigger key event while voice is active,
        // after a silence window to ignore synthetic key noise.
        if let startedUptime = voiceStartedUptime,
           ProcessInfo.processInfo.systemUptime - startedUptime > Self.externalEndSilenceWindow,
           !isVoiceHotkeyEvent(keyCode),
           !isTriggerKeyCode(keyCode),
           (type == .keyDown || type == .flagsChanged) {
            logger.log("external voice end detected")
            delegate?.keyboardEngineDidDetectExternalVoiceEnd(self)
            voiceStartedUptime = nil
        }

        if deferredEvents.isActive,
           !isTriggerKeyCode(keyCode),
           !isVoiceHotkeyEvent(keyCode),
           let copiedEvent = event.copy() {
            deferredEvents.append(copiedEvent)
            return nil
        }

        return triggerDetectorGroup.shouldSwallowEvent(keyCode: keyCode, after: results)
            ? nil
            : Unmanaged.passUnretained(event)
    }

    private func isTriggerKeyCode(_ keyCode: Int64) -> Bool {
        var keyCodes = config.triggerHotkey.keys.flatMap(\.keyCodes)
        if let secondary = config.triggerHotkey2 {
            keyCodes += secondary.keys.flatMap(\.keyCodes)
        }
        return keyCodes.contains(Int(keyCode))
    }

    private func isVoiceHotkeyEvent(_ keyCode: Int64) -> Bool {
        config.voiceHotkey.keys.flatMap(\.keyCodes).contains(Int(keyCode))
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
    let eventAddress = UInt(bitPattern: Unmanaged.passUnretained(event).toOpaque())

    // start() attaches this CFMachPort source only to the main run loop, so the callback
    // is already executing on the MainActor's thread. A main.sync hop here would deadlock.
    let resultAddress: UInt? = MainActor.assumeIsolated {
        guard let eventPointer = UnsafeMutableRawPointer(bitPattern: eventAddress) else {
            return eventAddress
        }
        let event = Unmanaged<CGEvent>.fromOpaque(eventPointer).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            engine.reenableEventTap()
            return eventAddress
        }
        guard [.flagsChanged, .keyDown, .keyUp].contains(type) else {
            return eventAddress
        }
        guard let returnedEvent = engine.handleKeyboardEvent(event, type: type) else {
            return nil
        }
        return UInt(bitPattern: returnedEvent.toOpaque())
    }
    return resultAddress.flatMap { address in
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else {
            return Unmanaged.passUnretained(event)
        }
        return Unmanaged<CGEvent>.fromOpaque(pointer)
    }
}

// MARK: - Hotkey Synthesis

final class HotkeySynthesizer: @unchecked Sendable {
    private let hotkey: Hotkey
    private let source = CGEventSource(stateID: .hidSystemState)

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    func tap(duration: TimeInterval, logger: RimeDouLogger) {
        var releasedKeys = Set<Key>()
        for key in hotkey.keys where key.isModifier {
            postModifier(key: key, down: true, releasedKeys: releasedKeys)
        }
        for key in hotkey.keys where !key.isModifier {
            postKey(key: key, down: true, releasedKeys: releasedKeys)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [self] in
            for key in hotkey.keys.reversed() where !key.isModifier {
                self.postKey(key: key, down: false, releasedKeys: releasedKeys)
                releasedKeys.insert(key)
            }
            for key in hotkey.keys.reversed() where key.isModifier {
                self.postModifier(key: key, down: false, releasedKeys: releasedKeys)
                releasedKeys.insert(key)
            }
            logger.log("voice hotkey tap completed")
        }
    }

    private func postModifier(key: Key, down: Bool, releasedKeys: Set<Key>) {
        guard let keyCode = key.keyCodes.first else { return }
        let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down)
        event?.flags = down ? flags(for: hotkey) : remainingFlags(excluding: key, releasedKeys: releasedKeys)
        event?.post(tap: .cghidEventTap)
    }

    private func postKey(key: Key, down: Bool, releasedKeys: Set<Key>) {
        guard let keyCode = key.keyCodes.first else { return }
        let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down)
        event?.flags = down ? flags(for: hotkey) : remainingFlags(excluding: key, releasedKeys: releasedKeys)
        event?.post(tap: .cghidEventTap)
    }

    private func remainingFlags(excluding excludedKey: Key, releasedKeys: Set<Key>) -> CGEventFlags {
        let remainingKeys = hotkey.keys.filter { $0 != excludedKey && !releasedKeys.contains($0) }
        return flags(for: Hotkey(keys: remainingKeys))
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
