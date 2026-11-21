import AppKit

final class SetupWindow: NSWindow {
    private let state = NSTextField(wrappingLabelWithString: "")

    let includePage = NSButton(checkboxWithTitle: "向模型提供当前幻灯片截图", target: nil, action: nil)

    init(owner: NSObject, calibrate: Selector, openNativeSession: Selector, chooseImages: Selector, modelSettings: Selector) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 470, height: 300),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "PPT Cursor"
        isReleasedWhenClosed = false
        let heading = NSTextField(labelWithString: "在 PowerPoint 中预览下一步")
        heading.font = .systemFont(ofSize: 21, weight: .semibold)
        let help = NSTextField(wrappingLabelWithString: "打开要编辑的幻灯片，点击下方按钮定位画布。进入框选模式时，沿页面边缘拖出矩形。建议出现时，按预览旁显示的快捷键采纳。")
        help.textColor = .secondaryLabelColor
        let start = NSButton(title: "定位画布并开始", target: owner, action: calibrate)
        start.keyEquivalent = "\r"
        let assets = NSButton(title: "选择图片素材…", target: owner, action: chooseImages)
        let settings = NSButton(title: "模型连接…", target: owner, action: modelSettings)
        let native = NSButton(title: "启动开放式预测…", target: owner, action: openNativeSession)
        native.toolTip = "使用选定的模型连接生成原生图形建议。可从菜单栏停止会话。"
        let buttons = NSStackView(views: [start, native])
        let options = NSStackView(views: [assets, settings])
        state.textColor = .secondaryLabelColor
        state.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [heading, help, includePage, options, buttons, state])
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
