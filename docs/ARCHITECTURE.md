# Architecture

PPT Cursor is a macOS menu-bar app with a Swift/AppKit controller and a Python staging worker. It edits the user's current PowerPoint document only after an explicit acceptance and a fresh baseline check.

```mermaid
flowchart LR
    U[User edits PowerPoint] --> S[Read settled slide snapshot]
    I[Explicit user request bound to document and page] --> M
    S --> H[Bounded content history]
    H --> M[Selected model]
    M -->|optional query| W[Commons search and validated candidates]
    W --> M
    M --> P[Stage disposable PPTX]
    P --> R[Geometry preview or LibreOffice render]
    R --> V[Control window and canvas preview]
    V -->|Accept| B[Recheck current document and baseline]
    B --> N[Native PowerPoint writeback]
    N --> C[Accepted checkpoint]
    C --> H
    V -->|Dismiss| H
```

## Ownership

| Component | Responsibility |
| --- | --- |
| `Sources/CursorApp/main.swift` | App lifecycle, session process, model configuration, user commands and phase feedback |
| `SessionPhase.swift` | Shared worker event vocabulary, elapsed labels and explanations |
| `DocumentFollowPolicy.swift` | Reject stale document observations and transient staging-document activations |
| `StagedPreview.swift` | Display proposal, suspend on focus changes, route acceptance and recheck before applying |
| `Sources/MacIntegration` | PowerPoint snapshots and guarded native writeback, with rollback checks |
| `Scripts/stage-drawing.py` | Context, provider calls, untrusted DrawingML validation, staged PPTX, rendering and session recovery |
| `Scripts/web_assets.py` | Bounded Commons search, license filtering, URL/redirect validation and raster normalization |

## Important boundaries

- The app sends API settings through the worker's standard input. Keys are not command arguments, proposal files or logs.
- Explicit editing requests use a private session file and are bound to the captured document/page before inference. A page switch cancels the request. Acceptance consumes it and restores automatic suggestions; dismissal may request another candidate for the same instruction.
- Keychain reads and writes run off the AppKit event loop. Reusing a live connection avoids another key read/write. Authorization failure keeps the previous connection preferences intact.
- Preview `metrics.json` records proposal format and model/search/render durations, without slide contents, prompts or credentials. It shares the temporary preview lifecycle rather than creating persistent telemetry.
- A phase event describes real work. The control window and menu bar use the same phase/elapsed function. Session diagnostics contain phase names and timestamps, not API keys or slide text.
- Acceptance is bound to the displayed proposal and current slide baseline. Faster rendering must never weaken that comparison.
- PowerPoint temporarily opens a staged deck to copy native content. The document follower must not treat that as the user's navigation: writeback invalidates pending observations and suspends following; a subsequent switch requires repeated observation.
- Swift omits nil optional fields while JXA may emit null. Content comparisons normalize these representations so a capture does not create a false editing transition.
- Model output and asset metadata are untrusted. The model does not directly execute arbitrary scripts or supply unchecked download URLs.
- Search is optional work selected by the model. User references remain independent inputs. A search failure can return to ordinary editing.
- Checkpoints are private, bounded, revision/structure checked and separate from the user's original file. They preserve accepted unsaved content; they do not authorize saving the original.

## Testing

`Scripts/test-offline.sh` checks the deterministic parts without provider credentials, network requests or live PowerPoint edits. Live acceptance requires a disposable public example, a configured model, an interactive desktop and separate verification of the final PowerPoint state. Synthetic shortcut events must not be described as a physical keyboard test.
