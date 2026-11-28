"""Compact model edits must preserve styling and remain native-write compatible."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from xml.etree import ElementTree as ET
from zipfile import ZipFile

spec = importlib.util.spec_from_file_location("staging", Path(__file__).with_name("stage-drawing.py"))
staging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(staging)
A, P = staging.A, staging.P


class TextEditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.source = self.folder / "source.pptx"
        fixture = Path(__file__).resolve().parents[1] / "Examples/Tab-Demo.pptx"
        with ZipFile(fixture) as original, ZipFile(self.source, "w") as dest:
            for member in original.infolist():
                data = original.read(member)
                if member.filename == "ppt/slides/slide1.xml":
                    data = data.replace(b"<a:r>", b'<a:r><a:rPr sz="2200" b="1" i="1"><a:solidFill><a:srgbClr val="287589"/></a:solidFill><a:latin typeface="Arial"/></a:rPr>')
                dest.writestr(member, data)
        self.state = dict(document=str(self.source), slideID=256, width=720, height=540, objects=[
            dict(id=json.dumps([f"TextBox {n}", 1], separators=(",", ":")), text=text, fontSize=22,
                 x=60+(n-1)*190, y=200, width=145, height=45, rotation=0)
            for n, text in enumerate(("Research", "Design", "Deliver"), 1)])
        self.baseline = self.folder / "baseline.pptx"
        self.tree = staging.copy_live_geometry(self.source, "256", self.state, self.baseline)
        self.shapes = staging.model_shapes(self.tree, self.state)
        self.shape = self.shapes[0]
        self.proposal = dict(summary="精简文案", replaceID=self.shape["replaceID"], drawing="",
                             referenceID=None, placement=None, imageSearch=None,
                             textEdit=dict(text="Research & <discover>", fontSize=28))

    def test_preserves_styles_and_produces_native_edit(self):
        drawing = staging.expand_text_edit(self.proposal, self.shapes)
        acceptance = staging.native_acceptance(self.tree, self.shape["replaceID"], drawing, self.state, "Edit")
        self.assertEqual(acceptance["edits"][0]["text"], "Research & <discover>")
        self.assertEqual(acceptance["edits"][0]["fontSize"], 28)
        element = ET.fromstring(f'<root xmlns:p="{P}" xmlns:a="{A}">{drawing}</root>')[0]
        font = element.find(f"{{{P}}}txBody/{{{A}}}p/{{{A}}}r/{{{A}}}rPr")
        self.assertEqual(font.attrib, dict(sz="2800", b="1", i="1"))
        self.assertEqual(font.find(f"{{{A}}}solidFill/{{{A}}}srgbClr").get("val"), "287589")
        self.assertEqual(font.find(f"{{{A}}}latin").get("typeface"), "Arial")
        fragment = self.folder / "drawing.xml"
        fragment.write_text(drawing)
        candidate = self.folder / "after.pptx"
        staging.stage(self.baseline, "256", fragment, candidate, self.shape["replaceID"])
        with ZipFile(candidate) as result, ZipFile(self.baseline) as original:
            for name in original.namelist():
                if name != "ppt/slides/slide1.xml":
                    self.assertEqual(result.read(name), original.read(name))
            slide = ET.fromstring(result.read("ppt/slides/slide1.xml"))
            self.assertEqual([node.text for node in slide.iter(f"{{{A}}}t")],
                             ["Research & <discover>", "Design", "Deliver"])

    def test_unsupported_or_stale_text_is_not_advertised(self):
        template = self.shape["drawing"]
        mixed = template.replace("</a:r>", "</a:r><a:r><a:rPr sz=\"2200\"/><a:t> extra</a:t></a:r>")
        self.assertEqual(staging.text_edit_fields(mixed, self.state["objects"][0]), ["fontSize"])
        self.assertEqual(staging.text_edit_fields(template, dict(text="Changed", fontSize=18)), [])
        inherited = template.replace(' sz="2200"', '')
        self.assertEqual(staging.text_edit_fields(inherited, self.state["objects"][0]), ["text", "fontSize"])
        field = template.replace("<a:r>", '<a:fld id="1" type="slidenum">').replace("</a:r>", "</a:fld>")
        self.assertEqual(staging.text_edit_fields(field, self.state["objects"][0]), [])

    def test_inherited_font_sizes_and_mixed_run_styles(self):
        template = self.shape["drawing"]
        variants = [template.replace(' sz="2200"', ''),
                    template.replace(template[template.index("<a:rPr"):template.index("</a:rPr>")+len("</a:rPr>")], ''),
                    template.replace("</a:r>", '</a:r><a:r><a:rPr i="1"/><a:t> extra</a:t></a:r>')]
        for drawing in variants:
            with self.subTest(drawing=drawing):
                target = dict(self.state["objects"][0])
                if "extra" in drawing:
                    target["text"] += " extra"
                shape = dict(self.shape, drawing=drawing, textEditFields=staging.text_edit_fields(drawing, target))
                proposal = dict(self.proposal, textEdit=dict(text=None, fontSize=28))
                expanded = staging.expand_text_edit(proposal, [shape])
                parse = lambda xml: ET.fromstring(f'<root xmlns:p="{P}" xmlns:a="{A}">{xml}</root>')[0]
                accepted = staging.equivalent_edit(parse(drawing), parse(expanded), target)
                self.assertEqual(accepted["fontSize"], 28)
                # An unrelated style change must still fail the native equivalence guard.
                altered = expanded.replace('sz="2800"', 'sz="2800" u="sng"', 1)
                self.assertIsNone(staging.equivalent_edit(parse(drawing), parse(altered), target))
                self.assertIsNone(staging.equivalent_edit(parse(drawing), parse(expanded), dict(target, fontSize=None)))

    def test_uniform_style_toggle_preserves_other_formatting(self):
        parse = lambda xml: ET.fromstring(f'<root xmlns:p="{P}" xmlns:a="{A}">{xml}</root>')[0]
        target = dict(self.state["objects"][0], textBold=True, textItalic=True)
        variants = [self.shape["drawing"], self.shape["drawing"].replace(' b="1" i="1"', ''),
                    self.shape["drawing"].replace('</a:r>', '</a:r><a:r><a:rPr b="1" i="1"/><a:t> more</a:t></a:r>')]
        for template in variants:
            with self.subTest(template=template):
                shape = dict(self.shape, drawing=template, textEditFields=staging.text_edit_fields(template, target))
                proposal = dict(self.proposal, textEdit=dict(text=None, fontSize=None, textBold=False, textItalic=False))
                drawing = staging.expand_text_edit(proposal, [shape])
                result = staging.equivalent_edit(parse(template), parse(drawing), target)
                self.assertFalse(result["textBold"])
                self.assertFalse(result["textItalic"])
                self.assertNotIn("text", result)
                self.assertNotIn("fontSize", result)
                self.assertIsNone(staging.equivalent_edit(parse(template), parse(drawing), dict(target, textBold=None)))
                self.assertIsNone(staging.equivalent_edit(parse(template), parse(drawing.replace('287589','FF0000')), target))
        no_properties = self.shape["drawing"]
        start, end = no_properties.index('<a:rPr'), no_properties.index('</a:rPr>') + len('</a:rPr>')
        no_properties = no_properties[:start] + no_properties[end:]
        target.update(textBold=False, textItalic=False)
        shape = dict(self.shape, drawing=no_properties, textEditFields=staging.text_edit_fields(no_properties, target))
        proposal = dict(self.proposal, textEdit=dict(text=None, fontSize=28, textBold=True, textItalic=True))
        result = staging.equivalent_edit(parse(no_properties), parse(staging.expand_text_edit(proposal, [shape])), target)
        self.assertEqual((result["textBold"], result["textItalic"], result["fontSize"]), (True, True, 28))
        for value in (0, 1, "true", [], {}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                staging.expand_text_edit(dict(proposal, textEdit=dict(text=None, fontSize=None, textBold=value)), [shape])
        mixed = no_properties.replace('</a:r>', '</a:r><a:r><a:rPr b="1"/><a:t> bold</a:t></a:r>')
        self.assertNotIn("textBold", staging.text_edit_fields(mixed, target))

    def test_unsaved_style_updates_model_and_render_baseline(self):
        state = copy.deepcopy(self.state)
        state["objects"][0].update(textBold=False, textItalic=False)
        tree = staging.copy_live_geometry(self.source, "256", state, self.folder / "style.pptx")
        shape = staging.model_shapes(tree, state)[0]
        self.assertIn('b="0" i="0"', shape["drawing"])
        self.assertIn("textBold", shape["textEditFields"])
        self.assertIn("textItalic", shape["textEditFields"])
        proposal = dict(self.proposal, textEdit=dict(text=None, fontSize=None, textBold=True, textItalic=True))
        drawing = staging.expand_text_edit(proposal, [shape])
        accepted = staging.native_acceptance(tree, shape["replaceID"], drawing, state, "Emphasize")
        self.assertTrue(accepted["edits"][0]["textBold"])
        self.assertTrue(accepted["edits"][0]["textItalic"])

    def test_invalid_or_conflicting_edits_are_rejected(self):
        invalid = [dict(textEdit={}), dict(textEdit=dict(text=None, fontSize=None)),
                   dict(textEdit=dict(text="a\nb", fontSize=None)), dict(textEdit=dict(text="\x00", fontSize=None)),
                   dict(textEdit=dict(text=True, fontSize=None)), dict(textEdit=dict(text="x"*20001, fontSize=None)),
                   *[dict(textEdit=dict(text=None, fontSize=size)) for size in (True, "24", 0, 4001, float("nan"), float("inf"))],
                   dict(drawing="<p:sp/>"), dict(replaceID=None), dict(replaceID=999),
                   dict(referenceID="reference-0"), dict(placement={}), dict(imageSearch="trees")]
        for changes in invalid:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                staging.expand_text_edit(dict(self.proposal, **changes), self.shapes)
        self.assertEqual(staging.expand_text_edit(dict(self.proposal, textEdit=None, drawing="existing"), self.shapes), "existing")

    def test_unsaved_font_size_updates_inherited_baseline(self):
        fixture = Path(__file__).resolve().parents[1] / "Examples/Tab-Demo.pptx"
        state = copy.deepcopy(self.state)
        state["objects"][0]["fontSize"] = 24
        tree = staging.copy_live_geometry(fixture, "256", state, self.folder / "unsaved.pptx")
        shapes = staging.model_shapes(tree, state)
        self.assertIn('<a:rPr sz="2400"', shapes[0]["drawing"])
        self.assertNotIn("<a:rPr", shapes[1]["drawing"])
        proposal = dict(self.proposal, textEdit=dict(text=None, fontSize=28))
        drawing = staging.expand_text_edit(proposal, shapes)
        acceptance = staging.native_acceptance(tree, proposal["replaceID"], drawing, state, "Resize")
        self.assertEqual(acceptance["edits"][0]["fontSize"], 28)

    def test_office_extension_does_not_break_other_shapes(self):
        shapes = self.tree.getElementsByTagNameNS(P, "sp")
        properties = shapes[0].getElementsByTagNameNS(A, "rPr")[0]
        hyperlink = self.tree.ownerDocument.createElementNS(A, "a:hlinkClick")
        hyperlink.setAttributeNS("http://schemas.openxmlformats.org/officeDocument/2006/relationships", "r:id", "rId1")
        properties.appendChild(hyperlink)
        catalog = staging.model_shapes(self.tree, self.state)
        self.assertEqual(catalog[0]["textEditFields"], [])
        self.assertEqual(catalog[1]["textEditFields"], ["text", "fontSize"])

    def test_prediction_pipeline_expands_before_native_validation(self):
        history = self.folder / "history.json"
        history.write_text(json.dumps([self.state]))
        output = self.folder / "preview"
        def render(source, selector, fragment, destination, replace_id, **kwargs):
            destination.mkdir()
            staging.stage(source, selector, fragment, destination / "after.pptx", replace_id)
            return True
        with patch.object(staging, "api_proposal", return_value=copy.deepcopy(self.proposal)) as api, \
                patch.object(staging, "render_pair", side_effect=render):
            staging.predict_preview(self.source, "256", history, output, api={"model": "test"})
        self.assertEqual(json.loads((output / "accept.json").read_text())["edits"][0]["fontSize"], 28)
        metrics = json.loads((output / "metrics.json").read_text())
        self.assertEqual(metrics["proposalKind"], "textEdit")
        self.assertEqual(len(metrics["modelSeconds"]), 1)
        self.assertFalse(metrics["requestedEdit"])
        self.assertNotIn("Research", json.dumps(metrics))
        schema = api.call_args.args[-1]
        self.assertIn("textEdit", schema["required"])
        self.assertFalse(schema["properties"]["textEdit"]["additionalProperties"])
        compact = len(json.dumps(self.proposal).encode())
        full = len(json.dumps(dict(self.proposal, textEdit=None,
                                  drawing=staging.expand_text_edit(self.proposal, self.shapes))).encode())
        print(f"Styled text fixture: compact {compact} bytes vs full DrawingML {full} bytes")


if __name__ == "__main__":
    unittest.main()
