import AppKit

/// A light slide on the dark editor has a broad, continuous perimeter. Measure multiple
/// scan lines and require a page-sized 4:3 or widescreen rectangle before using it.
enum PageLocator {
    static func locate(in window: PowerPointWindow, aspect: CGFloat) -> CGRect? {
        guard CGPreflightScreenCaptureAccess(), aspect > 0,
              let image = CGWindowListCreateImage(.null, .optionIncludingWindow, window.id,
                                                  [.boundsIgnoreFraming, .nominalResolution]) else { return nil }
        let width = image.width, height = image.height
        guard width > 200, height > 150 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            func light(_ x: Int, _ y: Int) -> Bool { bytes[y * width + x] >= 236 }
            var candidates: [(x: Int, y: Int, w: Int, h: Int)] = []
            for y in stride(from: height / 5, to: height * 9 / 10, by: max(4, height / 36)) {
                var x = 1
                while x < width - 1 {
                    guard light(x,y) else { x += 1; continue }
                    let left = x
                    while x < width - 1 && light(x,y) { x += 1 }
                    let span = x - left
                    guard span > width / 3, left > 2, x < width - 2 else { continue }
                    let h = Int((CGFloat(span) / aspect).rounded())
                    guard h > height / 4, h < height else { continue }
                    for edge in [left + 4, x - 5] {
                        var top = y, bottom = y
                        while top > 1 && light(edge,top-1) { top -= 1 }
                        while bottom < height-2 && light(edge,bottom+1) { bottom += 1 }
                        guard abs(bottom-top+1-h) <= max(3, h / 180) else { continue }
                        let corners = [(left+3,top+3),(x-4,top+3),(left+3,bottom-3),(x-4,bottom-3)]
                        guard corners.allSatisfy({ light($0.0,$0.1) }) else { continue }
                        candidates.append((left,top,span,bottom-top+1))
                    }
                }
            }
            guard let largest = candidates.max(by: { $0.w < $1.w }),
                  candidates.filter({ abs($0.x-largest.x) < 3 && abs($0.y-largest.y) < 3 && abs($0.w-largest.w) < 3 }).count >= 4 else { return nil }
            let sx = window.frame.width / CGFloat(width), sy = window.frame.height / CGFloat(height)
            return CGRect(x: window.frame.minX + CGFloat(largest.x) * sx,
                          y: window.frame.maxY - CGFloat(largest.y + largest.h) * sy,
                          width: CGFloat(largest.w) * sx, height: CGFloat(largest.h) * sy)
        }
    }
}
