import AppKit
import UniformTypeIdentifiers
import CursorCore
import MacIntegration

final class Controller: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let status = NSMenuItem(title: "先打开 PowerPoint，定位幻灯片画布", action: nil, keyEquivalent: "")
    private let toggle = NSMenuItem(title: "开始预测", action: #selector(toggleMonitoring), keyEquivalent: "")
    private lazy var setup = SetupWindow(owner: self, calibrate: #selector(startEditing), openNativeSession: #selector(openNativeSession), chooseImages: #selector(chooseImages), modelSettings: #selector(chooseModel))
    private var frame: NSRect?
    private var calibratedWindow: PowerPointWindow?
    private var calibration: NSPanel?
    private var overlay: NSPanel?
    private var suggestionPanel: SuggestionPanel?
    private var api: APISettings?
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
        didSet { retryItem.isHidden = failedContext == nil }
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
        for (title, action) in [("定位幻灯片画布…", #selector(calibrate)), ("采纳当前建议", #selector(accept)),
                                ("忽略当前建议", #selector(dismiss)), ("选择本次编辑的图片素材…", #selector(chooseImages)),
                                ("清空图片素材", #selector(clearImages)), ("在终端启动开放式预测…", #selector(openNativeSession)), ("模型连接…", #selector(chooseModel)), ("退出 PPT Cursor", #selector(quit))] {
            let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            entry.target = self
        }
        retryItem.target = self
        retryItem.isHidden = true
        menu.addItem(retryItem)
        let tabOption = menu.addItem(withTitle: "用 Tab 采纳可见建议", action: #selector(toggleTab(_:)), keyEquivalent: "")
        tabOption.target = self
        tabOption.state = useTab ? .on : .off
        toggle.target = self
        menu.insertItem(toggle, at: 3)
        let settings = menu.insertItem(withTitle: "打开控制窗口…", action: #selector(openSetup), keyEquivalent: "", at: 1)
        settings.target = self
        item.menu = menu
        if CommandLine.arguments.contains("--start-editing") { startEditing() } else { openSetup() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in self?.poll() }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                     object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.frontmost { self.poll(); return }
            guard self.monitoring else { return }
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

    @objc private func openNativeSession() {
        guard let script = Bundle.main.url(forResource: "stage-drawing", withExtension: "py"),
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            message("请从打包的 PPT Cursor 应用启动开放式会话")
            return
        }
        let chooser = NSOpenPanel()
        chooser.allowedContentTypes = [UTType(filenameExtension: "pptx")!]
        chooser.message = "选择已在 PowerPoint 打开的文稿。开放式预测使用 Codex CLI；按 Control-C 结束。"
        guard chooser.runModal() == .OK, let document = chooser.url else { return }
        let session = FileManager.default.temporaryDirectory.appendingPathComponent("PPT-Cursor-" + UUID().uuidString)
        let launcher = session.appendingPathComponent("PPT Cursor.command")
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
            let command = NativeSessionLauncher.command(script: script, document: document, codex: CodexInstallation.executable(), references: references, session: session, includePage: setup.includePage.state == .on)
            try command.write(to: launcher, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launcher.path)
        } catch {
            try? FileManager.default.removeItem(at: session)
            message(error.localizedDescription)
            return
        }
        if monitoring || locationRequest != nil { toggleMonitoring() }
        NSWorkspace.shared.open([launcher], withApplicationAt: terminal, configuration: .init()) { _, error in
            if let error {
                try? FileManager.default.removeItem(at: session)
                DispatchQueue.main.async { self.message(error.localizedDescription) }
            }
        }
    }

    @objc private func openSetup() {
        setup.update(status.title)
        NSApp.activate(ignoringOtherApps: true)
        setup.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSetup()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { inference?.cancel() }

    private var frontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() == "com.microsoft.powerpoint"
    }
    private func message(_ value: String) {
        status.title = value
        item.button?.toolTip = value
        setup.update(value)
        if CommandLine.arguments.contains("--verbose") {
            FileHandle.standardError.write(Data((value + "\n").utf8))
        }
    }
    private func invalidate() {
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
    private var useTab: Bool { AcceptShortcut.prefersTab }

    @objc private func toggleTab(_ sender: NSMenuItem) {
        let enabled = !useTab
        AcceptShortcut.prefersTab = enabled
        sender.state = enabled ? .on : .off
        if let (state, proposal) = pending {
            invalidate()
            if frontmost { show(state, proposal) } else { hiddenSuggestion = (state, proposal) }
        }
    }

    @objc private func dismiss() {
        if let (state, suggestion) = pending ?? hiddenSuggestion {
            history.recordDismissal(suggestion.summary, on: state)
        }
        invalidate()
        message("已忽略，继续编辑即可")
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggleMonitoring() {
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
        message(monitoring ? "等待 PowerPoint 编辑" : "已暂停")
    }

    @objc private func retryPrediction() {
        guard monitoring, let context = failedContext else { return }
        failedContext = nil
        waiting = context
        message("正在重新核对幻灯片…")
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.Powerpoint").first?.activate(options: [])
        poll()
    }

    @objc private func chooseModel() {
        guard let choice = ModelSettings.choose(current: api) else { return }
        let interrupted = waiting ?? inFlightContext ?? failedContext
        invalidate()
        waiting = interrupted
        switch choice {
        case .cli: api = nil; message("已选择 Codex CLI")
        case .api(let settings): api = settings; message("已选择 API 模型 " + settings.model)
        }
        if monitoring, interrupted != nil {
            message("模型连接已更新，正在重新核对幻灯片…")
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.Powerpoint").first?.activate(options: [])
            poll()
        }
    }

    @objc private func clearImages() {
        imageImport?.cancel()
        imageImport = nil
        invalidate()
        images.removeAll()
        predictWithImportedImages = false
        message("已清空素材")
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
            case .failure(let error): message(error.localizedDescription)
            }
            poll()
        }
    }

    @objc private func startEditing() {
        guard locationRequest == nil, calibration == nil else { return }
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
                    self.presentCalibration(aspect: slide.width / slide.height)
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
                self.message("已定位画布，等待编辑")
            }
        }
    }

    @objc private func calibrate() {
        let aspect = history.current.map { $0.width / $0.height }
        presentCalibration(aspect: aspect)
    }

    private func presentCalibration(aspect: Double?) {
        guard calibration == nil else { return }
        locationRequest = nil
        toggle.title = monitoring ? "暂停预测" : "开始预测"
        guard let ppt = NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.Powerpoint").first else {
            message("请先打开 PowerPoint 和要编辑的幻灯片")
            return
        }
        setup.orderOut(nil)
        ppt.activate(options: [])
        guard let window = PowerPointWindow.front(of: ppt) else {
            openSetup()
            message("请先显示 PowerPoint 的编辑窗口")
            return
        }
        invalidate()
        let panel = CalibrationPanel(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        let view = CalibrationView(frame: NSRect(origin: .zero, size: window.frame.size), aspect: aspect) { [weak self] rect in
            guard let self else { return }
            self.calibration?.orderOut(nil)
            self.calibration = nil
            guard let rect else {
                if self.monitoring, self.frame != nil {
                    self.message("已取消重新定位，继续使用原画布")
                    ppt.activate(options: [])
                } else {
                    self.message("已取消定位，可重新点击「定位画布并开始」。")
                    self.openSetup()
                }
                return
            }
            self.frame = rect
            self.calibratedWindow = window
            self.monitoring = true
            self.history.reset()
            self.toggle.title = "暂停预测"
            self.message("等待 PowerPoint 编辑")
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.Powerpoint").first?.activate(options: [])
        }
        panel.contentView = view
        calibration = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
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

    private func poll() {
        guard monitoring, frontmost, calibration == nil, !reading, !applying else { return }
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
                        self.message(context == nil ? "已读取幻灯片，等待编辑" : "正在判断下一步…")
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
                    guard !suggestion.edits.isEmpty || !suggestion.artwork.isEmpty else { self.message("等待更多编辑"); return }
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
        message(prediction.summary + (shortcutLabel.map { " · " + $0 + " 采纳" } ?? " · 点击采纳"))
    }

    @objc private func accept() {
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
        applying = true
        invalidate()
        let revision = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try PowerPointBridge.apply(proposal, to: state, images: references) }
            DispatchQueue.main.async {
                self.applying = false
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

let application = NSApplication.shared
let controller = Controller()
application.setActivationPolicy(.accessory)
application.delegate = controller
application.run()
