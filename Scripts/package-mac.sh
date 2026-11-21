#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./Scripts/build-app.sh
app="dist/PPT Cursor.app"
name="PPT-Cursor-macOS-$(uname -m).zip"
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
ditto -c -k --keepParent "$app" "$temp/$name"
ditto -x -k "$temp/$name" "$temp/unpacked"
copy="$temp/unpacked/PPT Cursor.app"
codesign --verify --deep --strict "$copy"
test -x "$copy/Contents/MacOS/PPTCursor"
for module in CursorCore MacIntegration; do
    test -d "$copy/Contents/Resources/PPTCursor_${module}.bundle"
done
mv "$temp/$name" "dist/$name"
(cd dist && shasum -a 256 "$name" > "$name.sha256")
