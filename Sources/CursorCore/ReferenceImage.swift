import Foundation
import ImageIO

public struct ReferenceImage: Sendable {
    public let id: String
    public let name: String
    public let png: Data
    public let thumbnail: Data
    public let pixelSize: CGSize?

    public init(id: String = UUID().uuidString, name: String, png: Data, thumbnail: Data) {
        self.id = id
        self.name = name
        if let source = CGImageSourceCreateWithData(png as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 {
            pixelSize = CGSize(width: width, height: height)
        } else { pixelSize = nil }
        self.png = png
        self.thumbnail = thumbnail
    }
}
