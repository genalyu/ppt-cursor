import AppKit
import CursorCore
import MacIntegration

enum PreviewError: Error { case usage, invalidSlide, renderingFailed }
do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 3 else { throw PreviewError.usage }
    let decoder = JSONDecoder()
    let slide = try decoder.decode(SlideSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: args[0])))
    let suggestion = try decoder.decode(Prediction.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
    try suggestion.validate(for: slide)
    guard slide.width > 0, slide.height > 0, slide.width <= 4096, slide.height <= 4096 else { throw PreviewError.invalidSlide }
    let frame = NSRect(x: 0, y: 0, width: slide.width, height: slide.height)
    let canvas = PreviewCanvas(slide: slide, suggestion: suggestion, frame: frame, diagnosticBackground: true)
    guard canvas.canPreviewAllArtwork else { throw PreviewError.renderingFailed }
    guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: frame) else { throw PreviewError.renderingFailed }
    canvas.cacheDisplay(in: frame, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw PreviewError.renderingFailed }
    try png.write(to: URL(fileURLWithPath: args[2]), options: .atomic)
} catch {
    FileHandle.standardError.write(Data("Usage: ppt-preview slide.json suggestion.json preview.png\nError: \(error)\n".utf8))
    exit(1)
}
