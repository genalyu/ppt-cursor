// Executed by macOS's JavaScript for Automation with a read-only PowerPoint object specifier.
function run() {
    const powerpoint = Application("com.microsoft.Powerpoint");
    if (!powerpoint.running() || !powerpoint.presentations.length) return "null";
    const presentation = powerpoint.activePresentation;
    const slide = powerpoint.activeWindow.view.slide;
    const shapes = slide.shapes();
    const page = presentation.pageSetup;
    const objects = shapes.map((shape, index) => {
        let text = null;
        if (shape.hasTextFrame()) text = String(shape.textFrame.textRange.content());
        return {
            id: String(shape.name()) + "#" + index,
            kind: String(shape.shapeType()),
            name: String(shape.name()),
            text: text,
            x: shape.leftPosition(), y: shape.top(),
            width: shape.width(), height: shape.height(), rotation: shape.rotation()
        };
    });
    return JSON.stringify({
        document: String(presentation.fullName() || presentation.name()),
        slideID: slide.slideID(), width: page.slideWidth(), height: page.slideHeight(), objects
    });
}
