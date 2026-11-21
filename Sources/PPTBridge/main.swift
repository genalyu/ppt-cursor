import Foundation
import CursorCore

do {
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
    let state = try JSONDecoder().decode(SlideSnapshot?.self, from: data)
    if let state {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(state))
    } else {
        print("No active PowerPoint presentation.")
    }
} catch {
    FileHandle.standardError.write(Data("PowerPoint snapshot failed: \(error)\n".utf8))
    exit(1)
}
