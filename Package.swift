// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RimeDou",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "RimeDouCore", targets: ["RimeDouCore"]),
        .executable(name: "rimedou", targets: ["RimeDou"])
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
        .testTarget(
            name: "RimeDouTests",
            dependencies: ["RimeDouCore"],
            path: "tests/RimeDouTests"
        )
    ]
)
