import AppKit
import UniformTypeIdentifiers
import CursorCore
import MacIntegration

private final class StagedActions: NSObject {
    let apply: (String) -> Void
    init(apply: @escaping (String) -> Void) { self.apply = apply }
    @objc func accept() { apply("采纳按钮") }
    var onDismiss: (() -> Void)?
    @objc func dismiss() { onDismiss?(); NSApp.terminate(nil) }
}

enum StagedPreview {
    static func display(directory: URL) throws {
        let diagnostics = ProcessInfo.processInfo.environment["PPT_CURSOR_TRACE_PREVIEW"] == "1"
        func trace(_ event: String) {
            if diagnostics { FileHandle.standardError.write(Data(("preview: " + event + "\n").utf8)) }
        }
        let baseline = try JSONDecoder().decode(SlideSnapshot.self, from: Data(contentsOf: directory.appendingPathComponent("baseline.json")))
        guard let artwork = NSImage(contentsOf: directory.appendingPathComponent("after.png")),
              let powerpoint = NSWorkspace.shared.frontmostApplication,
              powerpoint.bundleIdentifier?.lowercased() == "com.microsoft.powerpoint",
              let window = PowerPointWindow.front(of: powerpoint),
              try PowerPointBridge.capture() == baseline else {
            throw CocoaError(.userCancelled)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let aspect = baseline.width / baseline.height
        let geometryPreview = FileManager.default.fileExists(atPath: directory.appendingPathComponent("geometry-preview").path)
        let controlDirectory = ProcessInfo.processInfo.environment["PPT_CURSOR_CONTROL_DIRECTORY"].map { URL(fileURLWithPath: $0) }
        func consume(_ name: String) -> Bool {
            guard let file = controlDirectory?.appendingPathComponent(name),
                  FileManager.default.fileExists(atPath: file.path) else { return false }
            try? FileManager.default.removeItem(at: file)
            return true
        }
        func stopRequested() -> Bool {
            controlDirectory.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("stop").path) } ?? false
        }
        // Do not carry a menu click from a previous prediction into a new proposal.
        _ = consume("accept-preview")
        _ = consume("dismiss-preview")
        func locate(_ current: PowerPointWindow) -> NSRect? {
            let display = NSScreen.screens.map(\.visibleFrame).max {
                func area(_ screen: NSRect) -> CGFloat {
                    let overlap = screen.intersection(current.frame)
                    return overlap.isNull ? 0 : overlap.width * overlap.height
                }
                return area($0) < area($1)
            }
            return PreviewPlacement.lowerLeft(window: current.frame, aspect: aspect, display: display)
        }
        guard let frame = locate(window) else { throw CocoaError(.userCancelled) }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.title = "PPT Cursor 左下角预览"
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        let view = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        view.image = artwork
        view.imageScaling = .scaleAxesIndependently
        panel.contentView = view
        panel.orderFrontRegardless()
        let proposal = try? JSONDecoder().decode(Prediction.self, from: Data(contentsOf: directory.appendingPathComponent("accept.json")))
        struct Target: Decodable { let operation: String; let presetTarget: String? }
        let target = try? JSONDecoder().decode(Target.self, from: Data(contentsOf: directory.appendingPathComponent("target.json")))
        let direct = proposal != nil || target?.operation == "insert" || baseline.objects.contains { $0.id == target?.presetTarget && $0.autoShapeType != nil }
        var displayedWindow = window
        var displayedPage = frame
        var submission = StagedSubmission.ready
        weak var feedbackPanel: SuggestionPanel?
        weak var activeShortcut: AcceptShortcut?
        func matchesPage(_ current: PowerPointWindow) -> Bool {
            current.id == window.id && current.frame == displayedWindow.frame &&
                locate(current) == displayedPage
        }
        let actions = StagedActions { input in
            guard submission.canAccept, powerpoint.isActive, NSEvent.pressedMouseButtons == 0 else { return }
            if stopRequested() { app.terminate(nil); return }
            guard let current = PowerPointWindow.front(of: powerpoint), matchesPage(current) else {
                app.terminate(nil)
                return
            }
            print("PPT_CURSOR_PHASE=写入")
            fflush(stdout)
            guard direct else {
                submission = .exporting
                panel.orderOut(nil)
                feedbackPanel?.orderOut(nil)
                let save = NSSavePanel()
                save.allowedContentTypes = [UTType(filenameExtension: "pptx")!]
                save.nameFieldStringValue = "PowerPoint 建议副本.pptx"
                save.message = "将预览时的文稿另存为可编辑副本。请选择新文件名。"
                app.activate(ignoringOtherApps: true)
                while save.runModal() == .OK, let destination = save.url {
                    do {
                        let candidate = directory.appendingPathComponent("after.pptx")
                        try FileManager.default.copyItem(at: candidate, to: destination)
                        powerpoint.activate(options: [])
                        app.terminate(nil)
                        return
                    } catch let error as CocoaError where error.code == .fileWriteFileExists {
                        save.message = "这个文件名已在使用。请为建议副本选择另一个名称。"
                        let stem = destination.deletingPathExtension().lastPathComponent
                        save.nameFieldStringValue = stem + " 副本.pptx"
                    } catch {
                        NSAlert(error: error).runModal()
                    }
                }
                powerpoint.activate(options: [])
                DispatchQueue.global(qos: .userInitiated).async {
                    let valid = (try? PowerPointBridge.capture()) == baseline
                    DispatchQueue.main.async {
                        guard valid, powerpoint.isActive,
                              let current = PowerPointWindow.front(of: powerpoint),
                              matchesPage(current) else {
                            app.terminate(nil)
                            return
                        }
                        print("PPT_CURSOR_PHASE=待采纳")
                        fflush(stdout)
                        submission = .ready
                        panel.orderFrontRegardless()
                        feedbackPanel?.orderFrontRegardless()
                    }
                }
                return
            }
            submission = .writing
            activeShortcut?.disable()
            panel.orderOut(nil)
            feedbackPanel?.showStatus("正在写入 PowerPoint…", finished: false)
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result {
                    if let proposal { return try PowerPointBridge.apply(proposal, to: baseline) }
                    return try PowerPointBridge.applyStagedShape(from: directory, into: baseline)
                }
                DispatchQueue.main.async {
                    switch result {
                    case .success(let state):
                        do {
                            try JSONEncoder().encode(state).write(to: directory.appendingPathComponent("accepted.json"), options: .atomic)
                            print("已通过\(input)将建议写入 PowerPoint。")
                        } catch {
                            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                        }
                        app.terminate(nil)
                    case .failure(let error):
                        submission = .failed
                        print("PPT_CURSOR_PHASE=操作失败")
                        fflush(stdout)
                        feedbackPanel?.showStatus(error.localizedDescription, finished: true)
                        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                    }
                }
            }
        }
        actions.onDismiss = {
            guard submission.canAccept else { return }
            do { try Data().write(to: directory.appendingPathComponent("dismissed"), options: .atomic) }
            catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)) }
        }
        var shortcutLabel: String?
        let shortcut = AcceptShortcut {
            trace("shortcut received")
            guard let shortcutLabel else { return }
            actions.apply("快捷键 " + shortcutLabel)
        }
        activeShortcut = shortcut
        if direct {
            try proposal?.validate(for: baseline)
            shortcutLabel = shortcut.registerPreferred(useTab: AcceptShortcut.allowsTab(editingText: baseline.editingText))
        }
        let summary = proposal?.summary ?? (try? String(contentsOf: directory.appendingPathComponent("summary.txt"), encoding: .utf8)) ?? ""
        struct AssetSource: Decodable { let sourceURL: URL }
        let source = try? JSONDecoder().decode(AssetSource.self, from: Data(contentsOf: directory.appendingPathComponent("asset-source.json")))
        let controls = SuggestionPanel(summary: (geometryPreview ? "位置/尺寸示意 · " : "修改后预览 · ") + (!direct ? "可保存为副本 · " : "") + summary,
                                       shortcutLabel: shortcutLabel, owner: actions,
                                       accept: #selector(StagedActions.accept), dismiss: #selector(StagedActions.dismiss),
                                       page: frame, actionTitle: !direct ? "另存建议副本…" : nil, sourceURL: source?.sourceURL, alignLeft: true)
        feedbackPanel = controls
        controls.orderFrontRegardless()
        func recordLayout(window: NSRect) {
            func rect(_ frame: NSRect) -> [String: CGFloat] {
                ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
            }
            let layout: [String: Any] = ["placement": "lower-left", "window": rect(window),
                                         "preview": rect(panel.frame), "controls": rect(controls.frame)]
            if let data = try? JSONSerialization.data(withJSONObject: layout) {
                try? data.write(to: directory.appendingPathComponent("preview-layout.json"), options: .atomic)
            }
        }
        recordLayout(window: window.frame)
        let previewInfo = ["direct": direct]
        if let data = try? JSONSerialization.data(withJSONObject: previewInfo) {
            try? data.write(to: directory.appendingPathComponent("preview-info.json"), options: .atomic)
        }
        print("PPT_CURSOR_PREVIEW=" + directory.path)
        print("PPT_CURSOR_PHASE=待采纳")
        print("已显示建议 · " + (shortcutLabel ?? "点击面板采纳"))
        fflush(stdout)
        trace("panel shown; shortcut " + (shortcutLabel ?? "none"))
        let workspaceEvents = NSWorkspace.shared.notificationCenter
        var hidden = false
        var focusGeneration = 0
        func suspendPreview(_ reason: String) {
            guard submission.canAccept, !hidden else { return }
            print("PPT_CURSOR_PHASE=待切回")
            fflush(stdout)
            hidden = true
            focusGeneration += 1
            shortcut.disable()
            panel.orderOut(nil)
            controls.orderOut(nil)
            trace("suspended: " + reason)
        }
        let focusObserver = workspaceEvents.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                       object: nil, queue: .main) { _ in
            guard submission.canAccept, !powerpoint.isActive else { return }
            suspendPreview("application switch")
        }
        defer { workspaceEvents.removeObserver(focusObserver) }
        var reading = false
        var nextVerification = Date.distantPast
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            // A failed proposal cannot be applied twice, but retry/dismiss must still
            // release this child so the worker can continue. Never interrupt a write.
            guard submission.canHandleCommands else { return }
            if stopRequested() { app.terminate(nil); return }
            if let retry = controlDirectory?.appendingPathComponent("retry"),
               FileManager.default.fileExists(atPath: retry.path) { app.terminate(nil); return }
            if consume("dismiss-preview") { actions.dismiss(); return }
            guard submission.canAccept else { return }
            if consume("refresh-shortcut") {
                shortcut.disable()
                if direct && !hidden && powerpoint.isActive {
                    shortcutLabel = shortcut.registerPreferred(useTab: AcceptShortcut.allowsTab(editingText: baseline.editingText))
                    controls.updateShortcut(shortcutLabel)
                }
            }
            if powerpoint.isActive && consume("accept-preview") { actions.apply("菜单"); return }
            guard powerpoint.isActive else { suspendPreview("application switch"); return }
            guard NSEvent.pressedMouseButtons == 0 || (!hidden && controls.frame.contains(NSEvent.mouseLocation)) else {
                suspendPreview("mouse down")
                return
            }
            guard let current = PowerPointWindow.front(of: powerpoint) else {
                suspendPreview("window unavailable")
                return
            }
            guard current.id == window.id else {
                trace("dismissed on window switch")
                app.terminate(nil)
                return
            }
            if current.frame != displayedWindow.frame { suspendPreview("window moved or resized") }
            // Window/focus/mouse checks remain immediate. Expensive screenshot and JXA
            // verification runs at most once a second; acceptance always checks again.
            guard !reading, Date() >= nextVerification else { return }
            nextVerification = Date().addingTimeInterval(1)
            let generation = focusGeneration
            reading = true
            let page = locate(current)
            DispatchQueue.global(qos: .userInitiated).async {
                let valid = (try? PowerPointBridge.capture()) == baseline
                DispatchQueue.main.async {
                    reading = false
                    guard submission.canAccept, powerpoint.isActive, generation == focusGeneration,
                          let latest = PowerPointWindow.front(of: powerpoint),
                          latest.id == current.id, latest.frame == current.frame else { return }
                    guard valid else {
                        trace("dismissed on slide or selection change")
                        app.terminate(nil)
                        return
                    }
                    guard let page else {
                        suspendPreview("page unavailable")
                        return
                    }
                    if page != displayedPage || current.frame != displayedWindow.frame {
                        panel.setFrame(page, display: true)
                        controls.position(at: page)
                        displayedPage = page
                        displayedWindow = current
                        recordLayout(window: current.frame)
                    }
                    if hidden {
                        guard NSEvent.pressedMouseButtons == 0 else { return }
                        hidden = false
                        if direct {
                            shortcutLabel = shortcut.registerPreferred(useTab: AcceptShortcut.allowsTab(editingText: baseline.editingText))
                            controls.updateShortcut(shortcutLabel)
                        }
                        panel.orderFrontRegardless()
                        controls.orderFrontRegardless()
                        print("PPT_CURSOR_PHASE=待采纳")
                        fflush(stdout)
                        trace("resumed after baseline verification")
                    }
                }
            }
        }
        defer { shortcut.disable(); timer.invalidate(); controls.orderOut(nil); panel.orderOut(nil) }
        app.run()
    }
}
