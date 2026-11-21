import AppKit
import UniformTypeIdentifiers
import CursorCore
import MacIntegration

private final class StagedActions: NSObject {
    let apply: () -> Void
    init(apply: @escaping () -> Void) { self.apply = apply }
    @objc func accept() { apply() }
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
        guard let image = NSImage(contentsOf: directory.appendingPathComponent("overlay.png")),
              let powerpoint = NSWorkspace.shared.frontmostApplication,
              powerpoint.bundleIdentifier?.lowercased() == "com.microsoft.powerpoint",
              let window = PowerPointWindow.front(of: powerpoint),
              try PowerPointBridge.capture() == baseline else {
            throw CocoaError(.userCancelled)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let aspect = baseline.width / baseline.height
        let detected = CGPreflightScreenCaptureAccess() ? PageLocator.locate(in: window, aspect: aspect) : nil
        let frame: NSRect
        if let detected {
            frame = detected
        } else {
            let picker = CalibrationPanel(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            picker.isOpaque = false
            picker.backgroundColor = .clear
            picker.level = .screenSaver
            var selection: NSRect?
            let view = CalibrationView(frame: NSRect(origin: .zero, size: window.frame.size), aspect: aspect) { rect in
                selection = rect
                app.stopModal()
            }
            picker.contentView = view
            app.activate(ignoringOtherApps: true)
            picker.makeKeyAndOrderFront(nil)
            picker.makeFirstResponder(view)
            app.runModal(for: picker)
            picker.orderOut(nil)
            powerpoint.activate(options: [])
            guard let selection, let current = PowerPointWindow.front(of: powerpoint),
                  current.id == window.id, current.frame == window.frame,
                  try PowerPointBridge.capture() == baseline else { throw CocoaError(.userCancelled) }
            frame = selection
        }
        func locate(_ current: PowerPointWindow) -> NSRect? {
            if detected == nil { return current.id == window.id && current.frame == window.frame ? frame : nil }
            return PageLocator.locate(in: current, aspect: aspect)
        }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        let view = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        view.image = image
        view.imageScaling = .scaleAxesIndependently
        panel.contentView = view
        panel.orderFrontRegardless()
        let proposal = try? JSONDecoder().decode(Prediction.self, from: Data(contentsOf: directory.appendingPathComponent("accept.json")))
        struct Target: Decodable { let operation: String; let presetTarget: String? }
        let target = try? JSONDecoder().decode(Target.self, from: Data(contentsOf: directory.appendingPathComponent("target.json")))
        let direct = proposal != nil || target?.operation == "insert" || baseline.objects.contains { $0.id == target?.presetTarget && $0.autoShapeType != nil }
        var displayedWindow = window
        var displayedPage = frame
        var submitted = false
        weak var feedbackPanel: SuggestionPanel?
        weak var activeShortcut: AcceptShortcut?
        func matchesPage(_ current: PowerPointWindow) -> Bool {
            current.id == window.id && current.frame == displayedWindow.frame &&
                locate(current) == displayedPage
        }
        let actions = StagedActions {
            guard !submitted, powerpoint.isActive, NSEvent.pressedMouseButtons == 0 else { return }
            guard let current = PowerPointWindow.front(of: powerpoint), matchesPage(current) else {
                app.terminate(nil)
                return
            }
            guard direct else {
                submitted = true
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
                        submitted = false
                        panel.orderFrontRegardless()
                        feedbackPanel?.orderFrontRegardless()
                    }
                }
                return
            }
            submitted = true
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
                        } catch {
                            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                        }
                        app.terminate(nil)
                    case .failure(let error):
                        feedbackPanel?.showStatus(error.localizedDescription, finished: true)
                        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                    }
                }
            }
        }
        actions.onDismiss = {
            guard !submitted else { return }
            do { try Data().write(to: directory.appendingPathComponent("dismissed"), options: .atomic) }
            catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)) }
        }
        let shortcut = AcceptShortcut {
            trace("shortcut received")
            actions.accept()
        }
        activeShortcut = shortcut
        var shortcutLabel: String?
        if direct {
            try proposal?.validate(for: baseline)
            shortcutLabel = shortcut.registerPreferred(useTab: AcceptShortcut.allowsTab(editingText: baseline.editingText))
        }
        let summary = proposal?.summary ?? (try? String(contentsOf: directory.appendingPathComponent("summary.txt"), encoding: .utf8)) ?? ""
        let controls = SuggestionPanel(summary: !direct ? "可保存为副本 · " + summary : summary,
                                       shortcutLabel: shortcutLabel, owner: actions,
                                       accept: #selector(StagedActions.accept), dismiss: #selector(StagedActions.dismiss),
                                       page: frame, actionTitle: !direct ? "另存建议副本…" : nil)
        feedbackPanel = controls
        controls.orderFrontRegardless()
        trace("panel shown; shortcut " + (shortcutLabel ?? "none"))
        // A manually selected page cannot be remeasured after a scroll, zoom or canvas click.
        let manualMonitor = detected == nil ? NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel, .magnify, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
            if !submitted { app.terminate(nil) }
        } : nil
        defer { if let manualMonitor { NSEvent.removeMonitor(manualMonitor) } }
        let workspaceEvents = NSWorkspace.shared.notificationCenter
        var hidden = false
        var focusGeneration = 0
        func suspendPreview(_ reason: String) {
            guard !submitted, !hidden else { return }
            hidden = true
            focusGeneration += 1
            shortcut.disable()
            panel.orderOut(nil)
            controls.orderOut(nil)
            trace("suspended: " + reason)
        }
        let focusObserver = workspaceEvents.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                       object: nil, queue: .main) { _ in
            guard !submitted, !powerpoint.isActive else { return }
            suspendPreview("application switch")
        }
        defer { workspaceEvents.removeObserver(focusObserver) }
        var reading = false
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            guard !submitted else { return }
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
            guard !reading else { return }
            let generation = focusGeneration
            reading = true
            DispatchQueue.global(qos: .userInitiated).async {
                let page = locate(current)
                let valid = (try? PowerPointBridge.capture()) == baseline
                DispatchQueue.main.async {
                    reading = false
                    guard !submitted, powerpoint.isActive, generation == focusGeneration,
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
                    }
                    if hidden {
                        guard NSEvent.pressedMouseButtons == 0 else { return }
                        hidden = false
                        if direct {
                            let label = shortcut.registerPreferred(useTab: AcceptShortcut.allowsTab(editingText: baseline.editingText))
                            controls.updateShortcut(label)
                        }
                        panel.orderFrontRegardless()
                        controls.orderFrontRegardless()
                        trace("resumed after baseline verification")
                    }
                }
            }
        }
        defer { shortcut.disable(); timer.invalidate(); controls.orderOut(nil); panel.orderOut(nil) }
        app.run()
    }
}
