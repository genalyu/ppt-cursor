# Contributing to PPT Cursor

PPT Cursor is a macOS menu bar application for PowerPoint. The project uses Swift/AppKit for the UI and PowerPoint bridge, and Python for the staged DrawingML pipeline.

## Development

Use macOS 13+, Swift 5.9+, and Python 3 with Pillow. PowerPoint and LibreOffice are needed for live and full-render integration checks. Run `Scripts/check-environment.sh` to inspect local dependencies; it never reads API credentials.

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
./Scripts/test-offline.sh
./Scripts/build-app.sh
```

The runner uses XCTest when available and the same history assertions through swiftc on Command Line Tools installations without XCTest. These checks do not call a real model. `python3 Scripts/test-fast-preview.py --benchmark` additionally runs LibreOffice on a disposable copy of the public fixture. `Scripts/test-hotkey.sh` tests Carbon registration and dispatch in a logged-in macOS desktop; it does not prove physical keyboard delivery in PowerPoint.

## Code map

- `Sources/CursorApp`: onboarding, session controls, settings, shortcut registration, preview windows.
- `Sources/CursorCore`: snapshots, context, validation, model protocols and cancellation.
- `Sources/MacIntegration`: live snapshot capture and guarded writeback.
- `Scripts/stage-drawing.py`: history, provider requests, temporary PPTX staging and preview rendering.
- `Scripts/shape_inserts.py`: compact native diagram compiler; `test-shape-inserts.py` covers geometry, style, XML escaping, validation, package preservation and prediction routing.
- `Scripts/web_assets.py`: bounded Commons search, license filtering and normalized image downloads.
- `Scripts/test-style-bridge.sh`: executes the actual bridge against a JavaScriptCore double to verify style readback, stale-baseline rejection and rollback without Apple events.
- `Scripts/test-render-workspace.py`: renderer-profile reuse, isolation, cleanup and failure recovery; `--benchmark` runs real LibreOffice exports and compares all preview channels and PPTX parts.
- `Scripts/test-staged-history.py`: deterministic session regression scenarios.

Change the actual source repository, not a packaged resource copy. Build scripts copy resources into `dist`. Keep user edits and other work in progress intact.

## Review expectations

Include the user-visible problem, changed behavior, and relevant validation. For model or preview changes, distinguish synthetic regression tests, real provider timings, rendering timings, and actual keyboard acceptance. Test live behavior with a new copy of `Examples/Tab-Demo.pptx`; never automate edits to someone's working presentation.

Never bypass the baseline checks before writeback. Only consume an accept command for a currently visible and verified suggestion. Preview images must say when they are geometry diagrams rather than exact slide renders. Empty model results must use bounded backoff and stop when the session is paused; continuous sessions may retry indefinitely. Keep secrets out of command arguments, logs, fixtures and issue reports.

## Reporting bugs

Provide macOS and PowerPoint versions, the build/commit, provider/model name (no key), steps, expected/actual behavior, and whether the issue affects overlay or thumbnail previews. Use a minimal non-private PPTX when possible. Include model and preview timings separately for performance reports.
