// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "rimedou",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "RimeDouCore", targets: ["RimeDouCore"]),
        .executable(name: "rimedou", targets: ["rimedou"])
    ],
    targets: [
        .target(
            name: "RimeDouCore",
            path: "Sources/RimeDouCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "rimedou",
            dependencies: ["RimeDouCore"],
            path: "Sources/rimedou",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "RimeDouCoreTests",
            dependencies: ["RimeDouCore"],
            path: "Tests/RimeDouCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
