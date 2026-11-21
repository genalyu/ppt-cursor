import Foundation

enum NativeSessionLauncher {
    static func process(script: URL, document: URL, codex: URL?, references: [(url: URL, name: String)], includePage: Bool) -> Process {
        let process = Process()
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [codex?.deletingLastPathComponent().path, environment["PATH"], "/opt/homebrew/bin", "/usr/local/bin", home + "/anaconda3/bin", home + "/miniconda3/bin", "/usr/bin"].compactMap { $0 }
        environment["PATH"] = paths.joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PPT_CURSOR_MANAGED_SESSION"] = "1"
        process.environment = environment
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Finder and Terminal can resolve different Python installations.
        // Probe in PATH order, preserving spaces in interpreter and document paths.
        let launch = """
        oldifs=$IFS
        IFS=:
        for dir in $PATH; do
            IFS=$oldifs
            if [ -x "$dir/python3" ] && "$dir/python3" -c 'import PIL.Image' 2>/dev/null; then
                exec "$dir/python3" "$@"
            fi
            IFS=:
        done
        echo '找不到装有 Pillow 的 Python 3 环境' >&2
        exit 1
        """
        process.arguments = ["-c", launch, "ppt-cursor", script.path, "session", document.path]
            + (includePage ? ["--include-page"] : [])
            + references.flatMap { ["--named-reference", $0.url.path, $0.name] }
        return process
    }

    static func stop(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        if getpgid(pid) == pid { kill(-pid, SIGTERM) }
        else { process.terminate() }
    }
}
