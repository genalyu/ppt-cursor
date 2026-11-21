#!/bin/bash
# Run in a logged-in Mac desktop with PowerPoint and screen recording access.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
swift build --product PPTCursor
scratch=$(mktemp -d "$HOME/Library/Containers/com.microsoft.Powerpoint/Data/tmp/ppt-cursor-XXXXXX")
name="ppt-cursor-dark-$(uuidgen).pptx"
file="$scratch/$name"
opened=false
cleanup() {
    if "$opened"; then
    osascript - "$name" <<'APPLESCRIPT'
on run argv
    tell application "Microsoft PowerPoint"
        if exists presentation (item 1 of argv) then close presentation (item 1 of argv) saving no
    end tell
end run
APPLESCRIPT
    fi
    rm -rf "$scratch"
}
trap cleanup EXIT
python3 - "$file" <<'PY'
import sys
from zipfile import ZipFile
with ZipFile("Examples/Tab-Demo.pptx") as source, ZipFile(sys.argv[1], "w") as target:
    for entry in source.infolist():
        data = source.read(entry)
        if entry.filename == "ppt/slides/slide1.xml":
            assert data.count(b"<p:cSld><p:spTree>") == 1
            data = data.replace(b"<p:cSld>", b'<p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="101010"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>')
        target.writestr(entry, data)
PY
osascript - "$file" "$name" <<'APPLESCRIPT'
on run argv
    tell application "Microsoft PowerPoint"
        open (POSIX file (item 1 of argv))
        activate
        if name of active presentation is not (item 2 of argv) then error "Unexpected active presentation"
    end tell
end run
APPLESCRIPT
opened=true
"$(swift build --show-bin-path)/PPTCursor" --check-canvas
