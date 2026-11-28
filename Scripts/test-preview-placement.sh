#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import AppKit
let display = NSRect(x: 0, y: 0, width: 1440, height: 900)
let window = NSRect(x: 100, y: 80, width: 1200, height: 800)
let card = PreviewPlacement.lowerLeft(window: window, aspect: 16 / 9, display: display)!
precondition(card == NSRect(x: 116, y: 120, width: 320, height: 180))
let controlSize = NSSize(width: 320, height: 84)
let origin = SuggestionPanel.origin(for: card, panel: controlSize, displays: [display], alignLeft: true)
precondition(origin.x == card.minX && origin.y == card.maxY + 6)
for (win, screen) in [(window, display),
                      (NSRect(x: -1300, y: 0, width: 900, height: 700), NSRect(x: -1440, y: 0, width: 1440, height: 900)),
                      (NSRect(x: -100, y: -100, width: 800, height: 600), display),
                      (NSRect(x: 20, y: 20, width: 300, height: 400), display)] {
    for aspect in [CGFloat(16 / 9), CGFloat(4 / 3), CGFloat(0.75)] {
        let frame = PreviewPlacement.lowerLeft(window: win, aspect: aspect, display: screen)!
        let visible = win.intersection(screen)
        precondition(visible.contains(frame))
        precondition(abs(frame.width / frame.height - aspect) < 0.001)
        precondition(frame.minX == visible.minX + 16 && frame.minY == visible.minY + 40)
        let size = NSSize(width: max(240, frame.width), height: 84)
        let controls = NSRect(origin: SuggestionPanel.origin(for: frame, panel: size, displays: [screen], alignLeft: true), size: size)
        precondition(visible.contains(controls))
    }
}
precondition(PreviewPlacement.lowerLeft(window: .zero, aspect: 1, display: display) == nil)
precondition(PreviewPlacement.lowerLeft(window: window, aspect: .nan, display: display) == nil)
precondition(PreviewPlacement.lowerLeft(window: NSRect(x: 0, y: 0, width: 200, height: 150), aspect: 1, display: display) == nil)
print("Lower-left card and acceptance controls stay visible across window sizes and displays")
SWIFT
swiftc Sources/CursorApp/PreviewPlacement.swift Sources/CursorApp/SuggestionPanel.swift "$tmp/main.swift" -o "$tmp/check"
"$tmp/check"
