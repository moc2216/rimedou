import SwitchOnlyDoubaoVoiceInputCore
import Foundation

@main
struct TestRunner {
    static func main() {
        testScaffoldIsReady()
        testRightControlStartsDoubaoVoiceWhenIdle()
        testLeftControlDoesNothingWhenIdle()
        testRightControlStopsDoubaoVoiceAndRestoresPrimaryInput()
        testRightControlDoesNothingWhenExternalVoiceToolIsRunning()
        testRightControlWorksAfterExternalVoiceToolStops()
        testDoubaoSwitchFailureMovesToError()
        testPrimaryRestoreFailureMovesToError()
        testLoadsDefaultConfig()
        testMissingConfigFieldFailsClearly()
        testDefaultInputSourcesExistOnThisMac()
        testPrimaryInputSourceIsSelectableOnThisMac()
        testUnselectableInputSourceFailsClearly()
        testMissingInputSourceFailsClearly()
        testExternalVoiceToolRunningWhenBundleIdMatches()
        testExternalVoiceToolNotRunningWhenBundleIdDoesNotMatch()
        testMissingExternalVoiceAppPathWarnsButDoesNotBlock()
        HotkeyTests.run()
        DoubaoVoiceControllerTests.run()
        ExternalVoiceToolStateTrackerTests.run()
        SystemSwitchServicesTests.run()
        MenuBarPresentationTests.run()
        print("All tests passed")
    }

    private static func testScaffoldIsReady() {
        expect(Scaffold.status == "scaffold ready", "scaffold status should be ready")
    }

    private static func testRightControlStartsDoubaoVoiceWhenIdle() {
        let services = FakeServices()
        var coordinator = SwitchCoordinator(services: services)

        coordinator.handle(.rightControlPressed)

        expect(coordinator.state == .doubaoVoiceActive, "right Ctrl should enter doubao voice state")
        expect(services.actions == [.switchToDoubao, .startDoubaoVoice], "right Ctrl should switch to doubao and start voice")
    }

    private static func testLeftControlDoesNothingWhenIdle() {
        let services = FakeServices()
        var coordinator = SwitchCoordinator(services: services)

        coordinator.handle(.leftControlPressed)

        expect(coordinator.state == .idle, "left Ctrl should keep idle state")
        expect(services.actions.isEmpty, "left Ctrl should not trigger any action")
    }

    private static func testRightControlStopsDoubaoVoiceAndRestoresPrimaryInput() {
        let services = FakeServices()
        var coordinator = SwitchCoordinator(services: services)

        coordinator.handle(.rightControlPressed)
        services.actions.removeAll()
        coordinator.handle(.rightControlPressed)

        expect(coordinator.state == .idle, "second right Ctrl should return to idle")
        expect(services.actions == [.switchToPrimary], "second right Ctrl should restore primary input without canceling pending Doubao commit")
    }

    private static func testRightControlDoesNothingWhenExternalVoiceToolIsRunning() {
        let services = FakeServices()
        var coordinator = SwitchCoordinator(services: services)

        coordinator.handle(.externalVoiceToolStarted)
        coordinator.handle(.rightControlPressed)

        expect(coordinator.state == .suspended, "external voice tool should suspend coordinator")
        expect(services.actions.isEmpty, "suspended state should not trigger doubao actions")
    }

    private static func testRightControlWorksAfterExternalVoiceToolStops() {
        let services = FakeServices()
        var coordinator = SwitchCoordinator(services: services)

        coordinator.handle(.externalVoiceToolStarted)
        coordinator.handle(.externalVoiceToolStopped)
        coordinator.handle(.rightControlPressed)

        expect(coordinator.state == .doubaoVoiceActive, "right Ctrl should work after external voice tool stops")
        expect(services.actions == [.switchToDoubao, .startDoubaoVoice], "right Ctrl should trigger doubao after suspension ends")
    }

    private static func testDoubaoSwitchFailureMovesToError() {
        let services = FakeServices()
        services.failSwitchToDoubao = true
        var coordinator = SwitchCoordinator(services: services)

        coordinator.handle(.rightControlPressed)

        expect(coordinator.state == .error, "doubao switch failure should move to error")
        expect(services.actions == [.switchToDoubao], "doubao switch failure should stop following actions")
    }

    private static func testPrimaryRestoreFailureMovesToError() {
        let services = FakeServices()
        var coordinator = SwitchCoordinator(services: services)

        coordinator.handle(.rightControlPressed)
        services.actions.removeAll()
        services.failSwitchToPrimary = true
        coordinator.handle(.rightControlPressed)

        expect(coordinator.state == .error, "primary restore failure should move to error")
        expect(services.actions == [.switchToPrimary], "primary restore failure should be visible in action order")
    }

    private static func testLoadsDefaultConfig() {
        let config = expectNoThrow("default config should load") {
            try ConfigStore().load(path: "config/default.json")
        }

        expect(config.externalVoiceAppPath == "/Applications/Type4Me.app", "default external voice app path should match")
        expect(config.externalVoiceBundleId == "com.type4me.app", "default external voice bundle id should match")
        expect(config.primaryInputSourceId == "im.rime.inputmethod.Squirrel.Hans", "default primary input source should match")
        expect(config.doubaoInputSourceId == "com.bytedance.inputmethod.doubaoime.pinyin", "default doubao input source should match")
        expect(config.doubaoVoiceHotkey == .rightControl, "default doubao voice hotkey should match Doubao settings")
    }

