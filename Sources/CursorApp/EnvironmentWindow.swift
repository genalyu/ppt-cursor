import AppKit
import MacIntegration

private final class EnvironmentContentView: NSView { override var isFlipped: Bool { true } }

final class EnvironmentWindow: NSWindow, NSWindowDelegate {
    private let resultLabel = NSTextField(labelWithString: "正在检查…")
    private let rows = NSStackView()
    private let refreshButton = NSButton()
    private let copyButton = NSButton()
    private let modelState: () -> EnvironmentDiagnostics.Model
    private let configureModel: (() -> Void)?
    private let onClose: (() -> Void)?
    private var request: UUID?
    private var report: EnvironmentReport?

    init(modelState: @escaping () -> EnvironmentDiagnostics.Model, configureModel: (() -> Void)? = nil,
         onClose: (() -> Void)? = nil) {
        self.modelState = modelState
        self.configureModel = configureModel
        self.onClose = onClose
        super.init(contentRect: NSRect(x: 0, y: 0, width: 620, height: 630),
                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = "PPT Cursor 环境检查"
        isReleasedWhenClosed = false
        delegate = self
        contentMinSize = NSSize(width: 560, height: 420)
        let heading = NSTextField(labelWithString: "检查环境，继续编辑")
        heading.font = .systemFont(ofSize: 21, weight: .semibold)
        let hint = NSTextField(wrappingLabelWithString: "本机安装检查，无需密钥。模型登录、网络和服务响应仍以实际请求为准。")
        hint.textColor = .secondaryLabelColor
        resultLabel.font = .systemFont(ofSize: 15, weight: .medium)
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 18
        refreshButton.title = "重新检查"
        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        refreshButton.bezelStyle = .rounded
        copyButton.title = "复制诊断摘要"
        copyButton.target = self
        copyButton.action = #selector(copyReport)
        copyButton.isEnabled = false
        let guide = NSButton(title: "使用指南 ↗", target: self, action: #selector(openGuide))
        var buttons = [refreshButton, guide, copyButton]
        if configureModel != nil { buttons.append(NSButton(title: "模型连接…", target: self, action: #selector(openModel))) }
        let controls = NSStackView(views: buttons)
        controls.spacing = 10
        let content = NSStackView(views: [heading, hint, resultLabel, rows, controls])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 18
        content.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let container = EnvironmentContentView()
        container.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = container
        contentView = scroll
        container.addSubview(content)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
            hint.widthAnchor.constraint(equalTo: content.widthAnchor),
            rows.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])
        center()
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    @objc private func refresh() {
        let token = UUID()
        request = token
        report = nil
        resultLabel.stringValue = "正在检查本机依赖…"
        refreshButton.isEnabled = false
        copyButton.isEnabled = false
        let codex = CodexInstallation.executable()
        let environment = NativeSessionLauncher.environment(codex: codex)
        let powerpoint = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.Powerpoint")
        let resources = Bundle.main.resourceURL
        let model = modelState()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = EnvironmentDiagnostics.check(environment: environment, powerPoint: powerpoint, resources: resources, model: model)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.request == token else { return }
                self.report = result
                self.resultLabel.stringValue = result.summary
                for view in self.rows.arrangedSubviews { self.rows.removeArrangedSubview(view); view.removeFromSuperview() }
                for item in result.items {
                    let title = NSTextField(labelWithString: item.title + " · " + item.status.rawValue)
                    title.font = .systemFont(ofSize: 13, weight: .semibold)
                    title.textColor = item.status == .missing ? .systemOrange : .labelColor
                    let detail = NSTextField(wrappingLabelWithString: item.detail)
                    detail.font = .systemFont(ofSize: 12)
                    detail.textColor = .secondaryLabelColor
                    detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                    let row = NSStackView(views: [title, detail])
                    row.orientation = .vertical
                    row.alignment = .leading
                    row.spacing = 4
                    self.rows.addArrangedSubview(row)
                    row.widthAnchor.constraint(equalTo: self.rows.widthAnchor).isActive = true
                    detail.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
                }
                self.refreshButton.isEnabled = true
                self.copyButton.isEnabled = true
            }
        }
    }

    @objc private func copyReport() {
        guard let report else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.text, forType: .string)
        resultLabel.stringValue = "已复制诊断摘要"
    }

    @objc private func openGuide() {
        NSWorkspace.shared.open(URL(string: "https://github.com/genalyu/ppt-cursor/blob/main/docs/USER-GUIDE.zh-CN.md#环境检查")!)
    }

    @objc private func openModel() { configureModel?() }

    func windowWillClose(_ notification: Notification) {
        request = nil
        onClose?()
    }
}
