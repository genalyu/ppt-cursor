#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/main.swift" <<'SWIFT'
import AppKit

for (page, background, visible) in [(0.06, 0.28, true), (0.98, 0.28, true), (0.06, 0.06, false)] {
    let ctx = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
                        bytesPerRow: 800, space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: background, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
    ctx.setFillColor(gray: page, alpha: 1)
    ctx.fill(CGRect(x: 120, y: 150, width: 560, height: 315))
    let rect = PageLocator.pagePixels(in: ctx.makeImage()!, aspect: 16.0 / 9)
    precondition(rect == (visible ? CGRect(x: 120, y: 135, width: 560, height: 315) : nil))
}
SWIFT
swiftc -target "$(uname -m)-apple-macos13" "$root/Sources/CursorApp/PageLocator.swift" "$root/Sources/CursorApp/PowerPointWindow.swift" "$scratch/main.swift" -o "$scratch/check"
"$scratch/check"
