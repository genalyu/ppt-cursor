import Foundation

/// Worker protocol and compact menu-bar labels share one vocabulary.
enum SessionPhase: String, CaseIterable {
    case read = "读取"
    case predict = "预测"
    case search = "搜素材"
    case render = "生成预览"
    case preview = "待采纳"
    case apply = "写入"
    case waiting = "待切回"
    case document = "待文稿"
    case retry = "等待重试"
    case save = "待保存"
    case ready = "待编辑"
    case stopping = "正在结束"
    case paused = "已暂停"
    case error = "连接异常"
    case environment = "环境未就绪"
    case authorizing = "等待授权"
    case cancelled = "要求已取消"
    case failed = "操作失败"

    init?(event: String) {
        switch event {
        case "提供预览": self = .preview
        case "操作": self = .apply
        default:
            guard let phase = Self(rawValue: event) else { return nil }
            self = phase
        }
    }

    static func workerExit(_ code: Int32, detail: String) -> SessionPhase {
        if code == 0 { return .paused }
        if code == 3 { return .cancelled }
        let missing = ["找不到 LibreOffice", "找不到装有 Pillow", "缺少 Pillow", "找不到 osascript", "找不到 swift", "No module named 'PIL'"]
        return missing.contains(where: detail.contains) ? .environment : .error
    }

    var explanation: String {
        switch self {
        case .read: return "正在核对当前文稿和页面。"
        case .predict: return "模型正在准备下一步建议，你可以继续编辑。"
        case .search: return "正在搜索并检查公开图片素材。"
        case .render: return "正在生成修改后的预览。"
        case .preview: return "确认预览后采纳，或忽略并尝试其他建议。"
        case .apply: return "正在写入 PowerPoint，请稍候。"
        case .waiting: return "切回 PowerPoint 后自动继续。"
        case .document: return "请打开并保存一个本地 PPTX。"
        case .retry: return "稍后自动重试，也可以点击重新预测。"
        case .save: return "请保存当前文稿，保存后自动继续。"
        case .ready: return "继续编辑，AI 会跟随你的改动。"
        case .stopping: return "正在结束会话；本次写入和恢复缓存完成后停止。"
        case .paused: return "点击开始预测，继续与 AI 协作。"
        case .environment: return "点击环境检查，查看缺少的本机组件与安装步骤。"
        case .error: return "请检查模型连接，修正后重新预测。"
        case .authorizing: return "请处理 macOS 钥匙串授权弹窗；取消系统授权后可重新配置。窗口仍可正常操作。"
        case .cancelled: return "文稿或页面已变化，请在目标页重新提交修改要求。"
        case .failed: return "写入没有完成，请检查提示后重新预测。"
        }
    }

    func title(elapsed: TimeInterval) -> String {
        switch self {
        case .read, .predict, .search, .render, .apply, .stopping:
            return rawValue + " \(max(0, Int(elapsed)))s"
        default: return rawValue
        }
    }
}
