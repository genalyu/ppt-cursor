import Foundation

enum ResourcesBundle {
    static let value: Bundle = {
        if let url = Bundle.main.url(forResource: "PPTCursor_MacIntegration", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()
}
