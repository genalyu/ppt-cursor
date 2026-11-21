#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product PPTCursor
bin=$(swift build -c release --show-bin-path)
app="dist/PPT Cursor.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/PPTCursor" "$app/Contents/MacOS/"
cp Packaging/Info.plist "$app/Contents/"
for module in CursorCore MacIntegration; do
    ditto "$bin/PPTCursor_${module}.bundle" "$app/Contents/Resources/PPTCursor_${module}.bundle"
done
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
echo "$PWD/$app"
