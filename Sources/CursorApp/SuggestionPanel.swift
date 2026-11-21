import AppKit

/// A nonactivating control at the page edge leaves the entire slide preview click-through.
final class SuggestionPanel: NSPanel {
    init(summary: String, shortcutLabel: String?, owner: NSObject, accept: Selector, dismiss: Selector,
         page: NSRect, canAccept: Bool = true) {
        let width = min(420, max(240, page.width - 16))
        let size = NSSize(width: width, height: 84)
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "PPT Cursor 编辑建议"
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        let surface = NSVisualEffectView()
        surface.material = .popover
        surface.state = .active
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 10
        contentView = surface
        let label = NSTextField(wrappingLabelWithString: summary)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = summary
        let confirm = NSButton(title: shortcutLabel.map { "采纳  " + $0 } ?? "采纳", target: owner, action: accept)
        let skip = NSButton(title: "忽略", target: owner, action: dismiss)
        let buttons = NSStackView(views: canAccept ? [confirm, skip] : [skip])
        for view in [label as NSView, buttons] {
            surface.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: surface.topAnchor, constant: 8),
            buttons.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -9),
            buttons.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -6),
            label.bottomAnchor.constraint(lessThanOrEqualTo: buttons.topAnchor, constant: -2)
        ])
        position(at: page)
    }

    func position(at page: NSRect) {
        let displays = NSScreen.screens.map { $0.visibleFrame }
        setFrameOrigin(Self.origin(for: page, panel: frame.size, displays: displays))
    }

    static func origin(for page: NSRect, panel: NSSize, displays: [NSRect]) -> NSPoint {
        func coveredArea(_ display: NSRect) -> CGFloat {
            let overlap = display.intersection(page)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        let display = displays.max { coveredArea($0) < coveredArea($1) } ?? page
        let above = page.maxY + 6
        let y = above + panel.height <= display.maxY ? above : page.maxY - panel.height - 6
        return NSPoint(x: max(display.minX, min(page.maxX - panel.width - 6, display.maxX - panel.width)),
                       y: max(display.minY, min(y, display.maxY - panel.height)))
    }
}
