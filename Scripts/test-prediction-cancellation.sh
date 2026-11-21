#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation

func child() -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["30"]
    return process
}

let beforeLaunch = PredictionRun()
beforeLaunch.cancel()
do { try beforeLaunch.execute(child()); fatalError("Cancelled run launched") }
catch is CancellationError {}

let running = PredictionRun()
let finished = DispatchSemaphore(value: 0)
let process = child()
DispatchQueue.global().async {
    do { try running.execute(process); fatalError("Cancelled result accepted") }
    catch is CancellationError { finished.signal() }
    catch { fatalError("Unexpected error: \(error)") }
}
let deadline = Date().addingTimeInterval(5)
while !process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
precondition(process.isRunning)
running.cancel()
// A new edit owns a separate prediction while the previous process winds down.
let replacement = Process()
replacement.executableURL = URL(fileURLWithPath: "/usr/bin/true")
try PredictionRun().execute(replacement)
precondition(replacement.terminationStatus == 0)
precondition(finished.wait(timeout: .now() + 5) == .success)
precondition(!process.isRunning)
let stuck = Process()
stuck.executableURL = URL(fileURLWithPath: "/bin/sh")
stuck.arguments = ["-c", "trap '' TERM; exec /bin/sleep 30"]
let start = Date()
do { try PredictionRun().execute(stuck, timeout: 0.3); fatalError("Hung inference succeeded") }
catch is InferenceTimeout {}
precondition(!stuck.isRunning && Date().timeIntervalSince(start) < 5)
let next = Process()
next.executableURL = URL(fileURLWithPath: "/usr/bin/true")
try PredictionRun().execute(next)
precondition(next.terminationStatus == 0)
print("Cancellation, unresponsive child timeout and subsequent execution passed")
SWIFT
swiftc Sources/CursorCore/PredictionRun.swift "$tmp/main.swift" -o "$tmp/check"
"$tmp/check"
