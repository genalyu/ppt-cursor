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
precondition(finished.wait(timeout: .now() + 5) == .success)
precondition(!process.isRunning)
print("Cancellation before and during inference passed")
SWIFT
swiftc Sources/CursorCore/PredictionRun.swift "$tmp/main.swift" -o "$tmp/check"
"$tmp/check"
