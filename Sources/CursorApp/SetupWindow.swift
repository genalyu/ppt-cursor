import AppKit

final class SetupWindow: NSWindow {
    private let state = NSTextField(wrappingLabelWithString: "")

    let tabOption = NSButton(checkboxWithTitle: "用 Tab 采纳可见建议", target: nil, action: nil)
    let includePage = NSButton(checkboxWithTitle: "向模型提供当前幻灯片截图", target: nil, action: nil)

    init(owner: NSObject, calibrate: Selector, openNativeSession: Selector, chooseImages: Selector, modelSettings: Selector, toggleTab: Selector, prefersTab: Bool) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 470, height: 330),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "PPT Cursor"
        isReleasedWhenClosed = false
        let heading = NSTextField(labelWithString: "在 PowerPoint 中预览下一步")
        heading.font = .systemFont(ofSize: 21, weight: .semibold)
        let help = NSTextField(wrappingLabelWithString: "在 PowerPoint 打开本地 PPTX，启动开放式预测后选择这份文稿。移动或调整图形时，AI 会结合最近的编辑给出建议。按画布上显示的快捷键采纳。")
        help.textColor = .secondaryLabelColor
        let start = NSButton(title: "定位画布并开始", target: owner, action: calibrate)
        start.toolTip = "定位当前画布，启动布局和素材预测。"
        let assets = NSButton(title: "选择图片素材…", target: owner, action: chooseImages)
        let settings = NSButton(title: "模型连接…", target: owner, action: modelSettings)
        let native = NSButton(title: "启动开放式预测…", target: owner, action: openNativeSession)
        native.keyEquivalent = "\r"
        tabOption.target = owner
        tabOption.action = toggleTab
        tabOption.state = prefersTab ? .on : .off
        native.toolTip = "使用选定的模型连接生成原生图形建议。可从菜单栏停止会话。"
        let buttons = NSStackView(views: [native, start])
        let options = NSStackView(views: [assets, settings])
        state.textColor = .secondaryLabelColor
        state.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [heading, help, includePage, tabOption, options, buttons, state])
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
