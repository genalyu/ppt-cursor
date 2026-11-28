#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
for phase in SessionPhase.allCases {
    precondition(SessionPhase(event: phase.rawValue) == phase)
}
precondition(SessionPhase(event: "提供预览") == .preview)
precondition(SessionPhase(event: "操作") == .apply)
precondition(SessionPhase(event: "unknown") == nil)
precondition(SessionPhase.predict.title(elapsed: 12.9) == "预测 12s")
precondition(SessionPhase.search.title(elapsed: 3) == "搜素材 3s")
precondition(SessionPhase.paused.title(elapsed: 400) == "已暂停")
precondition(SessionPhase.preview.title(elapsed: 100) == "待采纳")
print("Session phases, worker compatibility and elapsed-time labels passed")
SWIFT
swiftc Sources/CursorApp/SessionPhase.swift "$tmp/main.swift" -o "$tmp/check"
"$tmp/check"
