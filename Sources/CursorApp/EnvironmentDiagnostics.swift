import Foundation
import Darwin

struct EnvironmentDiagnostic {
    enum Status: String { case ready = "可用", review = "待确认", missing = "需处理" }
    let title: String
    let status: Status
    let detail: String
    let reportDetail: String
}

struct EnvironmentReport {
    let items: [EnvironmentDiagnostic]
    var missingCount: Int { items.filter { $0.status == .missing }.count }
    var summary: String { missingCount == 0 ? "本机依赖已就绪" : "还有 \(missingCount) 项需要处理" }
    var text: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "source"
        return (["PPT Cursor 环境检查 · build \(version)", "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)", summary]
            + items.map { "\($0.title)：\($0.status.rawValue) · \($0.reportDetail)" }
            + ["模型登录、网络和服务响应未测试。摘要不包含密钥、文稿或完整本机路径。"])
            .joined(separator: "\n")
    }
}

enum EnvironmentDiagnostics {
    enum Model { case unlockedAPI, savedAPI, cli, missing }
    enum ProbeResult { case available, failed, timedOut }

    static func executable(_ name: String, environment: [String: String],
                           isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> URL? {
        candidates(name, environment: environment).first(where: { isExecutable($0.path) })
    }

    static func candidates(_ name: String, environment: [String: String]) -> [URL] {
        var seen = Set<String>()
        return (environment["PATH"] ?? "").components(separatedBy: ":").compactMap { directory in
            // Match the launcher's "$dir/python3" resolution, including paths with spaces.
            let path = URL(fileURLWithPath: directory + "/" + name).standardizedFileURL
            return seen.insert(path.path).inserted ? path : nil
        }
    }

    static func probePython(_ url: URL, environment: [String: String], timeout: TimeInterval = 2) -> ProbeResult {
        let process = Process()
        process.executableURL = url
        process.arguments = ["-c", "import PIL.Image"]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failed }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            return .timedOut
        }
        process.waitUntilExit()
        return process.terminationStatus == 0 ? .available : .failed
    }

    static func check(environment: [String: String], powerPoint: URL?, resources: URL?, model: Model,
                      isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:),
                      exists: (String) -> Bool = FileManager.default.fileExists(atPath:),
                      probe: (URL, [String: String], TimeInterval) -> ProbeResult = probePython,
                      budget: TimeInterval = 8) -> EnvironmentReport {
        var items: [EnvironmentDiagnostic] = []
        func add(_ title: String, _ status: EnvironmentDiagnostic.Status, _ detail: String, report: String? = nil) {
            items.append(EnvironmentDiagnostic(title: title, status: status, detail: detail, reportDetail: report ?? detail))
        }
        add("PowerPoint", powerPoint == nil ? .missing : .ready,
            powerPoint == nil ? "请安装桌面版 Microsoft PowerPoint，再打开并保存本地 PPTX。" : "已找到桌面版 PowerPoint。检查不会打开或修改文稿。")
        let deadline = Date().addingTimeInterval(budget)
        var python: URL?
        var timedOut = false
        for candidate in candidates("python3", environment: environment).filter({ isExecutable($0.path) }) {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { timedOut = true; break }
            switch probe(candidate, environment, min(2, remaining)) {
            case .available: python = candidate
            case .failed: break
            case .timedOut: timedOut = true
            }
            if python != nil { break }
        }
        if let python {
            add("Python 与 Pillow", .ready, "使用：\(python.path)\nPillow 可正常导入。", report: "已找到可导入 Pillow 的 Python 3。")
        } else {
            add("Python 与 Pillow", .missing,
                timedOut ? "部分 Python 检查超时。请按使用指南检查 Python/Pillow 安装或路径，然后重新检查。"
                         : "未找到可用的 Python 3 + Pillow。查看使用指南的安装步骤后重新检查。")
        }
        let office = executable("soffice", environment: environment, isExecutable: isExecutable)
            ?? (isExecutable("/Applications/LibreOffice.app/Contents/MacOS/soffice")
                ? URL(fileURLWithPath: "/Applications/LibreOffice.app/Contents/MacOS/soffice") : nil)
        let converter = executable("pdftoppm", environment: environment, isExecutable: isExecutable) != nil
            || isExecutable("/usr/bin/sips")
        if office == nil {
            add("预览渲染", .missing, "请安装 LibreOffice，用于文字、图片和图形的完整预览。安装后点击重新检查。")
        } else if !converter {
            add("预览渲染", .missing, "未找到系统图像转换工具 sips 或 pdftoppm。请查看使用指南的故障处理。")
        } else { add("预览渲染", .ready, "已找到 LibreOffice 和图像转换工具。") }
        let required = ["stage-drawing.py", "web_assets.py", "shape_inserts.py",
                        "PPTCursor_MacIntegration.bundle/snapshot.js", "PPTCursor_CursorCore.bundle/predict.txt"]
        let complete = resources.map { root in required.allSatisfy { exists(root.appendingPathComponent($0).path) } } ?? false
        add("应用组件", complete ? .ready : .missing,
            complete ? "预测、素材搜索、图形生成和 PowerPoint 组件齐全。"
                     : "应用组件不完整。请重新下载预览版；源码用户运行 Scripts/build-app.sh 后打开 dist 中的应用。")
        switch model {
        case .unlockedAPI:
            add("模型连接", .ready, "当前 API 配置已解锁，可沿用现有密钥；服务可用性以实际请求为准。")
        case .savedAPI:
            add("模型连接", .review, "已有保存的 API 配置。若启动提示授权，打开模型连接，密钥留空并保存以沿用原密钥。此检查不读取钥匙串。")
        case .cli:
            add("模型连接", .review, "已找到 Codex CLI，登录状态未检查。遇到鉴权失败时请先登录，或在模型连接中选择 API。")
        case .missing:
            add("模型连接", .missing, "请在模型连接中配置 API，或安装并登录 Codex CLI。")
        }
        return EnvironmentReport(items: items)
    }
}
