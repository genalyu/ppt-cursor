import AppKit

final class SetupWindow: NSWindow {
    private let sessionButton = NSButton()
    private let retryButton = NSButton()
    private let connection = NSTextField(labelWithString: "")
    private let state = NSTextField(wrappingLabelWithString: "")

    let tabOption = NSButton(checkboxWithTitle: "用 Tab 采纳可见建议", target: nil, action: nil)
    let includePage = NSButton(checkboxWithTitle: "向模型提供当前幻灯片截图", target: nil, action: nil)

    init(owner: NSObject, includePageChanged: Selector, chooseImages: Selector, modelSettings: Selector, toggleTab: Selector, prefersTab: Bool, toggleSession: Selector, retry: Selector, returnToEditor: Selector) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "PPT Cursor"
        isReleasedWhenClosed = false
        let heading = NSTextField(labelWithString: "在 PowerPoint 中预览下一步")
        heading.font = .systemFont(ofSize: 21, weight: .semibold)
        let help = NSTextField(wrappingLabelWithString: "在 PowerPoint 中打开并保存 PPTX，配置模型后点击开始。建议出现时按 Tab 采纳，编辑文字时使用 ⌥⌘Return。每次采纳前都会核对当前页。")
        help.textColor = .secondaryLabelColor
        let assets = NSButton(title: "选择图片素材…", target: owner, action: chooseImages)
        let settings = NSButton(title: "模型连接…", target: owner, action: modelSettings)
        includePage.target = owner
        includePage.action = includePageChanged
        tabOption.target = owner
        tabOption.action = toggleTab
        tabOption.state = prefersTab ? .on : .off
        sessionButton.title = "开始预测"
        sessionButton.target = owner
        sessionButton.action = toggleSession
        sessionButton.bezelStyle = .rounded
        retryButton.title = "重新预测"
        retryButton.target = owner
        retryButton.action = retry
        connection.font = .systemFont(ofSize: 12, weight: .medium)
        let editor = NSButton(title: "返回 PowerPoint", target: owner, action: returnToEditor)
        let sessionControls = NSStackView(views: [sessionButton, retryButton, editor])
        let privacy = NSTextField(wrappingLabelWithString: "开始后，当前页与最近编辑会发送给模型；需要素材时自动联网搜索公开图片，你提供的图片是可选补充。截图默认关闭，密钥存于钥匙串。")
        privacy.font = .systemFont(ofSize: 11)
        privacy.textColor = .secondaryLabelColor
        let options = NSStackView(views: [assets, settings])
        state.textColor = .secondaryLabelColor
        state.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [heading, help, connection, sessionControls, state, options, includePage, tabOption, privacy])
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
            privacy.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20),
            state.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        center()
    }

    func setRunning(_ running: Bool, canRetry: Bool, model: String, document: String?) {
        sessionButton.title = running ? "暂停预测" : "开始预测"
        retryButton.isEnabled = canRetry
        connection.stringValue = model + (document.map { " · " + $0 } ?? " · 等待本地 PPTX")
    }

    func update(_ value: String) { state.stringValue = value }
}
