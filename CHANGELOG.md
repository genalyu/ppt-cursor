# Changelog

## 0.1.0 preview — build 45

- Add an in-app environment check with actionable dependency results, refresh, usage-guide links and a copyable summary that omits credentials, document contents and full local paths.
- Share the launcher's Python search path, skip interpreters without Pillow and bound diagnostic probes. Check packaged resources and distinguish local installation readiness from model login/network readiness.
- Provide `--check-environment` and `--show-environment-check` without initializing the model controller or reading the Keychain. The source check script delegates to the built app when available.
- Show missing-dependency exits as “环境未就绪” instead of a generic connection error; explain how to reuse an existing key without entering it again.
- Add regression coverage for Python fallback, paths containing spaces, missing dependencies, diagnostic privacy, probe timeout and worker error classification.

## 0.1.0 preview — build 44

- Add compact, validated shape-insertion instructions for text labels, arrows, rectangles, rounded rectangles, ellipses and chevrons. The app generates editable native DrawingML, retaining the full-fragment path for designs needing other styles.
- Support shared fill, stroke, text color, typeface, size, weight, alignment and horizontal text inset; group multiple additions while preserving existing slide objects.
- Validate item counts, bounds, finite values, strings, colors and mutually exclusive operations. Package checks now compare all Python resources against their sources.
- A three-label fixture shrank from 2,626 bytes of DrawingML response to 517 bytes of compact JSON. Real qwen4-max generated the aligned labels in 4.608 s, with 2.404 s rendering; native acceptance and the next compact suggestion passed. Timings are samples, not a fixed speedup guarantee.
- Ask for shorter user-facing summaries that describe the visible change instead of coordinate lists.

## 0.1.0 preview — build 43

- Reuse an isolated LibreOffice profile within each editing session, avoiding repeated initialization for later previews. User LibreOffice profiles are never used.
- Rotate the temporary profile after export errors so a broken profile does not block every subsequent suggestion; remove it with the session on pause/exit.
- A repeatable public-fixture benchmark reduced warm full-preview time from 2.206–2.276 s with isolated exports to 1.499–1.517 s with session reuse, with identical RGBA pixels and PPTX part contents. Cold start still costs initialization.
- Verified two real accepted changes and a third preview in one qwen4-max session: render times 2.455 / 1.767 / 1.806 s. Model generation remains a separate bottleneck for DrawingML-heavy proposals.

## 0.1.0 preview — build 42

- Support direct native bold and italic changes for text with a known uniform style. Compact model edits preserve other formatting and carry unsaved styles into subsequent previews.
- Include style in the live baseline, preserve style-only suggestions during normalization, verify every written run and restore styles after a later write failure. Unknown/mixed properties remain unsupported for direct whole-range changes.
- Verified a real qwen4-max request to remove italics while retaining bold, Arial, 22 pt, color and placement, followed by another automatic suggestion without reconnecting the model.
- Add offline regression checks for inherited styles, combined edits, stale baselines, run readback failures and transactional rollback.

## 0.1.0 preview — build 41

- Keep the floating preview in the lower-left of the PowerPoint window, with acceptance controls aligned directly above it. The card follows window movement and stays inside the visible display.
- Use the complete proposed slide thumbnail instead of covering the central editing canvas. Native-session preview positioning no longer needs image-based canvas detection.
- Restore a bounded control-window content width when showing a long request or preview summary.
- Verified two explicit API text requests, native acceptance and continuation. The second used the new lower-left preview process and reused the already-unlocked connection without another authorization step.

## 0.1.0 preview — build 40

- Add an explicit editing-request field beside automatic suggestions. Requests are scoped to the captured document/page, keep the normal preview/acceptance boundary and return to automatic collaboration after acceptance.
- Move interactive Keychain reads and writes off the UI thread. Show a waiting-for-authorization state, prevent duplicate submissions, retain the previous connection on failure and avoid re-reading/re-writing a key already in memory.
- Make the control window scrollable and cap its expanded height to the visible screen, keeping the new request controls and preview reachable.
- Add temporary content-free proposal-format and phase-duration metrics, plus regression coverage for authorization waits, failed/cached connections, request forwarding, page scope and acceptance consumption.

## 0.1.0 preview — build 39

- Add compact `textEdit` proposals for text and uniform font-size changes. Local expansion preserves the original shape styling, then uses the existing preview and native equivalence checks.
- Support uniform font-size changes inherited from a template, including differently styled text runs. Keep unsaved live font-size edits in the disposable preview baseline.
- Reject conflicting operations, unsupported fields, multiline replacements and invalid sizes. Mixed-format text replacement still uses the full DrawingML path.
- Verified a real PowerPoint bridge write and saved-file round trip: changed text and size retained Arial, color, bold and italic. A test fixture's JSON response shrank from 741 to 194 bytes; this is not a measured model-latency improvement.

## 0.1.0 preview — build 38

### Editing reliability

- Prevent a native insertion's temporary PowerPoint document from restarting the active session. In-flight document observations crossing writeback are discarded; real document switches must remain stable.
- Keep predicting beyond early acceptances, recover from empty/transient failures with bounded backoff, and restore accepted unsaved objects from private bounded checkpoints.
- Treat missing optional fields and explicit nulls as the same slide content, preserving useful editing history across Swift/JXA snapshots.

### User experience

- Show actual prediction, search, render, review, writeback, waiting and failure stages, with elapsed time during work.
- Review the current proposal directly in the control window, accept/dismiss it, inspect the image source, or save a suggested copy when direct writeback is unsupported.
- Use a compact window when idle and expand only when a preview is available. Preserve provider preferences and show actionable Keychain recovery.
- Render pure geometric edits with a lightweight, explicitly labelled placement diagram.

### Automatic image assets

- Model-directed Commons search works without uploaded references or a search API key.
- Offer public-domain/CC0 candidates after bounded, host-validated downloads and raster normalization; retain provenance in picture alternative text.
- Fall back to normal editing when search is unavailable.

### Open-source project

- Chinese and English quick starts, reproducible overview/demo media, source credits, issue/PR templates, contribution/security guides and explicit quality roadmap.
- Offline checks cover API behavior, cancellation, continuous history, checkpoints, image search, fast preview, phases and document-follow races. See `docs/QA-2026-11-28.md` for live test evidence and remaining limitations.

This remains an ad-hoc-signed preview. Apple notarization and a broader PowerPoint/macOS compatibility matrix are not yet complete.
