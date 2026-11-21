import Foundation
import CryptoKit
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
            let vectorIDs: [String]
            let sources: [String: Data]
            let proposal: Prediction
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let used = Set(prediction.artwork.compactMap(\.referenceID))
        let sources = Dictionary(uniqueKeysWithValues: images.filter { used.contains($0.id) }.map { ($0.id, $0.vector ?? $0.png) })
        let data = try JSONEncoder().encode(Request(baseline: baseline, vectorIDs: images.filter { used.contains($0.id) && $0.vector != nil }.map(\.id), sources: sources, proposal: prediction))
        guard FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw BridgeFailure("无法准备 PowerPoint 操作。")
        }
        guard let result = try run(["apply", file.path]) else { throw BridgeFailure("幻灯片已关闭。") }
        return result
    }

    public static func applyStagedShape(from directory: URL, into baseline: SlideSnapshot) throws -> SlideSnapshot {
        struct Target: Decodable {
            let operation: String
            let page, slideID: Int
            let name, candidateSHA256: String
            let presetTarget: String?
        }
        struct NativeInsert: Encodable {
            let presetTarget: String?
            let path, name: String
            let page: Int
        }
        struct Request: Encodable {
            let baseline: SlideSnapshot
            let nativeInsert: NativeInsert
        }
        let target = try JSONDecoder().decode(Target.self, from: Data(contentsOf: directory.appendingPathComponent("target.json")))
        let candidate = try Data(contentsOf: directory.appendingPathComponent("after.pptx"), options: .mappedIfSafe)
        let canChangePreset = target.operation == "replace" && baseline.objects.contains { $0.id == target.presetTarget && $0.autoShapeType != nil }
        guard (target.operation == "insert" || canChangePreset), target.slideID == baseline.slideID, target.page > 0,
              SHA256.hash(data: candidate).map({ String(format: "%02x", $0) }).joined() == target.candidateSHA256 else {
            throw BridgeFailure("建议副本已变化，请重新生成预览。")
        }
        let name = "ppt-cursor-" + UUID().uuidString
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/com.microsoft.Powerpoint/Data/tmp").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent(name + ".pptx")
        try candidate.write(to: copy)
        let request = folder.appendingPathComponent("request.json")
        try JSONEncoder().encode(Request(baseline: baseline, nativeInsert: NativeInsert(presetTarget: canChangePreset ? target.presetTarget : nil, path: copy.path, name: target.name, page: target.page))).write(to: request)
        guard let result = try run(["apply", request.path]) else { throw BridgeFailure("幻灯片已关闭。") }
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
            if detail.contains("(-1712)") {
                let message = arguments.isEmpty
                    ? "读取幻灯片超时。请查看 PowerPoint 或 macOS 是否有等待处理的对话框。"
                    : "PowerPoint 未及时确认写入结果。请先核对幻灯片，再继续编辑。"
                throw BridgeFailure(message)
            }
            throw BridgeFailure(String(detail.prefix(1500)))
        }
        return try JSONDecoder().decode(SlideSnapshot?.self, from: data)
    }
}
