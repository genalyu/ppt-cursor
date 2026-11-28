#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
import JavaScriptCore
let context = JSContext()!
context.exceptionHandler = { _, error in
    fputs("Bridge regression failed: \(error?.toString() ?? "unknown")\n", stderr)
    exit(1)
}
let source = try String(contentsOfFile: "Sources/MacIntegration/Resources/snapshot.js", encoding: .utf8)
let test = try String(contentsOfFile: "Scripts/test-style-bridge.js", encoding: .utf8)
let result = context.evaluateScript(source + "\n" + test)
print(result!.toString()!)
SWIFT
swiftc "$tmp/main.swift" -o "$tmp/check"
"$tmp/check"
