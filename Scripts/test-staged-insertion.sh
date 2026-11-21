#!/bin/bash
# Exercise the staged-preview acceptance bridge against a disposable PowerPoint deck.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product PPTCursor
bin=$(swift build -c release --show-bin-path)
dir=$(mktemp -d "$HOME/Library/Containers/com.microsoft.Powerpoint/Data/tmp/ppt-cursor-insert-XXXXXX")
name=$(basename "$dir").pptx
cleanup() {
    osascript - "$name" <<'APPLE' >/dev/null 2>&1 || true
on run argv
    set deckName to item 1 of argv
    tell application "Microsoft PowerPoint"
        if exists presentation deckName then close presentation deckName saving no
    end tell
end run
APPLE
    rm -rf "$dir"
}
trap cleanup EXIT
cp Examples/Tab-Demo.pptx "$dir/$name"
cat > "$dir/shape.xml" <<'XML'
<p:sp><p:nvSpPr><p:cNvPr id="1" name="Generated Chevron"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
<p:spPr><a:xfrm><a:off x="1200000" y="2000000"/><a:ext cx="1800000" cy="650000"/></a:xfrm>
<a:prstGeom prst="chevron"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="5370EA"/></a:solidFill></p:spPr></p:sp>
XML
python3 Scripts/stage-drawing.py "$dir/$name" ppt/slides/slide1.xml "$dir/shape.xml" "$dir/after.pptx"
python3 - "$dir" <<'PY'
import hashlib,json,sys
from pathlib import Path
d=Path(sys.argv[1])
(d/'target.json').write_text(json.dumps(dict(operation='insert',page=1,slideID=256,name='Generated Chevron',
    candidateSHA256=hashlib.sha256((d/'after.pptx').read_bytes()).hexdigest())))
PY
cat > "$dir/main.swift" <<'SWIFT'
import Foundation
import MacIntegration
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let doc = folder.appendingPathComponent(CommandLine.arguments[2])
guard let before = try PowerPointBridge.capture(),
      URL(fileURLWithPath: before.document).resolvingSymlinksInPath() == doc.resolvingSymlinksInPath() else {
    fatalError("Test presentation must be active")
}
let after = try PowerPointBridge.insertStagedShape(from: folder, into: before)
precondition(after.objects.dropLast().elementsEqual(before.objects))
let shape = after.objects.last!
precondition(shape.autoShapeType == "autoshape chevron" && shape.solidFillRGB == [83,112,234])
precondition(abs(shape.x - 1200000 / 12700.0) < 0.01 && abs(shape.y - 2000000 / 12700.0) < 0.01)
do {
    _ = try PowerPointBridge.insertStagedShape(from: folder, into: before)
    fatalError("Repeated acceptance modified a stale slide")
} catch {
    guard error.localizedDescription.contains("Slide changed since preview") else { throw error }
}
let current = try PowerPointBridge.capture()
precondition(current == after)
print("Native geometry, fill, placement and stale acceptance verified")
SWIFT
swiftc -I "$bin/Modules" "$dir/main.swift" "$bin"/{CursorCore,MacIntegration}.build/*.swift.o -o "$dir/check"
open -a "Microsoft PowerPoint" "$dir/$name"
osascript - "$name" <<'APPLE'
on run argv
    set deckName to item 1 of argv
    tell application "Microsoft PowerPoint"
        set deadline to (current date) + 30
        repeat until exists presentation deckName
            if (current date) > deadline then error "PowerPoint did not open the test deck"
            delay 0.2
        end repeat
        activate
    end tell
end run
APPLE
"$dir/check" "$dir" "$name"
