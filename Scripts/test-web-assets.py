import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch
from zipfile import ZipFile
from PIL import Image
import web_assets

spec = importlib.util.spec_from_file_location("staging", Path(__file__).with_name("stage-drawing.py"))
staging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(staging)


def page(license_name="Public domain", image="https://upload.wikimedia.org/image.png"):
    return {"title": "File:Solar panel.png", "index": 1, "imageinfo": [{"thumburl": image,
        "descriptionurl": "https://commons.wikimedia.org/wiki/File:Solar_panel.png", "mime": "image/png",
        "extmetadata": {"LicenseShortName": {"value": license_name}, "Artist": {"value": "<b>NASA</b>"}}}]}


class WebAssetTests(unittest.TestCase):
    def test_untrusted_addresses_and_license_filter(self):
        for url in ("http://upload.wikimedia.org/a", "https://127.0.0.1/a", "https://upload.wikimedia.org.evil/a",
                    "https://user@upload.wikimedia.org/a", "https://upload.wikimedia.org:443/a"):
            self.assertFalse(web_assets.allowed_url(url), url)
        self.assertEqual(web_assets.candidates({"query": {"pages": [page("CC BY 4.0"), page(image="https://evil.test/a")]}}), [])
        self.assertEqual(web_assets.candidates({"query": {"pages": [page()]}})[0]["creator"], "NASA")
        with self.assertRaises(ValueError):
            web_assets.VerifiedRedirect().redirect_request(None, None, 302, "", {}, "https://127.0.0.1/private")

    def test_search_downloads_and_normalizes_real_pixels(self):
        data = io.BytesIO()
        Image.new("RGB", (64, 32), "green").save(data, "PNG")
        with tempfile.TemporaryDirectory() as tmp, patch.object(web_assets, "fetch", side_effect=[
            json.dumps({"query": {"pages": [page()]}}).encode(), data.getvalue()]):
            assets = web_assets.search_images("solar panels", Path(tmp))
            self.assertEqual(len(assets), 1)
            with Image.open(assets[0]["path"]) as image:
                self.assertEqual(image.size, (64, 32))
                self.assertEqual(image.mode, "RGBA")
            self.assertEqual(assets[0]["license"], "Public domain")

    def predict_search(self, fail=False, imported=False):
        source = Path(__file__).resolve().parents[1] / "Examples/Tab-Demo.pptx"
        objects = [dict(id=json.dumps([f"TextBox {n}", 1], separators=(",", ":")),
                        x=60+(n-1)*190, y=200, width=145, height=45, rotation=0) for n in range(1, 4)]
        state = dict(document=str(source), slideID=256, width=720, height=540, objects=objects)
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            picture = folder / "solar.png"
            Image.new("RGB", (100, 50), "green").save(picture)
            history = folder / "history.json"
            history.write_text(json.dumps([state]))
            provenance = {"path": picture, "title": "Solar panel", "license": "Public domain",
                          "sourceURL": "https://commons.wikimedia.org/wiki/File:Solar_panel.png", "creator": "NASA"}
            responses = [dict(summary="Search", replaceID=None, drawing="", referenceID=None,
                              placement=None, imageSearch="solar panels"),
                         dict(summary="Insert image", replaceID=None, drawing="", imageSearch=None,
                              referenceID=None if fail else ("reference-1" if imported else "reference-0"),
                              placement=None if fail else dict(x=50, y=50, width=200, height=100))]
            calls = []
            def model(settings, instructions, context, images, schema):
                calls.append((json.loads(context), images, schema))
                return responses[len(calls)-1]
            def render(baseline, selector, fragment, output, replace_id, **kwargs):
                output.mkdir()
                staging.stage_reference(baseline, selector, output / "after.pptx", *kwargs["reference_picture"])
                return True
            staging._last_phase = None
            log = io.StringIO()
            with patch.object(staging, "api_proposal", side_effect=model), \
                 patch.object(staging, "web_search", side_effect=OSError("offline") if fail else None,
                              return_value=[provenance]), \
                 patch.object(staging, "render_pair", side_effect=render) as renderer, redirect_stdout(log):
                staging.predict_preview(source, "256", history, folder / "output",
                                        references=[(picture, "User supplied")] if imported else [], api={"model": "test"})
            phases = [line for line in log.getvalue().splitlines() if line.startswith("PPT_CURSOR_PHASE=")]
            self.assertEqual(phases[:3], ["PPT_CURSOR_PHASE=预测", "PPT_CURSOR_PHASE=搜素材", "PPT_CURSOR_PHASE=预测"])
            self.assertEqual(len(calls), 2)
            self.assertIn("imageSearch", calls[0][2]["required"])
            if fail:
                renderer.assert_not_called()
                self.assertEqual(calls[1][0]["references"], [])
            else:
                self.assertEqual(phases[-1], "PPT_CURSOR_PHASE=生成预览")
                self.assertEqual(len(calls[1][0]["references"]), 2 if imported else 1)
                self.assertEqual(len(calls[1][1]), 2 if imported else 1)
                with ZipFile(folder / "output/after.pptx") as package:
                    xml = package.read("ppt/slides/slide1.xml").decode()
                    self.assertIn("Source: https://commons.wikimedia.org/", xml)
                    self.assertIn("License: Public domain", xml)
                self.assertTrue((folder / "output/asset-source.json").is_file())

    def test_model_can_search_without_user_images(self):
        self.predict_search()

    def test_user_images_remain_optional_and_available(self):
        self.predict_search(imported=True)

    def test_search_failure_returns_to_normal_prediction(self):
        self.predict_search(fail=True)

if __name__ == "__main__":
    unittest.main()
