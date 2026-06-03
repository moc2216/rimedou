public struct MenuBarPresentation: Equatable {
    public let statusTitle: String
    public let toggleTitle: String

    public init(isPaused: Bool, switchState: SwitchState?, isExternalVoiceToolRunning: Bool) {
        if isPaused {
            statusTitle = "状态：已暂停"
            toggleTitle = "启用"
            return
        }

        if isExternalVoiceToolRunning {
            statusTitle = "状态：Type4Me 运行中，已让渡"
            toggleTitle = "暂停"
            return
        }

        switch switchState {
        case .doubaoVoiceActive:
            statusTitle = "状态：豆包语音中"
        case .error:
            statusTitle = "状态：错误"
        case .suspended:
            statusTitle = "状态：已让渡"
        case .idle, .none:
            statusTitle = "状态：运行中"
        }

        toggleTitle = "暂停"
    }
}
