// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PPTCursor",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CursorCore", targets: ["CursorCore"]),
        .executable(name: "PPTCursor", targets: ["CursorApp"]),
        .executable(name: "ppt-preview", targets: ["CursorPreview"]),
        .executable(name: "ppt-inspect", targets: ["PPTBridge"])
    ],
    targets: [
        .target(name: "CursorCore", resources: [.process("Resources")]),
        .target(name: "MacIntegration", dependencies: ["CursorCore"], resources: [.process("Resources")]),
        .executableTarget(name: "CursorApp", dependencies: ["CursorCore", "MacIntegration"]),
        .executableTarget(name: "CursorPreview", dependencies: ["CursorCore", "MacIntegration"]),
        .executableTarget(name: "PPTBridge", dependencies: ["CursorCore", "MacIntegration"]),
        .testTarget(name: "CursorCoreTests", dependencies: ["CursorCore"])
    ]
)
