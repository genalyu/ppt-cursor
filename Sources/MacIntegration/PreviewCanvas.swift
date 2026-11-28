import AppKit
import CursorCore

/// The same view renders to the transparent panel and to a bitmap for regression inspection.
public final class PreviewCanvas: NSView {
    private let artworkImages: [NSImage?]
    public var canPreviewAllArtwork: Bool { artworkImages.allSatisfy { $0 != nil } }
    private let picturePreviews: [String: NSImage]
    let slide: SlideSnapshot
    let suggestion: Prediction
    private let background: NSImage?
    let diagnosticBackground: Bool

    public init(slide: SlideSnapshot, suggestion: Prediction, frame: NSRect, diagnosticBackground: Bool, images: [ReferenceImage] = [], pageImage: CGImage? = nil) {
        self.background = diagnosticBackground ? pageImage.map { NSImage(cgImage: $0, size: NSSize(width: slide.width, height: slide.height)) } : nil
        self.picturePreviews = Self.extractPictures(slide: slide, suggestion: suggestion, from: pageImage)
        self.artworkImages = suggestion.artwork.map { asset in
            let bytes: Data
            if let id = asset.referenceID {
                guard let reference = images.first(where: { $0.id == id }) else { return nil }
                bytes = reference.vector ?? reference.png
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
        object.rotation == 0
    }

    private static func extractPictures(slide: SlideSnapshot, suggestion: Prediction, from page: CGImage?) -> [String: NSImage] {
        guard let page, slide.width > 0, slide.height > 0 else { return [:] }
        let sx = CGFloat(page.width) / slide.width, sy = CGFloat(page.height) / slide.height
        let bounds = CGRect(x: 0, y: 0, width: slide.width, height: slide.height)
        let targets = Set(suggestion.edits.filter { $0.text == nil }.map(\.id))
        var result: [String: NSImage] = [:]
        for object in slide.objects where targets.contains(object.id) {
            guard supportsAppearancePreview(object) else { continue }
            let rect = CGRect(x: object.x, y: object.y, width: object.width, height: object.height)
            guard bounds.contains(rect), rect.width > 0, rect.height > 0 else { continue }
            // A screenshot includes pixels of every overlapping layer.
            let covered = slide.objects.contains { other in
                guard other.id != object.id else { return false }
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
        if let background {
            background.draw(in: pageBounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        } else if diagnosticBackground {
            NSColor.white.setFill()
            pageBounds.fill()
            for object in slide.objects {
                let rect = NSRect(x: object.x, y: object.y, width: object.width, height: object.height)
                NSGraphicsContext.saveGraphicsState()
                rotate(object.rotation, around: rect)
                let color = fillColor(object.solidFillRGB, transparency: object.fillTransparency)
                (color ?? NSColor(white: 0.94, alpha: 1)).setFill()
                outlinePath(for: object, in: rect).fill()
                drawLabel(object.text ?? object.name, in: rect, fontSize: object.fontSize, bold: object.textBold, italic: object.textItalic)
                NSGraphicsContext.restoreGraphicsState()
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
            rotate(edit.rotation, around: rect)
            let original = slide.objects.first { $0.id == edit.id }
            let outline = outlinePath(for: original, in: rect)
            if edit.text == nil, edit.fontSize == nil, edit.solidFillRGB == nil, edit.textBold == nil, edit.textItalic == nil,
               (original?.kind == "shape type picture" || original?.kind == "shape type group" ||
                (original?.width == p.width && original?.height == p.height)), let picture = picturePreviews[edit.id] {
                picture.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.7, respectFlipped: true, hints: nil)
            } else {
                let replacesText = edit.text.map { $0 != original?.text } ?? false
                let changesSize = edit.fontSize.map { $0 != original?.fontSize } ?? false
                if replacesText || changesSize || edit.textBold != nil || edit.textItalic != nil {
                    // Mask existing glyphs under the proposed text, including when clearing a box.
                    NSColor.white.setFill()
                    outline.fill()
                }
                let color = fillColor(edit.solidFillRGB ?? original?.solidFillRGB, transparency: original?.fillTransparency)
                (color ?? NSColor.systemTeal.withAlphaComponent(0.19)).setFill()
                outline.fill()
                drawLabel(edit.text ?? original?.text ?? original?.name ?? "", in: rect, fontSize: edit.fontSize ?? original?.fontSize, bold: edit.textBold ?? original?.textBold, italic: edit.textItalic ?? original?.textItalic)
            }
            outline.lineWidth = 2 / scale
            outline.setLineDash([6 / scale, 4 / scale], count: 2, phase: 0)
            NSColor.systemTeal.setStroke()
            outline.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        for (asset, image) in zip(suggestion.artwork, artworkImages) {
            let p = asset.placement
            let rect = NSRect(x: p.x, y: p.y, width: p.width, height: p.height)
            NSGraphicsContext.saveGraphicsState()
            rotate(asset.rotation ?? 0, around: rect)
            image?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.85,
                        respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func rotate(_ angle: Double, around rect: NSRect) {
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byDegrees: angle)
        transform.translateX(by: -rect.midX, yBy: -rect.midY)
        transform.concat()
    }

    private func outlinePath(for object: SlideObject?, in rect: NSRect) -> NSBezierPath {
        object?.autoShapeType == "autoshape oval" ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
    }

    private func fillColor(_ rgb: [Int]?, transparency: Double?) -> NSColor? {
        guard let rgb, rgb.count == 3 else { return nil }
        return NSColor(srgbRed: CGFloat(rgb[0]) / 255, green: CGFloat(rgb[1]) / 255,
                       blue: CGFloat(rgb[2]) / 255, alpha: 1 - (transparency ?? 0))
    }

    private func drawLabel(_ text: String, in rect: NSRect, fontSize: Double?, bold: Bool? = nil, italic: Bool? = nil) {
        let content = rect.insetBy(dx: 6, dy: 4)
        guard content.width > 0, content.height > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: content).addClip()
        var font = NSFont.systemFont(ofSize: fontSize ?? min(18, max(8, rect.height * 0.3)), weight: bold == true ? .bold : .regular)
        if italic == true { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        (text as NSString).draw(in: content, withAttributes: [.font: font, .foregroundColor: NSColor.black])
    }
}

