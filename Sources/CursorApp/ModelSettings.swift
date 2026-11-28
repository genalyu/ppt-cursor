import AppKit
import CursorCore
import Security
import LocalAuthentication

enum ModelConnection { case cli, api(APISettings) }

final class ModelSettings: NSObject {
    static let beijing = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    private static let keychainLock = NSLock()
    private static let defaults = UserDefaults.standard
    private static func query(_ base: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "io.github.genalyu.pptcursor.model",
         kSecAttrAccount as String: base]
    }

    static var hasSavedConnection: Bool { defaults.string(forKey: "modelBase") != nil }

    static func restore() -> APISettings? {
        guard let base = defaults.string(forKey: "modelBase"),
              APISettings.accepts(baseURL: base), let key = secret(base) else { return nil }
        return APISettings(model: defaults.string(forKey: "modelName") ?? "qwen4-max", key: key, baseURL: base)
    }

    private static func secret(_ base: String, interactive: Bool = false) -> String? {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        // Existing installations use the legacy login keychain, which can ignore
        // LAContext for an ACL/signature prompt. Deny interaction for background reads.
        var previousInteraction: DarwinBoolean = true
        if !interactive {
            SecKeychainGetUserInteractionAllowed(&previousInteraction)
            SecKeychainSetUserInteractionAllowed(false)
        }
        defer { if !interactive { SecKeychainSetUserInteractionAllowed(previousInteraction.boolValue) } }
        var item: CFTypeRef?
        var request = query(base)
        request[kSecReturnData as String] = true
        // A rebuilt ad-hoc signature can require Keychain authorization. Never
        // block startup or merely opening a settings form on a password dialog.
        if !interactive {
            let context = LAContext()
            context.interactionNotAllowed = true
            request[kSecUseAuthenticationContext as String] = context
        }
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(base: String, model: String, key: String) throws -> APISettings {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let request = query(base)
        var status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(request.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        defaults.set(base, forKey: "modelBase")
        defaults.set(model, forKey: "modelName")
        return APISettings(model: model, key: key, baseURL: base)
    }

    private let provider = NSPopUpButton()
    private let model = NSTextField()
    private let key = NSSecureTextField()
    private let endpoint = NSTextField()
    private let grid = NSGridView()
    private let panel = NSAlert()
    private var current: APISettings?

    @objc private func changeProvider() {
        let index = provider.indexOfSelectedItem
        let isBailian = index == 0
        let matches = current.map { ($0.baseURL != APISettings.openAIBase) == isBailian } ?? false
        endpoint.stringValue = matches ? current!.baseURL : (isBailian ? Self.beijing : APISettings.openAIBase)
        model.stringValue = matches ? current!.model : (isBailian ? "qwen4-max" : "gpt-5-mini")
        key.stringValue = ""
        key.placeholderString = Self.hasSavedConnection ? "留空沿用已保存密钥，必要时由系统授权" : "输入 API 密钥"
        key.toolTip = "密钥存储在 macOS 钥匙串。输入新值可替换此地址的密钥。"
        for i in 1...3 { grid.row(at: i).isHidden = index == 2 }
        grid.row(at: 3).isHidden = !isBailian
    }

    static func choose(current: APISettings?) -> ModelConnection? {
        let form = ModelSettings()
        return withExtendedLifetime(form) { form.show(current) }
    }

    private func show(_ settings: APISettings?) -> ModelConnection? {
        current = settings
        if current == nil, let base = Self.defaults.string(forKey: "modelBase"), APISettings.accepts(baseURL: base) {
            current = APISettings(model: Self.defaults.string(forKey: "modelName") ?? "qwen4-max", key: "", baseURL: base)
        }
        provider.addItems(withTitles: ["阿里云百炼", "OpenAI", "Codex CLI"])
        provider.selectItem(at: current.map { $0.baseURL == APISettings.openAIBase ? 1 : 0 } ?? 2)
        provider.target = self
        provider.action = #selector(changeProvider)
        for (label, field) in [("服务商", provider as NSView), ("模型", model), ("API 密钥", key), ("连接地址", endpoint)] {
            grid.addRow(with: [NSTextField(labelWithString: label), field])
            field.setAccessibilityLabel(label)
        }
        grid.column(at: 0).width = 76
        grid.column(at: 1).width = 350
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.rowSpacing = 12
        grid.columnSpacing = 14
        for index in 0..<grid.numberOfRows {
            grid.row(at: index).height = 26
            grid.row(at: index).yPlacement = .center
        }
        grid.frame = NSRect(x: 0, y: 0, width: 440, height: 146)
        endpoint.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        endpoint.toolTip = "百炼北京、国际地域或业务空间的 HTTPS 接口地址"
        model.placeholderString = "服务商提供的模型名称"
        if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            panel.icon = NSImage(contentsOf: icon)
        }
        panel.messageText = "模型连接"
        panel.informativeText = "API 模式会将当前页和编辑历史发送给所选服务商。密钥保存在此 Mac 的钥匙串中。"
        panel.accessoryView = grid
        panel.addButton(withTitle: "保存连接")
        panel.addButton(withTitle: "取消")
        changeProvider()
        while panel.runModal() == .alertFirstButtonReturn {
            if provider.indexOfSelectedItem == 2 {
                Self.defaults.removeObject(forKey: "modelBase")
                return .cli
            }
            let base = endpoint.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let name = model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard APISettings.accepts(baseURL: base), !name.isEmpty,
                  (base != APISettings.openAIBase) == (provider.indexOfSelectedItem == 0) else {
                panel.informativeText = "请检查模型名称及服务商的 HTTPS 接口地址。"
                continue
            }
            let typed = key.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = typed.isEmpty ? Self.secret(base, interactive: true) : typed else {
                panel.informativeText = "无法读取此连接的密钥。请完成系统钥匙串授权，或填写 API 密钥。"
                continue
            }
            do { return .api(try Self.save(base: base, model: name, key: value)) }
            catch { panel.informativeText = "无法保存到钥匙串：" + error.localizedDescription }
        }
        return nil
    }
}
