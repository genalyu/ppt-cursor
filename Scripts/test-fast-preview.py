"""Verify geometry previews preserve the candidate and never launch a renderer."""
import importlib.util
import json
from pathlib import Path
import tempfile
import time
from unittest.mock import patch
from zipfile import ZipFile

spec = importlib.util.spec_from_file_location("staging", Path(__file__).with_name("stage-drawing.py"))
staging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(staging)
source = Path(__file__).resolve().parents[1] / "Examples/Tab-Demo.pptx"
objects = [dict(id=json.dumps([f"TextBox {n}", 1], separators=(",", ":")), x=50 + (n-1)*190,
                y=200, width=145, height=45, rotation=0) for n in range(1, 4)]
state = dict(document=str(source), slideID=256, width=720, height=540, objects=objects)
with tempfile.TemporaryDirectory() as tmp:
    folder = Path(tmp)
    baseline = folder / "baseline.pptx"
    tree = staging.copy_live_geometry(source, "256", state, baseline)
    shape = staging.model_shapes(tree, state)[-1]
    drawing = staging.expand_transform('<a:xfrm><a:off x="5461000" y="1270000"/><a:ext cx="1841500" cy="571500"/></a:xfrm>', shape["drawing"])
    acceptance = staging.native_acceptance(tree, shape["replaceID"], drawing, state, "Align")
    assert acceptance and set(acceptance["edits"][0]) == {"id", "placement", "rotation"}
    fragment = folder / "drawing.xml"
    fragment.write_text(drawing)
    outline = staging.geometry_outline(acceptance, state)
    started = time.monotonic()
    with patch.object(staging, "export_page", side_effect=AssertionError("Geometry preview launched LibreOffice")):
        assert staging.render_pair(baseline, "256", fragment, folder / "fast", shape["replaceID"],
                                   require_visible=True, outline=outline, geometry_state=state)
    fast = time.monotonic() - started
    assert (folder / "fast/geometry-preview").is_file()
    assert (folder / "fast/after.png").stat().st_size > 0
    with ZipFile(folder / "fast/after.pptx") as candidate:
        assert b'y="1270000"' in candidate.read("ppt/slides/slide1.xml")
    print(f"Geometry preview: {fast:.3f}s; valid PPTX, no LibreOffice invocation")
    # Optional local benchmark includes real LibreOffice conversion (not needed in CI).
    import sys
    if "--benchmark" in sys.argv:
        started = time.monotonic()
        assert staging.render_pair(baseline, "256", fragment, folder / "full", shape["replaceID"],
                                   require_visible=True, outline=outline)
        full = time.monotonic() - started
        print(f"Full render: {full:.3f}s; geometry path {full / fast:.1f}x faster on this fixture")
