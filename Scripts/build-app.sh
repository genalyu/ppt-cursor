#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product PPTCursor
bin=$(swift build -c release --show-bin-path)
app="dist/PPT Cursor.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/PPTCursor" "$app/Contents/MacOS/"
cp Scripts/stage-drawing.py "$app/Contents/Resources/"
cp Packaging/Info.plist "$app/Contents/"
for module in CursorCore MacIntegration; do
    ditto "$bin/PPTCursor_${module}.bundle" "$app/Contents/Resources/PPTCursor_${module}.bundle"
done
if [ -n "${PPT_CURSOR_SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --entitlements Packaging/Release.entitlements \
        --sign "$PPT_CURSOR_SIGN_IDENTITY" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
echo "$PWD/$app"
