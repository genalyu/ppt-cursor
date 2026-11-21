import AppKit

struct PowerPointWindow {
    let id: CGWindowID
    let frame: NSRect

    static func front(of app: NSRunningApplication) -> PowerPointWindow? {
        guard let screensTop = NSScreen.screens.first?.frame.maxY,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"],
                  let height = bounds["Height"], width > 100, height > 75 else { continue }
            return PowerPointWindow(id: id, frame: NSRect(x: x, y: screensTop - y - height, width: width, height: height))
        }
        return nil
    }
}
