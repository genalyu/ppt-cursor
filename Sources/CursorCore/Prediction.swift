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
    public let id: String
    public let fontSize: Double?
    public let duplicate: Bool?
    public let placement: Placement
    public let rotation: Double
    public let text: String?
}

public struct Artwork: Codable, Sendable {
    public let placement: Placement
    public let referenceID: String?
    public let svg: String
}

public struct Prediction: Codable, Sendable {
    public let summary: String
    public let edits: [ObjectEdit]
    public let artwork: [Artwork]

    public func validate(for slide: SlideSnapshot, images: [ReferenceImage] = []) throws {
        let ids = Set(slide.objects.map(\.id))
        let sizedText = Set(slide.objects.filter { $0.fontSize != nil }.map(\.id))
        let placeholders = Set(slide.objects.filter { $0.kind == "shape type place holder" }.map(\.id))
        let originals = edits.filter { $0.duplicate != true }.map(\.id)
        guard summary.count <= 500, edits.count <= 100, artwork.count <= 12,
              edits.allSatisfy({ $0.duplicate != true || !placeholders.contains($0.id) }),
              edits.allSatisfy({ edit in
                  guard let size = edit.fontSize else { return true }
                  return sizedText.contains(edit.id) && (1...4000).contains(size)
              }),
              Set(originals).count == originals.count,
              edits.allSatisfy({ ids.contains($0.id) && $0.placement.validate(in: slide) && $0.rotation.isFinite && ($0.text?.count ?? 0) <= 20000 }),
              artwork.allSatisfy({ $0.placement.validate(in: slide) && validArtwork($0, images: images) }) else {
            throw PredictionError.invalidSuggestion
        }
    }
    private func validArtwork(_ art: Artwork, images: [ReferenceImage]) -> Bool {
        if let id = art.referenceID { return art.svg.isEmpty && images.contains { $0.id == id } }
        return VectorAsset.accepts(art.svg)
    }

}

public enum PredictionError: Error { case invalidSuggestion, missingResult }

enum PredictionInput {
    static let schema = ResourcesBundle.value.url(forResource: "prediction", withExtension: "json")!

    static func instructions() throws -> String {
        try String(contentsOf: ResourcesBundle.value.url(forResource: "predict", withExtension: "txt")!, encoding: .utf8)
    }

    static func context(_ context: EditContext, images: [ReferenceImage], hasPage: Bool) throws -> String {
        let catalog = images.map { ["id": $0.id, "name": $0.name] }
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
        for image in images {
            let url = dir.appendingPathComponent(image.id + ".png")
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
        guard process.terminationStatus == 0 else { throw PredictionError.missingResult }
        let suggestion = try JSONDecoder().decode(Prediction.self, from: Data(contentsOf: result))
        try suggestion.validate(for: context.current, images: images)
        return suggestion
    }
}
