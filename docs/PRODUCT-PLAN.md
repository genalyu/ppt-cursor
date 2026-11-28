# Product quality plan

The target is a dependable human–AI PowerPoint workflow with the installation, documentation, feedback and release discipline expected of a mature open-source desktop app. This is a completion checklist, not a claim that every item is already delivered.

## Live acceptance gates

- [x] Restart the packaged app and restore the user's existing provider.
- [x] Verify at least five consecutive real model suggestions and accepted writes on a disposable public fixture, including continuation beyond the third acceptance.
- [x] Verify automatic web search, preview, provenance and actual image insertion without uploaded references.
- [x] Verify distinct live prediction, search, rendering, ready, applying, background and paused states through controller events and observed control-window states; live elapsed labels advanced 3 s → 6 s. Every menu-bar frame has not been screen-recorded.
- [x] Pause/resume after unsaved insertion and prove continued prediction.
- [ ] Measure end-to-end latency by phase, and optimize observed bottlenecks without relaxing baseline verification.
- [ ] Verify keyboard and clickable acceptance separately; synthetic input is not evidence of a physical keyboard press.

## Product and release quality

- [x] Control window provides readable progress, a current preview, accept/dismiss, pause/retry and recovery actions.
- [x] Model setup, inaccessible credentials and dependencies have actionable feedback; key-free diagnostic UI verified in build 45, stale/write-failure recovery verified in build 46.
- [ ] Cancellation, switching documents, stale responses and failures preserve user work.
- [x] Regression checks and packaging pass locally and on CI through build 46; downloaded release checksum, signature and worker/bridge-source matches verified.
- [x] Current Apple Silicon preview download, prerequisites and troubleshooting. Intel builds and a broader compatibility matrix remain open.
- [x] Bilingual README with concise value proposition, verified preview renders, workflow and installation. Native screenshots remain to be added.
- [x] Short promotional video and longer demo replay, with source provenance and explicit non-real-time labelling. Native screen-recorded walkthrough remains open.
- [x] Reproducible media sources, captions, credits and the existing public demo deck.
- [x] Contribution guide, architecture, roadmap, changelog, security policy, issue/PR templates and useful repository metadata.

## Current priorities after build 47

- Compact native additions now pass real-model label generation, editable group acceptance and automatic continuation. The aligned-label request took 4.608 s model / 2.404 s render; the next compact proposal took 6.686 / 1.732 s. Broaden representative diagrams and complex-style coverage without sacrificing output fidelity.
- Broaden real-provider timing samples beyond the verified API font-size and CLI requested-text scenarios. Temporary format/duration metrics are implemented without logging prompts or slide contents.
- The full explicit-request control-window submission/acceptance path passed twice through the API connection; the real CLI/model/staging path also passed. Continue covering broader edit types and longer sessions.
- Authorization now runs off the UI thread with an explicit pending state; native waiting-state responsiveness was verified. Keep testing recovery and normal switching without extra key reads/writes.
- Pause/quit now wait through writeback and checkpoint persistence; real-process and isolated-controller tests cover shutdown and serialized restart. Live document-switch/cancellation coverage remains open.
- Failed acceptance now retains retry controls, with a real rejection → retry → acceptance → continuation test. Keep covering document switches and cancellation under real editing.
- Uniform bold/italic now pass native writeback and real-provider acceptance. Broaden text color/alignment and mixed-run editing, add native UI footage and finish the remaining live gates above.
- Reuse the already-unlocked running connection while the owner is away; avoid restarts or credential operations requiring their interaction.

## Benchmark

[CC Switch](https://github.com/farion1231/cc-switch) is a reference for product presentation, onboarding and maintenance completeness. PPT Cursor has a different scope and should make its own capabilities and limitations explicit. Stars are not an acceptance criterion.

## Test discipline

Only disposable copies of public example presentations are used for automated live acceptance. Never modify or include a user's working presentation in public screenshots or recordings. Record actual measurements separately from mocked regressions. Keep this checklist open until current evidence satisfies each gate.
