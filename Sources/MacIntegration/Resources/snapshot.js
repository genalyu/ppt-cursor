// Executed by macOS's JavaScript for Automation with a read-only PowerPoint object specifier.
function snapshot() {
    const powerpoint = Application("com.microsoft.Powerpoint");
    if (!powerpoint.running() || !powerpoint.presentations.length) return "null";
    const presentation = powerpoint.activePresentation;
    if (!presentation.slides.length) return "null";
    const index = powerpoint.activeWindow.view.slide.slideIndex();
    if (!index) return "null";
    const slide = presentation.slides[index - 1];
    const shapes = slide.shapes;
    const page = presentation.pageSetup;
    const objects = Array.from({length: shapes.length}, (_, index) => {
        const shape = shapes[index];
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
        slideID: slide.slideID(), width: page.slideWidth(), height: presentation.slideMaster.height(), objects
    });
}

function sameState(actual, expected) {
    if (!actual || !expected) return actual === expected;
    if (typeof actual !== "object" || typeof expected !== "object") return actual === expected;
    const keys = Object.keys(actual);
    return keys.length === Object.keys(expected).length &&
        keys.every(key => Object.prototype.hasOwnProperty.call(expected, key) && sameState(actual[key], expected[key]));
}

function run(args) {
    if (!args.length) return snapshot();
    if (args.length !== 2 || args[0] !== "apply") throw Error("Invalid bridge request");
    ObjC.import("Foundation");
    const source = $.NSString.stringWithContentsOfFileEncodingError(args[1], $.NSUTF8StringEncoding, null);
    const request = JSON.parse(ObjC.unwrap(source));
    const baseline = JSON.parse(snapshot());
    for (const object of request.baseline.objects) { if (object.text === undefined) object.text = null; }
    if (!sameState(baseline, request.baseline)) throw Error("Slide changed since preview");
    const proposal = request.proposal;

    const app = Application("com.microsoft.Powerpoint");
    const slide = app.activePresentation.slides[app.activeWindow.view.slide.slideIndex() - 1];
    const changes = proposal.edits.map(edit => {
        const index = baseline.objects.findIndex(object => object.id === edit.id);
        if (index < 0) throw Error("Missing target");
        return {shape: slide.shapes[index], original: baseline.objects[index], edit};
    });
    function write(shape, p, rotation, text) {
        // PowerPoint couples both dimensions when aspect locking is enabled. Write the
        // previewed geometry as a pair, then restore the editor's original lock setting.
        const close = (a, b) => Math.abs(a - b) <= 0.02;
        const resize = !close(shape.width(), p.width) || !close(shape.height(), p.height);
        const locked = resize && shape.lockAspectRatio() === true;
        if (locked) shape.lockAspectRatio = false;
        try {
            if (text != null && String(shape.textFrame.textRange.content()) !== text) {
                shape.textFrame.textRange.content = text;
            }
            if (!close(shape.width(), p.width)) shape.width = p.width;
            if (!close(shape.height(), p.height)) shape.height = p.height;
            if (!close(shape.rotation(), rotation)) shape.rotation = rotation;
            if (!close(shape.leftPosition(), p.x)) shape.leftPosition = p.x;
            if (!close(shape.top(), p.y)) shape.top = p.y;
        } finally {
            if (locked) shape.lockAspectRatio = true;
        }
        const angleDifference = ((shape.rotation() - rotation) % 360 + 540) % 360 - 180;
        if (!close(shape.width(), p.width) || !close(shape.height(), p.height) ||
            !close(shape.leftPosition(), p.x) || !close(shape.top(), p.y) || !close(angleDifference, 0)) {
            throw Error("PowerPoint 返回的图形位置或尺寸与预览不符");
        }
    }
    // Paste through PowerPoint's native view; keep every existing pasteboard item/type.
    // Only restore our temporary pasteboard if another app hasn't copied something meanwhile.
    function pasteArtwork(asset) {
        ObjC.import("AppKit");
        const board = $.NSPasteboard.generalPasteboard;
        const saved = [];
        const existing = board.pasteboardItems;
        for (let i = 0; i < existing.count; i++) {
            const source = existing.objectAtIndex(i), copy = $.NSPasteboardItem.alloc.init;
            const types = source.types;
            for (let t = 0; t < types.count; t++) {
                const type = types.objectAtIndex(t), data = source.dataForType(type);
                if (!data || !copy.setDataForType(data, type)) throw Error("无法保存原剪贴板内容");
            }
            saved.push(copy);
        }
        const data = asset.referenceID
            ? $.NSData.alloc.initWithBase64EncodedStringOptions($(request.sources[asset.referenceID]), 0)
            : $(asset.svg).dataUsingEncoding($.NSUTF8StringEncoding);
        const image = $.NSImage.alloc.initWithData(data);
        if (!image || !image.isValid) throw Error("无法渲染建议素材");
        const count = slide.shapes.length;
        board.clearContents;
        let version = board.changeCount;
        try {
            if (!board.setDataForType(image.TIFFRepresentation, $("public.tiff"))) throw Error("无法准备素材");
            version = board.changeCount;
            app.activeWindow.view.pasteObject();
            if (slide.shapes.length !== count + 1) throw Error("PowerPoint 未返回新增图片");
            const shape = slide.shapes[count];
            inserted.push(shape);
            write(shape, asset.placement, 0, null);
        } finally {
            if (board.changeCount === version) {
                board.clearContents;
                if (saved.length) board.writeObjects($(saved));
            }
        }
    }
    const inserted = [];
    const started = [];
    try {
        for (const change of changes) {
            started.push(change);
            write(change.shape, change.edit.placement, change.edit.rotation, change.edit.text);
        }
        for (const asset of proposal.artwork) pasteArtwork(asset);
    } catch (error) {
        const failed = [];
        for (const shape of inserted.reverse()) {
            try { app.delete(shape); } catch (_) { failed.push("新增素材"); }
        }
        for (const change of started.reverse()) {
            try { write(change.shape, change.original, change.original.rotation, change.original.text); }
            catch (_) { failed.push(change.original.name); }
        }
        if (failed.length) throw Error("Apply failed; could not restore: " + failed.join(", "));
        throw error;
    }
    return snapshot();
}
