import RimeDouCore

enum SystemSwitchServicesTests {
    static func run() {
        testSwitchToDoubaoWaitsUntilSystemReportsDoubao()
        testSwitchToDoubaoFailsWhenSystemNeverReportsDoubao()
        testSwitchToPrimaryWaitsUntilSystemReportsPrimary()
        testSwitchToPrimaryKeepsSingleSelectionAfterCommitGrace()
        testSwitchToPrimaryRetriesWhenFirstConfirmationFails()
        testRestorePrimaryInputSourceIfNeededDoesNothingWhenAlreadyPrimary()
        testRestorePrimaryInputSourceIfNeededSelectsPrimaryWhenStuckOnDoubao()
    }

    private static func testSwitchToDoubaoWaitsUntilSystemReportsDoubao() {
        let inputSources = FakeInputSourceSelector(
            currentInputSourceIds: [
                "im.rime.inputmethod.Squirrel.Hans",
                "im.rime.inputmethod.Squirrel.Hans",
                "com.bytedance.inputmethod.doubaoime.pinyin"
            ]
        )
        let services = SystemSwitchServices(config: defaultConfig(), inputSourceService: inputSources)

        let result = services.switchToDoubao()

        TestExpect.isTrue(result, "switch to Doubao should wait until current input source is Doubao")
        TestExpect.equal(inputSources.selectedInputSourceIds, ["com.bytedance.inputmethod.doubaoime.pinyin"], "switch to Doubao should select Doubao once")
    }

    private static func testSwitchToDoubaoFailsWhenSystemNeverReportsDoubao() {
        let inputSources = FakeInputSourceSelector(
            currentInputSourceIds: Array(repeating: "im.rime.inputmethod.Squirrel.Hans", count: 30)
        )
        let services = SystemSwitchServices(config: defaultConfig(), inputSourceService: inputSources)

        let result = services.switchToDoubao()

        TestExpect.isTrue(!result, "switch to Doubao should fail if system never reports Doubao")
    }

    private static func testSwitchToPrimaryWaitsUntilSystemReportsPrimary() {
        let inputSources = FakeInputSourceSelector(
            currentInputSourceIds: [
                "com.bytedance.inputmethod.doubaoime.pinyin",
                "com.bytedance.inputmethod.doubaoime.pinyin",
                "im.rime.inputmethod.Squirrel.Hans"
            ]
        )
        let services = SystemSwitchServices(config: defaultConfig(), inputSourceService: inputSources)

        let result = services.switchToPrimary()

        TestExpect.isTrue(result, "switch to primary should wait until current input source is primary")
        TestExpect.equal(inputSources.selectedInputSourceIds, ["im.rime.inputmethod.Squirrel.Hans"], "switch to primary should select primary once")
    }

    private static func testSwitchToPrimaryKeepsSingleSelectionAfterCommitGrace() {
        let inputSources = FakeInputSourceSelector(
            currentInputSourceIds: ["im.rime.inputmethod.Squirrel.Hans"]
        )
        let services = SystemSwitchServices(config: defaultConfig(), inputSourceService: inputSources)

        let result = services.switchToPrimary()

        TestExpect.isTrue(result, "switch to primary should still succeed after commit grace")
        TestExpect.equal(inputSources.selectedInputSourceIds, ["im.rime.inputmethod.Squirrel.Hans"], "commit grace should not duplicate primary selection")
    }

    private static func testSwitchToPrimaryRetriesWhenFirstConfirmationFails() {
        let inputSources = FakeInputSourceSelector(
            currentInputSourceIds: Array(repeating: "com.bytedance.inputmethod.doubaoime.pinyin", count: 26)
                + ["im.rime.inputmethod.Squirrel.Hans"]
        )
        let services = SystemSwitchServices(config: defaultConfig(), inputSourceService: inputSources)

        let result = services.switchToPrimary()

        TestExpect.isTrue(result, "switch to primary should retry when first confirmation fails")
        TestExpect.equal(inputSources.selectedInputSourceIds, ["im.rime.inputmethod.Squirrel.Hans", "im.rime.inputmethod.Squirrel.Hans"], "switch to primary should retry selection once")
    }

    private static func testRestorePrimaryInputSourceIfNeededDoesNothingWhenAlreadyPrimary() {
        let inputSources = FakeInputSourceSelector(
            currentInputSourceIds: ["im.rime.inputmethod.Squirrel.Hans"]
        )
        let services = SystemSwitchServices(config: defaultConfig(), inputSourceService: inputSources)

        let result = services.restorePrimaryInputSourceIfNeeded()

        TestExpect.isTrue(result, "idle primary guard should succeed when already primary")
        TestExpect.equal(inputSources.selectedInputSourceIds, [], "idle primary guard should not select primary when already primary")
    }

    private static func testRestorePrimaryInputSourceIfNeededSelectsPrimaryWhenStuckOnDoubao() {
        let inputSources = FakeInputSourceSelector(
            currentInputSourceIds: [
                "com.bytedance.inputmethod.doubaoime.pinyin",
                "im.rime.inputmethod.Squirrel.Hans"
            ]
        )
        let services = SystemSwitchServices(config: defaultConfig(), inputSourceService: inputSources)

        let result = services.restorePrimaryInputSourceIfNeeded()

        TestExpect.isTrue(result, "idle primary guard should restore primary when stuck on Doubao")
        TestExpect.equal(inputSources.selectedInputSourceIds, ["im.rime.inputmethod.Squirrel.Hans"], "idle primary guard should select primary once")
    }

    private static func defaultConfig() -> AppConfig {
        AppConfig(
            externalVoiceAppPath: "/Applications/Type4Me.app",
            externalVoiceBundleId: "com.type4me.app",
            primaryInputSourceId: "im.rime.inputmethod.Squirrel.Hans",
            doubaoInputSourceId: "com.bytedance.inputmethod.doubaoime.pinyin",
            doubaoVoiceHotkey: .rightControl
        )
    }
}

private final class FakeInputSourceSelector: InputSourceSelecting {
    var selectedInputSourceIds: [String] = []
    private var currentInputSourceIds: [String]

    init(currentInputSourceIds: [String]) {
        self.currentInputSourceIds = currentInputSourceIds
    }

    func selectInputSource(id: String) throws {
        selectedInputSourceIds.append(id)
    }

    func currentInputSourceId() throws -> String {
        if currentInputSourceIds.isEmpty {
            return ""
        }

        return currentInputSourceIds.removeFirst()
    }
}
