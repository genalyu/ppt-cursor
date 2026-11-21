import Foundation
import CursorCore

public struct BridgeFailure: LocalizedError {
    public let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

public enum PowerPointBridge {
    public static func capture() throws -> SlideSnapshot? { try run([]) }

    public static func apply(_ prediction: Prediction, to baseline: SlideSnapshot, images: [ReferenceImage] = []) throws -> SlideSnapshot {
        try prediction.validate(for: baseline, images: images)
        struct Request: Encodable {
            let baseline: SlideSnapshot
            let sources: [String: Data]
            let proposal: Prediction
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let used = Set(prediction.artwork.compactMap(\.referenceID))
        let sources = Dictionary(uniqueKeysWithValues: images.filter { used.contains($0.id) }.map { ($0.id, $0.png) })
        let data = try JSONEncoder().encode(Request(baseline: baseline, sources: sources, proposal: prediction))
        guard FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw BridgeFailure("无法准备 PowerPoint 操作。")
        }
        guard let result = try run(["apply", file.path]) else { throw BridgeFailure("幻灯片已关闭。") }
        return result
    }

    private static func run(_ arguments: [String]) throws -> SlideSnapshot? {
        let script = ResourcesBundle.value.url(forResource: "snapshot", withExtension: "js")!
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", script.path] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: data, as: UTF8.self)
            if detail.contains("(-1743)") {
                throw BridgeFailure("请在系统设置 → 隐私与安全性 → 自动化中允许 PPT Cursor 控制 Microsoft PowerPoint，然后返回幻灯片。")
            }
            throw BridgeFailure(String(detail.prefix(1500)))
        }
        return try JSONDecoder().decode(SlideSnapshot?.self, from: data)
    }
}
