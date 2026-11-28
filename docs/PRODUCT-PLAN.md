# Product quality plan

The target is a dependable human–AI PowerPoint workflow with the installation, documentation, feedback and release discipline expected of a mature open-source desktop app. This is a completion checklist, not a claim that every item is already delivered.

## Live acceptance gates

- [x] Restart the packaged app and restore the user's existing provider.
- [x] Verify at least five consecutive real model suggestions and accepted writes on a disposable public fixture, including continuation beyond the third acceptance.
- [x] Verify automatic web search, preview, provenance and actual image insertion without uploaded references.
- [ ] Observe distinct live prediction, search, rendering, ready, applying, background and paused states; elapsed labels must advance.
- [x] Pause/resume after unsaved insertion and prove continued prediction.
- [ ] Measure end-to-end latency by phase, and optimize observed bottlenecks without relaxing baseline verification.
- [ ] Verify keyboard and clickable acceptance separately; synthetic input is not evidence of a physical keyboard press.

## Product and release quality

- [x] Control window provides readable progress, a current preview, accept/dismiss, pause/retry and recovery actions.
- [ ] Model setup, inaccessible credentials and dependencies have actionable feedback.
- [ ] Cancellation, switching documents, stale responses and failures preserve user work.
- [x] Regression checks and packaging pass locally and on CI for build 39; downloaded release checksum, signature and worker-source match verified.
- [x] Current Apple Silicon preview download, prerequisites and troubleshooting. Intel builds and a broader compatibility matrix remain open.
- [x] Bilingual README with concise value proposition, verified preview renders, workflow and installation. Native screenshots remain to be added.
- [x] Short promotional video and longer demo replay, with source provenance and explicit non-real-time labelling. Native screen-recorded walkthrough remains open.
- [x] Reproducible media sources, captions, credits and the existing public demo deck.
- [x] Contribution guide, architecture, roadmap, changelog, security policy, issue/PR templates and useful repository metadata.

## Current priorities after build 40 implementation

- Broaden real-provider timing samples beyond the verified API font-size and CLI requested-text scenarios. Temporary format/duration metrics are implemented without logging prompts or slide contents.
- Verify the full explicit-request control-window submission/acceptance path after owner-operated Keychain authorization. The real CLI/model/staging path has passed.
- Authorization now runs off the UI thread with an explicit pending state; native waiting-state responsiveness was verified. Keep testing recovery and normal switching without extra key reads/writes.
- Broaden direct native formatting and verify it in PowerPoint, then add native UI footage and finish the remaining live gates above.

## Benchmark

[CC Switch](https://github.com/farion1231/cc-switch) is a reference for product presentation, onboarding and maintenance completeness. PPT Cursor has a different scope and should make its own capabilities and limitations explicit. Stars are not an acceptance criterion.

## Test discipline

Only disposable copies of public example presentations are used for automated live acceptance. Never modify or include a user's working presentation in public screenshots or recordings. Record actual measurements separately from mocked regressions. Keep this checklist open until current evidence satisfies each gate.
