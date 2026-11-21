# PPT Cursor for Mac

PPT Cursor 是一个用于 Microsoft PowerPoint 的 macOS 菜单栏应用。它读取当前页和最近几次编辑，将上下文交给 Codex 推断下一步，在画布上显示建议。用户按 **⌥⌘Return** 采纳。每次写入前，应用会重新核对演示文稿、幻灯片和图形状态。

## 本地构建与运行

需要 macOS 13 或更新版本、Microsoft PowerPoint 桌面版、包含 Swift 5.9 或更高版本的 Xcode Command Line Tools，以及已登录的 Codex CLI。当前版本可从 ChatGPT 桌面应用、Homebrew 的 Apple Silicon 路径或 Intel 路径发现 Codex。

```sh
./Scripts/build-app.sh
open "dist/PPT Cursor.app"
```

1. 在 PowerPoint 普通视图中打开要编辑的页面。
2. 点击菜单栏里的叠放矩形图标，选择「定位幻灯片画布」，沿实际页面边缘拖出一个矩形。定位完成后开始预测。
3. 按系统提示允许自动化 PowerPoint。移动或调整几个图形，使编辑意图逐渐明确。
4. 看到青色轮廓时，按 **⌥⌘Return** 或从菜单选择「采纳当前建议」。继续编辑会清除旧建议。「暂停预测」会停止读取新状态。
5. 调整页面缩放、移动窗口或更换显示器后，请重新定位画布。

## 数据与当前支持范围

开始预测后，幻灯片中的文字、图形名称、位置、尺寸、文稿标识及同页最近几次状态会发送给本机登录的 Codex 所使用的模型服务。打开应用时默认暂停。实时状态保存在内存，推断请求使用临时目录。

目前可以采纳原生图形的位置、尺寸、旋转和文字变化。新增矢量素材已有生成及预览路径，插入仍在集成。预览显示轮廓与文字位置；字体与主题效果以 PowerPoint 为准。应用由构建脚本在本地临时签名。

## 开发验证

```sh
swift build
./Scripts/test-history.sh
swift run ppt-inspect
swift run ppt-inspect predict before.json intermediate.json current.json > suggestion.json
swift run ppt-preview current.json suggestion.json preview.png
```

`ppt-inspect` 从当前 PowerPoint 编辑页读取 JSON。开发样本应使用自己的测试文稿。请勿将私有幻灯片内容提交到公开仓库。

MIT License
