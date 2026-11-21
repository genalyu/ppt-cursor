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
    if (proposal.artwork.length) throw Error("Artwork insertion unavailable in this bridge");
    const app = Application("com.microsoft.Powerpoint");
    const slide = app.activePresentation.slides[app.activeWindow.view.slide.slideIndex() - 1];
    const changes = proposal.edits.map(edit => {
        const index = baseline.objects.findIndex(object => object.id === edit.id);
        if (index < 0) throw Error("Missing target");
        return {shape: slide.shapes[index], original: baseline.objects[index], edit};
    });
    function write(shape, p, rotation, text) {
        if (shape.width() !== p.width) shape.width = p.width;
        if (shape.height() !== p.height) shape.height = p.height;
        if (shape.rotation() !== rotation) shape.rotation = rotation;
        if (shape.leftPosition() !== p.x) shape.leftPosition = p.x;
        if (shape.top() !== p.y) shape.top = p.y;
        if (text != null && String(shape.textFrame.textRange.content()) !== text) shape.textFrame.textRange.content = text;
    }
    const started = [];
    try {
        for (const change of changes) {
            started.push(change);
            write(change.shape, change.edit.placement, change.edit.rotation, change.edit.text);
        }
    } catch (error) {
        const failed = [];
        for (const change of started.reverse()) {
            try { write(change.shape, change.original, change.original.rotation, change.original.text); }
            catch (_) { failed.push(change.original.name); }
        }
        if (failed.length) throw Error("Apply failed; could not restore: " + failed.join(", "));
        throw error;
    }
    return snapshot();
}
