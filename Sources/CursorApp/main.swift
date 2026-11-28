import AppKit
import UniformTypeIdentifiers
import CursorCore
import MacIntegration

final class Controller: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let status = NSMenuItem(title: "打开要编辑的 PowerPoint 文稿", action: nil, keyEquivalent: "")
    private let toggle = NSMenuItem(title: "开始预测", action: #selector(toggleMonitoring), keyEquivalent: "")
    private lazy var setup = SetupWindow(owner: self, includePageChanged: #selector(refreshNativeSettings), chooseImages: #selector(chooseImages), modelSettings: #selector(chooseModel), toggleTab: #selector(toggleTab), prefersTab: useTab, toggleSession: #selector(toggleMonitoring), retry: #selector(retryPrediction), returnToEditor: #selector(returnToPowerPoint), accept: #selector(accept), dismiss: #selector(dismiss), submitInstruction: #selector(submitInstruction))
    private var documentLookup: UUID?
    private var awaitingDocument = false
    private var followsActiveDocument = true
    private var checkingDocument = false
    private var nextDocumentCheck = Date.distantPast
    private var nativeDocument: URL?
    private var documentFollow = DocumentFollowPolicy()
    private var hasNativePreview = false
    private var nativeProcess: Process?
    private var nativeDirectory: URL?
    private var frame: NSRect?
    private var calibratedWindow: PowerPointWindow?
    private var overlay: NSPanel?
    private var suggestionPanel: SuggestionPanel?
    private var api: APISettings?
    private var modelLookup: UUID?
    private var connectingModel = false
    private var images: [ReferenceImage] = []
    private var predictWithImportedImages = false
    private var imageImport: Task<Void, Never>?
    private var history = EditHistory()
    private var monitoring = false
    private var reading = false
    private var locationRequest: UUID?
    private var inference: PredictionRun?
    private var applying = false
    private var inFlightContext: EditContext?
    private var hiddenSuggestion: (SlideSnapshot, Prediction)?
    private let retryItem = NSMenuItem(title: "重试上次预测", action: #selector(retryPrediction), keyEquivalent: "")
    private var failedContext: EditContext? {
        didSet { retryItem.isHidden = failedContext == nil && nativeProcess == nil }
    }
    private var waiting: EditContext?
    private var pending: (SlideSnapshot, Prediction)?
    private var generation = 0
    private lazy var shortcut = AcceptShortcut { [weak self] in self?.accept() }
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var dragMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle.angled", accessibilityDescription: "PPT Cursor")
        item.button?.toolTip = "PPT Cursor"
        let menu = NSMenu()
        menu.addItem(status)
        menu.addItem(.separator())
        for (title, action) in [("采纳当前建议", #selector(accept)),
                                ("忽略当前建议", #selector(dismiss)), ("选择本次编辑的图片素材…", #selector(chooseImages)),
                                ("清空图片素材", #selector(clearImages)), ("为其他文稿启动预测…", #selector(chooseNativeDocument)), ("模型连接…", #selector(chooseModel)), ("退出 PPT Cursor", #selector(quit))] {
            let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            entry.target = self
        }
        retryItem.target = self
        retryItem.isHidden = true
        menu.addItem(retryItem)
        menu.addItem(tabOption)
        tabOption.target = self
        tabOption.state = useTab ? .on : .off
        toggle.target = self
        menu.insertItem(toggle, at: 3)
        let settings = menu.insertItem(withTitle: "打开控制窗口…", action: #selector(openSetup), keyEquivalent: "", at: 1)
        settings.target = self
        item.menu = menu
        setPhase(.read)
        openSetup()
        restoreModelConnection()
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in self?.poll() }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                     object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.frontmost { self.poll(); return }
            guard self.monitoring, !self.connectingModel else { return }
            // An already submitted prediction uses an immutable snapshot. Its result
            // stays hidden until a foreground capture confirms that snapshot again.
            if self.inference != nil, self.inFlightContext != nil, self.pending == nil { return }
            let ready = self.pending ?? self.hiddenSuggestion
            let interrupted = self.waiting ?? self.inFlightContext
            let failed = self.failedContext
            self.invalidate()
            self.failedContext = failed
            self.hiddenSuggestion = ready
            self.waiting = interrupted
        }
    }

    private func restoreModelConnection() {
        let request = UUID()
        modelLookup = request
        message("正在读取已保存的模型连接…")
        DispatchQueue.global(qos: .userInitiated).async {
            let restored = ModelSettings.restore()
            DispatchQueue.main.async {
                guard self.modelLookup == request else { return }
                self.modelLookup = nil
                self.api = restored
                self.updateSessionControls()
                if restored == nil && ModelSettings.hasSavedConnection {
                    self.setPhase(.error)
                    self.message("模型密钥需要钥匙串授权，请打开模型连接并重新保存连接")
                } else if CommandLine.arguments.contains("--start-editing") {
                    self.startEditing()
                } else if restored != nil || UserDefaults.standard.bool(forKey: "hasStartedSession") {
                    self.awaitCurrentDocument()
                } else { self.setPhase(.paused); self.message("配置模型后点击开始预测") }
            }
        }
    }

    private func awaitCurrentDocument() {
        guard !awaitingDocument else { return }
        followsActiveDocument = true
        awaitingDocument = true
        setPhase(.document)
        updateSessionControls()
        checkForDocument()
    }

    private func checkForDocument() {
        guard awaitingDocument, documentLookup == nil, nativeProcess == nil else { return }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.Powerpoint").isEmpty {
            openNativeSession()
        } else {
            message("请在 PowerPoint 中打开本地 PPTX")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.checkForDocument() }
        }
    }

    @objc private func refreshNativeSettings() {
        guard let document = nativeDocument, nativeProcess != nil else { return }
        stopNativeSession()
        startNativeSession(document)
    }

    @objc private func openNativeSession() {
        guard nativeProcess == nil else { message("开放式预测已启动，可从菜单停止"); return }
        guard documentLookup == nil else { return }
        let request = UUID()
        documentLookup = request
        message("正在读取 PowerPoint 当前文稿…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard self.documentLookup == request else { return }
            self.message("正在读取当前文稿。如果 macOS 提示 PPT Cursor 请求控制 PowerPoint，请处理授权弹窗。")
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try PowerPointBridge.currentDocumentURL() }
            DispatchQueue.main.async {
                guard self.documentLookup == request else { return }
                self.documentLookup = nil
                switch result {
                case .success(let document?):
                    self.startNativeSession(document)
                case .success(nil):
                    self.message("请打开或保存本地 PPTX")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.checkForDocument() }
                case .failure(let error):
                    self.awaitingDocument = false
                    self.setPhase(.error)
                    self.updateSessionControls()
                    self.message(error.localizedDescription)
                }
            }
        }
    }

    @objc private func chooseNativeDocument() {
        guard !connectingModel else { message("请先处理系统钥匙串授权弹窗"); return }
        documentLookup = nil
        guard nativeProcess == nil else { message("请先停止当前开放式预测"); return }
        let chooser = NSOpenPanel()
        chooser.allowedContentTypes = [UTType(filenameExtension: "pptx")!]
        chooser.message = "选择已在 PowerPoint 打开的文稿。本次开放式预测使用 " + (api?.model ?? "Codex CLI") + "。"
        guard chooser.runModal() == .OK, let document = chooser.url else { return }
        followsActiveDocument = false
        startNativeSession(document)
    }

    private func startNativeSession(_ document: URL, instruction: NativeEditInstruction? = nil) {
        guard !connectingModel else { return }
        defer { updateSessionControls() }
        setPhase(.read)
        awaitingDocument = false
        guard api != nil || !ModelSettings.hasSavedConnection else {
            setPhase(.error)
            message("模型密钥尚未解锁，请在模型连接中完成钥匙串授权")
            return
        }
        guard let script = Bundle.main.url(forResource: "stage-drawing", withExtension: "py") else {
            setPhase(.error)
            message("请从打包的 PPT Cursor 应用启动开放式会话")
            return
        }
        // Prediction reads the PowerPoint document. Only the canvas overlay needs screen access.
        let session = FileManager.default.temporaryDirectory.appendingPathComponent("PPT-Cursor-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let references = try images.enumerated().map { index, image in
                let folder = session.appendingPathComponent(String(index))
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                let stem = URL(fileURLWithPath: image.name).deletingPathExtension().lastPathComponent
                let url = folder.appendingPathComponent(stem + ".png")
                try image.png.write(to: url)
                return (url, image.name)
            }
            var instructionFile: URL?
            if let instruction {
                let file = session.appendingPathComponent("instruction.json")
                let data = try JSONEncoder().encode(instruction)
                guard FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                instructionFile = file
            }
            let process = NativeSessionLauncher.process(script: script, document: document, codex: CodexInstallation.executable(), references: references, includePage: setup.includePage.state == .on, instructionFile: instructionFile)
            if let api {
                let settings = try JSONEncoder().encode(api)
                guard settings.count <= 4096 else { message("模型名称或密钥过长"); try? FileManager.default.removeItem(at: session); return }
                let input = Pipe()
                try input.fileHandleForWriting.write(contentsOf: settings)
                try input.fileHandleForWriting.close()
                process.standardInput = input
                process.arguments?.append("--api-stdin")
            }
            process.environment?["TMPDIR"] = session.path
            process.environment?["PPT_CURSOR_CONTROL_DIRECTORY"] = session.path
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            if monitoring || locationRequest != nil { toggleMonitoring() }
            nativeDocument = document
            nativeProcess = process
            nativeDirectory = session
            UserDefaults.standard.set(true, forKey: "hasStartedSession")
            updateSessionControls()
            DispatchQueue.global(qos: .utility).async {
                var pending = Data()
                var lastLine = ""
                func report(_ data: Data) {
                    let line = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !line.isEmpty else { return }
                    lastLine = String(line.prefix(240))
                    let status = lastLine
                    DispatchQueue.main.async {
                        guard self.nativeProcess === process else { return }
                        if status.hasPrefix("已采纳，"), let instruction {
                            self.setup.clearInstruction(ifMatching: instruction.text)
                        }
                        if status.hasPrefix("PPT_CURSOR_PREVIEW=") {
                            let directory = URL(fileURLWithPath: String(status.dropFirst("PPT_CURSOR_PREVIEW=".count))).resolvingSymlinksInPath()
                            guard directory.path.hasPrefix(session.resolvingSymlinksInPath().path + "/"),
                                  let image = NSImage(contentsOf: directory.appendingPathComponent("after.png")) else { return }
                            let summary = (try? String(contentsOf: directory.appendingPathComponent("summary.txt"), encoding: .utf8)) ?? "当前建议"
                            let diagram = FileManager.default.fileExists(atPath: directory.appendingPathComponent("geometry-preview").path)
                            let infoData = try? Data(contentsOf: directory.appendingPathComponent("preview-info.json"))
                            let info = infoData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Bool] }
                            self.hasNativePreview = true
                            self.setup.showPreview(image: image, summary: (diagram ? "位置/尺寸示意 · " : "") + summary,
                                                   direct: info?["direct"] ?? false, source: self.previewSource(in: directory))
                            return
                        }
                        if status.hasPrefix("PPT_CURSOR_PHASE="),
                           let next = Phase(event: String(status.dropFirst("PPT_CURSOR_PHASE=".count))) {
                            self.setPhase(next)
                            return
                        }
                        if !status.hasPrefix("preview: ") { self.message(status) }
                        if status.contains("无法自动定位画布") { self.openSetup() }
                    }
                }
                let reader = output.fileHandleForReading
                while true {
                    let chunk = reader.availableData
                    if chunk.isEmpty { break }
                    pending.append(chunk)
                    while let newline = pending.firstIndex(of: 10) {
                        report(Data(pending[..<newline]))
                        pending.removeSubrange(...newline)
                    }
                    if pending.count > 8192 { pending = Data(pending.suffix(8192)) }
                }
                report(pending)
                process.waitUntilExit()
                let finalStatus = process.terminationStatus == 0 ? "开放式预测已结束" :
                    "开放式预测已退出（" + String(process.terminationStatus) + "）" + lastLine
                try? FileManager.default.removeItem(at: session)
                DispatchQueue.main.async {
                    guard self.nativeProcess === process else { return }
                    self.nativeProcess = nil
                    self.nativeDirectory = nil
                    self.nativeDocument = nil
                    self.updateSessionControls()
                    self.setPhase(process.terminationStatus == 0 ? .paused : (process.terminationStatus == 3 ? .cancelled : .error))
                    self.message(finalStatus)
                }
            }
            returnToPowerPoint()
            message("正在为“" + document.lastPathComponent + "”启动开放式预测…")
        } catch {
            try? FileManager.default.removeItem(at: session)
            setPhase(.error)
            message(error.localizedDescription)
            return
        }
    }

    @objc private func stopNativeSession() {
        documentFollow.invalidate()
        awaitingDocument = false
        nativeDocument = nil
        documentLookup = nil
        setPhase(.paused)
        guard let process = nativeProcess else { updateSessionControls(); message("已暂停，点击开始预测即可继续"); return }
        NativeSessionLauncher.stop(process)
        nativeProcess = nil
        // The output reader removes the directory once the process has actually exited.
        nativeDirectory = nil
        updateSessionControls()
        setPhase(.paused)
        message("开放式预测已停止")
    }

    private func updateSessionControls() {
        let active = nativeProcess != nil || awaitingDocument || documentLookup != nil || monitoring
        toggle.title = active ? "暂停预测" : "开始预测"
        setup.setRunning(active, canRetry: nativeProcess != nil || failedContext != nil, model: api?.model ?? (ModelSettings.hasSavedConnection ? "模型密钥待授权" : "Codex CLI"), document: nativeDocument?.lastPathComponent)
        setup.setConnecting(connectingModel)
        retryItem.isHidden = nativeProcess == nil && failedContext == nil
        retryItem.title = nativeProcess != nil ? "重新预测当前页" : "重试上次预测"
    }

    private func sendSessionCommand(_ command: String) {
        guard let directory = nativeDirectory else { return }
        do { try Data().write(to: directory.appendingPathComponent(command), options: .atomic) }
        catch { message("操作未发送：" + error.localizedDescription) }
    }

    @objc private func submitInstruction() {
        guard !connectingModel, modelLookup == nil else { message("请先完成模型连接"); return }
        guard phase != .apply, !applying else { message("请等当前修改写入完成后再提交要求"); return }
        let text = setup.requestedInstruction
        guard !text.isEmpty, text.unicodeScalars.count <= 2000 else {
            message("请输入 1–2000 字的本次修改要求"); return
        }
        guard api != nil || !ModelSettings.hasSavedConnection else {
            setPhase(.error); message("请先在模型连接中解锁已保存的密钥"); return
        }
        stopNativeSession()
        if monitoring { monitoring = false; invalidate() }
        let request = UUID()
        documentLookup = request
        setPhase(.read)
        message("正在将要求绑定到当前文稿和页面…")
        updateSessionControls()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () throws -> (URL, NativeEditInstruction) in
                guard let snapshot = try PowerPointBridge.capture(),
                      let document = try PowerPointBridge.currentDocumentURL() else {
                    throw NSError(domain: "PPTCursor.Instruction", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "请先在 PowerPoint 中打开并保存本地 PPTX。"])
                }
                return (document, NativeEditInstruction(text: text, document: snapshot.document, slideID: snapshot.slideID))
            }
            DispatchQueue.main.async {
                guard self.documentLookup == request else { return }
                self.documentLookup = nil
                switch result {
                case .success(let (document, instruction)):
                    self.followsActiveDocument = true
                    self.startNativeSession(document, instruction: instruction)
                case .failure(let error):
                    self.setPhase(.failed)
                    self.message(error.localizedDescription)
                }
                self.updateSessionControls()
            }
        }
    }

    @objc private func returnToPowerPoint() {
        guard let powerpoint = NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.Powerpoint").first else {
            message("请先在 PowerPoint 中打开本地 PPTX")
            return
        }
        setup.orderOut(nil)
        powerpoint.activate(options: [.activateIgnoringOtherApps])
    }

    @objc private func openSetup() {
        updateSessionControls()
        setup.update(status.title == phase.rawValue ? phase.explanation : status.title)
        NSApp.activate(ignoringOtherApps: true)
        setup.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSetup()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { inference?.cancel(); stopNativeSession() }

    private var frontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() == "com.microsoft.powerpoint"
    }
    private typealias Phase = SessionPhase
    private var phase: Phase = .paused
    private var phaseStarted = Date()

    private func previewSource(in directory: URL) -> URL? {
        struct Source: Decodable { let sourceURL: URL }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("asset-source.json")) else { return nil }
        return (try? JSONDecoder().decode(Source.self, from: data))?.sourceURL
    }

    private func refreshStatusTitle() {
        item.button?.title = phase.title(elapsed: Date().timeIntervalSince(phaseStarted))
        item.button?.imagePosition = .imageLeading
        setup.updatePhase(phase.title(elapsed: Date().timeIntervalSince(phaseStarted)))
    }

    private func setPhase(_ next: Phase) {
        guard next != phase else { refreshStatusTitle(); return }
        phase = next
        phaseStarted = Date()
        if ![.preview, .waiting, .apply].contains(next) { setup.clearPreview(); hasNativePreview = false }
        if next == .apply { documentFollow.invalidate() }
        setup.setApplying(next == .apply)
        if let directory = nativeDirectory {
            let record = ["phase": next.rawValue, "time": ISO8601DateFormatter().string(from: Date())]
            if let data = try? JSONSerialization.data(withJSONObject: record) {
                let url = directory.appendingPathComponent("session-events.jsonl")
                if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data + Data([10]))
                }
            }
        }
        refreshStatusTitle()
        status.title = next.rawValue
        setup.update(next.explanation)
        item.button?.toolTip = next.rawValue
    }

    private func message(_ value: String) {
        status.title = phase.rawValue + " · " + value
        item.button?.toolTip = status.title
        setup.update(value)
        if CommandLine.arguments.contains("--verbose") {
            FileHandle.standardError.write(Data((value + "\n").utf8))
        }
    }
    private func invalidate() {
        if nativeProcess == nil && !connectingModel { setPhase(monitoring ? .read : .paused) }
        generation += 1
        inference?.cancel()
        inference = nil
        pending = nil
        failedContext = nil
        hiddenSuggestion = nil
        inFlightContext = nil
        waiting = nil
        if let dragMonitor {
            NSEvent.removeMonitor(dragMonitor)
            self.dragMonitor = nil
        }
        shortcut.disable()
        suggestionPanel?.orderOut(nil)
        suggestionPanel = nil
        overlay?.orderOut(nil)
        overlay = nil
    }
    private let tabOption = NSMenuItem(title: "用 Tab 采纳可见建议", action: #selector(toggleTab), keyEquivalent: "")
    private var useTab: Bool { AcceptShortcut.prefersTab }

    @objc private func toggleTab() {
        let enabled = !useTab
        AcceptShortcut.prefersTab = enabled
        tabOption.state = enabled ? .on : .off
        setup.tabOption.state = tabOption.state
        if let (state, proposal) = pending {
            invalidate()
            if frontmost { show(state, proposal) } else { hiddenSuggestion = (state, proposal) }
        }
        if nativeProcess != nil { sendSessionCommand("refresh-shortcut") }
    }

    @objc private func dismiss() {
        if nativeProcess != nil { sendSessionCommand("dismiss-preview"); return }
        if let (state, suggestion) = pending ?? hiddenSuggestion {
            history.recordDismissal(suggestion.summary, on: state)
        }
        invalidate()
        message("已忽略，继续编辑即可")
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggleMonitoring() {
        guard !connectingModel else { message("请先处理系统钥匙串授权弹窗"); return }
        guard modelLookup == nil else { message("正在读取模型连接，请稍候"); return }
        if nativeProcess != nil || awaitingDocument || documentLookup != nil { stopNativeSession(); return }
        if !monitoring && locationRequest == nil { awaitCurrentDocument(); return }
        if locationRequest != nil {
            locationRequest = nil
            monitoring = false
            invalidate()
            history.reset()
            toggle.title = "开始预测"
            message("已暂停")
            return
        }
        if !monitoring && frame == nil { startEditing(); return }
        monitoring.toggle()
        invalidate()
        history.reset()
        toggle.title = monitoring ? "暂停预测" : "开始预测"
        message(monitoring ? "正在读取当前页" : "已暂停")
    }

    @objc private func retryPrediction() {
        if nativeProcess != nil {
            sendSessionCommand("retry")
            message("已请求重新预测，切回 PowerPoint 后继续")
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.Powerpoint").first?.activate(options: [])
            return
        }
        guard monitoring, let context = failedContext else { return }
        failedContext = nil
        waiting = context
        message("正在重新核对幻灯片…")
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.Powerpoint").first?.activate(options: [])
        poll()
    }

    @objc private func chooseModel() {
        guard !connectingModel else { message("请先处理系统钥匙串授权弹窗"); return }
        guard let choice = ModelSettings.choose(current: api) else { return }
        modelLookup = nil
        let document = nativeDocument
        if nativeProcess != nil || awaitingDocument || documentLookup != nil { stopNativeSession() }
        let interrupted = waiting ?? inFlightContext ?? failedContext
        invalidate()
        connectingModel = true
        setPhase(.authorizing)
        updateSessionControls()
        ModelSettings.resolve(choice) { [weak self] result in
            guard let self else { return }
            self.connectingModel = false
            switch result {
            case .failure(let error):
                self.setPhase(.error)
                self.message(error.localizedDescription)
            case .success(let connection):
                switch connection {
                case .cli: self.api = nil
                case .api(let settings): self.api = settings
                }
                self.waiting = interrupted
                self.setPhase(.paused)
                self.message("已选择 " + (self.api?.model ?? "Codex CLI"))
                if let document { self.startNativeSession(document) }
                else if self.monitoring, interrupted != nil { self.poll() }
            }
            self.updateSessionControls()
        }
    }

    @objc private func clearImages() {
        imageImport?.cancel()
        imageImport = nil
        invalidate()
        images.removeAll()
        predictWithImportedImages = false
        message("已清空素材")
        refreshNativeSettings()
    }

    @objc private func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .svg]
        panel.allowsMultipleSelection = true
        panel.message = "选择供预测使用的图片。模型会收到文件名及缩略图。重新选择将替换本次素材。"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        imageImport?.cancel()
        let interrupted = waiting ?? inFlightContext
        invalidate()
        waiting = interrupted
        message("正在载入 " + String(urls.count) + " 张素材…")
        imageImport = Task { @MainActor in
            let worker = Task.detached(priority: .userInitiated) {
                try urls.map { url in
                    try Task.checkCancellation()
                    return try autoreleasepool { try ImageImport.read(url) }
                }
            }
            let result = await withTaskCancellationHandler {
                await worker.result
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            imageImport = nil
            switch result {
            case .success(let imported):
                images = imported
                predictWithImportedImages = true
                message("已载入 " + String(imported.count) + " 张素材")
                refreshNativeSettings()
            case .failure(let error): message(error.localizedDescription)
            }
            poll()
        }
    }

    @objc private func startEditing() {
        awaitingDocument = false
        documentLookup = nil
        if nativeProcess != nil { stopNativeSession() }
        guard locationRequest == nil else { return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            openSetup()
            message("自动定位需要屏幕录制权限。请在系统设置中允许 PPT Cursor，然后重新打开应用。")
            return
        }

        guard let ppt = NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.Powerpoint").first else {
            message("请打开 PowerPoint 和要编辑的演示文稿，然后点击「定位画布并开始」。")
            openSetup()
            return
        }
        guard let window = PowerPointWindow.front(of: ppt) else {
            message("请显示 PowerPoint 的编辑窗口，然后点击「定位画布并开始」。")
            openSetup()
            return
        }
        let request = UUID()
        locationRequest = request
        toggle.title = "暂停预测"
        message("正在读取页面尺寸。若系统询问，请允许控制 PowerPoint。")
        ppt.activate(options: [])
        DispatchQueue.global(qos: .userInitiated).async {
            let capture = Result { try PowerPointBridge.capture() }
            DispatchQueue.main.async {
                guard self.locationRequest == request else { return }
                self.locationRequest = nil
                self.toggle.title = self.monitoring ? "暂停预测" : "开始预测"
                let slide: SlideSnapshot
                switch capture {
                case .success(let current?):
                    slide = current
                case .success(nil):
                    self.message("请先在 PowerPoint 编辑窗口打开一页幻灯片，再开始预测。")
                    self.openSetup()
                    return
                case .failure(let error):
                    self.message(error.localizedDescription)
                    self.openSetup()
                    return
                }
                self.setup.orderOut(nil)
                guard CGPreflightScreenCaptureAccess(), let current = PowerPointWindow.front(of: ppt),
                      current.id == window.id, slide.height > 0,
                      let page = PageLocator.locate(in: current, aspect: slide.width / slide.height) else {
                    self.openSetup()
                    self.message("无法自动定位画布。请在 PowerPoint 普通视图中完整显示当前页，然后重新定位。")
                    return
                }
                self.invalidate()
                self.frame = page
                self.calibratedWindow = current
                self.history.reset()
                _ = self.history.observe(slide)
                self.monitoring = true
                self.toggle.title = "暂停预测"
                ppt.activate(options: [])
                self.message("已定位画布，正在读取当前页")
            }
        }
    }

    private var editingWithPointer: Bool {
        NSEvent.pressedMouseButtons & 1 != 0
    }

    private func hideDuringCanvasDrag() {
        guard let ready = pending, frontmost, let frame, frame.contains(NSEvent.mouseLocation),
              suggestionPanel?.frame.contains(NSEvent.mouseLocation) != true else { return }
        invalidate()
        hiddenSuggestion = ready
    }

    private func followPowerPointDocument() {
        guard followsActiveDocument, frontmost, phase != .apply, let process = nativeProcess, let document = nativeDocument,
              !checkingDocument, Date() >= nextDocumentCheck else { return }
        nextDocumentCheck = Date().addingTimeInterval(2)
        checkingDocument = true
        let observationGeneration = documentFollow.generation
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try PowerPointBridge.currentDocumentURL() }
            DispatchQueue.main.async {
                self.checkingDocument = false
                guard self.nativeProcess === process, self.frontmost, case .success(let current?) = result else { return }
                guard self.documentFollow.shouldFollow(current, active: document, generation: observationGeneration,
                                                      applying: self.phase == .apply) else {
                    if current.resolvingSymlinksInPath() != document.resolvingSymlinksInPath() {
                        self.nextDocumentCheck = Date().addingTimeInterval(0.5)
                    }
                    return
                }
                self.stopNativeSession()
                self.imageImport?.cancel()
                self.images.removeAll()
                self.startNativeSession(current)
            }
        }
    }

    private func poll() {
        refreshStatusTitle()
        guard !connectingModel else { return }
        followPowerPointDocument()
        guard monitoring, frontmost, !reading, !applying else { return }
        // A held drag may pause between mouse movements. Sample the committed slide after release.
        guard !editingWithPointer else {
            hideDuringCanvasDrag()
            return
        }
        if let old = calibratedWindow, let ppt = NSWorkspace.shared.frontmostApplication {
            guard let current = PowerPointWindow.front(of: ppt), old.id == current.id else {
                invalidate()
                frame = nil
                calibratedWindow = nil
                monitoring = false
                toggle.title = "开始预测"
                history.reset()
                message("PowerPoint 窗口已改变，请重新定位画布")
                return
            }
            if old.frame.size != current.frame.size {
                let ready = pending ?? hiddenSuggestion
                let interrupted = waiting ?? inFlightContext
                invalidate()
                hiddenSuggestion = ready
                waiting = interrupted
                frame = nil
                calibratedWindow = current
            } else if old.frame.origin != current.frame.origin {
                frame = frame?.offsetBy(dx: current.frame.minX - old.frame.minX, dy: current.frame.minY - old.frame.minY)
                calibratedWindow = current
                if let frame {
                    overlay?.setFrame(frame, display: true)
                    suggestionPanel?.position(at: frame)
                }
            }
        }
        reading = true
        let revision = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try PowerPointBridge.capture() }
            DispatchQueue.main.async {
                self.reading = false
                guard self.monitoring, self.frontmost, !self.editingWithPointer, revision == self.generation else { return }
                switch result {
                case .success(let value):
                    guard let state = value else { self.invalidate(); self.history.reset(); return }
                    let previous = self.history.current
                    let viewChanged = previous.map {
                        $0.viewZoom != state.viewZoom || $0.width != state.width || $0.height != state.height
                    } ?? false
                    if self.frame == nil || viewChanged {
                        if viewChanged { self.invalidate() }
                        guard let window = self.calibratedWindow, CGPreflightScreenCaptureAccess(),
                              let page = PageLocator.locate(in: window, aspect: state.width / state.height) else {
                            self.invalidate()
                            self.frame = nil
                            self.monitoring = false
                            self.history.reset()
                            self.toggle.title = "开始预测"
                            self.message("页面显示范围已改变，请重新定位幻灯片画布")
                            return
                        }
                        self.frame = page
                    }
                    let edit = self.history.observe(state)
                    if previous != state || self.predictWithImportedImages {
                        var context = self.predictWithImportedImages ? self.history.currentContext : edit
                        context?.imagesJustImported = self.predictWithImportedImages
                        self.predictWithImportedImages = false
                        self.invalidate()
                        self.waiting = context
                        self.message(context == nil ? "已读取当前页" : "正在判断下一步…")
                        return
                    }
                    if let (baseline, suggestion) = self.hiddenSuggestion, baseline == state {
                        self.hiddenSuggestion = nil
                        self.show(state, suggestion)
                    } else {
                        self.startPrediction()
                    }
                case .failure(let error):
                    self.invalidate()
                    self.message(error.localizedDescription)
                }
            }
        }
    }

    private func startPrediction() {
        guard imageImport == nil, inference == nil, let context = waiting else { return }
        setPhase(.predict)
        waiting = nil
        let references = images
        var currentPage: Data?
        if setup.includePage.state == .on, let window = calibratedWindow, let frame {
            currentPage = PageLocator.previewData(in: window, expected: frame, aspect: context.current.width / context.current.height)
        }
        let connection = api
        let page = currentPage
        let run = PredictionRun()
        inference = run
        inFlightContext = context
        let revision = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () throws -> Prediction in
                if let connection {
                    return try APIPredictor(settings: connection).predict(context, images: references, currentPage: page, run: run)
                }
                guard let executable = CodexInstallation.executable() else {
                    throw NSError(domain: "PPTCursor", code: 1, userInfo: [NSLocalizedDescriptionKey: "请安装并登录 Codex CLI"])
                }
                return try Predictor(executable: executable).predict(context, images: references, currentPage: page, run: run)
            }
            DispatchQueue.main.async {
                // A cancelled request can finish after the next prediction has started.
                guard self.inference === run, self.generation == revision else { return }
                self.inference = nil
                self.inFlightContext = nil
                switch result {
                case .success(let suggestion):
                    guard !suggestion.edits.isEmpty || !suggestion.artwork.isEmpty else { self.message("当前页暂无可见改动"); return }
                    // PowerPoint may have changed during inference, between two polling ticks.
                    // Publish only after a fresh capture confirms the baseline and the mouse is up.
                    self.generation += 1 // Reject any capture already in flight when inference finished.
                    self.hiddenSuggestion = (context.current, suggestion)
                    self.poll()
                case .failure(let error):
                    self.failedContext = context
                    self.message(error.localizedDescription + " · 可从菜单重试上次预测")
                }
            }
        }
    }

    private func show(_ state: SlideSnapshot, _ prediction: Prediction) {
        guard let frame else { return }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        let moving = Set(prediction.edits.map(\.id))
        let needsAppearance = state.objects.contains { moving.contains($0.id) && PreviewCanvas.supportsAppearancePreview($0) }
        let localPage = needsAppearance ? calibratedWindow.flatMap {
            PageLocator.pageImage(in: $0, expected: frame, aspect: state.width / state.height)
        } : nil
        let canvas = PreviewCanvas(slide: state, suggestion: prediction, frame: NSRect(origin: .zero, size: frame.size), diagnosticBackground: false, images: images, pageImage: localPage)
        guard canvas.canPreviewAllArtwork else {
            failedContext = history.currentContext
            message("建议中的图片无法预览，可从菜单重试上次预测")
            return
        }
        panel.contentView = canvas
        panel.orderFrontRegardless()
        overlay = panel
        pending = (state, prediction)
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.hideDuringCanvasDrag()
        }
        let registerTab = AcceptShortcut.allowsTab(editingText: state.editingText)
        let shortcutLabel = shortcut.registerPreferred(useTab: registerTab)
        let controls = SuggestionPanel(summary: prediction.summary, shortcutLabel: shortcutLabel,
                                       owner: self, accept: #selector(accept), dismiss: #selector(dismiss), page: frame)
        suggestionPanel = controls
        controls.orderFrontRegardless()
        setPhase(.preview)
        message(prediction.summary + (shortcutLabel.map { " · " + $0 + " 采纳" } ?? " · 点击采纳"))
    }

    @objc private func accept() {
        if nativeProcess != nil {
            guard hasNativePreview else { return }
            setPhase(.apply)
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.Powerpoint").first?.activate(options: [])
            sendSessionCommand("accept-preview")
            return
        }
        guard frontmost, !editingWithPointer, !applying, let (state, proposal) = pending else { return }
        guard let expectedWindow = calibratedWindow,
              let powerpoint = NSWorkspace.shared.frontmostApplication,
              let currentWindow = PowerPointWindow.front(of: powerpoint),
              currentWindow.id == expectedWindow.id,
              currentWindow.frame == expectedWindow.frame else {
            invalidate()
            message("PowerPoint 窗口已改变，已收起旧建议")
            poll()
            return
        }
        let references = images
        setPhase(.apply)
        applying = true
        invalidate()
        let revision = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try PowerPointBridge.apply(proposal, to: state, images: references) }
            DispatchQueue.main.async {
                self.applying = false
                self.setPhase(.read)
                guard revision == self.generation else { return }
                switch result {
                case .success(let state): _ = self.history.observe(state, acceptedSuggestion: proposal.summary); self.message("已采纳")
                case .failure(let error): self.message(error.localizedDescription)
                }
            }
        }
    }
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--show-staged-preview" {
    do { try StagedPreview.display(directory: URL(fileURLWithPath: CommandLine.arguments[2])) }
    catch {
        FileHandle.standardError.write(Data(("无法显示当前页预览：" + error.localizedDescription + "\n").utf8))
        exit(1)
    }
    exit(0)
}

