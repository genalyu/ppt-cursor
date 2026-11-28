import Foundation

public struct BridgeFailure: LocalizedError {
    public let errorDescription: String?
    init(_ message: String) { errorDescription = message }

    static func message(forScriptError detail: String, applying: Bool) -> String {
        if detail.contains("(-1743)") {
            return "请在系统设置 → 隐私与安全性 → 自动化中允许 PPT Cursor 控制 Microsoft PowerPoint，然后返回幻灯片。"
        }
        if detail.contains("(-1712)") {
            return applying
                ? "PowerPoint 未及时确认写入结果。请先核对幻灯片，再点击重新预测。"
                : "读取幻灯片超时。请查看 PowerPoint 或 macOS 是否有等待处理的对话框。"
        }
        if detail.contains("Slide changed since preview") || detail.contains("Missing target") {
            return "当前页或选区已变化，本条建议未写入。请点击重新预测。"
        }
        // Do not expose local script paths, an osascript wrapper, or arbitrary
        // provider/document details in the product's failure message.
        return applying
            ? "PowerPoint 未完成操作。请先核对当前页，再点击重新预测；必要时保存文稿后重试。"
            : "暂时无法读取幻灯片。请确认 PowerPoint 中已打开本地 PPTX、没有未关闭的对话框，然后重试。"
    }
}
