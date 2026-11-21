import AppKit
import PDFKit

public enum NativeSlideRenderer {
    /// Render a saved presentation through PowerPoint using a uniquely named working copy.
    public static func render(file: URL, page: Int) throws -> Data {
        let manager = FileManager.default
        guard page > 0, file.pathExtension.lowercased() == "pptx" else {
            throw BridgeFailure("请选择 PPTX 文件并指定从 1 开始的页码。")
        }
        let name = "ppt-cursor-" + UUID().uuidString
        let scratch = manager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.microsoft.Powerpoint/Data/tmp")
            .appendingPathComponent(name)
        try manager.createDirectory(at: scratch, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: scratch) }
        let copy = scratch.appendingPathComponent(name + ".pptx")
        let pdf = scratch.appendingPathComponent("render.pdf")
        try manager.copyItem(at: file, to: copy)
        let script = ResourcesBundle.value.url(forResource: "render", withExtension: "applescript")!
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [script.path, copy.path, copy.lastPathComponent, pdf.path]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let detail = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BridgeFailure(String(decoding: detail, as: UTF8.self))
        }
        guard let document = PDFDocument(url: pdf), page <= document.pageCount,
              let slide = document.page(at: page - 1) else {
            throw BridgeFailure("无法读取 PowerPoint 导出的第 \(page) 页。")
        }
        let size = slide.bounds(for: .mediaBox).size
        let image = slide.thumbnail(of: NSSize(width: size.width * 2, height: size.height * 2), for: .mediaBox)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw BridgeFailure("无法生成幻灯片预览图。")
        }
        return png
    }
}
