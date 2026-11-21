# PPT Cursor for Mac

PPT Cursor 是一个用于 Microsoft PowerPoint 的 macOS 菜单栏应用。它读取当前页和最近几次编辑，将上下文交给所选模型推断下一步，在画布上显示建议。用户按 **⌥⌘Return** 采纳。每次写入前，应用会重新核对演示文稿、幻灯片和图形状态。

## 下载 Mac 测试版

[下载 Apple Silicon 版 ZIP](https://raw.githubusercontent.com/genalyu/ppt-cursor/416d8df258a835f5c8ff36cbbbf4b8cbd1ecabf0/PPT-Cursor-macOS-arm64.zip) · [SHA-256 校验文件](https://raw.githubusercontent.com/genalyu/ppt-cursor/416d8df258a835f5c8ff36cbbbf4b8cbd1ecabf0/PPT-Cursor-macOS-arm64.zip.sha256)

解压后打开 PPT Cursor。测试包需要 macOS 13 或更新版本、PowerPoint，以及已登录的 Codex CLI 或 OpenAI API 密钥。此构建使用本地临时签名，尚未通过 Apple 公证。Intel Mac 可使用下方源码构建方式。

## 本地构建与运行

需要 macOS 13 或更新版本、Microsoft PowerPoint 桌面版、包含 Swift 5.9 或更高版本的 Xcode Command Line Tools，以及已登录的 Codex CLI 或 OpenAI API 密钥。当前版本可从 ChatGPT 桌面应用、Homebrew 的 Apple Silicon 路径或 Intel 路径发现 Codex。

```sh
./Scripts/build-app.sh
open "dist/PPT Cursor.app"
```

1. 在 PowerPoint 普通视图中打开要编辑的页面。
2. 在 PPT Cursor 启动窗口点击「定位画布并开始」，应用会在已有屏幕读取权限时尝试识别浅色页面边界。进入框选模式时，沿 PowerPoint 窗口内的实际页面边缘拖出一个矩形。默认仅在本机处理窗口像素。在控制窗口勾选「向模型提供当前幻灯片截图」后，每次预测会重新核对页面边界，并将匹配的页面裁图提供给模型；无法确认边界时使用对象与历史数据。也可以从菜单栏重新定位。定位完成后开始预测。
3. 按系统提示允许自动化 PowerPoint。移动或调整几个图形，使编辑意图逐渐明确。
4. 看到青色轮廓时，按 **⌥⌘Return**、点击页面边缘的「采纳」，或从菜单选择「采纳当前建议」。继续编辑会清除旧建议。「暂停预测」会停止读取新状态。
5. 拖动同一个 PowerPoint 窗口时，预览跟随窗口移动。改变窗口大小、切换到另一个演示文稿窗口或调整页面缩放后，请重新定位画布。

## 选择模型连接

默认使用本机 Codex 登录。也可从控制窗口点击「模型连接…」，填写支持图像输入及结构化输出的 OpenAI 模型名称和 API 密钥，再选择「使用 API」。此模式通过 Responses API 预测，按该 API 账户的用量计费。密钥只在本次运行的内存中使用。退出应用后恢复默认连接。

## 数据与当前支持范围

开始预测后，幻灯片中的文字、图形名称、位置、尺寸、文稿标识及同页最近几次状态会发送给所选连接的模型服务。打开应用时默认暂停。实时状态保存在内存，推断请求使用临时目录。

目前可以采纳原生图形的位置、尺寸、旋转和文字变化。模型可生成独立 SVG 素材，预览后通过 PowerPoint 原生粘贴插入为可移动、缩放的图片。当前使用 TIFF 渲染插图。预览显示轮廓与文字位置；字体与主题效果以 PowerPoint 为准。应用由构建脚本在本地临时签名。

## 验证记录

在 Mac 版 PowerPoint 的三卡片测试文稿中，将前两张卡片的纵坐标从 220 改到 112 后，真实模型建议第三张上移 108 点。应用显示预览后，测试程序投递 macOS Carbon 快捷键事件，随后从 PowerPoint 读回三个对象的纵坐标均为 112。该项覆盖应用收到快捷键事件后的采纳和写入流程。物理键盘触发系统全局快捷键仍待独立验收。

锁定宽高比的图片已验证可按预览分别写入宽度和高度。测试从 192 × 96 调整到 180 × 80，再恢复到 192 × 96，两次都读回目标尺寸并保留原来的锁定状态。

## 开发验证

```sh
swift build
./Scripts/test-history.sh
./Scripts/test-api-prediction.sh
swift run ppt-inspect
swift run ppt-inspect predict before.json intermediate.json current.json > suggestion.json
swift run ppt-preview current.json suggestion.json preview.png
```

`ppt-inspect` 从当前 PowerPoint 编辑页读取 JSON。开发样本应使用自己的测试文稿。请勿将私有幻灯片内容提交到公开仓库。

MIT License

### 提供已有图片

从菜单中选择「选择本次编辑的图片素材…」即可载入 PNG、JPEG、HEIC 或 TIFF，可一次选择多张。预测时，模型会看到所选素材的文件名和缩略图；模型选择某张图片后，画布预览和最终插入均使用同一份本地像素数据。应用保留方向和透明度，长边最多 3072 像素。可在菜单中随时清空素材。

带素材的预测也可通过命令行复现。每个 `--image` 对应一张图片，后续 JSON 文件按编辑时间排序。

```sh
swift run ppt-inspect predict --image swatch.png before.json current.json
```

临时离开 PowerPoint 时，应用会隐藏预览并释放快捷键。返回同一页后会核对内容，再恢复仍然有效的建议。命令行启动时可以传入 `--start-editing` 直接定位当前页，或用 `--verbose` 将状态与建议输出到终端。
