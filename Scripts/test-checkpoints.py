"""Accepted native objects survive session restart without saving the user's PPTX."""
import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("staging", Path(__file__).with_name("stage-drawing.py"))
staging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(staging)

class CheckpointTests(unittest.TestCase):
    def test_inserted_object_survives_restart_and_file_revision_is_guarded(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            source = folder / "original.pptx"
            shutil.copyfile(Path(__file__).resolve().parents[1] / "Examples/Tab-Demo.pptx", source)
            original = source.read_bytes()
            objects = [dict(id=json.dumps([f"TextBox {n}", 1], separators=(",", ":")),
                            x=60+(n-1)*190, y=200, width=145, height=45) for n in range(1, 4)]
            objects.append(dict(id='["Inserted Step",1]', x=50, y=50, width=100, height=40))
            state = dict(document=str(source), slideID=256, width=720, height=540, objects=objects,
                         acceptedSuggestion="Insert a step")
            drawing = folder / "shape.xml"
            drawing.write_text('''<p:sp><p:nvSpPr><p:cNvPr id="1" name="Inserted Step"/>
              <p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>
              <a:xfrm><a:off x="635000" y="635000"/><a:ext cx="1270000" cy="508000"/></a:xfrm>
              <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:sp>''')
            candidate = folder / "candidate.pptx"
            staging.stage(source, "256", drawing, candidate)
            cache = folder / "cache"
            with patch.dict(staging.os.environ, {"PPT_CURSOR_ACCEPTED_CACHE": str(cache)}):
                staging.save_checkpoint(source, staging.file_revision(source), candidate, [state])
                candidate.unlink()  # original worker and its temporary files are gone
                recovered = staging.restore_checkpoint(source, state, folder)
                self.assertIsNotNone(recovered)
                copy, revision, history = recovered
                self.assertEqual(history[-1]["acceptedSuggestion"], "Insert a step")
                tree = staging.copy_live_geometry(copy, "256", state, folder / "next.pptx")
                self.assertIn(("Inserted Step", 1), staging.native_shape_index(tree))
                self.assertEqual(source.read_bytes(), original)
                self.assertEqual((cache / next(cache.glob('*.zip')).name).stat().st_mode & 0o777, 0o600)
                # A user-created object after pausing invalidates that cached package.
                changed = dict(state, objects=state['objects'] + [dict(id='["User Shape",1]')])
                self.assertIsNone(staging.restore_checkpoint(source, changed, folder))
                # Saving/replacing the source makes its revision authoritative again.
                source.write_bytes(original)
                self.assertIsNone(staging.restore_checkpoint(source, state, folder))

    def test_watch_restores_accepted_baseline_and_history(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, candidate = root / "source.pptx", root / "candidate.pptx"
            source.write_bytes(b"original")
            candidate.write_bytes(b"accepted native group")
            state = dict(document=str(source), slideID=1, objects=[dict(id="group", x=5)],
                         acceptedSuggestion="Insert group")
            with patch.dict(staging.os.environ, {"PPT_CURSOR_ACCEPTED_CACHE": str(root / "cache")}):
                staging.save_checkpoint(source, staging.file_revision(source), candidate, [state])
                observed = []
                current = dict(state)
                current.pop("acceptedSuggestion")
                def predict(baseline, selector, history_file, *args):
                    observed.append((baseline.read_bytes(), json.loads(history_file.read_text())))
                    raise StopIteration()
                with patch.object(staging.subprocess, "check_output", return_value=json.dumps(current)), \
                     patch.object(staging, "predict_preview", side_effect=predict), patch.object(staging.time, "sleep"):
                    with self.assertRaises(StopIteration):
                        staging.watch_preview(source, root / "preview", root / "canvas")
                self.assertEqual(observed[0][0], b"accepted native group")
                self.assertEqual(observed[0][1][-1]["acceptedSuggestion"], "Insert group")

    def test_corrupt_cache_is_ignored(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source.pptx"
            source.touch()
            state = dict(document=str(source), slideID=1, objects=[])
            staging.checkpoint_path(root, source, 1).write_bytes(b"partial write")
            with patch.dict(staging.os.environ, {"PPT_CURSOR_ACCEPTED_CACHE": tmp}):
                self.assertIsNone(staging.restore_checkpoint(source, state, root))

    def test_cache_is_bounded(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source.pptx"
            source.write_bytes(b"candidate")
            cache = root / "cache"
            with patch.dict(staging.os.environ, {"PPT_CURSOR_ACCEPTED_CACHE": str(cache)}):
                for n in range(20):
                    staging.save_checkpoint(source, staging.file_revision(source), source,
                                            [dict(document=str(source), slideID=n+1, objects=[])])
            self.assertEqual(len(list(cache.glob('*.zip'))), 12)
            self.assertEqual(list(cache.glob('*.tmp')), [])

if __name__ == '__main__':
    unittest.main()
