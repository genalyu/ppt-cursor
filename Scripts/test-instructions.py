"""Requested edits stay on their page and stop steering after acceptance."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("staging", Path(__file__).with_name("stage-drawing.py"))
staging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(staging)


class InstructionTests(unittest.TestCase):
    def test_scope_and_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "test.pptx"
            source.touch()
            request = dict(text=" 将标题改为测试 ", document=str(source), slideID=256)
            state = dict(document=str(source), slideID=256)
            self.assertEqual(staging.instruction_text(request, source, state), "将标题改为测试")
            for changed in (None, dict(state, slideID=257), dict(state, document=str(source.parent / "other.pptx"))):
                with self.assertRaises(ValueError):
                    staging.instruction_text(request, source, changed)
            for changes in (dict(text=""), dict(text="x"*2001), dict(slideID=True), dict(document="wrong"), dict(extra=1)):
                with self.assertRaises(ValueError):
                    staging.instruction_text(dict(request, **changes), source, state)

    def test_request_is_forwarded_and_explanation_preserved(self):
        source = Path(__file__).resolve().parents[1] / "Examples/Tab-Demo.pptx"
        state = dict(document=str(source), slideID=256, width=720, height=540, objects=[
            dict(id=json.dumps([f"TextBox {n}", 1], separators=(",", ":")),
                 x=60+(n-1)*190, y=200, width=145, height=45, rotation=0)
            for n in range(1, 4)])
        with tempfile.TemporaryDirectory() as tmp:
            history = Path(tmp) / "history.json"
            history.write_text(json.dumps([state]))
            answer = dict(summary="当前标题已经符合要求", drawing="", replaceID=None)
            with patch.object(staging, "api_proposal", return_value=answer) as api:
                reason = staging.predict_preview(source, "256", history, Path(tmp) / "out",
                                                 api={"model": "test"}, user_instruction="保持原有标题")
            self.assertEqual(reason, answer["summary"])
            self.assertEqual(json.loads(api.call_args.args[2])["userRequest"], "保持原有标题")
            self.assertIn("Prioritize that request", api.call_args.args[1])

    def test_acceptance_returns_to_automatic_suggestions(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            source = folder / "test.pptx"
            source.touch()
            before = dict(document=str(source), slideID=256, width=720, height=540,
                          objects=[dict(id="shape", x=0)])
            after = dict(before, objects=[dict(id="shape", x=10)])
            request = dict(text="向右移动", document=str(source), slideID=256)
            seen = []
            def predict(baseline, slide, history, candidate, *args, **kwargs):
                seen.append(kwargs.get("user_instruction"))
                if len(seen) == 2:
                    raise StopIteration()
                candidate.mkdir()
                (candidate / "summary.txt").write_text("Move")
            def accept(command):
                (Path(command[-1]) / "accepted.json").write_text(json.dumps(after))
            with patch.object(staging.subprocess, "check_output", return_value=json.dumps(before)), \
                    patch.object(staging.subprocess, "run", side_effect=accept), \
                    patch.object(staging, "predict_preview", side_effect=predict), patch.object(staging.time, "sleep"):
                with self.assertRaises(StopIteration):
                    staging.watch_preview(source, folder / "preview", folder / "canvas", instruction=request)
            self.assertEqual(seen, ["向右移动", None])


if __name__ == "__main__":
    unittest.main()
