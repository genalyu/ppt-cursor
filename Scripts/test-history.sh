#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Run the same assertions on machines that have Command Line Tools but no XCTest.
sed -e 's/^import XCTest/import Foundation/' -e '/^@testable import CursorCore/d' -e 's/: XCTestCase//g' Tests/CursorCoreTests/HistoryTests.swift > "$tmp/main.swift"
cat >> "$tmp/main.swift" <<'SWIFT'
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTAssertNotNil<T>(_ value: T?) { precondition(value != nil) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b) }
let tests = HistoryTests()
tests.testDismissalsFollowRecentEditsOnOneSlide()
try tests.testModelSeesTextRangesAcrossAnEdit()
try tests.testDocumentIdentityStaysLocal()
try tests.testModelSeesOrderedChangesAndUnchangedObjectsOnlyOnce()
tests.testRealChangesOnlyAndBoundedHistory()
tests.testDocumentAndSlideChangesReseedContext()
tests.testSelectionUpdatesContextWithoutInventingAnEdit()
print("History tests passed")
SWIFT
swiftc Sources/CursorCore/Context.swift "$tmp/main.swift" -o "$tmp/check"
"$tmp/check"
