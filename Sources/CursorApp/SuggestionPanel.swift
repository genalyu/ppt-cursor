import AppKit

/// A nonactivating control at the page edge leaves the entire slide preview click-through.
final class SuggestionPanel: NSPanel {
    private let label = NSTextField(wrappingLabelWithString: "")
    private let confirm = NSButton()
    private let skip = NSButton()
    private var sourceURL: URL?
    private let alignLeft: Bool

    @objc private func openSource() {
        if let sourceURL { NSWorkspace.shared.open(sourceURL) }
    }

    func updateShortcut(_ label: String?) {
        confirm.title = label.map { "采纳  " + $0 } ?? "采纳"
    }

    func showStatus(_ text: String, finished: Bool) {
        label.stringValue = text
        label.toolTip = text
        confirm.isHidden = true
        skip.isHidden = !finished
        skip.title = "关闭"
    }

    init(summary: String, shortcutLabel: String?, owner: NSObject, accept: Selector, dismiss: Selector,
         page: NSRect, canAccept: Bool = true, actionTitle: String? = nil, sourceURL: URL? = nil, alignLeft: Bool = false) {
        self.alignLeft = alignLeft
        let width = min(420, max(240, page.width - (alignLeft ? 0 : 16)))
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
        label.stringValue = summary
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = summary
        confirm.title = actionTitle ?? shortcutLabel.map { "采纳  " + $0 } ?? "采纳"
        confirm.target = owner
        confirm.action = accept
        skip.title = "忽略"
        skip.target = owner
        skip.action = dismiss
        var actions: [NSView] = canAccept ? [confirm, skip] : [skip]
        if let sourceURL, sourceURL.scheme == "https", sourceURL.host == "commons.wikimedia.org" {
            self.sourceURL = sourceURL
            actions.insert(NSButton(title: "素材来源", target: self, action: #selector(openSource)), at: 0)
        }
        let buttons = NSStackView(views: actions)
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
        setFrameOrigin(Self.origin(for: page, panel: frame.size, displays: displays, alignLeft: alignLeft))
    }

    static func origin(for page: NSRect, panel: NSSize, displays: [NSRect], alignLeft: Bool = false) -> NSPoint {
        func coveredArea(_ display: NSRect) -> CGFloat {
            let overlap = display.intersection(page)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        let display = displays.max { coveredArea($0) < coveredArea($1) } ?? page
        let above = page.maxY + 6
        let y = above + panel.height <= display.maxY ? above : page.maxY - panel.height - 6
        return NSPoint(x: max(display.minX, min(alignLeft ? page.minX : page.maxX - panel.width - 6, display.maxX - panel.width)),
                       y: max(display.minY, min(y, display.maxY - panel.height)))
    }
}
