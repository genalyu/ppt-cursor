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
    public let placement: Placement
    public let rotation: Double
    public let text: String?
}

public struct Artwork: Codable, Sendable {
    public let placement: Placement
    public let svg: String
}

public struct Prediction: Codable, Sendable {
    public let summary: String
    public let edits: [ObjectEdit]
    public let artwork: [Artwork]

    public func validate(for slide: SlideSnapshot) throws {
        let ids = Set(slide.objects.map(\.id))
        guard summary.count <= 500, edits.count <= 100, artwork.count <= 12,
              Set(edits.map(\.id)).count == edits.count,
              edits.allSatisfy({ ids.contains($0.id) && $0.placement.validate(in: slide) && $0.rotation.isFinite && ($0.text?.count ?? 0) <= 20000 }),
              artwork.allSatisfy({ $0.placement.validate(in: slide) && VectorAsset.accepts($0.svg) }) else {
            throw PredictionError.invalidSuggestion
        }
    }
}

public enum PredictionError: Error { case invalidSuggestion, missingResult }

/// Uses the installed CLI's existing sign-in. The subprocess works inside an empty temporary
/// directory. User content travels through stdin, never through a shell or command-line argument.
public struct Predictor: Sendable {
    public let executable: URL
    public init(executable: URL) { self.executable = executable }

    public func predict(_ context: EditContext) throws -> Prediction {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: dir) }
        let result = dir.appendingPathComponent("response.json")
        let prompt = try String(contentsOf: Bundle.module.url(forResource: "predict", withExtension: "txt")!)
        let schema = Bundle.module.url(forResource: "prediction", withExtension: "json")!
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = dir
        process.arguments = ["exec", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only",
                             "--output-schema", schema.path, "--output-last-message", result.path, "-"]
        let input = dir.appendingPathComponent("input")
        var request = Data((prompt + "\n").utf8)
        request.append(try JSONEncoder().encode(context))
        try request.write(to: input)
        let handle = try FileHandle(forReadingFrom: input)
        defer { try? handle.close() }
        process.standardInput = handle
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw PredictionError.missingResult }
        let suggestion = try JSONDecoder().decode(Prediction.self, from: Data(contentsOf: result))
        try suggestion.validate(for: context.current)
        return suggestion
    }
}
