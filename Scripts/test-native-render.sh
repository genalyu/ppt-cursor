#!/bin/bash
# Exercise PowerPoint's native PDF renderer using a disposable copy of the fixture.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d "$HOME/Library/Containers/com.microsoft.Powerpoint/Data/tmp/ppt-cursor-XXXXXX")
trap 'rm -rf "$scratch"' EXIT
name=$(basename "$scratch")
cat > "$scratch/shape.xml" <<'DRAWING'
<p:sp>
  <p:nvSpPr><p:cNvPr id="1" name="Cursor Chevron"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
  <p:spPr>
    <a:xfrm><a:off x="1200000" y="2000000"/><a:ext cx="1800000" cy="650000"/></a:xfrm>
    <a:prstGeom prst="chevron"><a:avLst/></a:prstGeom>
    <a:solidFill><a:srgbClr val="5370EA"/></a:solidFill>
  </p:spPr>
</p:sp>
DRAWING
python3 "$root/Scripts/stage-drawing.py" "$root/Examples/Tab-Demo.pptx" ppt/slides/slide1.xml \
    "$scratch/shape.xml" "$scratch/$name.pptx"
osascript - "$scratch" "$name" <<'APPLESCRIPT'
on run argv
    set folderPath to item 1 of argv
    set deckName to item 2 of argv
    set inputFile to POSIX file (folderPath & "/" & deckName & ".pptx")
    set firstPDF to POSIX file (folderPath & "/before.pdf")
    set secondPDF to POSIX file (folderPath & "/after.pdf")
    tell application "Microsoft PowerPoint"
        open inputFile
        set deck to presentation (deckName & ".pptx")
        try
            save deck in firstPDF as save as PDF
            set targetShape to shape "Cursor Chevron" of slide 1 of deck
            set top of targetShape to (top of targetShape) - 60
            save deck in secondPDF as save as PDF
        on error errorText number errorCode
            close deck saving no
            error errorText number errorCode
        end try
        close deck saving no
    end tell
end run
APPLESCRIPT
for version in before after; do
    pdftoppm -singlefile -f 1 -r 72 "$scratch/$version.pdf" "$scratch/$version"
done
if cmp -s "$scratch/before.ppm" "$scratch/after.ppm"; then
    echo 'Expected the moved shape to change the rendered slide.' >&2
    exit 1
fi
echo 'PowerPoint rendered distinct slide images before and after the move.'
