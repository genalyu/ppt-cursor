import Foundation
import CursorCore
import MacIntegration

func predict(arguments: [String]) throws {
    var files: [String] = []
    var images: [ReferenceImage] = []
    var iterator = arguments.makeIterator()
    while let arg = iterator.next() {
        if arg == "--image" {
            guard let path = iterator.next() else { throw CLIError.usage }
            images.append(try ImageImport.read(URL(fileURLWithPath: path)))
        } else {
            files.append(arg)
        }
    }
    guard !files.isEmpty, files.count >= 2 || !images.isEmpty else { throw CLIError.usage }
    var history = EditHistory()
    var context: EditContext?
    for file in files {
        let state = try JSONDecoder().decode(SlideSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: file)))
        context = history.observe(state)
    }
    guard var context = context ?? (images.isEmpty ? nil : history.currentContext) else { throw CLIError.noChange }
    context.imagesJustImported = files.count == 1 && !images.isEmpty
    guard let executable = CodexInstallation.executable(preferShellPath: true) else { throw CLIError.codexMissing }
    let prediction = try Predictor(executable: executable).predict(context, images: images)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(prediction))
}

enum CLIError: Error { case usage, noChange, codexMissing }

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.first == "render" {
        guard arguments.count == 4, let page = Int(arguments[2]) else { throw CLIError.usage }
        let png = try NativeSlideRenderer.render(file: URL(fileURLWithPath: arguments[1]), page: page)
        try png.write(to: URL(fileURLWithPath: arguments[3]), options: .withoutOverwriting)
        exit(0)
    }
    if arguments.first == "predict" {
        try predict(arguments: Array(arguments.dropFirst()))
        exit(0)
    }
    guard arguments.isEmpty else { throw CLIError.usage }
    let state = try PowerPointBridge.capture()
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
