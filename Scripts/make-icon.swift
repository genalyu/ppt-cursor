import AppKit

// A reproducible vector-drawn application icon; no external artwork dependency.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 65, y: 65, width: 894, height: 894), xRadius: 205, yRadius: 205)
        NSGradient(starting: NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.29, alpha: 1),
                   ending: NSColor(calibratedRed: 0.06, green: 0.37, blue: 0.45, alpha: 1))!.draw(in: background, angle: 45)
        NSColor.white.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: NSRect(x: 205, y: 270, width: 615, height: 470), xRadius: 42, yRadius: 42).fill()
        NSColor(calibratedRed: 0.05, green: 0.58, blue: 0.67, alpha: 1).setFill()
        for x in [270, 440, 610] {
            NSBezierPath(roundedRect: NSRect(x: x, y: 470, width: 135, height: 150), xRadius: 17, yRadius: 17).fill()
        }
        NSColor(calibratedRed: 0.07, green: 0.18, blue: 0.3, alpha: 1).setFill()
        let cursor = NSBezierPath()
        cursor.move(to: NSPoint(x: 590, y: 430))
        cursor.line(to: NSPoint(x: 780, y: 290))
        cursor.line(to: NSPoint(x: 690, y: 270))
        cursor.line(to: NSPoint(x: 650, y: 190))
        cursor.close()
        cursor.fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let filename = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
    }
}
