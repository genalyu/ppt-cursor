import AppKit

public enum CodexInstallation {
    public static func executable(preferShellPath: Bool = false) -> URL? {
        let shell = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
            .filter { $0.hasPrefix("/") }.map { String($0) + "/codex" }
        let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
        let bundles = [registered?.path, "/Applications/ChatGPT.app", "/Applications/Codex.app"].compactMap { $0 }
        let desktop = bundles.flatMap { bundle in
            [bundle + "/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
             bundle + "/Contents/Resources/codex"]
        }
        let installed = desktop + ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        let candidates = preferShellPath ? shell + installed : installed + shell
        for path in candidates {
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &directory),
               !directory.boolValue, FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
