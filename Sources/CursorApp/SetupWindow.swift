import AppKit

final class SetupWindow: NSWindow {
    private let sessionButton = NSButton()
    private let retryButton = NSButton()
    private let connection = NSTextField(labelWithString: "")
    private let state = NSTextField(wrappingLabelWithString: "")
    private let phaseLabel = NSTextField(labelWithString: "已暂停")
    private let previewImage = NSImageView()
    private let previewSummary = NSTextField(wrappingLabelWithString: "")
    private let acceptButton = NSButton()
    private let dismissButton = NSButton()
    private let sourceButton = NSButton()
    private var sourceURL: URL?
    private var reviewStack: NSStackView!

    let tabOption = NSButton(checkboxWithTitle: "用 Tab 采纳可见建议", target: nil, action: nil)
    let includePage = NSButton(checkboxWithTitle: "向模型提供当前幻灯片截图", target: nil, action: nil)

    init(owner: NSObject, includePageChanged: Selector, chooseImages: Selector, modelSettings: Selector, toggleTab: Selector, prefersTab: Bool, toggleSession: Selector, retry: Selector, returnToEditor: Selector, accept: Selector, dismiss: Selector) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "PPT Cursor"
        isReleasedWhenClosed = false
        let heading = NSTextField(labelWithString: "PPT Cursor")
        heading.font = .systemFont(ofSize: 21, weight: .semibold)
        let help = NSTextField(wrappingLabelWithString: "你编辑，AI 接着想。先预览，再采纳。\n打开本地 PPTX，开始后切回 PowerPoint。")
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
        phaseLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        phaseLabel.setAccessibilityIdentifier("session-phase")
        previewImage.imageScaling = .scaleProportionallyUpOrDown
        previewImage.setAccessibilityLabel("当前建议预览")
        previewImage.heightAnchor.constraint(equalToConstant: 190).isActive = true
        previewSummary.font = .systemFont(ofSize: 12, weight: .medium)
        acceptButton.title = "采纳当前建议"
        acceptButton.target = owner
        acceptButton.action = accept
        acceptButton.bezelStyle = .rounded
        dismissButton.title = "忽略，换一条"
        dismissButton.target = owner
        dismissButton.action = dismiss
        sourceButton.title = "素材来源 ↗"
        sourceButton.target = self
        sourceButton.action = #selector(openSource)
        sourceButton.isHidden = true
        reviewStack = NSStackView(views: [previewImage, previewSummary, NSStackView(views: [acceptButton, dismissButton, sourceButton])])
        reviewStack.orientation = .vertical
        reviewStack.alignment = .leading
        reviewStack.spacing = 8
        reviewStack.isHidden = true
        let stack = NSStackView(views: [heading, help, connection, phaseLabel, state, sessionControls, reviewStack, options, includePage, tabOption, privacy])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        for label in [help, state, previewSummary, privacy] {
            label.preferredMaxLayoutWidth = 512
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let container = NSView()
        contentView = container
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: 512),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor),
            privacy.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20),
            state.widthAnchor.constraint(equalTo: stack.widthAnchor),
            reviewStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            previewImage.widthAnchor.constraint(equalTo: stack.widthAnchor),
            previewSummary.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        center()
    }

    func setRunning(_ running: Bool, canRetry: Bool, model: String, document: String?) {
        sessionButton.title = running ? "暂停预测" : "开始预测"
        retryButton.isEnabled = canRetry
        connection.stringValue = model + (document.map { " · " + $0 } ?? " · 等待本地 PPTX")
    }

    func updatePhase(_ value: String) { phaseLabel.stringValue = value }

    @objc private func openSource() {
        if let sourceURL { NSWorkspace.shared.open(sourceURL) }
    }

    private func resizeContent(height: CGFloat) {
        let size = frameRect(forContentRect: NSRect(x: 0, y: 0, width: 560, height: height)).size
        setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    func showPreview(image: NSImage, summary: String, direct: Bool, source: URL?) {
        sourceURL = source.flatMap { $0.scheme == "https" && $0.host == "commons.wikimedia.org" ? $0 : nil }
        sourceButton.isHidden = sourceURL == nil
        resizeContent(height: 700)
        acceptButton.title = direct ? "采纳当前建议" : "另存建议副本…"
        previewImage.image = image
        previewSummary.stringValue = summary
        reviewStack.isHidden = false
        acceptButton.isEnabled = true
        dismissButton.isEnabled = true
    }

    func clearPreview() {
        reviewStack.isHidden = true
        sourceURL = nil
        resizeContent(height: 430)
        previewImage.image = nil
        previewSummary.stringValue = ""
    }

    func setApplying(_ applying: Bool) {
        acceptButton.isEnabled = !applying
        dismissButton.isEnabled = !applying
    }

    func update(_ value: String) { state.stringValue = value }
}
