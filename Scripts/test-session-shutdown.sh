#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/worker.py" <<'PY'
import importlib.util, os, sys, time
from pathlib import Path
os.setpgid(0,0)
spec=importlib.util.spec_from_file_location('staging',sys.argv[1]);staging=importlib.util.module_from_spec(spec);spec.loader.exec_module(staging)
root=Path(os.environ['PPT_CURSOR_CONTROL_DIRECTORY'])
if sys.argv[2]=='protected':
    with staging.preview_transaction() as active:
        assert active
        (root/'ready').touch()
        while not (root/'stop').exists(): time.sleep(.01)
        # A slow native write followed by accepted-checkpoint persistence.
        time.sleep(.35)
        (root/'write-finished').touch()
        time.sleep(.15)
        (root/'checkpoint-finished').touch()
elif sys.argv[2]=='already-stopped':
    with staging.preview_transaction() as active:
        assert not active
        (root/'rejected-new-preview').touch()
    (root/'ready').touch()
else:
    (root/'ready').touch()
while True: time.sleep(.02)
PY
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let staging = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Scripts/stage-drawing.py")
func wait(_ condition: () -> Bool, timeout: TimeInterval = 6) {
    let end = Date().addingTimeInterval(timeout)
    while !condition() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    precondition(condition(), "Timed out waiting for shutdown lifecycle")
}
for mode in ["protected", "prediction", "already-stopped"] {
    let folder = root.appendingPathComponent(mode)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    if mode == "already-stopped" { try Data().write(to: folder.appendingPathComponent("stop")) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [root.appendingPathComponent("worker.py").path, staging.path, mode]
    var environment = ProcessInfo.processInfo.environment
    environment["PPT_CURSOR_CONTROL_DIRECTORY"] = folder.path
    process.environment = environment
    try process.run()
    defer { if process.isRunning { process.terminate() } }
    wait { FileManager.default.fileExists(atPath: folder.appendingPathComponent("ready").path) }
    var completed = false
    let started = Date()
    NativeSessionLauncher.stop(process) { error in precondition(error == nil); completed = true }
    if mode == "protected" {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        precondition(process.isRunning && !completed, "Killed an active write or blocked UI instead of deferring")
    }
    wait { completed && !process.isRunning }
    if mode == "protected" {
        precondition(Date().timeIntervalSince(started) >= 0.45)
        precondition(FileManager.default.fileExists(atPath: folder.appendingPathComponent("checkpoint-finished").path))
    } else { precondition(Date().timeIntervalSince(started) < 2) }
    if mode == "already-stopped" {
        precondition(FileManager.default.fileExists(atPath: folder.appendingPathComponent("rejected-new-preview").path))
    }
}
print("Cross-process shutdown waits for write/checkpoint, keeps run loop responsive, cancels prediction, rejects late previews")
SWIFT
swiftc Sources/CursorApp/NativeSessionLauncher.swift "$tmp/main.swift" -o "$tmp/check"
"$tmp/check" "$tmp"
