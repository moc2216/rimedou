// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DoubaoVoiceBridge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "DoubaoVoiceBridgeCore", targets: ["DoubaoVoiceBridgeCore"]),
        .executable(name: "DoubaoVoiceBridge", targets: ["DoubaoVoiceBridge"])
    ],
    targets: [
        .target(name: "DoubaoVoiceBridgeCore"),
        .executableTarget(
            name: "DoubaoVoiceBridge",
            dependencies: ["DoubaoVoiceBridgeCore"]
        ),
        .testTarget(
            name: "DoubaoVoiceBridgeCoreTests",
            dependencies: ["DoubaoVoiceBridgeCore"]
        )
    ]
)
