import AppKit
import CursorCore

/// The same view renders to the transparent panel and to a bitmap for regression inspection.
public final class PreviewCanvas: NSView {
    private let artworkImages: [NSImage?]
    public var canPreviewAllArtwork: Bool { artworkImages.allSatisfy { $0 != nil } }
    private let picturePreviews: [String: NSImage]
    let slide: SlideSnapshot
    let suggestion: Prediction
    let diagnosticBackground: Bool

    public init(slide: SlideSnapshot, suggestion: Prediction, frame: NSRect, diagnosticBackground: Bool, images: [ReferenceImage] = [], pageImage: CGImage? = nil) {
        self.picturePreviews = Self.extractPictures(slide: slide, suggestion: suggestion, from: pageImage)
        self.artworkImages = suggestion.artwork.map { asset in
            let bytes: Data
            if let id = asset.referenceID {
                guard let reference = images.first(where: { $0.id == id }) else { return nil }
                bytes = reference.png
            } else {
                bytes = Data(asset.svg.utf8)
            }
            guard let image = NSImage(data: bytes), image.isValid,
                  image.size.width > 0, image.size.height > 0 else { return nil }
            return image
        }
        self.slide = slide
        self.suggestion = suggestion
        self.diagnosticBackground = diagnosticBackground
        super.init(frame: frame)
    }
    public static func supportsAppearancePreview(_ object: SlideObject) -> Bool {
        object.rotation == 0 && (object.kind == "shape type picture" || object.kind == "shape type group")
    }

    private static func extractPictures(slide: SlideSnapshot, suggestion: Prediction, from page: CGImage?) -> [String: NSImage] {
        guard let page, slide.width > 0, slide.height > 0 else { return [:] }
        let sx = CGFloat(page.width) / slide.width, sy = CGFloat(page.height) / slide.height
        let bounds = CGRect(x: 0, y: 0, width: slide.width, height: slide.height)
        let targets = Set(suggestion.edits.filter { $0.text == nil }.map(\.id))
        var result: [String: NSImage] = [:]
        for (index, object) in slide.objects.enumerated() where targets.contains(object.id) {
            guard supportsAppearancePreview(object) else { continue }
            let rect = CGRect(x: object.x, y: object.y, width: object.width, height: object.height)
            guard bounds.contains(rect), rect.width > 0, rect.height > 0 else { continue }
            // Groups can have transparent gaps. An intersecting shape behind the group
            // would otherwise appear to move with it in the cropped preview.
            let neighbors = slide.objects.enumerated().filter { offset, _ in
                object.kind == "shape type group" ? offset != index : offset > index
            }
            let covered = neighbors.contains { _, other in
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
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        transform.concat()
        let pageBounds = NSRect(x: 0, y: 0, width: slide.width, height: slide.height)
        NSBezierPath(rect: pageBounds).addClip()
        if diagnosticBackground {
            NSColor.white.setFill()
            pageBounds.fill()
            for object in slide.objects {
                let rect = NSRect(x: object.x, y: object.y, width: object.width, height: object.height)
                NSColor(white: 0.94, alpha: 1).setFill()
                rect.fill()
                drawLabel(object.text ?? object.name, in: rect, fontSize: object.fontSize)
            }
        }
        // Existing shapes retain their slide order; PowerPoint appends copies above them.
        let editsByID = Dictionary(grouping: suggestion.edits.filter { $0.duplicate != true }, by: \.id)
        let originals = slide.objects.compactMap { editsByID[$0.id]?.first }
        let copies = suggestion.edits.filter { $0.duplicate == true }
        for edit in originals + copies {
            let p = edit.placement
            let rect = NSRect(x: p.x, y: p.y, width: p.width, height: p.height)
            NSGraphicsContext.saveGraphicsState()
            let rotation = NSAffineTransform()
            rotation.translateX(by: rect.midX, yBy: rect.midY)
            rotation.rotate(byDegrees: edit.rotation)
            rotation.translateX(by: -rect.midX, yBy: -rect.midY)
            rotation.concat()
            if edit.text == nil, edit.fontSize == nil, let picture = picturePreviews[edit.id] {
                picture.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.7, respectFlipped: true, hints: nil)
            } else {
                let original = slide.objects.first { $0.id == edit.id }
                let replacesText = edit.text.map { $0 != original?.text } ?? false
                let changesSize = edit.fontSize.map { $0 != original?.fontSize } ?? false
                if replacesText || changesSize {
                    // Mask existing glyphs under the proposed text, including when clearing a box.
                    NSColor.white.setFill()
                    rect.fill()
                }
                NSColor.systemTeal.withAlphaComponent(0.19).setFill()
                rect.fill()
                drawLabel(edit.text ?? original?.text ?? original?.name ?? "", in: rect, fontSize: edit.fontSize ?? original?.fontSize)
            }
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 2 / scale
            outline.setLineDash([6 / scale, 4 / scale], count: 2, phase: 0)
            NSColor.systemTeal.setStroke()
            outline.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        for (asset, image) in zip(suggestion.artwork, artworkImages) {
            let p = asset.placement
            image?.draw(in: NSRect(x: p.x, y: p.y, width: p.width, height: p.height),
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

