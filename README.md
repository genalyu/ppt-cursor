# PPT Cursor for Mac

PPT Cursor 是一个用于 Microsoft PowerPoint 的 macOS 菜单栏应用。它读取当前页和最近几次编辑，将上下文交给所选模型推断下一步，在画布上显示建议。默认按 **⌥⌘Return** 采纳。也可在菜单栏勾选「用 Tab 采纳可见建议」，只在 PowerPoint 位于前台且有建议时启用 Tab。编辑文本期间，采纳键会切换为 ⌥⌘Return，面板会显示当前快捷键。每次写入前，应用会重新核对演示文稿、幻灯片和图形状态。

## 下载 Mac 测试版

[下载 Preview 21 · Apple Silicon ZIP](https://github.com/genalyu/ppt-cursor/releases/download/v0.1.0-preview.21/PPT-Cursor-macOS-arm64.zip) · [SHA-256 校验文件](https://github.com/genalyu/ppt-cursor/releases/download/v0.1.0-preview.21/PPT-Cursor-macOS-arm64.zip.sha256)

解压后打开 PPT Cursor。测试包需要 macOS 13 或更新版本、PowerPoint，以及已登录的 Codex CLI 或 OpenAI API 密钥。此构建使用本地临时签名，尚未通过 Apple 公证。Intel Mac 可使用下方源码构建方式。

## 试一次拖动预测

用 PowerPoint 打开[对齐示例](https://raw.githubusercontent.com/genalyu/ppt-cursor/main/Examples/Tab-Demo.pptx)，在 PPT Cursor 中点击「定位画布并开始」。依次将 Research 和 Design 两个文本框各向上拖动约 2 厘米，使它们的上边缘齐平，暂时保留 Deliver 的位置。模型可能建议将 Deliver 上移到同一高度。看到预览后，按面板显示的快捷键采纳。要使用 Tab，请先在菜单栏勾选「用 Tab 采纳可见建议」。

## 本地构建与运行

需要 macOS 13 或更新版本、Microsoft PowerPoint 桌面版、包含 Swift 5.9 或更高版本的 Xcode Command Line Tools，以及已登录的 Codex CLI 或 OpenAI API 密钥。当前版本可从 ChatGPT 桌面应用、Homebrew 的 Apple Silicon 路径或 Intel 路径发现 Codex。

```sh
./Scripts/build-app.sh
open "dist/PPT Cursor.app"
```

1. 在 PowerPoint 普通视图中打开要编辑的页面。
2. 在 PPT Cursor 启动窗口点击「定位画布并开始」，应用会在已有屏幕读取权限时尝试识别浅色页面边界。进入框选模式时，沿 PowerPoint 窗口内的实际页面边缘拖出一个矩形。默认仅在本机处理窗口像素。在控制窗口勾选「向模型提供当前幻灯片截图」后，每次预测会重新核对页面边界，并将匹配的页面裁图提供给模型；无法确认边界时使用对象与历史数据。也可以从菜单栏重新定位。定位完成后开始预测。
3. 按系统提示允许自动化 PowerPoint。移动或调整几个图形，使编辑意图逐渐明确。
4. 看到青色轮廓时，按 **⌥⌘Return**、点击页面边缘的「采纳」，或从菜单选择「采纳当前建议」。继续编辑会清除旧建议。「暂停预测」会停止读取新状态。模型请求失败后，可在菜单中选择「重试上次预测」。应用会重新读取当前页，确认编辑状态仍然匹配后再请求模型。
5. 拖动同一个 PowerPoint 窗口时，预览跟随窗口移动。改变窗口大小、切换到另一个演示文稿窗口或调整页面缩放后，请重新定位画布。

### 发布者签名和公证

发布者可将 `PPT_CURSOR_SIGN_IDENTITY` 设为钥匙串中的 Developer ID Application 证书名，将 `PPT_CURSOR_NOTARY_PROFILE` 设为已配置的 notarytool 钥匙串配置名，然后运行 `./Scripts/package-mac.sh`。脚本会签名、提交公证、将票据附加到应用，并解压最终 ZIP 检查票据。默认本地构建使用临时签名。

## 选择模型连接

默认使用本机 Codex 登录。也可从控制窗口点击「模型连接…」，填写支持图像输入及结构化输出的 OpenAI 模型名称和 API 密钥，再选择「使用 API」。此模式通过 Responses API 预测，按该 API 账户的用量计费。密钥只在本次运行的内存中使用。退出应用后恢复默认连接。

## 数据与当前支持范围

开始预测后，幻灯片中的文字、图形名称、位置、尺寸、文稿标识及同页最近几次状态会发送给所选连接的模型服务。打开应用时默认暂停。实时状态保存在内存，推断请求使用临时目录。

临时翻页时，应用在本机保留最近离开的三页编辑历史。返回内容未变的页面后，新的编辑可以延续该页此前的操作。切换文稿会清空缓存。

预测上下文包含当前页原生表格的总行列数和左上角最多 8 行 × 8 列的文字，每格最多 512 个字符。合并标题的延续位置会标记出来。

模型可以建议移动、缩放、旋转、修改文字、调整统一字号或更改已有纯色填充，也可以在指定位置创建可编辑的原生对象副本，为副本设置新文字。模型可生成独立 SVG 素材，预览后通过 PowerPoint 原生粘贴插入为可移动、缩放的图片。生成的 SVG 以矢量格式嵌入 PPTX，放大后仍保留路径细节。页面边界可核实时，移动或缩放未旋转、无遮挡的图片会在目标位置显示半透明原图。其他原生对象显示轮廓与文字位置，字体与主题效果以 PowerPoint 为准。应用由构建脚本在本地临时签名。

## 验证记录

在 Mac 版 PowerPoint 的三卡片测试文稿中，将前两张卡片的纵坐标从 220 改到 112 后，真实模型建议第三张上移 108 点。应用显示预览后，测试程序投递 macOS Carbon 快捷键事件，随后从 PowerPoint 读回三个对象的纵坐标均为 112。该项覆盖应用收到快捷键事件后的采纳和写入流程。物理键盘触发系统全局快捷键仍待独立验收。

锁定宽高比的图片已验证可按预览分别写入宽度和高度。测试从 192 × 96 调整到 180 × 80，再恢复到 192 × 96，两次都读回目标尺寸并保留原来的锁定状态。

## 试用原生图形预测

Preview 21 可从菜单栏选择「在终端启动开放式预测…」，再选择已经打开的本地 PPTX。切回 PowerPoint 后编辑，按 Control-C 结束终端中的会话。启动开放式会话前勾选「向模型提供当前幻灯片截图」，模型还会收到由 LibreOffice 渲染的当前页图像。可直接写回的建议会显示采纳按钮和可用快捷键。源码版还支持将其余复杂图形建议另存为可编辑的 PPTX 副本。此模式需要已登录的 Codex CLI、LibreOffice 和安装了 Pillow 的 Python 3。也可以直接运行包内脚本：

```sh
python3 "/Applications/PPT Cursor.app/Contents/Resources/stage-drawing.py" session "/path/to/slides.pptx"
```

### 从源码启动

在 PowerPoint 中打开本地 PPTX，从仓库运行下列命令。需要 Swift、已登录的 Codex CLI、LibreOffice，以及安装了 Pillow 的 Python 3。源码版在缺少 Poppler 时使用 macOS 自带的 `sips` 渲染预览。

```sh
python3 Scripts/stage-drawing.py session Examples/Tab-Demo.pptx
```

切回 PowerPoint 后移动图形。连续编辑稳定后，模型会结合当前页与历史生成 DrawingML，应用在临时副本中渲染差异。画布面板会显示建议及可用的采纳方式。支持写回位置、尺寸、旋转、单段文字、明确指定的 RGB 纯色填充，以及能从已有对象复制得到的原生图形。其他修改目前仅供预览。可追加 `--reference 图片路径` 提供参考素材。按 Control-C 结束监听。

## 开发验证

```sh
swift build
./Scripts/test-history.sh
./Scripts/test-api-prediction.sh
swift run ppt-inspect
swift run ppt-inspect predict before.json intermediate.json current.json > suggestion.json
swift run ppt-preview current.json suggestion.json preview.png
swift run ppt-inspect render Examples/Tab-Demo.pptx 1 slide.png
swift run ppt-preview --page slide.png current.json suggestion.json preview.png
```

`ppt-inspect` 从当前 PowerPoint 编辑页读取 JSON。开发样本应使用自己的测试文稿。请勿将私有幻灯片内容提交到公开仓库。

MIT License

### 提供已有图片

从菜单中选择「选择本次编辑的图片素材…」即可载入 PNG、JPEG、HEIC、TIFF 或自包含 SVG，可一次选择多张。预测时，模型会看到所选素材的文件名和缩略图；模型选择某张图片后，画布预览和最终插入均使用同一份本地像素数据。位图保留方向和透明度，长边最多 3072 像素。支持的 SVG 在预览和插入时使用原始矢量文件。可在菜单中随时清空素材。

带素材的预测也可通过命令行复现。每个 `--image` 对应一张图片，后续 JSON 文件按编辑时间排序。

```sh
swift run ppt-inspect predict --image swatch.png current.json
```

临时离开 PowerPoint 时，应用会隐藏预览并释放快捷键。返回同一页后会核对内容，再恢复仍然有效的建议。命令行启动时可以传入 `--start-editing` 直接定位当前页，或用 `--verbose` 将状态与建议输出到终端。
