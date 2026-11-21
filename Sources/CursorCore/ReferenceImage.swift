import Foundation

public struct ReferenceImage: Sendable {
    public let id: String
    public let name: String
    public let png: Data
    public let thumbnail: Data

    public init(name: String, png: Data, thumbnail: Data) {
        id = UUID().uuidString
        self.name = name
        self.png = png
        self.thumbnail = thumbnail
    }
}
