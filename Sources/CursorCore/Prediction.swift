import Foundation

public struct Placement: Codable, Sendable {
    public let x, y, width, height: Double

    func validate(in slide: SlideSnapshot) -> Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0 &&
        width <= slide.width * 4 && height <= slide.height * 4 &&
        x < slide.width && y < slide.height && x + width > 0 && y + height > 0
    }
}

public struct ObjectEdit: Codable, Sendable {
    public var solidFillRGB: [Int]? = nil
    public let id: String
    public let fontSize: Double?
    public let duplicate: Bool?
    public let placement: Placement
    public let rotation: Double
    public let text: String?
}

public struct Artwork: Codable, Sendable {
    public var rotation: Double? = nil
    public let placement: Placement
    public let referenceID: String?
    public let svg: String
}

public struct Prediction: Codable, Sendable {
    public let summary: String
    public let edits: [ObjectEdit]
    public let artwork: [Artwork]

    public func validate(for slide: SlideSnapshot, images: [ReferenceImage] = []) throws {
        let sources = Dictionary(slide.objects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let originals = edits.filter { $0.duplicate != true }.map(\.id)
        guard Set(images.map(\.id)).count == images.count, summary.count <= 500, edits.count <= 100, artwork.count <= 12,
              Set(originals).count == originals.count,
              edits.allSatisfy({ edit in
                  guard let source = sources[edit.id], edit.placement.validate(in: slide),
                        edit.rotation.isFinite else { return false }
                  if edit.duplicate == true && source.kind == "shape type place holder" { return false }
                  if let text = edit.text, source.text == nil || text.count > 20000 { return false }
                  if let rgb = edit.solidFillRGB, source.solidFillRGB == nil || rgb.count != 3 || !rgb.allSatisfy({ (0...255).contains($0) }) { return false }
                  if let size = edit.fontSize, source.fontSize == nil || !(1...4000).contains(size) { return false }
                  return true
              }),
              artwork.allSatisfy({ ($0.rotation ?? 0).isFinite && $0.placement.validate(in: slide) && validArtwork($0, images: images) }) else {
            throw PredictionError.invalidSuggestion
        }
    }
    private func validArtwork(_ art: Artwork, images: [ReferenceImage]) -> Bool {
        if let id = art.referenceID { return art.svg.isEmpty && images.contains { $0.id == id } }
        return VectorAsset.accepts(art.svg)
    }

}

public enum PredictionError: LocalizedError {
    case invalidSuggestion, missingResult, invalidResponse, cliFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidSuggestion: return "建议中的对象、位置或素材无法应用到当前幻灯片"
        case .missingResult: return "模型未返回完整的编辑建议"
        case .invalidResponse: return "模型返回的数据格式无法读取"
        case .cliFailed(let status): return "Codex CLI 运行失败（退出码 \(status)），请检查登录状态和网络连接"
        }
    }
}

