// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwitchOnlyDoubaoVoiceInput",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "switch-only-doubao-voice-input",
            targets: ["SwitchOnlyDoubaoVoiceInput"]
        ),
        .executable(
            name: "switch-only-doubao-voice-input-tests",
            targets: ["SwitchOnlyDoubaoVoiceInputTests"]
        )
    ],
    targets: [
        .target(
            name: "SwitchOnlyDoubaoVoiceInputCore",
            path: "src/SwitchOnlyDoubaoVoiceInputCore"
        ),
        .executableTarget(
            name: "SwitchOnlyDoubaoVoiceInput",
            dependencies: ["SwitchOnlyDoubaoVoiceInputCore"],
            path: "src/SwitchOnlyDoubaoVoiceInput"
        ),
        .executableTarget(
            name: "SwitchOnlyDoubaoVoiceInputTests",
            dependencies: ["SwitchOnlyDoubaoVoiceInputCore"],
            path: "tests/SwitchOnlyDoubaoVoiceInputTests"
        )
    ]
)
