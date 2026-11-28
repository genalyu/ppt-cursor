"""Check the open-ended Responses API path without sending presentation data."""
import json
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import patch

api_proposal = runpy.run_path(str(Path(__file__).with_name("stage-drawing.py")))["api_proposal"]


class StagedAPITests(unittest.TestCase):
    def setUp(self):
        patcher = patch("http.client.HTTPSConnection")
        self.connection = patcher.start().return_value
        self.addCleanup(patcher.stop)
        self.response = self.connection.getresponse.return_value
        self.response.status = 200

    def predict(self, images=()):
        return api_proposal({"model": "example", "key": "test"}, "instructions", "history", images, {"type": "object"})

    def test_ordered_images_and_structured_result(self):
        proposal = {"summary": "Place logo", "referenceID": "reference-0"}
        self.response.read.return_value = json.dumps({"status": "completed", "output": [
            {"type": "reasoning"}, {"content": [{"type": "output_text", "text": json.dumps(proposal)}]}]})
        with tempfile.TemporaryDirectory() as folder:
            page, logo = (Path(folder) / name for name in ("page.png", "logo.png"))
            page.write_bytes(b"p")
            logo.write_bytes(b"l")
            self.assertEqual(self.predict([page, logo]), proposal)
        args, options = self.connection.request.call_args
        self.assertEqual(args, ("POST", "/v1/responses"))
        body = json.loads(options["body"])
        self.assertIs(body["store"], False)
        self.assertIs(body["text"]["format"]["strict"], True)
        content = body["input"][0]["content"]
        self.assertEqual(content[0]["text"], "history")
        self.assertEqual([item["image_url"] for item in content[1:]],
                         ["data:image/png;base64,cA==", "data:image/png;base64,bA=="])

    def test_bailian_request(self):
        settings = {"model": "qwen4-max", "key": "test",
                    "baseURL": "https://example.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"}
        self.response.read.return_value = b'{"choices":[{"finish_reason":"stop","message":{"content":"{}"}}]}'
        api_proposal(settings, "instructions", "history", [], {"type": "object"})
        args, options = self.connection.request.call_args
        self.assertEqual(args, ("POST", "/compatible-mode/v1/chat/completions"))
        self.assertEqual(json.loads(options["body"])["reasoning_effort"], "low")
        self.assertEqual(options["headers"]["Authorization"], "Bearer test")
        settings["baseURL"] = "https://unrelated.example/compatible-mode/v1"
        with self.assertRaises(ValueError):
            api_proposal(settings, "instructions", "history", [], {})

    def test_invalid_response_is_recoverable(self):
        for raw in ("garbled", '{"status":"incomplete"}', '{"status":"completed","output":null}',
                    '{"status":"completed","output":[null,{"content":[{"type":"output_text"}]}]}'):
            with self.subTest(raw=raw):
                self.response.read.return_value = raw
                with self.assertRaises(ValueError):
                    self.predict()
        for status in (401, 403, 429, 503):
            self.response.status = status
            with self.assertRaises(ValueError):
                self.predict()


if __name__ == "__main__":
    unittest.main()
