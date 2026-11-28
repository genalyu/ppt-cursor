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

- [ ] Control window provides readable progress, a current preview, accept/dismiss, pause/retry and recovery actions.
- [ ] Model setup, inaccessible credentials and dependencies have actionable feedback.
- [ ] Cancellation, switching documents, stale responses and failures preserve user work.
- [x] Regression checks and packaging pass locally and on CI for build 38.
- [x] Current Apple Silicon preview download, prerequisites and troubleshooting. Intel builds and a broader compatibility matrix remain open.
- [x] Bilingual README with concise value proposition, verified preview renders, workflow and installation. Native screenshots remain to be added.
- [x] Short promotional video and longer demo replay, with source provenance and explicit non-real-time labelling. Native screen-recorded walkthrough remains open.
- [x] Reproducible media sources, captions, credits and the existing public demo deck.
- [ ] Contribution guide, architecture, roadmap, changelog, security policy, issue/PR templates and useful repository metadata.

## Benchmark

[CC Switch](https://github.com/farion1231/cc-switch) is a reference for product presentation, onboarding and maintenance completeness. PPT Cursor has a different scope and should make its own capabilities and limitations explicit. Stars are not an acceptance criterion.

## Test discipline

Only disposable copies of public example presentations are used for automated live acceptance. Never modify or include a user's working presentation in public screenshots or recordings. Record actual measurements separately from mocked regressions. Keep this checklist open until current evidence satisfies each gate.
