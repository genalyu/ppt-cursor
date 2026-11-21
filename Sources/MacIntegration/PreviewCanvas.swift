import AppKit
import CursorCore

/// The same view renders to the transparent panel and to a bitmap for regression inspection.
public final class PreviewCanvas: NSView {
    let images: [ReferenceImage]
    private let picturePreviews: [String: NSImage]
    let slide: SlideSnapshot
    let suggestion: Prediction
    let diagnosticBackground: Bool

    public init(slide: SlideSnapshot, suggestion: Prediction, frame: NSRect, diagnosticBackground: Bool, images: [ReferenceImage] = [], pageImage: CGImage? = nil) {
        self.picturePreviews = Self.extractPictures(slide: slide, suggestion: suggestion, from: pageImage)
        self.images = images
        self.slide = slide
        self.suggestion = suggestion
        self.diagnosticBackground = diagnosticBackground
        super.init(frame: frame)
    }
    private static func extractPictures(slide: SlideSnapshot, suggestion: Prediction, from page: CGImage?) -> [String: NSImage] {
        guard let page, slide.width > 0, slide.height > 0 else { return [:] }
        let sx = CGFloat(page.width) / slide.width, sy = CGFloat(page.height) / slide.height
        let bounds = CGRect(x: 0, y: 0, width: slide.width, height: slide.height)
        let targets = Set(suggestion.edits.filter { $0.text == nil }.map(\.id))
        var result: [String: NSImage] = [:]
        for (index, object) in slide.objects.enumerated() where targets.contains(object.id) {
            guard object.kind == "shape type picture", object.rotation == 0 else { continue }
            let rect = CGRect(x: object.x, y: object.y, width: object.width, height: object.height)
            guard bounds.contains(rect), rect.width > 0, rect.height > 0 else { continue }
            let covered = slide.objects.dropFirst(index + 1).contains { other in
                let angle = other.rotation * .pi / 180
                let w = abs(cos(angle)) * other.width + abs(sin(angle)) * other.height
                let h = abs(sin(angle)) * other.width + abs(cos(angle)) * other.height
                return rect.intersects(CGRect(x: other.x + (other.width - w) / 2,
                                              y: other.y + (other.height - h) / 2, width: w, height: h))
            }
            guard !covered else { continue }
            let pixels = CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy)
            if let crop = page.cropping(to: pixels) {
                result[object.id] = NSImage(cgImage: crop, size: rect.size)
            }
        }
        return result
    }

    required public init?(coder: NSCoder) { nil }
    public override var isFlipped: Bool { true }

    public override func draw(_ dirtyRect: NSRect) {
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
                drawLabel(object.text ?? object.name, in: rect, fontSize: object.fontSize)
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
            if let picture = picturePreviews[edit.id] {
                picture.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.7, respectFlipped: true, hints: nil)
            } else {
                NSColor.systemTeal.withAlphaComponent(0.19).setFill()
                rect.fill()
                let original = slide.objects.first { $0.id == edit.id }
                drawLabel(edit.text ?? original?.text ?? original?.name ?? "", in: rect, fontSize: original?.fontSize)
            }
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 2 / scale
            outline.setLineDash([6 / scale, 4 / scale], count: 2, phase: 0)
            NSColor.systemTeal.setStroke()
            outline.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        for asset in suggestion.artwork {
            let p = asset.placement
            let bytes = asset.referenceID.flatMap { id in images.first { $0.id == id }?.png } ?? Data(asset.svg.utf8)
            NSImage(data: bytes)?.draw(in: NSRect(x: p.x, y: p.y, width: p.width, height: p.height),
                                                      from: .zero, operation: .sourceOver, fraction: 0.85,
                                                      respectFlipped: true, hints: nil)
        }
    }

    private func drawLabel(_ text: String, in rect: NSRect, fontSize: Double?) {
        let content = rect.insetBy(dx: 6, dy: 4)
        guard content.width > 0, content.height > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: content).addClip()
        let font = NSFont.systemFont(ofSize: fontSize ?? min(18, max(8, rect.height * 0.3)), weight: .medium)
        (text as NSString).draw(in: content, withAttributes: [.font: font, .foregroundColor: NSColor.black])
    }
}