// Runs through the packaged resource path and native automation bridge without logging slide content.
if CommandLine.arguments.dropFirst().elementsEqual(["--check-canvas"]) {
    guard let ppt = NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.Powerpoint").first,
          let window = PowerPointWindow.front(of: ppt), let slide = try? PowerPointBridge.capture(),
          let rect = PageLocator.locate(in: window, aspect: slide.width / slide.height) else { exit(1) }
    print("Window: \(window.frame), page: \(rect)")
    exit(0)
}

if CommandLine.arguments.dropFirst().elementsEqual(["--check-powerpoint"]) {
    do {
        if let slide = try PowerPointBridge.capture() {
            print("Connected: slide \(slide.slideID), \(slide.objects.count) objects, \(slide.width) × \(slide.height) pt")
        } else { print("Connected: no active slide.") }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
        exit(1)
    }
}

if CommandLine.arguments.dropFirst().elementsEqual(["--configure-bailian"]) {
    let key = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { exit(1) }
    _ = try ModelSettings.save(base: ModelSettings.beijing, model: "qwen4-max", key: key)
    exit(0)
}
if CommandLine.arguments.dropFirst().elementsEqual(["--check-model"]) {
    guard let settings = ModelSettings.restore() else { print("Codex CLI"); exit(1) }
    print(settings.model, settings.baseURL)
    exit(0)
}

let application = NSApplication.shared
let controller = Controller()
application.setActivationPolicy(.accessory)
application.delegate = controller
application.run()
