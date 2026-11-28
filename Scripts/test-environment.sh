#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
let env = NativeSessionLauncher.environment(codex: URL(fileURLWithPath: "/codex/bin/codex"), bundleURL: URL(fileURLWithPath: "/project/dist/PPT Cursor.app"), inherited: ["PATH": "/broken:/working path:/broken"], home: URL(fileURLWithPath: "/private-user"))
precondition(env["PATH"]!.hasPrefix("/project/.venv/bin:/codex/bin:/broken:/working path:"))
let candidates = EnvironmentDiagnostics.candidates("python3", environment: env).map(\.path)
precondition(candidates.filter { $0 == "/broken/python3" }.count == 1)
var tried: [String] = []
let report = EnvironmentDiagnostics.check(environment: env, powerPoint: URL(fileURLWithPath: "/Applications/PowerPoint.app"), resources: URL(fileURLWithPath: "/resources"), model: .savedAPI,
    isExecutable: { ["/broken/python3", "/working path/python3", "/Applications/LibreOffice.app/Contents/MacOS/soffice", "/usr/bin/sips"].contains($0) },
    exists: { _ in true }, probe: { url, _, _ in
        tried.append(url.path)
        return url.path == "/broken/python3" ? .failed : .available
    })
precondition(tried == ["/broken/python3", "/working path/python3"])
precondition(report.missingCount == 0)
precondition(report.items.last!.status == .review)
precondition(report.items[1].detail.contains("/working path/python3"))
precondition(!report.text.contains("/working path") && !report.text.contains("/private-user"))
let missing = EnvironmentDiagnostics.check(environment: [:], powerPoint: nil, resources: nil, model: .missing, isExecutable: { _ in false }, exists: { _ in false })
precondition(missing.missingCount == 5)
precondition(missing.items.allSatisfy { !$0.detail.isEmpty })
let timed = EnvironmentDiagnostics.check(environment: env, powerPoint: nil, resources: nil, model: .cli, isExecutable: { $0 == "/broken/python3" }, exists: { _ in false }, probe: { _, _, seconds in precondition(seconds <= 2); return .timedOut })
precondition(timed.items[1].detail.contains("超时"))
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let sleeper = root.appendingPathComponent("slow-python")
try "#!/bin/sh\nexec /bin/sleep 30\n".write(to: sleeper, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sleeper.path)
let start = Date()
precondition(EnvironmentDiagnostics.probePython(sleeper, environment: [:], timeout: 0.1) == .timedOut)
precondition(Date().timeIntervalSince(start) < 3)
print("Environment path selection, fallback, missing dependencies, privacy and probe timeout passed")
SWIFT
swiftc Sources/CursorApp/EnvironmentDiagnostics.swift Sources/CursorApp/NativeSessionLauncher.swift "$tmp/main.swift" -o "$tmp/check"
"$tmp/check" "$tmp"

# An older bundled executable must never be invoked by this diagnostic wrapper.
mkdir -p "$tmp/Scripts" "$tmp/dist/PPT Cursor.app/Contents/MacOS"
cp Scripts/check-environment.sh "$tmp/Scripts/"
cat > "$tmp/dist/PPT Cursor.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleVersion</key><string>44</string></dict></plist>
PLIST
cat > "$tmp/dist/PPT Cursor.app/Contents/MacOS/PPTCursor" <<'STUB'
#!/bin/sh
touch incorrectly-started-controller
exit 0
STUB
chmod +x "$tmp/dist/PPT Cursor.app/Contents/MacOS/PPTCursor"
sh "$tmp/Scripts/check-environment.sh" > "$tmp/report" 2>&1 || true
test ! -e "$tmp/incorrectly-started-controller"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 45' "$tmp/dist/PPT Cursor.app/Contents/Info.plist"
sh "$tmp/Scripts/check-environment.sh" > "$tmp/report" 2>&1
test -e "$tmp/incorrectly-started-controller"
printf 'Diagnostic wrapper skips incompatible builds and uses supported builds.\n'
