import Foundation

enum PreviewPlacement {
    /// A compact card at the PowerPoint window's lower-left, inside the visible display.
    static func lowerLeft(window: NSRect, aspect: CGFloat, display: NSRect?) -> NSRect? {
        guard aspect.isFinite, aspect > 0, window.width > 0, window.height > 0 else { return nil }
        let visible = display.map { window.intersection($0) } ?? window
        guard !visible.isNull, visible.width >= 272 else { return nil }
        // Reserve room above the card for the 84-point acceptance panel.
        let width = min(320, visible.width * 0.35, visible.width - 32, (visible.height - 146) * aspect)
        guard width >= 80 else { return nil }
        return NSRect(x: visible.minX + 16, y: visible.minY + 40, width: width, height: width / aspect)
    }
}
