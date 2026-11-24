"""Exercise the open-ended watch loop with recorded PowerPoint states."""
import importlib.util
import json
from pathlib import Path
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("staging", Path(__file__).with_name("stage-drawing.py"))
staging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(staging)


def predictions(sequence):
    observed = []
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / "test.pptx"
        source.touch()
        states = []
        for slide, x in sequence:
            document = str(source) if slide else str(Path(tmp) / "other.pptx")
            states.append(json.dumps(dict(document=document, slideID=slide, width=720, height=540,
                                          objects=[dict(id="shape", x=x)])))
        def record(source, selector, history_file, *args):
            history = json.loads(history_file.read_text())
            assert all(str(state["slideID"]) == selector for state in history)
            observed.append([state["objects"][0]["x"] for state in history])
        with patch.object(staging.subprocess, "check_output", side_effect=states), \
             patch.object(staging, "predict_preview", side_effect=record), patch.object(staging.time, "sleep"):
            try:
                staging.watch_preview(source, Path(tmp) / "preview")
            except StopIteration:
                pass
    return observed


edited = [(1, 10), (1, 20), (1, 20)]
assert predictions(edited + [(2, 5), (1, 20), (1, 20), (1, 30), (1, 30)]) == [[10, 20], [10, 20, 30]]
assert predictions(edited + [(2, 5), (1, 88), (1, 30), (1, 30)]) == [[10, 20], [88, 30]]
assert predictions(edited + [(0, 0), (1, 20), (1, 30), (1, 30)]) == [[10, 20], [20, 30]]
assert predictions(edited + [(i, 5) for i in range(2, 6)] + [(1, 20), (1, 30), (1, 30)]) == [[10, 20], [20, 30]]
print("Verified history across page return, changed content, document switch and cache eviction")


def accepted_baselines(save_before_last_edit):
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        source = folder / "test.pptx"
        source.write_bytes(b"original file")
        reads = []
        def state(x, preset):
            return dict(document=str(source), slideID=256, width=720, height=540,
                        objects=[dict(id="figure", kind="shape type auto", autoShapeType=preset, x=x)])
        before, moved, accepted, next_edit = state(0, "chevron"), state(10, "chevron"), state(10, "diamond"), state(20, "diamond")
        def capture():
            for item in (before, moved, moved, moved, accepted):
                yield json.dumps(item)
            if save_before_last_edit:
                source.write_bytes(b"new saved version")
            for item in (next_edit, next_edit):
                yield json.dumps(item)
        def predict(baseline, selector, history_file, candidate, *args):
            reads.append(baseline.read_bytes())
            if len(reads) == 1:
                candidate.mkdir()
                (candidate / "after.pptx").write_bytes(b"accepted diamond")
                (candidate / "summary.txt").write_text("Change shape")
        def accept(command):
            (Path(command[-1]) / "accepted.json").write_text(json.dumps(accepted))
        with patch.object(staging.subprocess, "check_output", side_effect=capture()), \
             patch.object(staging.subprocess, "run", side_effect=accept), \
             patch.object(staging, "predict_preview", side_effect=predict), patch.object(staging.time, "sleep"):
            try:
                staging.watch_preview(source, folder / "preview", folder / "canvas")
            except StopIteration:
                pass
        return reads

assert accepted_baselines(False) == [b"original file", b"accepted diamond", b"accepted diamond"]
assert accepted_baselines(True) == [b"original file", b"accepted diamond", b"new saved version"]
print("Verified accepted geometry before save and refreshed baseline after save")


def stale_during_prediction():
    source = Path(__file__).resolve().parents[1] / "Examples/Tab-Demo.pptx"
    def snapshot(x):
        objects = [dict(id=json.dumps([f"TextBox {n}", 1], separators=(",", ":")), x=x if n == 1 else n * 190,
                        y=200, width=145, height=45, rotation=0) for n in range(1, 4)]
        return json.dumps(dict(document=str(source), slideID=256, width=720, height=540, objects=objects))
    # First edit changes again before the request. The next changes during inference.
    states = map(snapshot, [10, 20, 20, 30, 30, 30, 30, 40, 40, 40, 40, 40])
    requested = []
    def model(settings, prompt, context, images, schema):
        requested.append(json.loads(context)["current"]["objects"][0]["x"])
        if requested == [30]:
            # This malformed response must be discarded before any validation or rendering.
            return None
        return {"drawing": "", "replaceID": None, "summary": ""}
    with tempfile.TemporaryDirectory() as tmp, patch.object(staging.subprocess, "check_output", side_effect=states), \
         patch.object(staging, "api_proposal", side_effect=model), patch.object(staging, "render_pair") as render, \
         patch.object(staging.time, "sleep"):
        try:
            staging.watch_preview(source, Path(tmp) / "preview", api={"model": "test"})
        except StopIteration:
            pass
        render.assert_not_called()
    assert requested == [30, 40], requested

stale_during_prediction()
print("Verified stale request skipped, stale result discarded and latest edit predicted")


