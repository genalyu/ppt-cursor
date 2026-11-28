// Executed by macOS's JavaScript for Automation with a read-only PowerPoint object specifier.
function snapshot() {
    const powerpoint = Application("com.microsoft.Powerpoint");
    if (!powerpoint.running() || !powerpoint.presentations.length) return "null";
    const shows = powerpoint.slideShowWindows;
    for (let i = 0; i < shows.length; i++) {
        if (shows[i].active()) return "null";
    }
    const viewType = powerpoint.activeWindow.viewType();
    if (viewType !== "normal view" && viewType !== "slide view") return "null";
    const presentation = powerpoint.activePresentation;
    if (!presentation.slides.length) return "null";
    const index = powerpoint.activeWindow.view.slide.slideIndex();
    if (!index) return "null";
    const slide = presentation.slides[index - 1];
    const shapes = slide.shapes;
    const page = presentation.pageSetup;
    const nameCounts = new Map();
    const objects = Array.from({length: shapes.length}, (_, index) => {
        const shape = shapes[index];
        const name = String(shape.name());
        // Unrelated insertions and layer moves must not change this object's history key.
        const occurrence = (nameCounts.get(name) || 0) + 1;
        nameCounts.set(name, occurrence);
        let text = null;
        if (shape.hasTextFrame()) text = String(shape.textFrame.textRange.content());
        let fontSize, textBold, textItalic;
        if (text) {
            // PowerPoint reports the first run's size for the entire range, including mixed text.
            const runs = shape.textFrame.textRange.textFlows;
            const count = runs.length;
            if (count > 0 && count <= 64) {
                const size = runs[0].font.fontSize();
                let uniform = Number.isFinite(size) && size > 0;
                for (let i = 1; uniform && i < count; i++) uniform = runs[i].font.fontSize() === size;
                if (uniform) fontSize = size;
                const uniformFlag = property => {
                    const value = runs[0].font[property]();
                    if (typeof value !== "boolean") return undefined;
                    for (let i = 1; i < count; i++) if (runs[i].font[property]() !== value) return undefined;
                    return value;
                };
                textBold = uniformFlag("bold");
                textItalic = uniformFlag("italic");
            }
        }
        const kind = String(shape.shapeType());
        let solidFillRGB, fillTransparency;
        if (kind === "shape type auto" || kind === "shape type text box") {
            const fill = shape.fillFormat;
            if (fill.visible() && fill.fillFormatType() === "fill solid") {
                const transparency = fill.transparency();
                if (Number.isFinite(transparency) && transparency >= 0 && transparency <= 1) fillTransparency = transparency;
                const rgb = fill.foreColor();
                if (Array.isArray(rgb) && rgb.length === 3 &&
                    rgb.every(value => Number.isInteger(value) && value >= 0 && value <= 255)) solidFillRGB = rgb;
            }
        }
        let table;
        if (kind === "shape type table") {
            const rows = shape.numberOfRows(), columns = shape.numberOfColumns();
            const visibleSample = [];
            const cellsByRow = shape.tableObject.rows;
            let previousRow = [];
            for (let r = 0; r < Math.min(rows, 8); r++) {
                const cells = cellsByRow[r].cells, values = [], row = [];
                for (let c = 0; c < Math.min(columns, 8); c++) {
                    const cell = cells[c].shape;
                    const value = String(cell.textFrame.textRange.content()).slice(0, 512);
                    // PowerPoint returns the same text and origin at every coordinate of a merged cell.
                    const neighbors = [row[c - 1], previousRow[c]];
                    const merged = value !== "" && neighbors.some(other => other && other.value === value &&
                        other.cell.leftPosition() === cell.leftPosition() && other.cell.top() === cell.top());
                    row.push({value, cell});
                    values.push(merged ? null : value);
                }
                visibleSample.push(values);
                previousRow = row;
            }
            table = {rows, columns, visibleSample};
        }
        return {
            table, fontSize, textBold, textItalic, solidFillRGB, fillTransparency,
            autoShapeType: kind === "shape type auto" ? String(shape.autoShapeType()) : undefined,
            id: JSON.stringify([name, occurrence]),
            kind,
            name,
            text: text,
            x: shape.leftPosition(), y: shape.top(),
            width: shape.width(), height: shape.height(), rotation: shape.rotation()
        };
    });
    const selectedIDs = [];
    const selection = powerpoint.activeWindow.selection;
    const selectionType = selection.selectionType();
    if (selectionType === "selection type shapes" || selectionType === "selection type text") {
        const selected = selection.shapeRange.shapes;
        for (let i = 0; i < selected.length; i++) {
            const item = selected[i];
            const name = item.name();
            let matches = objects.filter(object => object.name === name);
            if (matches.length > 1) {
                const x = item.leftPosition(), y = item.top();
                matches = matches.filter(object => object.x === x && object.y === y);
            }
            if (matches.length === 1) selectedIDs.push(matches[0].id);
        }
    }
    let textSelection;
    if (selectionType === "selection type text") {
        const range = selection.textRange;
        const offset = range.offset(), length = range.textLength();
        if (Number.isInteger(offset) && Number.isInteger(length)) textSelection = {offset, length};
    }
    return JSON.stringify({
        textSelection,
        editingText: selectionType === "selection type text",
        viewZoom: powerpoint.activeWindow.view.zoom(), selectedIDs,
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
    if (args.length === 1 && args[0] === "document") {
        const app = Application("com.microsoft.Powerpoint");
        if (!app.running() || !app.presentations.length) return "null";
        return JSON.stringify(String(app.activePresentation.fullName() || ""));
    }
    if (args.length === 1 && args[0] === "settled") {
        ObjC.import("AppKit");
        const ready = () => Number($.NSEvent.pressedMouseButtons) === 0 &&
            String(ObjC.unwrap($.NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier)).toLowerCase() === "com.microsoft.powerpoint";
        if (!ready()) return JSON.stringify("deferred");
        const result = snapshot();
        return ready() ? result : JSON.stringify("deferred");
    }
    if (args.length !== 2 || args[0] !== "apply") throw Error("Invalid bridge request");
    ObjC.import("Foundation");
    const source = $.NSString.stringWithContentsOfFileEncodingError(args[1], $.NSUTF8StringEncoding, null);
    const request = JSON.parse(ObjC.unwrap(source));
    const baseline = JSON.parse(snapshot());
    for (const object of request.baseline.objects) { if (object.text === undefined) object.text = null; }
    if (baseline && request.baseline.selectedIDs === undefined) delete baseline.selectedIDs;
    if (baseline && request.baseline.editingText === undefined) delete baseline.editingText;
    if (baseline && request.baseline.textSelection === undefined) delete baseline.textSelection;
    if (baseline && request.baseline.viewZoom === undefined) delete baseline.viewZoom;
    if (!sameState(baseline, request.baseline)) throw Error("Slide changed since preview");
    const proposal = request.nativeInsert ? {edits: [], artwork: []} : request.proposal;

    const app = Application("com.microsoft.Powerpoint");
    const slide = app.activePresentation.slides[app.activeWindow.view.slide.slideIndex() - 1];
    const changes = proposal.edits.map(edit => {
        const index = baseline.objects.findIndex(object => object.id === edit.id);
        if (index < 0) throw Error("Missing target");
        return {shape: slide.shapes[index], original: baseline.objects[index], edit};
    });
    function write(shape, p, rotation, text, fontSize, fill, textBold, textItalic) {
        // PowerPoint couples both dimensions when aspect locking is enabled. Write the
        // previewed geometry as a pair, then restore the editor's original lock setting.
        // The PowerPoint Apple event bridge drops bare line feeds.
        const nativeText = text == null ? null : text.replace(/\r\n|\n/g, "\r");
        const close = (a, b) => Math.abs(a - b) <= 0.02;
        const resize = !close(shape.width(), p.width) || !close(shape.height(), p.height);
        const locked = resize && shape.lockAspectRatio() === true;
        if (locked) shape.lockAspectRatio = false;
        try {
            if (fill != null && !sameState(shape.fillFormat.foreColor(), fill)) shape.fillFormat.foreColor = fill;
            if (nativeText != null && String(shape.textFrame.textRange.content()) !== nativeText) {
                shape.textFrame.textRange.content = nativeText;
            }
            if (fontSize != null && !close(shape.textFrame.textRange.font.fontSize(), fontSize)) {
                shape.textFrame.textRange.font.fontSize = fontSize;
            }
            if (textBold != null) shape.textFrame.textRange.font.bold = textBold;
            if (textItalic != null) shape.textFrame.textRange.font.italic = textItalic;
            if (!close(shape.width(), p.width)) shape.width = p.width;
            if (!close(shape.height(), p.height)) shape.height = p.height;
            if (!close(shape.rotation(), rotation)) shape.rotation = rotation;
            if (!close(shape.leftPosition(), p.x)) shape.leftPosition = p.x;
            if (!close(shape.top(), p.y)) shape.top = p.y;
        } finally {
            if (locked) shape.lockAspectRatio = true;
        }
        if (nativeText != null && String(shape.textFrame.textRange.content()) !== nativeText) throw Error("文字与预览不符");
        if (fill != null && !sameState(shape.fillFormat.foreColor(), fill)) throw Error("填充颜色与预览不符");
        if (fontSize != null && !close(shape.textFrame.textRange.font.fontSize(), fontSize)) throw Error("字号与预览不符");
        for (const [property, expected] of [["bold", textBold], ["italic", textItalic]]) {
            if (expected == null) continue;
            const runs = shape.textFrame.textRange.textFlows;
            if (!runs.length) throw Error("文字样式与预览不符");
            for (let i = 0; i < runs.length; i++) {
                if (runs[i].font[property]() !== expected) throw Error("文字样式与预览不符");
            }
        }
        const angleDifference = ((shape.rotation() - rotation) % 360 + 540) % 360 - 180;
        if (!close(shape.width(), p.width) || !close(shape.height(), p.height) ||
            !close(shape.leftPosition(), p.x) || !close(shape.top(), p.y) || !close(angleDifference, 0)) {
            throw Error("PowerPoint 返回的图形位置或尺寸与预览不符");
        }
    }
    // Paste through PowerPoint's native view; keep every existing pasteboard item/type.
    // Only restore our temporary pasteboard if another app hasn't copied something meanwhile.
    function pasteArtwork(asset, copySource) {
        ObjC.import("AppKit");
        const board = $.NSPasteboard.generalPasteboard;
        const originalVersion = board.changeCount;
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
        const data = copySource ? null : asset.referenceID
            ? $.NSData.alloc.initWithBase64EncodedStringOptions($(request.sources[asset.referenceID]), 0)
            : $(asset.svg).dataUsingEncoding($.NSUTF8StringEncoding);
        const image = data ? $.NSImage.alloc.initWithData(data) : null;
        if (!copySource && (!image || !image.isValid)) throw Error("无法渲染建议素材");
        const count = slide.shapes.length;
        let vectorURL = null;
        if (!copySource && (!asset.referenceID || request.vectorIDs.includes(asset.referenceID))) {
            const path = args[1] + "-" + ObjC.unwrap($.NSUUID.UUID.UUIDString) + ".svg";
            vectorURL = $.NSURL.fileURLWithPath($(path));
            if (!data.writeToURLAtomically(vectorURL, true)) throw Error("无法准备矢量素材");
        }
        if (board.changeCount !== originalVersion) {
            if (vectorURL) $.NSFileManager.defaultManager.removeItemAtURLError(vectorURL, null);
            throw Error("剪贴板已更新，请重试采纳");
        }
        board.clearContents;
        let version = board.changeCount;
        try {
            if (copySource) {
                copySource.copyShape();
            } else {
                let item = vectorURL;
                if (!item) {
                    item = $.NSPasteboardItem.alloc.init;
                    if (!item.setDataForType(data, $("public.png")) ||
                        !item.setDataForType(image.TIFFRepresentation, $("public.tiff"))) throw Error("无法准备图片");
                }
                const prepared = board.writeObjects($([item]));
                if (!prepared) throw Error("无法准备素材");
            }
            version = board.changeCount;
            if (request.nativeInsert && (!app.frontmost() || snapshot() !== asset.original)) throw Error("原幻灯片状态已变化");
            app.activeWindow.view.pasteObject();
            if (slide.shapes.length !== count + 1) throw Error("PowerPoint 未返回新增对象");
            const shape = slide.shapes[count];
            inserted.push(shape);
            if (request.nativeInsert) {
                shape.leftPosition = asset.x;
                shape.top = asset.y;
                return;
            }
            write(shape, asset.placement, asset.rotation || 0, asset.text, asset.fontSize, asset.solidFillRGB, asset.textBold, asset.textItalic);
        } finally {
            if (vectorURL) $.NSFileManager.defaultManager.removeItemAtURLError(vectorURL, null);
            if (board.changeCount === version) {
                board.clearContents;
                if (saved.length) board.writeObjects($(saved));
            }
        }
    }
    const inserted = [];
    const started = [];
    if (!app.frontmost()) throw Error("PowerPoint 已切至后台，建议未执行");
    try {
        if (request.nativeInsert && request.nativeInsert.presetTarget) {
            const native = request.nativeInsert;
            const index = baseline.objects.findIndex(object => object.id === native.presetTarget);
            if (index < 0 || !baseline.objects[index].autoShapeType) throw Error("原形状已变化");
            const original = snapshot();
            app.open(Path(native.path));
            const deck = app.presentations.byName(native.path.split("/").pop());
            let preset, placement;
            try {
                const source = deck.slides[native.page - 1].shapes[index];
                if (source.name() !== native.name) throw Error("建议图形与预览不符");
                preset = source.autoShapeType();
                placement = {x: source.leftPosition(), y: source.top(), width: source.width(),
                             height: source.height(), rotation: source.rotation()};
            } finally { deck.close({saving: "no"}); }
            if (!app.frontmost() || snapshot() !== original) throw Error("原幻灯片状态已变化");
            const shape = slide.shapes[index], previous = shape.autoShapeType();
            try {
                shape.autoShapeType = preset;
                write(shape, placement, placement.rotation);
                const expected = JSON.parse(original), actual = JSON.parse(snapshot());
                // write() has verified native point and rotation tolerances.
                for (const key of Object.keys(placement)) expected.objects[index][key] = actual.objects[index][key];
                expected.objects[index].autoShapeType = String(preset);
                if (!sameState(actual, expected)) throw Error("更换形状后的属性与预览不符");
            } catch (error) {
                shape.autoShapeType = previous;
                write(shape, baseline.objects[index], baseline.objects[index].rotation);
                throw error;
            }
        } else if (request.nativeInsert) {
            const native = request.nativeInsert, position = {original: snapshot()};
            pasteArtwork(position, {copyShape() {
                app.open(Path(native.path));
                const deck = app.presentations.byName(native.path.split("/").pop());
                try {
                    const shapes = deck.slides[native.page - 1].shapes;
                    const source = shapes[shapes.length - 1];
                    if (source.name() !== native.name) throw Error("建议图形与预览不符");
                    position.x = source.leftPosition();
                    position.y = source.top();
                    source.copyShape();
                } finally { deck.close({saving: "no"}); }
            }});
        }
        for (const change of changes.filter(change => change.edit.duplicate)) {
            pasteArtwork(change.edit, change.shape);
        }
        for (const change of changes.filter(change => !change.edit.duplicate)) {
            started.push(change);
            write(change.shape, change.edit.placement, change.edit.rotation, change.edit.text, change.edit.fontSize, change.edit.solidFillRGB, change.edit.textBold, change.edit.textItalic);
        }
        for (const asset of proposal.artwork) pasteArtwork(asset);
    } catch (error) {
        const failed = [];
        for (const shape of inserted.reverse()) {
            try { app.delete(shape); } catch (_) { failed.push("新增素材"); }
        }
        for (const change of started.reverse()) {
            try { write(change.shape, change.original, change.original.rotation, change.original.text, change.edit.fontSize == null ? null : change.original.fontSize, change.edit.solidFillRGB == null ? null : change.original.solidFillRGB, change.edit.textBold == null ? null : change.original.textBold, change.edit.textItalic == null ? null : change.original.textItalic); }
            catch (_) { failed.push(change.original.name); }
        }
        if (failed.length) throw Error("Apply failed; could not restore: " + failed.join(", "));
        throw error;
    }
    return snapshot();
}
