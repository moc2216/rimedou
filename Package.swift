// swift-tools-version: 5.9
/**
 * [INPUT]: 依赖 Swift PackageDescription 描述包结构、target、product 与平台约束
 * [OUTPUT]: 对外提供 DoubaoVoiceBridge SwiftPM 包定义
 * [POS]: 项目根配置入口，连接 Core 库、菜单栏可执行文件与测试 target
 * [PROTOCOL]: 变更时更新此头部，然后检查 codex.md
 */
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
        .target(
            name: "DoubaoVoiceBridgeCore",
            exclude: ["codex.md"]
        ),
        .executableTarget(
            name: "DoubaoVoiceBridge",
            dependencies: ["DoubaoVoiceBridgeCore"],
            exclude: ["codex.md"]
        ),
        .testTarget(
            name: "DoubaoVoiceBridgeCoreTests",
            dependencies: ["DoubaoVoiceBridgeCore"],
            exclude: ["codex.md"]
        )
    ]
)
