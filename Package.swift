// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RimeDou",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "rimedou",
            targets: ["RimeDou"]
        ),
        .executable(
            name: "rimedou-tests",
            targets: ["RimeDouTests"]
        )
    ],
    targets: [
        .target(
            name: "RimeDouCore",
            path: "src/RimeDouCore"
        ),
        .executableTarget(
            name: "RimeDou",
            dependencies: ["RimeDouCore"],
            path: "src/RimeDou"
        ),
        .executableTarget(
            name: "RimeDouTests",
            dependencies: ["RimeDouCore"],
            path: "tests/RimeDouTests"
        )
    ]
)
