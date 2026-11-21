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
