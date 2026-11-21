import AppKit

/// Locate a uniform light or dark perimeter corroborated by multiple scan lines
/// and the slide dimensions reported by PowerPoint.
enum PageLocator {
    private static func capture(_ window: PowerPointWindow) -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        return CGWindowListCreateImage(.null, .optionIncludingWindow, window.id,
                                       [.boundsIgnoreFraming, .nominalResolution])
    }

    static func locate(in window: PowerPointWindow, aspect: CGFloat) -> CGRect? {
        guard let image = capture(window), let page = pagePixels(in: image, aspect: aspect) else { return nil }
        return screenRect(page, image: image, window: window)
    }

    private static func screenRect(_ rect: CGRect, image: CGImage, window: PowerPointWindow) -> CGRect {
        let sx = window.frame.width / CGFloat(image.width)
        let sy = window.frame.height / CGFloat(image.height)
        return CGRect(x: window.frame.minX + rect.minX * sx, y: window.frame.maxY - rect.maxY * sy,
                      width: rect.width * sx, height: rect.height * sy)
    }

    /// Recheck the perimeter in the very same captured frame before sending any cropped pixels.
    static func previewData(in window: PowerPointWindow, expected: CGRect, aspect: CGFloat) -> Data? {
        guard let cropped = pageImage(in: window, expected: expected, aspect: aspect) else { return nil }
        return NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])
    }

    static func pageImage(in window: PowerPointWindow, expected: CGRect, aspect: CGFloat) -> CGImage? {
        guard let image = capture(window), let pixels = pagePixels(in: image, aspect: aspect) else { return nil }
        let actual = screenRect(pixels, image: image, window: window)
        guard abs(actual.minX - expected.minX) <= 3, abs(actual.minY - expected.minY) <= 3,
              abs(actual.maxX - expected.maxX) <= 3, abs(actual.maxY - expected.maxY) <= 3 else { return nil }
        return image.cropping(to: pixels)
    }

    static func pagePixels(in image: CGImage, aspect: CGFloat) -> CGRect? {
        guard aspect > 0 else { return nil }
        let width = image.width, height = image.height
        guard width > 200, height > 150 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            var pages: [CGRect] = []
            for darkPage in [false, true] {
                func matches(_ x: Int, _ y: Int) -> Bool {
                    let shade = bytes[y * width + x]
                    return darkPage ? shade <= 36 : shade >= 236
                }
                var candidates: [(x: Int, y: Int, w: Int, h: Int)] = []
                for y in stride(from: height / 5, to: height * 9 / 10, by: max(4, height / 36)) {
                    var x = 1
                    while x < width - 1 {
                        guard matches(x,y) else { x += 1; continue }
                        let left = x
                        while x < width - 1 && matches(x,y) { x += 1 }
                        let span = x - left
                        guard span > width / 3, left > 2, x < width - 2 else { continue }
                        let h = Int((CGFloat(span) / aspect).rounded())
                        guard h > height / 4, h < height else { continue }
                        for edge in [left + 4, x - 5] {
                            var top = y, bottom = y
                            while top > 1 && matches(edge,top-1) { top -= 1 }
                            while bottom < height-2 && matches(edge,bottom+1) { bottom += 1 }
                            guard abs(bottom-top+1-h) <= max(3, h / 180) else { continue }
                            let corners = [(left+3,top+3),(x-4,top+3),(left+3,bottom-3),(x-4,bottom-3)]
                            guard corners.allSatisfy({ matches($0.0,$0.1) }) else { continue }
                            candidates.append((left,top,span,bottom-top+1))
                        }
                    }
                }
                guard let largest = candidates.max(by: { $0.w < $1.w }),
                      candidates.filter({ abs($0.x-largest.x) < 3 && abs($0.y-largest.y) < 3 && abs($0.w-largest.w) < 3 }).count >= 4 else { continue }
                pages.append(CGRect(x: largest.x, y: largest.y, width: largest.w, height: largest.h))
            }
            // A slide can contain an opposite-colored picture with the same aspect ratio.
            return pages.max { $0.width < $1.width }
        }
    }
}
