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
precondition(SessionPhase.authorizing.title(elapsed: 100) == "等待授权")
precondition(SessionPhase.workerExit(1, detail: "找不到装有 Pillow 的 Python 3 环境") == .environment)
precondition(SessionPhase.workerExit(1, detail: "HTTP 401 invalid API key") == .error)
precondition(SessionPhase.workerExit(3, detail: "page changed") == .cancelled)
precondition(SessionPhase.workerExit(0, detail: "") == .paused)
print("Session phases, worker compatibility and elapsed-time labels passed")
SWIFT
swiftc Sources/CursorApp/SessionPhase.swift "$tmp/main.swift" -o "$tmp/check"
"$tmp/check"
