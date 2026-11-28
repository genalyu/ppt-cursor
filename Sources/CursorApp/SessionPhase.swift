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
    case paused = "已暂停"
    case error = "连接异常"

    init?(event: String) {
        switch event {
        case "提供预览": self = .preview
        case "操作": self = .apply
        default:
            guard let phase = Self(rawValue: event) else { return nil }
            self = phase
        }
    }

    func title(elapsed: TimeInterval) -> String {
        switch self {
        case .read, .predict, .search, .render, .apply:
            return rawValue + " \(max(0, Int(elapsed)))s"
        default: return rawValue
        }
    }
}
