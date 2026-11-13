import ApplicationServices
import Foundation
import IOKit.hidsystem

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
    let capacity: Int
    var count: Int { events.count }

    init(capacity: Int = 2048) { self.capacity = capacity }


    mutating func begin() {
        guard !isActive else { return }
        isActive = true
        events.removeAll(keepingCapacity: true)
    }

    @discardableResult
    mutating func append(_ event: Event) -> Bool {
        guard isActive, events.count < capacity else { return false }
        events.append(event)
        return true
    }

    mutating func keepPrefix(_ count: Int) {
        events.removeLast(max(0, events.count - count))
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
    private var chordPressedCodes = Set<Int64>()

    public init(triggerHotkey: Hotkey, tapMaxDuration: TimeInterval) {
        self.triggerHotkey = triggerHotkey
        self.tapMaxDuration = tapMaxDuration
    }

    public func process(event: KeyboardEvent) -> TriggerDetectionResult {
        if triggerHotkey.isModifierOnly, triggerHotkey.keys.count > 1 {
            return processModifierChord(event: event)
        }
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

    /// A modifier chord is one gesture, ending only after every modifier is up.
    /// Extra keys cancel the entire gesture; releasing an extra modifier cannot
    /// re-arm the chord at the tail of a larger shortcut (such as the mouse trigger).
    private func processModifierChord(event: KeyboardEvent) -> TriggerDetectionResult {
        let code: Int64
        let rawFlags: UInt64
        let timestamp: TimeInterval
        let down: Bool
        switch event {
        case .flagsChanged(let keyCode, let flags, let time):
            code = keyCode; rawFlags = flags; timestamp = time
            down = modifierIsPressed(keyCode: keyCode, rawFlags: flags) && !chordPressedCodes.contains(keyCode)
        case .keyDown(let keyCode, let flags, let time):
            code = keyCode; rawFlags = flags; timestamp = time; down = true
        case .keyUp(let keyCode, let flags, let time):
            code = keyCode; rawFlags = flags; timestamp = time; down = false
        }
        guard isTriggerKeyCode(code) else {
            if !chordPressedCodes.isEmpty { otherKeyPressed = true }
            return .ignored
        }
        if down {
            if triggerDownAt != nil { otherKeyPressed = true }
            chordPressedCodes.insert(code)
        } else {
            chordPressedCodes.remove(code)
        }
        let relevant: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        let expected = flags(for: triggerHotkey)
        if !CGEventFlags(rawValue: rawFlags).intersection(relevant).subtracting(expected).isEmpty {
            otherKeyPressed = true
        }
        if chordPressedCodes.isEmpty {
            defer { triggerDownAt = nil; otherKeyPressed = false }
            guard let started = triggerDownAt else { return .ignored }
            if otherKeyPressed { return .cancelled(.otherKeyPressed) }
            return timestamp - started <= tapMaxDuration ? .triggerTap : .cancelled(.heldTooLong)
        }
        let allPressed = triggerHotkey.keys.allSatisfy { key in
            key.keyCodes.contains { chordPressedCodes.contains(Int64($0)) }
        }
        if down, allPressed, !otherKeyPressed, triggerDownAt == nil, modifierFlagsMatch(rawFlags) {
            triggerDownAt = timestamp
            return .triggerDown
        }
        return .ignored
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

    /// A trigger modifier's keyUp can be consumed above the session tap (observed
    /// 2026-09-12: HID-level tools ate the second right-Command release). When the
    /// system's live modifier flags no longer contain the trigger while a trigger
    /// down is still armed, reconstruct the tap from that evidence.
    func reconcileModifierGesture(modifierFlagsRaw: UInt64, timestamp: TimeInterval) -> TriggerDetectionResult {
        guard triggerHotkey.isModifierOnly, triggerHotkey.keys.count == 1,
              let code = activeTriggerKeyCode, isTriggerKeyCode(code),
              CGEventFlags(rawValue: modifierFlagsRaw).intersection(flags(for: triggerHotkey)).isEmpty
        else { return .ignored }
        return finishTrigger(keyCode: code, timestamp: timestamp)
    }

    func reset() {
        activeTriggerKeyCode = nil
        triggerDownAt = nil
        otherKeyPressed = false
        chordPressedCodes.removeAll()
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
final class TriggerDetectorGroup {
    private let detectors: [TriggerDetector]
    private var swallowedKeyCodes = Set<Int64>()
    private var swallowCurrentEvent = false

    init(hotkeys: [Hotkey], tapMaxDuration: TimeInterval) {
        precondition(!hotkeys.isEmpty, "at least one trigger hotkey is required")
        self.detectors = hotkeys.map { TriggerDetector(triggerHotkey: $0, tapMaxDuration: tapMaxDuration) }
    }

    /// Processes the event through every detector; result order matches hotkey order.
    /// When any detector fires a tap, all detectors reset so another armed trigger
    /// cannot fire a second tap on its own release.
    func process(event: KeyboardEvent) -> [TriggerDetectionResult] {
        let results = detectors.map { $0.process(event: event) }
        switch event {
        case .keyDown(let code, _, _):
            let begins = zip(detectors, results).contains { $0.shouldSwallowEvent(keyCode: code, after: $1) }
            if begins { swallowedKeyCodes.insert(code) }
            swallowCurrentEvent = swallowedKeyCodes.contains(code)
        case .keyUp(let code, _, _):
            swallowCurrentEvent = swallowedKeyCodes.remove(code) != nil
        case .flagsChanged:
            swallowCurrentEvent = false
        }
        if results.contains(.triggerTap) { reset() }
        return results
    }

    func reset() {
        detectors.forEach { $0.reset() }
    }

    func synchronizePressedKeys(_ pressed: Set<Int64>) {
        reset()
        swallowedKeyCodes.formIntersection(pressed)
    }

    func reconcileModifierGestures(modifierFlagsRaw: UInt64, timestamp: TimeInterval) -> [TriggerDetectionResult] {
        let results = detectors.map { $0.reconcileModifierGesture(modifierFlagsRaw: modifierFlagsRaw, timestamp: timestamp) }
        if results.contains(.triggerTap) { reset() }
        return results
    }

    func shouldSwallowEvent(keyCode: Int64, after results: [TriggerDetectionResult]) -> Bool {
        swallowCurrentEvent
    }
}

public protocol KeyboardEngineDelegate: AnyObject {
    @MainActor func keyboardEngineDidDetectTriggerTap(_ engine: KeyboardEngine)
    @MainActor func keyboardEngineDidDetectExternalVoiceEnd(_ engine: KeyboardEngine)
    @MainActor func keyboardEngineDidDetectManagedVoiceHotkeyTap(_ engine: KeyboardEngine)
    @MainActor func keyboardEngineDidDetectVoiceCancel(_ engine: KeyboardEngine) -> Bool
    @MainActor func keyboardEngineDidOverflowInputBuffer(_ engine: KeyboardEngine)
}

public extension KeyboardEngineDelegate {
    @MainActor func keyboardEngineDidDetectManagedVoiceHotkeyTap(_ engine: KeyboardEngine) {}
    @MainActor func keyboardEngineDidDetectVoiceCancel(_ engine: KeyboardEngine) -> Bool { false }
    @MainActor func keyboardEngineDidOverflowInputBuffer(_ engine: KeyboardEngine) {}
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


    private let config: RimeDouConfig
    private let logger: RimeDouLogger
    private let triggerDetectorGroup: TriggerDetectorGroup
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var voiceProvider: VoiceProviderDefinition?
    private var passingEscapeGesture = false
    private var providerDetector: TriggerDetector?
    private var deferAfterCurrentEvent = false
    private var isHandlingKeyboardEvent = false
    private var pressedKeys = Set<Int64>()
    private var liveModifiers = CGEventFlags()
    private var suppressedProviderKeys = Set<Int64>()
    private var overflowReported = false
    private var lastCompleteGestureCount = 0
    private var bufferedProviderGestureStart: Int?
    private var bufferedProviderGestureArmed = false
    let syntheticEventMarker = Int64.random(in: 1...Int64.max)
    private let postEvent: (CGEvent) -> Void
    private let postEventToPID: ((CGEvent, pid_t) -> Void)?
    /// Destination for replayed input. Some machines run session-wide event filters
    /// (espanso, remappers) that swallow synthetic printable keyDowns posted at the
    /// HID tap, while physical keys and modifier flags still pass. Replay therefore
    /// posts directly to the original app when a target is known (2026-09-12 live
    /// probe: HID-posted digits vanished, PostToPid digits landed).
    public var replayTargetPID: pid_t?
    private lazy var replaySource: CGEventSource? = {
        let source = CGEventSource(stateID: .privateState)
        source?.userData = syntheticEventMarker
        return source
    }()
    private lazy var hotkeySender = HotkeySender(marker: syntheticEventMarker, postEvent: postEvent)
    public var isSendingHotkey: Bool { hotkeySender.isSending }
    public var deferredEventCount: Int { deferredEvents.count }
    public var isDeferringInput: Bool { deferredEvents.isActive }
    public var canReconfigure: Bool { !isSendingHotkey && !isDeferringInput && pressedKeys.isEmpty && liveModifiers.isEmpty }
    private var deferredEvents = DeferredEventBuffer<CGEvent>()
    public weak var delegate: KeyboardEngineDelegate?

    public init(config: RimeDouConfig, logger: RimeDouLogger,
                postEvent: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
                postEventToPID: ((CGEvent, pid_t) -> Void)? = nil) {
        self.postEvent = postEvent
        self.postEventToPID = postEventToPID
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
        let modifierCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        pressedKeys = Set((0..<128).filter { !modifierCodes.contains($0) && CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0)) }.map(Int64.init))
        liveModifiers = CGEventSource.flagsState(.combinedSessionState).intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
        triggerDetectorGroup.synchronizePressedKeys(pressedKeys)
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
        voiceProvider = nil
        providerDetector = nil
        hotkeySender.releaseAll()
        // A stopped tap is not evidence of a safe input destination. Retain the buffer.

        guard eventTap != nil || runLoopSource != nil else { return }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap { CFMachPortInvalidate(tap) }
        eventTap = nil
        runLoopSource = nil
        logger.log("keyboard engine stopped")
    }

    @discardableResult
    public func sendHotkey(_ hotkey: Hotkey, completion: @escaping () -> Void = {}) -> Bool {
        hotkeySender.tap(hotkey, duration: config.tapDuration, completion: completion)
    }

    public func setVoiceProvider(_ provider: VoiceProviderDefinition?) {
        bufferedProviderGestureStart = nil
        bufferedProviderGestureArmed = false
        voiceProvider = provider
        providerDetector = provider.map { TriggerDetector(triggerHotkey: $0.transportHotkey, tapMaxDuration: config.tapMaxDuration) }
    }

    /// Poll-driven reconciliation of trigger gestures whose release events were
    /// consumed above the session tap (2026-09-12). Returns true when a complete
    /// tap was reconstructed and dispatched.
    @discardableResult
    public func reconcileTriggerGestures() -> Bool {
        guard !deferredEvents.isActive, !isSendingHotkey else { return false }
        let relevant: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        let flags = CGEventSource.flagsState(.combinedSessionState).intersection(relevant)
        let results = triggerDetectorGroup.reconcileModifierGestures(modifierFlagsRaw: flags.rawValue,
                                                                     timestamp: ProcessInfo.processInfo.systemUptime)
        guard results.contains(.triggerTap) else { return false }
        delegate?.keyboardEngineDidDetectTriggerTap(self)
        return true
    }

    public func beginInputDeferral(afterCurrentEvent: Bool = false) {
        if afterCurrentEvent, isHandlingKeyboardEvent {
            deferAfterCurrentEvent = true
        } else {
            deferredEvents.begin()
        }
    }

    /// The caller must verify both input source and destination focus first.
    /// Wait for key releases so shortcuts and autorepeat are not split in half.
    @discardableResult
    public func completeInputDeferral() -> Bool {
        guard inputDeferralWaitReason == nil else { return false }
        if deferredEvents.count == 0 {
            // Window completion may precede a stop trigger's release. Retire that
            // old gesture so its tail cannot start a new voice session after finish.
            triggerDetectorGroup.reset()
            discardInputDeferral()
            return true
        }
        guard let replaySource else { return false }
        let events = deferredEvents.drain()
        bufferedProviderGestureStart = nil
        bufferedProviderGestureArmed = false
        overflowReported = false
        lastCompleteGestureCount = 0
        for event in events {
            event.setSource(replaySource)
            if let postEventToPID, let pid = replayTargetPID {
                postEventToPID(event, pid)
            } else {
                postEvent(event)
            }
        }
        return true
    }

    /// Diagnostic categories only: never expose key codes or buffered content.
    var inputDeferralWaitReason: String? {
        if isSendingHotkey { return "hotkey-release" }
        // No replay means no gesture can be split. Provider-consumed releases
        // may leave stale pressed state, but must not trap an empty session.
        if deferredEvents.count == 0 { return nil }
        if !pressedKeys.isEmpty { return "key-release" }
        if !liveModifiers.isEmpty { return "modifier-release" }
        if replaySource == nil { return "replay-event-source" }
        return nil
    }

    public func discardInputDeferral() {
        _ = deferredEvents.drain()
        deferAfterCurrentEvent = false
        overflowReported = false
        lastCompleteGestureCount = 0
        bufferedProviderGestureStart = nil
        bufferedProviderGestureArmed = false
    }

    func handleKeyboardEvent(_ event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }
        isHandlingKeyboardEvent = true
        defer {
            isHandlingKeyboardEvent = false
            if deferAfterCurrentEvent {
                deferAfterCurrentEvent = false
                deferredEvents.begin()
            }
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let wasPressedBeforeEvent = pressedKeys.contains(code)
        let now = ProcessInfo.processInfo.systemUptime
        let keyboardEvent: KeyboardEvent
        liveModifiers = event.flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
        switch type {
        case .keyDown:
            pressedKeys.insert(code)
            keyboardEvent = .keyDown(keyCode: code, rawFlags: event.flags.rawValue, timestamp: now)
        case .keyUp:
            pressedKeys.remove(code)
            keyboardEvent = .keyUp(keyCode: code, rawFlags: event.flags.rawValue, timestamp: now)
        case .flagsChanged:
            keyboardEvent = .flagsChanged(keyCode: code, rawFlags: event.flags.rawValue, timestamp: now)
        default:
            return Unmanaged.passUnretained(event)
        }
        let wasDeferring = deferredEvents.isActive
        let providerAtEntry = voiceProvider
        let results = triggerDetectorGroup.process(event: keyboardEvent)
        let swallowTrigger = triggerDetectorGroup.shouldSwallowEvent(keyCode: code, after: results)
        let providerResult = providerDetector?.process(event: keyboardEvent) ?? .ignored

        if passingEscapeGesture, code == 53 {
            if type == .keyUp {
                passingEscapeGesture = false
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return Unmanaged.passUnretained(event)
            }
            passingEscapeGesture = false
        }
        if providerAtEntry?.id == .qianwen, code == 53, !swallowTrigger,
           liveModifiers.isEmpty,
           type == .keyDown || (type == .keyUp && !wasPressedBeforeEvent),
           delegate?.keyboardEngineDidDetectVoiceCancel(self) == true {
            // The provider receives the complete cancel gesture while later input waits.
            passingEscapeGesture = type == .keyDown
            return Unmanaged.passUnretained(event)
        }

        if !wasDeferring {
            if results.contains(.triggerTap) {
                delegate?.keyboardEngineDidDetectTriggerTap(self)
            } else if providerResult == .triggerTap {
                delegate?.keyboardEngineDidDetectManagedVoiceHotkeyTap(self)
            } else if providerAtEntry?.externalStopPolicy == .anyUserKeyboardInput,
                      !isProviderTransportEvent(code: code, type: type, event: event),
                      !results.contains(.triggerDown),
                      type == .keyDown,
                      event.flags.intersection([.maskControl, .maskAlternate, .maskCommand]).isEmpty {
                // Only a bare keyDown counts as the user typing. Shortcut-modified
                // keyDowns do not: doubao's own startup synthesizes Ctrl+Space (the
                // macOS input-source hotkey) to select itself, and other session-level
                // tools inject shortcuts too (both observed killing sessions on
                // 2026-09-12). Shift stays allowed: shifted letters are typing.
                // The delegate must arm deferral here, on this callback, before return.
                delegate?.keyboardEngineDidDetectExternalVoiceEnd(self)
            } else if providerAtEntry?.externalStopPolicy == .anyUserKeyboardInput,
                      type == .keyUp,
                      !wasPressedBeforeEvent,
                      !isProviderTransportEvent(code: code, type: type, event: event) {
                // The vendor's voice overlay consumes ordinary keyDowns above the
                // session layer while listening (observed 2026-09-12); only the
                // matching keyUp still arrives here. An orphan keyUp — no keyDown
                // of that key was ever seen — means the vendor took the key and
                // its voice has ended. End the session instead of hanging.
                delegate?.keyboardEngineDidDetectExternalVoiceEnd(self)
            }
        }
        if swallowTrigger { return nil }
        if deferredEvents.isActive, !deferAfterCurrentEvent {
            guard !overflowReported else { return nil }
            if voiceProvider?.transportHotkey.isModifierOnly == true {
                // Keep modifiers used for typing. Remove only a completed, contiguous
                // transport gesture, so a shared Control/Option shortcut replays intact.
                if isProviderTransportEvent(code: code, type: type, event: event) {
                    if bufferedProviderGestureStart == nil { bufferedProviderGestureStart = deferredEvents.count }
                    if providerResult == .triggerDown { bufferedProviderGestureArmed = true }
                } else {
                    bufferedProviderGestureStart = nil
                    bufferedProviderGestureArmed = false
                }
                // Timing is compressed during replay, so discard long transport
                // holds too: otherwise a cancelled hold becomes a fresh short tap.
                if liveModifiers.isEmpty, bufferedProviderGestureArmed, let start = bufferedProviderGestureStart {
                    deferredEvents.keepPrefix(start)
                    bufferedProviderGestureStart = nil
                    bufferedProviderGestureArmed = false
                    if pressedKeys.isEmpty, liveModifiers.isEmpty { lastCompleteGestureCount = deferredEvents.count }
                    return nil
                }
                if liveModifiers.isEmpty {
                    bufferedProviderGestureStart = nil
                    bufferedProviderGestureArmed = false
                }
            } else if isProviderTransportEvent(code: code, type: type, event: event) { return nil }
            if let copy = event.copy(), deferredEvents.append(copy) {
                if pressedKeys.isEmpty, liveModifiers.isEmpty { lastCompleteGestureCount = deferredEvents.count }
                return nil
            }
            // Preserve complete gestures only: a full buffer must not replay an
            // unmatched keyDown or half of a modifier shortcut.
            deferredEvents.keepPrefix(lastCompleteGestureCount)
            bufferedProviderGestureStart = nil
            bufferedProviderGestureArmed = false
            overflowReported = true
            delegate?.keyboardEngineDidOverflowInputBuffer(self)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func isProviderTransportEvent(code: Int64, type: CGEventType, event: CGEvent) -> Bool {
        guard let hotkey = voiceProvider?.transportHotkey else { return false }
        if hotkey.isModifierOnly { return hotkey.keys.flatMap(\.keyCodes).contains(Int(code)) }
        if type == .keyUp, suppressedProviderKeys.remove(code) != nil { return true }
        let normalCodes = hotkey.keys.filter { !$0.isModifier }.flatMap(\.keyCodes)
        let modifiers = event.flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
        if type == .keyDown, normalCodes.contains(Int(code)), modifiers == flags(for: hotkey) {
            suppressedProviderKeys.insert(code)
            return true
        }
        return false
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

@MainActor
final class HotkeySender {
    private let marker: Int64
    private let postEvent: (CGEvent) -> Void
    private let source = CGEventSource(stateID: .hidSystemState)
    private var held: [Key] = []
    private var releaseTask: Task<Void, Never>?
    var isSending: Bool { !held.isEmpty }

    init(marker: Int64, postEvent: @escaping (CGEvent) -> Void) {
        self.marker = marker
        self.postEvent = postEvent
        source?.userData = marker
    }

    @discardableResult
    func tap(_ hotkey: Hotkey, duration: TimeInterval, completion: @escaping () -> Void) -> Bool {
        guard !isSending, !hotkey.keys.isEmpty else { return false }
        for key in hotkey.keys.filter(\.isModifier) + hotkey.keys.filter({ !$0.isModifier }) {
            held.append(key)
            guard post(key, down: true) else { releaseAll(); return false }
        }
        releaseTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            guard let self else { return }
            self.releaseKeys()
            self.releaseTask = nil
            completion()
        }
        return true
    }

    func releaseAll() {
        releaseTask?.cancel()
        releaseTask = nil
        releaseKeys()
    }

    private func releaseKeys() {
        while let key = held.popLast() { _ = post(key, down: false) }
    }

    private func post(_ key: Key, down: Bool) -> Bool {
        guard let code = key.keyCodes.first,
              let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else { return false }
        // Generic Control/Option bits do not identify the configured side.
        // Match native flagsChanged events, including IOKit's device-side bits.
        let sideFlags = held.reduce(UInt64(0)) { $0 | $1.nativeModifierMask }
        event.flags = CGEventFlags(rawValue: flags(for: Hotkey(keys: held)).rawValue | sideFlags)
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        postEvent(event)
        return true
    }
}

// MARK: - Key code and flag helpers (defined on Key)

extension Key {
    fileprivate var nativeModifierMask: UInt64 {
        switch self {
        case .leftShift, .shift: return UInt64(NX_DEVICELSHIFTKEYMASK)
        case .rightShift: return UInt64(NX_DEVICERSHIFTKEYMASK)
        case .leftControl, .control: return UInt64(NX_DEVICELCTLKEYMASK)
        case .rightControl: return UInt64(NX_DEVICERCTLKEYMASK)
        case .leftOption, .option: return UInt64(NX_DEVICELALTKEYMASK)
        case .rightOption: return UInt64(NX_DEVICERALTKEYMASK)
        case .leftCommand, .command: return UInt64(NX_DEVICELCMDKEYMASK)
        case .rightCommand: return UInt64(NX_DEVICERCMDKEYMASK)
        case .tab, .space, .character: return 0
        }
    }

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
