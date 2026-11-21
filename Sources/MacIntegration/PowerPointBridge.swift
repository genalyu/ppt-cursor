import Foundation
import CursorCore

public struct BridgeFailure: LocalizedError {
    public let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

public enum PowerPointBridge {
    public static func capture() throws -> SlideSnapshot? { try run([]) }

    public static func apply(_ prediction: Prediction, to baseline: SlideSnapshot) throws -> SlideSnapshot {
        try prediction.validate(for: baseline)
        struct Request: Encodable {
            let baseline: SlideSnapshot
            let proposal: Prediction
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let data = try JSONEncoder().encode(Request(baseline: baseline, proposal: prediction))
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
            throw BridgeFailure(String(decoding: data.prefix(1500), as: UTF8.self))
        }
        return try JSONDecoder().decode(SlideSnapshot?.self, from: data)
    }
}
