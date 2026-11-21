#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -n "${PPT_CURSOR_NOTARY_PROFILE:-}" ] && [ -z "${PPT_CURSOR_SIGN_IDENTITY:-}" ]; then
    echo "Notarization requires PPT_CURSOR_SIGN_IDENTITY (Developer ID Application)." >&2
    exit 1
fi
./Scripts/build-app.sh
app="dist/PPT Cursor.app"
name="PPT-Cursor-macOS-$(uname -m).zip"
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
ditto -c -k --keepParent "$app" "$temp/$name"
if [ -n "${PPT_CURSOR_NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$temp/$name" --keychain-profile "$PPT_CURSOR_NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    rm "$temp/$name"
    ditto -c -k --keepParent "$app" "$temp/$name"
fi
ditto -x -k "$temp/$name" "$temp/unpacked"
copy="$temp/unpacked/PPT Cursor.app"
codesign --verify --deep --strict "$copy"
if [ -n "${PPT_CURSOR_NOTARY_PROFILE:-}" ]; then
    xcrun stapler validate "$copy"
    spctl --assess --type execute "$copy"
fi
test -x "$copy/Contents/MacOS/PPTCursor"
for module in CursorCore MacIntegration; do
    test -d "$copy/Contents/Resources/PPTCursor_${module}.bundle"
done
mv "$temp/$name" "dist/$name"
(cd dist && shasum -a 256 "$name" > "$name.sha256")
