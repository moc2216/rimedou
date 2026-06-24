import Foundation

public final class SystemSwitchServices: SwitchCoordinatingServices {
    private let config: AppConfig
    private let inputSourceService: InputSourceSelecting
    private let doubaoVoiceController: DoubaoVoiceController

    public init(
        config: AppConfig,
        inputSourceService: InputSourceSelecting = InputSourceService(),
        doubaoVoiceController: DoubaoVoiceController? = nil
    ) {
        self.config = config
        self.inputSourceService = inputSourceService
        self.doubaoVoiceController = doubaoVoiceController ?? DoubaoVoiceController(voiceHotkey: config.doubaoVoiceHotkey)
    }

    public func switchToDoubao() -> Bool {
        do {
            try inputSourceService.selectInputSource(id: config.doubaoInputSourceId)
            return waitUntilCurrentInputSource(id: config.doubaoInputSourceId)
        } catch {
            return false
        }
    }

    public func switchToPrimary() -> Bool {
        waitBeforeRestoringPrimaryInput()
        return selectPrimaryWithRetry()
    }

    public func restorePrimaryInputSourceIfNeeded() -> Bool {
        do {
            if try inputSourceService.currentInputSourceId() == config.primaryInputSourceId {
                return true
            }

            return selectPrimaryWithRetry()
        } catch {
            return false
        }
    }

    public func startDoubaoVoice() -> Bool {
        doubaoVoiceController.startVoiceInput()
    }

    private func waitUntilCurrentInputSource(id expectedInputSourceId: String) -> Bool {
        let deadline = Date().addingTimeInterval(1.2)

        repeat {
            if (try? inputSourceService.currentInputSourceId()) == expectedInputSourceId {
                return true
            }

            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline

        return (try? inputSourceService.currentInputSourceId()) == expectedInputSourceId
    }

    private func waitBeforeRestoringPrimaryInput() {
        Thread.sleep(forTimeInterval: 1.2)
    }

    private func selectPrimaryWithRetry() -> Bool {
        do {
            try inputSourceService.selectInputSource(id: config.primaryInputSourceId)
            if waitUntilCurrentInputSource(id: config.primaryInputSourceId) {
                return true
            }

            Thread.sleep(forTimeInterval: 0.25)
            try inputSourceService.selectInputSource(id: config.primaryInputSourceId)
            return waitUntilCurrentInputSource(id: config.primaryInputSourceId)
        } catch {
            return false
        }
    }
}