extension Prediction {
    static func read(_ data: Data, for slide: SlideSnapshot, images: [ReferenceImage]) throws -> Prediction {
        guard let suggestion = try? JSONDecoder().decode(Prediction.self, from: data) else {
            throw PredictionError.invalidResponse
        }
        try suggestion.validate(for: slide, images: images)
        let artwork = suggestion.artwork.map { art -> Artwork in
            guard let id = art.referenceID, let size = images.first(where: { $0.id == id })?.pixelSize else { return art }
            let box = art.placement
            let scale = min(box.width / size.width, box.height / size.height)
            let width = size.width * scale, height = size.height * scale
            let fit = Placement(x: box.x + (box.width - width) / 2, y: box.y + (box.height - height) / 2,
                                width: width, height: height)
            return Artwork(placement: fit, referenceID: id, svg: art.svg)
        }
        let sources = Dictionary(slide.objects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let normalized = suggestion.edits.map { edit in
            let nativeText = edit.text?.replacingOccurrences(of: "\r\n", with: "\r")
                .replacingOccurrences(of: "\n", with: "\r")
            let angle = edit.rotation.truncatingRemainder(dividingBy: 360)
            return ObjectEdit(solidFillRGB: edit.solidFillRGB, id: edit.id, fontSize: edit.fontSize, duplicate: edit.duplicate,
                              placement: edit.placement, rotation: angle < 0 ? angle + 360 : angle, text: nativeText)
        }
        // Match the write tolerance in the PowerPoint automation bridge.
        func differs(_ proposed: Double, _ existing: Double) -> Bool { abs(proposed - existing) > 0.02 }
        let edits = normalized.filter { edit in
            guard edit.duplicate != true, let source = sources[edit.id] else { return true }
            let box = edit.placement
            return differs(box.x, source.x) || differs(box.y, source.y) || differs(box.width, source.width) ||
                differs(box.height, source.height) || differs(edit.rotation, source.rotation) ||
                (edit.text != nil && edit.text != source.text) ||
                (edit.solidFillRGB != nil && edit.solidFillRGB != source.solidFillRGB) ||
                (edit.fontSize.map { differs($0, source.fontSize ?? 0) } ?? false)
        }
        let fitted = Prediction(summary: suggestion.summary, edits: edits, artwork: artwork)
        try fitted.validate(for: slide, images: images)
        return fitted
    }
}

enum PredictionInput {
    static let schema = ResourcesBundle.value.url(forResource: "prediction", withExtension: "json")!

    static func instructions() throws -> String {
        try String(contentsOf: ResourcesBundle.value.url(forResource: "predict", withExtension: "txt")!, encoding: .utf8)
    }

    static func context(_ context: EditContext, images: [ReferenceImage], hasPage: Bool) throws -> String {
        let catalog = images.map { image in
            var entry = ["id": image.id, "name": image.name]
            if let size = image.pixelSize { entry["pixels"] = "\(Int(size.width))x\(Int(size.height))" }
            return entry
        }
        let prefix = hasPage ? "The first attached image is the current slide, not an insertable reference. Remaining attachments follow catalog order.\n" : ""
        return try prefix + String(decoding: JSONEncoder().encode(catalog), as: UTF8.self) + "\n" +
            String(decoding: JSONEncoder().encode(context), as: UTF8.self)
    }
}

/// Uses the installed CLI's existing sign-in. The subprocess works inside an empty temporary
/// directory. User content travels through stdin, never through a shell or command-line argument.
public struct Predictor: Sendable {
    public let executable: URL
    public init(executable: URL) { self.executable = executable }

    public func predict(_ context: EditContext, images: [ReferenceImage] = [], currentPage: Data? = nil, run: PredictionRun = PredictionRun()) throws -> Prediction {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: dir) }
        let result = dir.appendingPathComponent("response.json")
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = dir
        process.arguments = ["exec", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only",
                             "--output-schema", PredictionInput.schema.path, "--output-last-message", result.path, "-"]
        var attachments: [String] = []
        if let currentPage {
            let pageURL = dir.appendingPathComponent("current-page.png")
            try currentPage.write(to: pageURL)
            attachments += ["--image", pageURL.path]
        }
        for (index, image) in images.enumerated() {
            let url = dir.appendingPathComponent("reference-\(index).png")
            try image.thumbnail.write(to: url)
            attachments += ["--image", url.path]
        }
        process.arguments?.insert(contentsOf: attachments, at: 1)
        let input = dir.appendingPathComponent("input")
        let request = try PredictionInput.instructions() + "\n" +
            PredictionInput.context(context, images: images, hasPage: currentPage != nil)
        try Data(request.utf8).write(to: input)
        let handle = try FileHandle(forReadingFrom: input)
        defer { try? handle.close() }
        process.standardInput = handle
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try run.execute(process)
        guard process.terminationStatus == 0 else { throw PredictionError.cliFailed(process.terminationStatus) }
        guard fm.fileExists(atPath: result.path) else { throw PredictionError.missingResult }
        return try Prediction.read(Data(contentsOf: result), for: context.current, images: images)
    }
}
