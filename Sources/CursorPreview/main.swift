import AppKit
import CursorCore

/// The same view renders to the transparent panel and to a bitmap for regression inspection.
final class PreviewCanvas: NSView {
    let slide: SlideSnapshot
    let suggestion: Prediction
    let diagnosticBackground: Bool

    init(slide: SlideSnapshot, suggestion: Prediction, frame: NSRect, diagnosticBackground: Bool) {
        self.slide = slide
        self.suggestion = suggestion
        self.diagnosticBackground = diagnosticBackground
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let scale = min(bounds.width / slide.width, bounds.height / slide.height)
        let origin = NSPoint(x: (bounds.width - scale * slide.width) / 2,
                             y: (bounds.height - scale * slide.height) / 2)
        let transform = NSAffineTransform()
        transform.translateX(by: origin.x, yBy: origin.y)
        transform.scale(by: scale)
        transform.concat()
        if diagnosticBackground {
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: slide.width, height: slide.height).fill()
            for object in slide.objects {
                let rect = NSRect(x: object.x, y: object.y, width: object.width, height: object.height)
                NSColor(white: 0.94, alpha: 1).setFill()
                rect.fill()
                drawLabel(object.text ?? object.name, in: rect)
            }
        }
        for edit in suggestion.edits {
            let p = edit.placement
            let rect = NSRect(x: p.x, y: p.y, width: p.width, height: p.height)
            NSGraphicsContext.saveGraphicsState()
            let rotation = NSAffineTransform()
            rotation.translateX(by: rect.midX, yBy: rect.midY)
            rotation.rotate(byDegrees: edit.rotation)
            rotation.translateX(by: -rect.midX, yBy: -rect.midY)
            rotation.concat()
            NSColor.systemTeal.withAlphaComponent(0.19).setFill()
            rect.fill()
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 2 / scale
            outline.setLineDash([6 / scale, 4 / scale], count: 2, phase: 0)
            NSColor.systemTeal.setStroke()
            outline.stroke()
            let original = slide.objects.first { $0.id == edit.id }
            drawLabel(edit.text ?? original?.text ?? original?.name ?? "", in: rect)
            NSGraphicsContext.restoreGraphicsState()
        }
        for asset in suggestion.artwork {
            let p = asset.placement
            NSImage(data: Data(asset.svg.utf8))?.draw(in: NSRect(x: p.x, y: p.y, width: p.width, height: p.height),
                                                      from: .zero, operation: .sourceOver, fraction: 0.85,
                                                      respectFlipped: true, hints: nil)
        }
    }

    private func drawLabel(_ text: String, in rect: NSRect) {
        let font = NSFont.systemFont(ofSize: min(18, max(8, rect.height * 0.3)), weight: .medium)
        (text as NSString).draw(in: rect.insetBy(dx: 6, dy: 4), withAttributes: [.font: font, .foregroundColor: NSColor.black])
    }
}

enum PreviewError: Error { case usage, invalidSlide, renderingFailed }
do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 3 else { throw PreviewError.usage }
    let decoder = JSONDecoder()
    let slide = try decoder.decode(SlideSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: args[0])))
    let suggestion = try decoder.decode(Prediction.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
    try suggestion.validate(for: slide)
    guard slide.width > 0, slide.height > 0, slide.width <= 4096, slide.height <= 4096 else { throw PreviewError.invalidSlide }
    let frame = NSRect(x: 0, y: 0, width: slide.width, height: slide.height)
    let canvas = PreviewCanvas(slide: slide, suggestion: suggestion, frame: frame, diagnosticBackground: true)
    guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: frame) else { throw PreviewError.renderingFailed }
    canvas.cacheDisplay(in: frame, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw PreviewError.renderingFailed }
    try png.write(to: URL(fileURLWithPath: args[2]), options: .atomic)
} catch {
    FileHandle.standardError.write(Data("Usage: ppt-preview slide.json suggestion.json preview.png\nError: \(error)\n".utf8))
    exit(1)
}