    private static func testMissingConfigFieldFailsClearly() {
        let path = ".build/test-missing-config-field.json"
        let invalidConfig = """
        {
          "externalVoiceAppPath": "/Applications/Type4Me.app",
          "externalVoiceBundleId": "com.type4me.app",
          "primaryInputSourceId": "im.rime.inputmethod.Squirrel.Hans"
        }
        """

        expectNoThrow("test config fixture should be writable") {
            try invalidConfig.write(toFile: path, atomically: true, encoding: .utf8)
        }

        expectThrows("missing doubao input source should fail clearly") {
            _ = try ConfigStore().load(path: path)
        }
    }

    private static func testDefaultInputSourcesExistOnThisMac() {
        let config = expectNoThrow("default config should load") {
            try ConfigStore().load(path: "config/default.json")
        }
        let service = InputSourceService()

        expect(service.containsInputSource(id: config.primaryInputSourceId), "primary input source should exist on this Mac")
        expect(service.containsInputSource(id: config.doubaoInputSourceId), "doubao input source should exist on this Mac")
    }

    private static func testPrimaryInputSourceIsSelectableOnThisMac() {
        let config = expectNoThrow("default config should load") {
            try ConfigStore().load(path: "config/default.json")
        }
        let service = InputSourceService()

        expect(service.containsSelectableInputSource(id: config.primaryInputSourceId), "primary input source should be selectable on this Mac")
    }

    private static func testUnselectableInputSourceFailsClearly() {
        let config = expectNoThrow("default config should load") {
            try ConfigStore().load(path: "config/default.json")
        }
        let service = InputSourceService()

        if service.containsSelectableInputSource(id: config.doubaoInputSourceId) {
            return
        }

        expectThrows("unselectable doubao input source should fail clearly") {
            try service.selectInputSource(id: config.doubaoInputSourceId)
        }
    }

    private static func testMissingInputSourceFailsClearly() {
        let service = InputSourceService()

        expectThrows("missing input source should fail clearly") {
            try service.requireInputSource(id: "invalid.input.source")
        }
    }

    private static func testExternalVoiceToolRunningWhenBundleIdMatches() {
        let monitor = VoiceToolMonitor(
            config: AppConfig(
                externalVoiceAppPath: "/Applications/Type4Me.app",
                externalVoiceBundleId: "com.type4me.app",
                primaryInputSourceId: "im.rime.inputmethod.Squirrel.Hans",
                doubaoInputSourceId: "com.bytedance.inputmethod.doubaoime.pinyin",
                doubaoVoiceHotkey: .rightControl
            ),
            runningBundleIds: { ["com.type4me.app"] },
            pathExists: { _ in true }
        )

        expect(monitor.isExternalVoiceToolRunning(), "matching bundle id should report external voice tool running")
    }

    private static func testExternalVoiceToolNotRunningWhenBundleIdDoesNotMatch() {
        let monitor = VoiceToolMonitor(
            config: AppConfig(
                externalVoiceAppPath: "/Applications/Type4Me.app",
                externalVoiceBundleId: "com.type4me.app",
                primaryInputSourceId: "im.rime.inputmethod.Squirrel.Hans",
                doubaoInputSourceId: "com.bytedance.inputmethod.doubaoime.pinyin",
                doubaoVoiceHotkey: .rightControl
            ),
            runningBundleIds: { ["com.example.OtherApp"] },
            pathExists: { _ in true }
        )

        expect(!monitor.isExternalVoiceToolRunning(), "non-matching bundle id should report external voice tool not running")
    }

    private static func testMissingExternalVoiceAppPathWarnsButDoesNotBlock() {
        let monitor = VoiceToolMonitor(
            config: AppConfig(
                externalVoiceAppPath: "/Applications/MissingVoiceTool.app",
                externalVoiceBundleId: "com.type4me.app",
                primaryInputSourceId: "im.rime.inputmethod.Squirrel.Hans",
                doubaoInputSourceId: "com.bytedance.inputmethod.doubaoime.pinyin",
                doubaoVoiceHotkey: .rightControl
            ),
            runningBundleIds: { [] },
            pathExists: { _ in false }
        )

        expect(monitor.configurationWarnings() == [.externalVoiceAppPathMissing("/Applications/MissingVoiceTool.app")], "missing external voice app path should warn")
        expect(!monitor.isExternalVoiceToolRunning(), "missing path should not force running state")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fatalError(message)
        }
    }

    private static func expectNoThrow<T>(_ message: String, _ work: () throws -> T) -> T {
        do {
            return try work()
        } catch {
            fatalError("\(message): \(error)")
        }
    }

    private static func expectThrows(_ message: String, _ work: () throws -> Void) {
        do {
            try work()
            fatalError(message)
        } catch {
            return
        }
    }
}

private final class FakeServices: SwitchCoordinatingServices {
    var actions: [SwitchAction] = []
    var failSwitchToDoubao = false
    var failSwitchToPrimary = false

    func switchToDoubao() -> Bool {
        actions.append(.switchToDoubao)
        return !failSwitchToDoubao
    }

    func switchToPrimary() -> Bool {
        actions.append(.switchToPrimary)
        return !failSwitchToPrimary
    }

    func startDoubaoVoice() -> Bool {
        actions.append(.startDoubaoVoice)
        return true
    }

    func stopDoubaoVoiceIfPossible() -> Bool {
        actions.append(.stopDoubaoVoice)
        return true
    }

}
