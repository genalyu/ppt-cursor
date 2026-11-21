import AppKit

final class SetupWindow: NSWindow {
    private let state = NSTextField(wrappingLabelWithString: "")

    init(owner: NSObject, calibrate: Selector, chooseImages: Selector) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 470, height: 232),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "PPT Cursor"
        isReleasedWhenClosed = false
        let heading = NSTextField(labelWithString: "在 PowerPoint 中预览下一步")
        heading.font = .systemFont(ofSize: 21, weight: .semibold)
        let help = NSTextField(wrappingLabelWithString: "打开要编辑的幻灯片，然后沿页面边缘框选画布。编辑时按 ⌥⌘Return 采纳建议。")
        help.textColor = .secondaryLabelColor
        let start = NSButton(title: "定位画布并开始", target: owner, action: calibrate)
        start.keyEquivalent = "\r"
        let assets = NSButton(title: "选择图片素材…", target: owner, action: chooseImages)
        let buttons = NSStackView(views: [start, assets])
        state.textColor = .secondaryLabelColor
        state.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [heading, help, buttons, state])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        contentView = container
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor),
            state.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        center()
    }

    func update(_ value: String) { state.stringValue = value }
}
