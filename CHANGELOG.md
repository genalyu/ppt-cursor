# Changelog

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
