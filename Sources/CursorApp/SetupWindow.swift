import AppKit

final class SetupWindow: NSWindow {
    private let state = NSTextField(wrappingLabelWithString: "")

    let tabOption = NSButton(checkboxWithTitle: "用 Tab 采纳可见建议", target: nil, action: nil)
    let includePage = NSButton(checkboxWithTitle: "向模型提供当前幻灯片截图", target: nil, action: nil)

    init(owner: NSObject, includePageChanged: Selector, chooseImages: Selector, modelSettings: Selector, toggleTab: Selector, prefersTab: Bool) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 470, height: 330),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "PPT Cursor"
        isReleasedWhenClosed = false
        let heading = NSTextField(labelWithString: "在 PowerPoint 中预览下一步")
        heading.font = .systemFont(ofSize: 21, weight: .semibold)
        let help = NSTextField(wrappingLabelWithString: "打开本地 PPTX 后自动开始预测。移动或调整图形时，AI 会结合最近的编辑给出建议。按画布上显示的快捷键采纳。")
        help.textColor = .secondaryLabelColor
        let assets = NSButton(title: "选择图片素材…", target: owner, action: chooseImages)
        let settings = NSButton(title: "模型连接…", target: owner, action: modelSettings)
        includePage.target = owner
        includePage.action = includePageChanged
        tabOption.target = owner
        tabOption.action = toggleTab
        tabOption.state = prefersTab ? .on : .off
        let options = NSStackView(views: [assets, settings])
        state.textColor = .secondaryLabelColor
        state.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [heading, help, includePage, tabOption, options, state])
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
