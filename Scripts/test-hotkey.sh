#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import AppKit
import Carbon

// Exercise the same application-target Carbon handler as an OS hotkey notification.
// This verifies dispatch, payload filtering and registration lifecycle separately from hardware.
_ = NSApplication.shared
let savedPreference = UserDefaults.standard.object(forKey: "acceptWithTab")
defer { UserDefaults.standard.set(savedPreference, forKey: "acceptWithTab") }
for enabled in [true, false] {
    AcceptShortcut.prefersTab = enabled
    precondition(AcceptShortcut.allowsTab(editingText: false) == enabled)
    precondition(!AcceptShortcut.allowsTab(editingText: true))
    precondition(!AcceptShortcut.allowsTab(editingText: nil))
}
var count = 0
let shortcut = AcceptShortcut { count += 1 }
func send(id: UInt32) {
    var event: EventRef?
    precondition(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                             0, EventAttributes(kEventAttributeNone), &event) == noErr)
    defer { ReleaseEvent(event) }
    var payload = EventHotKeyID(signature: 0x50505443, id: id)
    precondition(SetEventParameter(event, EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size,
                                   &payload) == noErr)
    _ = SendEventToEventTarget(event, GetApplicationEventTarget())
}
send(id: 1)
precondition(count == 0, "Disabled shortcut accepted")
precondition(shortcut.enable(), "Shortcut is already assigned or could not be registered")
send(id: 2)
precondition(count == 0, "Unrelated hotkey triggered acceptance")
send(id: 1)
precondition(count == 1, "Registered hotkey did not dispatch")
shortcut.disable()
send(id: 1)
precondition(count == 1, "Late hotkey dispatched after release")
precondition(shortcut.enable(useTab: true), "Tab could not be registered")
send(id: 1)
precondition(count == 1, "Queued event from an older preview accepted the new preview")
send(id: 2)
precondition(count == 2)
shortcut.disable()
send(id: 2)
precondition(count == 2, "Released Tab still dispatched")
for flags in [UInt32(0), UInt32(kEventHotKeyExclusive)] {
    var reserved: EventHotKeyRef?
    precondition(RegisterEventHotKey(UInt32(kVK_Tab), 0, EventHotKeyID(signature: 123, id: 1),
                                    GetApplicationEventTarget(), flags, &reserved) == noErr)
    precondition(shortcut.registerPreferred(useTab: true) == "⌥⌘↩")
    shortcut.disable()
    var alternate: EventHotKeyRef?
    precondition(RegisterEventHotKey(UInt32(kVK_Return), UInt32(optionKey | cmdKey),
                                    EventHotKeyID(signature: 123, id: 2), GetApplicationEventTarget(),
                                    flags, &alternate) == noErr)
    precondition(shortcut.registerPreferred(useTab: true) == nil)
    UnregisterEventHotKey(alternate)
    UnregisterEventHotKey(reserved)
}
precondition(shortcut.registerPreferred(useTab: true) == "Tab")
shortcut.disable()
var replacementCount = 0
let replacement = AcceptShortcut { replacementCount += 1 }
precondition(replacement.enable(useTab: true))
send(id: 1)
precondition(replacementCount == 0, "A previous preview instance accepted a new suggestion")
replacement.disable()
if CommandLine.arguments.contains("--system-tab") {
    guard CGPreflightPostEventAccess() else {
        FileHandle.standardError.write(Data("System Tab check requires macOS permission to post keyboard events.\n".utf8))
        exit(77)
    }
    precondition(replacement.enable(useTab: true))
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
    let focusDeadline = Date().addingTimeInterval(2)
    while !NSApplication.shared.isActive && Date() < focusDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    precondition(NSApplication.shared.isActive, "Test application did not acquire focus")
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Tab), keyDown: down) else {
            fatalError("Could not create Tab event")
        }
        event.flags = []
        event.post(tap: .cghidEventTap)
    }
    let deadline = Date().addingTimeInterval(3)
    while replacementCount == 0 && Date() < deadline {
        if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.05),
                                       inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
        }
    }
    replacement.disable()
    precondition(replacementCount == 1, "System Tab did not dispatch exactly once")
    print("System Tab dispatched")
}
print("Carbon registration, routing, filtering and release passed")
SWIFT
swiftc Sources/CursorApp/AcceptShortcut.swift "$tmp/main.swift" -o "$tmp/check"
"$tmp/check" "$@"
