import XCTest
@testable import RimeDouCore

final class ProviderTests: XCTestCase {
    func testInstalledProviderDetectionHandlesIndependentAndLegacySources() {
        let d = VoiceProviderRegistry.doubaoInputSourceIdentifier
        let q = VoiceProviderRegistry.qianwenInputSourceIdentifier
        let legacy = VoiceProviderRegistry.qianwenLegacyInputSourceIdentifier
        let cases: [(Set<String>, Set<VoiceProviderID>)] = [
            ([], []), ([d], [.doubao]), ([q], [.qianwen]), ([legacy], [.qianwen]),
            ([d, q], [.doubao, .qianwen]), ([d, legacy], [.doubao, .qianwen]),
            ([VoiceProviderRegistry.qianwenServiceBundleIdentifier, "im.rime.inputmethod.Squirrel.Hans"], [])
        ]
        for (sources, expected) in cases {
            XCTAssertEqual(VoiceProviderRegistry.installedProviders { sources.contains($0) }, expected)
        }
    }

    func testAvailabilityAndSavedSelectionNeverFailOver() {
        XCTAssertNil(VoiceProviderSelectionResolver.resolve(saved: nil, usableProviders: []))
        XCTAssertEqual(VoiceProviderSelectionResolver.resolve(saved: nil, usableProviders: [.doubao]), .doubao)
        XCTAssertEqual(VoiceProviderSelectionResolver.resolve(saved: nil, usableProviders: [.qianwen]), .qianwen)
        XCTAssertEqual(VoiceProviderSelectionResolver.resolve(saved: nil, usableProviders: [.doubao, .qianwen]), .doubao)
        XCTAssertEqual(VoiceProviderSelectionResolver.resolve(saved: .qianwen, usableProviders: [.doubao]), .qianwen)
    }

    func testLegacyConfigLeavesQianwenUnconfigured() throws {
        let config = try RimeDouConfig.load(from: Data(#"{"voiceHotkey":"RightControl"}"#.utf8))
        XCTAssertNil(config.qianwenVoiceHotkey)
        XCTAssertNil(VoiceProviderRegistry.definition(for: .qianwen, config: config))
        XCTAssertEqual(VoiceProviderRegistry.definition(for: .doubao, config: config)?.restorePolicy, .immediate)
        XCTAssertEqual(try RimeDouConfig.load(from: JSONEncoder().encode(config)), config)
    }

    func testSessionFreezesProviderAndConfig() throws {
        var config = try RimeDouConfig.load(from: Data(#"{"qianwenVoiceHotkey":"RightOption"}"#.utf8))
        let provider = try XCTUnwrap(VoiceProviderRegistry.definition(for: .qianwen, config: config))
        let session = VoiceSessionSnapshot(provider: provider, config: config, restoreInputSourceIdentifier: "im.rime.inputmethod.Squirrel.Hans")
        config.qianwenVoiceHotkey = Hotkey(keys: [.leftShift])
        config.qianwenCompletionTimeout = 20
        XCTAssertEqual(session.provider.transportHotkey, Hotkey(keys: [.rightOption]))
        XCTAssertEqual(session.config.qianwenCompletionTimeout, 60)
        XCTAssertEqual(session.provider.restorePolicy, .waitForProviderWindow)
    }

    func testQianwenConflictsDisableOnlyQianwen() throws {
        for key in ["RightCommand", "RightControl", "Control", "RightControl+Space", "RightCommand+Space", "Space+Tab", "NotAKey"] {
            var warnings: [String] = []
            let data = try JSONSerialization.data(withJSONObject: ["qianwenVoiceHotkey": key])
            let config = try RimeDouConfig.load(from: data, onWarning: { warnings.append($0) })
            XCTAssertNil(config.qianwenVoiceHotkey, key)
            XCTAssertEqual(config.voiceHotkey, RimeDouConfig.default.voiceHotkey)
            XCTAssertEqual(config.triggerHotkey, RimeDouConfig.default.triggerHotkey)
            XCTAssertFalse(warnings.isEmpty, key)
        }
    }

    func testQianwenConflictWithSecondTriggerKeepsMouseTrigger() throws {
        let config = try RimeDouConfig.load(from: Data(#"{"triggerHotkey2":"Control+Option+Command+Z","qianwenVoiceHotkey":"Control+Option+Command+Z"}"#.utf8))
        XCTAssertNotNil(config.triggerHotkey2)
        XCTAssertNil(config.qianwenVoiceHotkey)
    }

    func testQianwenTimingAndValidConfigRoundTrip() throws {
        let config = try RimeDouConfig.load(from: Data(#"{"qianwenVoiceHotkey":"RightOption","qianwenCompletionTimeout":0,"qianwenGoneStabilityDelay":0}"#.utf8))
        XCTAssertEqual(config.qianwenVoiceHotkey, Hotkey(keys: [.rightOption]))
        XCTAssertEqual(config.qianwenCompletionTimeout, 60)
        XCTAssertEqual(config.qianwenGoneStabilityDelay, 0.15)
        XCTAssertEqual(try RimeDouConfig.load(from: JSONEncoder().encode(config)), config)
    }

    func testRuntimeProviderIdentityRequiresExactIdentifier() {
        XCTAssertEqual(VoiceProviderRegistry.provider(forInputSourceIdentifier: "com.qianwen.inputmethod.desktopime.hans"), .qianwen)
        XCTAssertEqual(VoiceProviderRegistry.provider(forInputSourceIdentifier: "com.qianwen.inputmethod.desktopime.pinyin"), .qianwen)
        for value in ["千问", "doubao", "com.qianwen.inputmethod.desktopime.hans.other", ""] {
            XCTAssertNil(VoiceProviderRegistry.provider(forInputSourceIdentifier: value))
        }
    }
}