def dismissed_history(mark_dismissed):
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        source = folder / "test.pptx"
        source.touch()
        def state(page, x):
            return json.dumps(dict(document=str(source), slideID=page, width=720, height=540,
                                   objects=[dict(id="shape", x=x)]))
        states = [state(1, 0), state(1, 10), state(1, 10), state(1, 10),
                  state(2, 0), state(2, 20), state(2, 20),
                  state(1, 10), state(1, 30), state(1, 30)]
        requests = []
        def predict(baseline, page, history_file, candidate, refs, dismissed, *args):
            requests.append((page, list(dismissed)))
            if len(requests) == 1:
                candidate.mkdir()
                (candidate / "summary.txt").write_text("Align the third object")
        def preview(command):
            if mark_dismissed:
                (Path(command[-1]) / "dismissed").touch()
        with patch.object(staging.subprocess, "check_output", side_effect=states), \
             patch.object(staging.subprocess, "run", side_effect=preview), \
             patch.object(staging, "predict_preview", side_effect=predict), patch.object(staging.time, "sleep"):
            try:
                staging.watch_preview(source, folder / "preview", folder / "canvas")
            except StopIteration:
                pass
        return requests


assert dismissed_history(True) == [("1", []), ("2", []), ("1", ["Align the third object"])]
assert dismissed_history(False) == [("1", []), ("2", []), ("1", [])]
print("Verified explicit dismissals persist on the original slide and ordinary preview exits do not count")

# Opening a finished page should request one review even with no edit history.
source = Path(__file__).resolve().parents[1] / "Examples/Tab-Demo.pptx"
stationary = json.dumps(dict(document=str(source), slideID=256, width=720, height=540,
                             objects=[dict(id="figure", x=10)]))
with tempfile.TemporaryDirectory() as tmp, patch.object(staging.subprocess, "check_output", side_effect=[stationary] * 6), \
     patch.object(staging, "predict_preview") as review, patch.object(staging.time, "sleep"):
    try:
        staging.watch_preview(source, Path(tmp) / "preview", Path(tmp) / "canvas")
    except StopIteration:
        pass
    review.assert_called_once()
print("Verified one review of a stationary page without repeated idle requests")

# A second suggestion starts from the confirmed writeback even with no new foreground sample.
with tempfile.TemporaryDirectory() as tmp:
    folder = Path(tmp)
    source = folder / "follow.pptx"
    source.touch()
    def page(x):
        return dict(document=str(source), slideID=1, objects=[dict(id="shape", x=x)])
    states = iter(map(json.dumps, [page(0), page(0), page(0), "deferred", "deferred"]))
    requests = []
    def propose(baseline, selector, history_file, candidate, refs, dismissed, image, api, check):
        requests.append(json.loads(history_file.read_text())[-1])
        if len(requests) == 1:
            candidate.mkdir()
            (candidate / "summary.txt").write_text("Move shape")
        else:
            check()
            check()
    def apply(command):
        (Path(command[-1]) / "accepted.json").write_text(json.dumps(page(10)))
    with patch.object(staging.subprocess, "check_output", side_effect=states), \
         patch.object(staging.subprocess, "run", side_effect=apply), \
         patch.object(staging, "predict_preview", side_effect=propose), patch.object(staging.time, "sleep"):
        try:
            staging.watch_preview(source, folder / "preview", folder / "canvas")
        except StopIteration:
            pass
    assert len(requests) == 2 and requests[1]["acceptedSuggestion"] == "Move shape"
    assert requests[1]["objects"] == page(10)["objects"]
print("Verified immediate follow-up from confirmed acceptance while PowerPoint is in the background")

# A completed first prediction can be rendered in the background, but is shown
# only after a matching foreground snapshot is available.
with tempfile.TemporaryDirectory() as tmp:
    folder = Path(tmp)
    source = folder / "background.pptx"
    source.touch()
    current = dict(document=str(source), slideID=1, objects=[dict(id="figure", x=0)])
    samples = iter(map(json.dumps, [current, current, current, "deferred", "deferred", current]))
    events = []
    def render_in_background(baseline, selector, history_file, candidate, refs, dismissed, image, api, check):
        check()
        check()
        candidate.mkdir()
        events.append("rendered")
    with patch.object(staging.subprocess, "check_output", side_effect=samples), \
         patch.object(staging.subprocess, "run", side_effect=lambda command: events.append("shown")), \
         patch.object(staging, "predict_preview", side_effect=render_in_background), patch.object(staging.time, "sleep"):
        try:
            staging.watch_preview(source, folder / "preview", folder / "canvas")
        except StopIteration:
            pass
    assert events == ["rendered", "shown"], events

# An unchanged foreground page gets another assessment after 30 seconds,
# and returning to it also starts a new assessment without another edit.
with tempfile.TemporaryDirectory() as tmp:
    folder = Path(tmp)
    source = folder / "continuous.pptx"
    source.touch()
    page = json.dumps(dict(document=str(source), slideID=1, objects=[dict(id="figure", x=0)]))
    samples = [(0, page), (1, page), (12, page), (32, page), (34, '"deferred"'), (35, page)]
    clock = [0]
    reviews = []
    def read_samples():
        for clock[0], sample in samples:
            yield sample
    with patch.object(staging.subprocess, "check_output", side_effect=read_samples()), \
         patch.object(staging, "predict_preview", side_effect=lambda *args: reviews.append(clock[0])), \
         patch.object(staging.time, "monotonic", side_effect=lambda: clock[0]), patch.object(staging.time, "sleep"):
        try:
            staging.watch_preview(source, folder / "preview", folder / "canvas")
        except StopIteration:
            pass
    assert reviews == [1, 32, 35], reviews
