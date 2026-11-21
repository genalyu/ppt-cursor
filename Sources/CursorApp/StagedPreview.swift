import AppKit
import CursorCore
import MacIntegration

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
        let shortcut = AcceptShortcut {
            guard powerpoint.isActive, NSEvent.pressedMouseButtons == 0,
                  let proposal else { return }
            panel.orderOut(nil)
            do { _ = try PowerPointBridge.apply(proposal, to: baseline) }
            catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)) }
            app.terminate(nil)
        }
        if let proposal {
            try proposal.validate(for: baseline)
            if let key = shortcut.registerPreferred(useTab: baseline.editingText == false) {
                print(proposal.summary + " · " + key + " 采纳")
            }
        }
        var reading = false
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            guard powerpoint.isActive, NSEvent.pressedMouseButtons == 0,
                  let current = PowerPointWindow.front(of: powerpoint),
                  current.id == window.id, current.frame == window.frame else {
                app.terminate(nil)
                return
            }
            guard !reading else { return }
            reading = true
            DispatchQueue.global(qos: .userInitiated).async {
                let valid = (try? PowerPointBridge.capture()) == baseline
                DispatchQueue.main.async {
                    reading = false
                    if !valid { app.terminate(nil) }
                }
            }
        }
        defer { shortcut.disable(); timer.invalidate(); panel.orderOut(nil) }
        app.run()
    }
}
