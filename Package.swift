// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PPTCursor",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CursorCore", targets: ["CursorCore"]),
               .executable(name: "ppt-inspect", targets: ["PPTBridge"])],
    targets: [.target(name: "CursorCore", resources: [.process("Resources")]), .executableTarget(name: "PPTBridge", dependencies: ["CursorCore"], resources: [.process("Resources")]),
              .testTarget(name: "CursorCoreTests", dependencies: ["CursorCore"])]
)
