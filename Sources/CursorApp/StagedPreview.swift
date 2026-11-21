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
        let baseline = try JSONDecoder().decode(SlideSnapshot.self, from: Data(contentsOf: directory.appendingPathComponent("baseline.json")))
        guard let image = NSImage(contentsOf: directory.appendingPathComponent("overlay.png")),
              let powerpoint = NSWorkspace.shared.frontmostApplication,
              powerpoint.bundleIdentifier?.lowercased() == "com.microsoft.powerpoint",
              let window = PowerPointWindow.front(of: powerpoint),
              let frame = PageLocator.locate(in: window, aspect: baseline.width / baseline.height),
              try PowerPointBridge.capture() == baseline else {
            throw CocoaError(.userCancelled)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
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
        var submitted = false
        weak var feedbackPanel: SuggestionPanel?
        weak var activeShortcut: AcceptShortcut?
        func matchesPage(_ current: PowerPointWindow) -> Bool {
            current.id == window.id && current.frame == window.frame &&
                PageLocator.locate(in: current, aspect: baseline.width / baseline.height) == frame
        }
        let actions = StagedActions {
            guard !submitted, powerpoint.isActive, NSEvent.pressedMouseButtons == 0 else { return }
            guard let current = PowerPointWindow.front(of: powerpoint), matchesPage(current) else {
                app.terminate(nil)
                return
            }
            guard let proposal else {
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
                        try FileManager.default.copyItem(at: directory.appendingPathComponent("after.pptx"), to: destination)
                        powerpoint.activate(options: [])
                        app.terminate(nil)
                        return
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
                let result = Result { try PowerPointBridge.apply(proposal, to: baseline) }
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
        let shortcut = AcceptShortcut { actions.accept() }
        activeShortcut = shortcut
        var shortcutLabel: String?
        if let proposal {
            try proposal.validate(for: baseline)
            shortcutLabel = shortcut.registerPreferred(useTab: AcceptShortcut.allowsTab(editingText: baseline.editingText))
        }
        let summary = proposal?.summary ?? (try? String(contentsOf: directory.appendingPathComponent("summary.txt"), encoding: .utf8)) ?? ""
        let controls = SuggestionPanel(summary: proposal == nil ? "可保存为副本 · " + summary : summary,
                                       shortcutLabel: shortcutLabel, owner: actions,
                                       accept: #selector(StagedActions.accept), dismiss: #selector(StagedActions.dismiss),
                                       page: frame, actionTitle: proposal == nil ? "另存建议副本…" : nil)
        feedbackPanel = controls
        controls.orderFrontRegardless()
        var reading = false
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            guard !submitted else { return }
            guard powerpoint.isActive, (NSEvent.pressedMouseButtons == 0 || controls.frame.contains(NSEvent.mouseLocation)),
                  let current = PowerPointWindow.front(of: powerpoint),
                  current.id == window.id, current.frame == window.frame else {
                app.terminate(nil)
                return
            }
            guard !reading else { return }
            reading = true
            DispatchQueue.global(qos: .userInitiated).async {
                let valid = matchesPage(current) && (try? PowerPointBridge.capture()) == baseline
                DispatchQueue.main.async {
                    reading = false
                    if !submitted && !valid { app.terminate(nil) }
                }
            }
        }
        defer { shortcut.disable(); timer.invalidate(); controls.orderOut(nil); panel.orderOut(nil) }
        app.run()
    }
}
