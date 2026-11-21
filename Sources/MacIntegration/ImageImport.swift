import AppKit
import ImageIO
import UniformTypeIdentifiers
import CursorCore

public enum ImageImport {
    public static func read(_ url: URL, id: String = UUID().uuidString) throws -> ReferenceImage {
        let vector: Data?
        let source: CGImageSource
        if url.pathExtension.lowercased() == "svg" {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard let data = try handle.read(upToCount: 200_001),
                  let svg = String(data: data, encoding: .utf8), VectorAsset.accepts(svg),
                  let image = NSImage(data: data), image.isValid,
                  image.size.width.isFinite, image.size.height.isFinite,
                  (0.01...4096).contains(image.size.width), (0.01...4096).contains(image.size.height),
                  let pixels = image.tiffRepresentation,
                  let decoded = CGImageSourceCreateWithData(pixels as CFData, nil) else {
                throw BridgeFailure("无法预览此 SVG。请选择自包含的矢量图或导出为 PNG。")
            }
            source = decoded
            vector = data
        } else {
            guard let decoded = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                throw BridgeFailure("无法读取图片 " + url.lastPathComponent)
            }
            source = decoded
            vector = nil
        }
        func png(maxDimension: Int) throws -> Data {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                             kCGImageSourceCreateThumbnailWithTransform: true,
                                             kCGImageSourceThumbnailMaxPixelSize: maxDimension]
            let bytes = NSMutableData()
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let dest = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else {
                throw BridgeFailure("无法解码图片 " + url.lastPathComponent)
            }
            CGImageDestinationAddImage(dest, image, nil)
            guard CGImageDestinationFinalize(dest) else { throw BridgeFailure("无法准备图片 " + url.lastPathComponent) }
            return bytes as Data
        }
        return try ReferenceImage(id: id, name: url.lastPathComponent, png: png(maxDimension: 3072), thumbnail: png(maxDimension: 384), vector: vector)
    }
}
