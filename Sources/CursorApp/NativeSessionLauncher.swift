import Foundation

enum NativeSessionLauncher {
    static func command(script: URL, document: URL, codex: URL?, references: [(url: URL, name: String)], session: URL, includePage: Bool = false) -> String {
        func quote(_ path: String) -> String {
            "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        var lines = ["#!/bin/sh", "session_dir=" + quote(session.path), "trap 'rm -rf \"$session_dir\"' EXIT", "trap 'exit 130' HUP INT TERM"]
        if let codex {
            lines.append("export PATH=" + quote(codex.deletingLastPathComponent().path) + ":\"$PATH\"")
        }
        let arguments = [script.path, "session", document.path] + (includePage ? ["--include-page"] : []) + references.flatMap { ["--named-reference", $0.url.path, $0.name] }
        lines.append("python3 " + arguments.map(quote).joined(separator: " "))
        return lines.joined(separator: "\n") + "\n"
    }
}
