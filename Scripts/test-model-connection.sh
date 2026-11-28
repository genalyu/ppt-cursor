#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build --target CursorCore
bin=$(swift build --show-bin-path)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
import CursorCore

let domain = "PPTCursor.ConnectionTest." + UUID().uuidString
let preferences = UserDefaults(suiteName: domain)!
defer { preferences.removePersistentDomain(forName: domain) }
let base = APISettings.openAIBase
var result: Result<ModelConnection, Error>?
let entered = DispatchSemaphore(value: 0)
let gate = DispatchSemaphore(value: 0)
ModelSettings.resolve(.api(base: base, model: "new", typedKey: "", cachedSettings: nil), preferences: preferences,
    loadKey: { _ in
        precondition(!Thread.isMainThread)
        entered.signal()
        gate.wait()
        return "fixture-key"
    }, writeKey: { _, _, _ in fatalError("Reused key was rewritten") }) {
        precondition(Thread.isMainThread)
        result = $0
    }
precondition(entered.wait(timeout: .now() + 2) == .success)
var ticks = 0
let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in ticks += 1 }
RunLoop.main.run(until: Date().addingTimeInterval(0.08))
timer.invalidate()
precondition(ticks > 0 && result == nil, "Authorization blocked the UI run loop")
gate.signal()
func waitForResult() {
    let deadline = Date().addingTimeInterval(2)
    while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    precondition(result != nil)
}
waitForResult()
guard case .success(.api(let settings)) = result! else { fatalError("Expected restored connection") }
precondition(settings.model == "new" && preferences.string(forKey: "modelName") == "new")
result = nil
ModelSettings.resolve(.api(base: base, model: "cached", typedKey: "", cachedSettings: settings), preferences: preferences,
    loadKey: { _ in fatalError("Cached connection prompted again") },
    writeKey: { _, _, _ in fatalError("Cached connection rewrote the key") }) { result = $0 }
waitForResult()
precondition(preferences.string(forKey: "modelName") == "cached")
result = nil
ModelSettings.resolve(.api(base: base, model: "denied", typedKey: "", cachedSettings: nil), preferences: preferences,
    loadKey: { _ in nil }, writeKey: { _, _, _ in fatalError() }) { result = $0 }
waitForResult()
guard case .failure = result! else { fatalError("Denied authorization succeeded") }
precondition(preferences.string(forKey: "modelName") == "cached", "Failure replaced the working settings")
result = nil
ModelSettings.resolve(.api(base: base, model: "typed", typedKey: "test-only", cachedSettings: nil), preferences: preferences,
    loadKey: { _ in fatalError("New key unnecessarily read the old key") },
    writeKey: { base, model, key in
        precondition(!Thread.isMainThread && key == "test-only")
        return APISettings(model: model, key: key, baseURL: base)
    }) { result = $0 }
waitForResult()
guard case .success(.api(let typed)) = result! else { fatalError() }
precondition(typed.model == "typed")
print("Authorization wait leaves the main run loop responsive; cached, denied and new-key paths passed")
SWIFT
swiftc -I "$bin/Modules" Sources/CursorApp/ModelSettings.swift "$tmp/main.swift" "$bin"/CursorCore.build/*.swift.o -o "$tmp/check"
"$tmp/check"
