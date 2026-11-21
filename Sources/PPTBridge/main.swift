import Foundation
import CursorCore

func capture() throws -> SlideSnapshot? {
    let script = Bundle.module.url(forResource: "snapshot", withExtension: "js")!
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-l", "JavaScript", script.path]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
    return try JSONDecoder().decode(SlideSnapshot?.self, from: data)
}

func predict(files: [String]) throws {
    guard files.count >= 2 else { throw CLIError.usage }
    var history = EditHistory()
    var context: EditContext?
    for file in files {
        let state = try JSONDecoder().decode(SlideSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: file)))
        context = history.observe(state)
    }
    guard let context else { throw CLIError.noChange }
    let candidates = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        .map { String($0) + "/codex" } +
        ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"]
    guard let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else { throw CLIError.codexMissing }
    let prediction = try Predictor(executable: URL(fileURLWithPath: path)).predict(context)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(prediction))
}

enum CLIError: Error { case usage, noChange, codexMissing }

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.first == "predict" {
        try predict(files: Array(arguments.dropFirst()))
        exit(0)
    }
    guard arguments.isEmpty else { throw CLIError.usage }
    let state = try capture()
    if let state {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(state))
    } else {
        print("No active PowerPoint presentation.")
    }
} catch {
    FileHandle.standardError.write(Data("PPT Cursor failed: \(error)\n".utf8))
    exit(1)
}
