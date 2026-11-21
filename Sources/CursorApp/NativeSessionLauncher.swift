import Foundation

enum NativeSessionLauncher {
    static func command(script: URL, document: URL, codex: URL?) -> String {
        func quote(_ path: String) -> String {
            "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        var lines = ["#!/bin/sh", "rm -f \"$0\""]
        if let codex {
            lines.append("export PATH=" + quote(codex.deletingLastPathComponent().path) + ":\"$PATH\"")
        }
        lines.append("exec python3 " + quote(script.path) + " session " + quote(document.path))
        return lines.joined(separator: "\n") + "\n"
    }
}
