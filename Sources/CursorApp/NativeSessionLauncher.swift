import Foundation

struct NativeEditInstruction: Encodable {
    let text: String
    let document: String
    let slideID: Int
}

enum NativeSessionLauncher {
    static func environment(codex: URL? = nil, bundleURL: URL = Bundle.main.bundleURL,
                            inherited: [String: String] = ProcessInfo.processInfo.environment,
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String: String] {
        var environment = inherited
        let home = home.path
        // Source builds live under <repository>/dist; Finder does not inherit a venv.
        let projectPython = bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".venv/bin").path
        let paths = [projectPython, codex?.deletingLastPathComponent().path, environment["PATH"], "/opt/homebrew/bin", "/usr/local/bin", home + "/anaconda3/bin", home + "/miniconda3/bin", "/usr/bin"].compactMap { $0 }
        environment["PATH"] = paths.joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PPT_CURSOR_MANAGED_SESSION"] = "1"
        return environment
    }

    static func process(script: URL, document: URL, codex: URL?, references: [(url: URL, name: String)], includePage: Bool, instructionFile: URL? = nil) -> Process {
        let process = Process()
        process.environment = environment(codex: codex)
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
        echo '找不到装有 Pillow 的 Python 3 环境。源码用户请在项目 .venv 中安装 requirements.txt；详见 README。' >&2
        exit 1
        """
        process.arguments = ["-c", launch, "ppt-cursor", script.path, "session", document.path]
            + (includePage ? ["--include-page"] : [])
            + (instructionFile.map { ["--instruction-file", $0.path] } ?? [])
            + references.flatMap { ["--named-reference", $0.url.path, $0.name] }
        return process
    }

    static func stop(_ process: Process, completion: @escaping (Error?) -> Void = { _ in }) {
        guard process.isRunning else { DispatchQueue.main.async { completion(nil) }; return }
        guard let directory = process.environment?["PPT_CURSOR_CONTROL_DIRECTORY"] else {
            let error = NSError(domain: "PPTCursor.Shutdown", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "缺少会话控制目录，无法安全结束。请等待本次操作完成后重试。"])
            DispatchQueue.main.async { completion(error) }; return
        }
        let root = URL(fileURLWithPath: directory)
        do { try Data().write(to: root.appendingPathComponent("stop"), options: .atomic) }
        catch { DispatchQueue.main.async { completion(error) }; return }
        DispatchQueue.global(qos: .userInitiated).async {
            // The worker holds this lock across preview writeback AND its checkpoint.
            // Wait off the UI thread; never time out by killing a possibly active write.
            let descriptor = open(root.appendingPathComponent("preview.lock").path, O_CREAT | O_RDWR, 0o600)
            guard descriptor >= 0 else {
                let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                DispatchQueue.main.async { completion(error) }; return
            }
            defer { close(descriptor) }
            while flock(descriptor, LOCK_EX) != 0 {
                if errno == EINTR { continue }
                let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                DispatchQueue.main.async { completion(error) }; return
            }
            if process.isRunning {
                let pid = process.processIdentifier
                if getpgid(pid) == pid { kill(-pid, SIGTERM) }
                else { process.terminate() }
            }
            DispatchQueue.main.async { completion(nil) }
        }
    }
}
