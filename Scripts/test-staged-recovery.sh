#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
precondition(StagedSubmission.ready.canAccept && StagedSubmission.ready.canHandleCommands)
for busy in [StagedSubmission.writing, .exporting] {
    precondition(!busy.canAccept && !busy.canHandleCommands)
}
precondition(!StagedSubmission.failed.canAccept && StagedSubmission.failed.canHandleCommands)
let stale = BridgeFailure.message(forScriptError: "/private/user/secret/snapshot.js: Error: Slide changed since preview (-2700)", applying: true)
precondition(stale.contains("本条建议未写入") && stale.contains("重新预测") && !stale.contains("/private"))
let unknown = BridgeFailure.message(forScriptError: "/private/document: unknown runtime failure", applying: true)
precondition(unknown.contains("先核对") && !unknown.contains("未写入") && !unknown.contains("/private"))
precondition(BridgeFailure.message(forScriptError: "(-1743)", applying: true).contains("自动化"))
precondition(BridgeFailure.message(forScriptError: "(-1712)", applying: true).contains("未及时确认写入"))
precondition(BridgeFailure.message(forScriptError: "(-1712)", applying: false).contains("读取幻灯片超时"))
print("Failed writes retain retry without allowing duplicate acceptance; actionable path-free errors passed")
SWIFT
swiftc Sources/CursorApp/StagedSubmission.swift Sources/MacIntegration/BridgeFailure.swift "$tmp/main.swift" -o "$tmp/check"
"$tmp/check"
