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

assert accepted_baselines(False) == [b"original file", b"accepted diamond"]
assert accepted_baselines(True) == [b"original file", b"new saved version"]
print("Verified accepted geometry before save and refreshed baseline after save")
