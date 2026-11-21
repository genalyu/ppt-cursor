import AppKit
import CursorCore

enum ModelConnection { case cli, api(APISettings) }

enum ModelSettings {
    static func choose(current: APISettings?) -> ModelConnection? {
        let panel = NSAlert()
        panel.messageText = "模型连接"
        panel.informativeText = "使用 OpenAI API 时，当前页和编辑历史会发送到所选模型并按 API 用量计费。密钥只保留到应用退出。"
        let model = NSTextField(string: current?.model ?? "gpt-5-mini")
        model.placeholderString = "模型名称"
        model.setAccessibilityLabel("模型名称")
        let key = NSSecureTextField(string: "")
        key.placeholderString = current == nil ? "OpenAI API 密钥" : "留空以沿用本次连接的密钥"
        key.setAccessibilityLabel("OpenAI API 密钥")
        let stack = NSStackView(views: [model, key])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.frame = NSRect(x: 0, y: 0, width: 340, height: 58)
        panel.accessoryView = stack
        panel.addButton(withTitle: "使用 API")
        panel.addButton(withTitle: "使用 Codex CLI")
        panel.addButton(withTitle: "取消")
        panel.window.initialFirstResponder = current == nil ? key : model
        while true {
            switch panel.runModal() {
            case .alertFirstButtonReturn:
                let name = model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let secret = key.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    panel.messageText = "请填写模型名称"
                    panel.window.initialFirstResponder = model
                    continue
                }
                if !secret.isEmpty { return .api(APISettings(model: name, key: secret)) }
                if let current { return .api(current.selecting(model: name)) }
                panel.messageText = "请填写 OpenAI API 密钥"
                panel.window.initialFirstResponder = key
            case .alertSecondButtonReturn: return .cli
            default: return nil
            }
        }
    }
}
