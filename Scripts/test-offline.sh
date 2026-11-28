#!/bin/sh
# Deterministic checks: no provider keys, network requests, or PowerPoint edits.
set -eu
cd "$(dirname "$0")/.."
swift build
if printf 'import XCTest\n' | swiftc -typecheck - >/dev/null 2>&1; then
    swift test
else
    printf 'XCTest unavailable; running the equivalent history assertions with swiftc.\n'
    ./Scripts/test-history.sh
fi
python3 Scripts/test-staged-api.py
python3 Scripts/test-text-edits.py
python3 Scripts/test-instructions.py
python3 Scripts/test-staged-history.py
python3 Scripts/test-fast-preview.py
python3 Scripts/test-render-workspace.py
python3 Scripts/test-checkpoints.py
python3 Scripts/test-web-assets.py
./Scripts/test-session-status.sh
./Scripts/test-model-connection.sh
./Scripts/test-preview-placement.sh
./Scripts/test-document-follow.sh
./Scripts/test-api-prediction.sh
./Scripts/test-style-bridge.sh
./Scripts/test-prediction-cancellation.sh
./Scripts/test-page-locator.sh
printf 'All offline checks passed.\n'
