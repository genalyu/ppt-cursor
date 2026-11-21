import AppKit

final class CalibrationView: NSView {
    let finish: (NSRect?) -> Void
    private let aspect: Double?
    private var start: NSPoint?
    private var end: NSPoint?

    init(frame: NSRect, aspect: Double?, finish: @escaping (NSRect?) -> Void) {
        self.aspect = aspect
        self.finish = finish
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finish(nil) }
    }
    private var selection: NSRect? {
        guard let start, let end else { return nil }
        let box = NSRect(x: min(start.x,end.x), y: min(start.y,end.y),
                      width: abs(end.x-start.x), height: abs(end.y-start.y)).intersection(bounds)
        guard !box.isNull else { return nil }
        guard let aspect, aspect.isFinite, aspect > 0 else { return box }
        let width = min(box.width, box.height * aspect)
        let height = width / aspect
        return NSRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
    }
    override func mouseDown(with event: NSEvent) { start = event.locationInWindow; end = start; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) { end = event.locationInWindow; needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        end = event.locationInWindow
        guard let rect = selection, rect.width > 100, rect.height > 75 else { return }
        finish(window?.convertToScreen(rect))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()
        if let rect = selection {
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            NSColor.systemTeal.setStroke()
            NSBezierPath(rect: rect).stroke()
        }
        let label = "沿幻灯片页面边缘拖出矩形 · Esc 取消" as NSString
        label.draw(at: NSPoint(x: 32, y: bounds.maxY-80),
                   withAttributes: [.foregroundColor: NSColor.white, .backgroundColor: NSColor.black,
                                    .font: NSFont.systemFont(ofSize: 18, weight: .medium)])
    }
}
final class CalibrationPanel: NSPanel { override var canBecomeKey: Bool { true } }
