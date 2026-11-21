import AppKit
import CursorCore
import MacIntegration

final class Controller: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let status = NSMenuItem(title: "先打开 PowerPoint，定位幻灯片画布", action: nil, keyEquivalent: "")
    private let toggle = NSMenuItem(title: "开始预测", action: #selector(toggleMonitoring), keyEquivalent: "")
    private var frame: NSRect?
    private var calibration: NSPanel?
    private var overlay: NSPanel?
    private var history = EditHistory()
    private var monitoring = false
    private var reading = false
    private var inference: PredictionRun?
    private var applying = false
    private var waiting: EditContext?
    private var pending: (SlideSnapshot, Prediction)?
    private var generation = 0
    private lazy var shortcut = AcceptShortcut { [weak self] in self?.accept() }
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle.angled", accessibilityDescription: "PPT Cursor")
        item.button?.toolTip = "PPT Cursor"
        let menu = NSMenu()
        menu.addItem(status)
        menu.addItem(.separator())
        for (title, action) in [("定位幻灯片画布…", #selector(calibrate)), ("采纳当前建议", #selector(accept)),
                                ("忽略当前建议", #selector(dismiss)), ("退出 PPT Cursor", #selector(quit))] {
            let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            entry.target = self
        }
        toggle.target = self
        menu.insertItem(toggle, at: 3)
        item.menu = menu
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in self?.poll() }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                     object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.frontmost else { return }
            self.invalidate()
            self.history.reset()
        }
    }

    func applicationWillTerminate(_ notification: Notification) { inference?.cancel() }

    private var frontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() == "com.microsoft.powerpoint"
    }
    private func message(_ value: String) { status.title = value; item.button?.toolTip = value }
    private func invalidate() {
        generation += 1
        inference?.cancel()
        pending = nil
        waiting = nil
        shortcut.disable()
        overlay?.orderOut(nil)
        overlay = nil
    }
    @objc private func dismiss() { invalidate(); message("已忽略，继续编辑即可") }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggleMonitoring() {
        if !monitoring && frame == nil { calibrate(); return }
        monitoring.toggle()
        invalidate()
        history.reset()
        toggle.title = monitoring ? "暂停预测" : "开始预测"
        message(monitoring ? "等待 PowerPoint 编辑" : "已暂停")
    }

    @objc private func calibrate() {
        guard calibration == nil else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) else { return }
        invalidate()
        let panel = CalibrationPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        let view = CalibrationView(frame: NSRect(origin: .zero, size: screen.frame.size)) { [weak self] rect in
            guard let self else { return }
            self.calibration?.orderOut(nil)
            self.calibration = nil
            guard let rect else { return }
            self.frame = rect
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

    private func poll() {
        guard monitoring, frontmost, calibration == nil, !reading, !applying else { return }
        reading = true
        let revision = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try PowerPointBridge.capture() }
            DispatchQueue.main.async {
                self.reading = false
                guard self.monitoring, self.frontmost, revision == self.generation else { return }
                switch result {
                case .success(let value):
                    guard let state = value else { self.invalidate(); self.history.reset(); return }
                    let previous = self.history.current
                    let context = self.history.observe(state)
                    if previous != state {
                        self.invalidate()
                        self.waiting = context
                        self.message(context == nil ? "已读取幻灯片，等待编辑" : "正在判断下一步…")
                        return
                    }
                    self.startPrediction()
                case .failure(let error):
                    self.invalidate()
                    self.message(error.localizedDescription)
                }
            }
        }
    }

    private func startPrediction() {
        guard inference == nil, let context = waiting else { return }
        waiting = nil
        let run = PredictionRun()
        inference = run
        let revision = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () throws -> Prediction in
                let paths = ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                             "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
                guard let path = paths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
                    throw NSError(domain: "PPTCursor", code: 1, userInfo: [NSLocalizedDescriptionKey: "请安装并登录 Codex CLI"])
                }
                return try Predictor(executable: URL(fileURLWithPath: path)).predict(context, run: run)
            }
            DispatchQueue.main.async {
                self.inference = nil
                guard self.generation == revision, self.frontmost else { return }
                switch result {
                case .success(let suggestion):
                    guard !suggestion.edits.isEmpty || !suggestion.artwork.isEmpty else { self.message("等待更多编辑"); return }
                    self.show(context.current, suggestion)
                case .failure(let error): self.message(error.localizedDescription)
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
        panel.contentView = PreviewCanvas(slide: state, suggestion: prediction, frame: NSRect(origin: .zero, size: frame.size), diagnosticBackground: false)
        panel.orderFrontRegardless()
        overlay = panel
        pending = (state, prediction)
        message(prediction.summary + (shortcut.enable() ? " · ⌥⌘↩ 采纳" : " · 从菜单采纳"))
    }

    @objc private func accept() {
        guard frontmost, !applying, let (state, proposal) = pending else { return }
        applying = true
        invalidate()
        let revision = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try PowerPointBridge.apply(proposal, to: state) }
            DispatchQueue.main.async {
                self.applying = false
                guard revision == self.generation else { return }
                switch result {
                case .success(let state): _ = self.history.observe(state); self.message("已采纳")
                case .failure(let error): self.message(error.localizedDescription)
                }
            }
        }
    }
}

// Runs through the packaged resource path and native automation bridge without logging slide content.
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
