import Foundation
import ImageIO
import UniformTypeIdentifiers
import CursorCore

public enum ImageImport {
    public static func read(_ url: URL) throws -> ReferenceImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw BridgeFailure("无法读取图片 " + url.lastPathComponent) }
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
        return try ReferenceImage(name: url.lastPathComponent, png: png(maxDimension: 3072), thumbnail: png(maxDimension: 384))
    }
}
