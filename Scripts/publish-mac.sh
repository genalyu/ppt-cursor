#!/bin/sh
# Publish a notarized Mac build from its stable version tag.
set -eu
cd "$(dirname "$0")/.."

: "${PPT_CURSOR_SIGN_IDENTITY:?Set the Developer ID Application signing identity}"
: "${PPT_CURSOR_NOTARY_PROFILE:?Set the notarytool keychain profile}"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)
tag="v$version"
repository=genalyu/ppt-cursor

if [ -n "$(git status --porcelain)" ]; then
    echo "Commit or set aside working tree changes before publishing." >&2
    exit 1
fi
# Resolve both lightweight and annotated tags in the destination repository.
refs=$(git ls-remote --tags "https://github.com/$repository.git" "refs/tags/$tag" "refs/tags/$tag^{}")
remote_commit=$(echo "$refs" | awk 'NR == 1 { commit=$1 } /\^\{\}$/ { commit=$1 } END { print commit }')
if [ "$remote_commit" != "$(git rev-parse HEAD)" ]; then
    echo "The remote tag $tag must point to this checkout." >&2
    exit 1
fi

gh auth status --hostname github.com >/dev/null
python3 Scripts/test-staged-api.py
python3 Scripts/test-staged-history.py
swift test
./Scripts/test-prediction-cancellation.sh
./Scripts/test-api-prediction.sh
./Scripts/package-mac.sh

archive="PPT-Cursor-macOS-$(uname -m).zip"
(cd dist && shasum -a 256 -c "$archive.sha256")
# Keep incomplete uploads out of the public release. A retry can repair a draft.
draft=$(gh release view "$tag" --repo "$repository" --json isDraft --jq .isDraft 2>/dev/null || true)
case "$draft" in
    true) ;;
    false) echo "$tag already has a published release." >&2; exit 1 ;;
    *) gh release create "$tag" --repo "$repository" --verify-tag --draft \
        --title "PPT Cursor $version for Mac" --generate-notes ;;
esac
gh release upload "$tag" "dist/$archive" "dist/$archive.sha256" --repo "$repository" --clobber
gh release edit "$tag" --repo "$repository" --draft=false
