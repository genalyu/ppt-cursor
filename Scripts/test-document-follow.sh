#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
let active = URL(fileURLWithPath: "/tmp/real.pptx")
let staging = URL(fileURLWithPath: "/tmp/staged.pptx")
let other = URL(fileURLWithPath: "/tmp/other.pptx")
let time = Date(timeIntervalSince1970: 100)
var policy = DocumentFollowPolicy()
let beforeWrite = policy.generation
policy.invalidate()
// An in-flight observation must remain invalid even after writeback finishes.
precondition(!policy.shouldFollow(staging, active: active, generation: beforeWrite, applying: false, now: time))
precondition(!policy.shouldFollow(staging, active: active, generation: policy.generation, applying: true, now: time))
let current = policy.generation
precondition(!policy.shouldFollow(staging, active: active, generation: current, applying: false, now: time))
precondition(!policy.shouldFollow(active, active: active, generation: current, applying: false, now: time.addingTimeInterval(1)))
precondition(!policy.shouldFollow(other, active: active, generation: current, applying: false, now: time.addingTimeInterval(2)))
precondition(!policy.shouldFollow(other, active: active, generation: current, applying: false, now: time.addingTimeInterval(2.1)))
precondition(policy.shouldFollow(other, active: active, generation: current, applying: false, now: time.addingTimeInterval(3)))
policy.invalidate()
precondition(!policy.shouldFollow(other, active: active, generation: current, applying: false, now: time.addingTimeInterval(5)))
print("Document following rejects transient staging decks and observations crossing a write")
SWIFT
swiftc Sources/CursorApp/DocumentFollowPolicy.swift "$tmp/main.swift" -o "$tmp/check"
"$tmp/check"
