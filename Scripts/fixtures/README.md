# Shutdown UI integration fixture

`shutdown-worker.py` is a deterministic substitute for the staging worker, **only for a disposable app copy**. It never calls a model or edits a presentation. The normal offline suite already tests real process locking without this UI fixture.

To reproduce the controller checks:

1. Build the real app, then copy it outside `dist` and give the copy a unique bundle identifier. Keep the production app and its credentials untouched.
2. In the copy's Resources, rename the real `stage-drawing.py` to `stage-drawing-real.py`, copy this fixture as `stage-drawing.py`, and ad-hoc sign the copy.
3. Launch its executable with `PPT_CURSOR_SHUTDOWN_EVIDENCE` pointing to a temporary directory. Open a disposable public PPTX in PowerPoint and click Start in the test app.
4. The UI clearly identifies the simulated write. Click Pause or use Command-Q. The fixture waits for the stop request, simulates a three-second write and one-second checkpoint, and exits. Verify both completion markers, UI responsiveness and eventual termination/cleanup.
5. To test a real preview child without generating a proposal, also set `PPT_CURSOR_SHUTDOWN_PREVIEW` to a valid public-test preview directory with a fresh matching baseline. The fixture runs the production preview child, which should close on pause. Do not accept it unless performing a separately authorized live-write test.

Each run records evidence under its worker PID. Use marker timestamps to confirm that a queued replacement starts only after the previous checkpoint. Never package or publish the modified app copy; release packaging must compare its worker to the real source.
