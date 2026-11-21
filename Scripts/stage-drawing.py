#!/usr/bin/env python3
"""Place a model-authored DrawingML shape into a disposable PPTX for preview."""
import argparse
import json
import os
from pathlib import Path
import posixpath
import re
import shutil
import subprocess
import tempfile
from xml.dom import Node, minidom
from xml.etree import ElementTree
from zipfile import ZipFile

P = "http://schemas.openxmlformats.org/presentationml/2006/main"
A = "http://schemas.openxmlformats.org/drawingml/2006/main"
XMLNS = "http://www.w3.org/2000/xmlns/"


def slide_part(package, selector):
    if re.fullmatch(r"ppt/slides/slide[1-9][0-9]*\.xml", selector):
        return selector
    if not re.fullmatch(r"[1-9][0-9]*", selector):
        raise ValueError("Expected a live slide ID or a slide part name")
    rel_ns = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    pkg_ns = "http://schemas.openxmlformats.org/package/2006/relationships"
    presentation = ElementTree.fromstring(package.read("ppt/presentation.xml"))
    entries = presentation.findall(f"{{{P}}}sldIdLst/{{{P}}}sldId")
    matches = [entry for entry in entries if entry.get("id") == selector]
    if len(matches) != 1:
        raise ValueError("Slide ID does not uniquely identify a slide in this presentation")
    rid = matches[0].attrib[f"{{{rel_ns}}}id"]
    relations = ElementTree.fromstring(package.read("ppt/_rels/presentation.xml.rels"))
    targets = [r.attrib["Target"] for r in relations.findall(f"{{{pkg_ns}}}Relationship")
               if r.get("Id") == rid and r.get("Type") == rel_ns + "/slide"
               and r.get("TargetMode", "Internal") == "Internal"]
    if len(targets) != 1:
        raise ValueError("Missing internal slide relationship")
    return posixpath.normpath(posixpath.join("ppt", targets[0])).lstrip("/")


def stage(source, part, fragment, output, replace_id=None):
    raw = fragment.read_bytes()
    if len(raw) > 200_000 or b"<!" in raw or b"<?" in raw:
        raise ValueError("Expected a self-contained UTF-8 DrawingML fragment")
    wrapper = f'<root xmlns:p="{P}" xmlns:a="{A}">{raw.decode("utf-8")}</root>'
    root = minidom.parseString(wrapper).documentElement
    shapes = [node for node in root.childNodes if node.nodeType == Node.ELEMENT_NODE]
    if len(shapes) != 1 or (shapes[0].namespaceURI, shapes[0].localName) != (P, "sp"):
        raise ValueError("Expected one native p:sp")
    shape = shapes[0]
    for node in [shape, *shape.getElementsByTagName("*")]:
        if node.namespaceURI not in (A, P) or node.localName in ("extLst", "hlinkClick", "hlinkHover"):
            raise ValueError("Unsupported embedded content")
        if any(attr.namespaceURI not in (None, XMLNS) for attr in node.attributes.values()):
            raise ValueError("Shape must be self-contained")
    props = shape.getElementsByTagNameNS(P, "cNvPr")
    if len(props) != 1:
        raise ValueError("Expected one native shape identity")
    with tempfile.TemporaryDirectory(dir=output.parent) as directory:
        candidate = Path(directory) / "candidate.pptx"
        with ZipFile(source) as original, ZipFile(candidate, "w") as staged:
            part = slide_part(original, part)
            slide = minidom.parseString(original.read(part))
            if (slide.documentElement.namespaceURI, slide.documentElement.localName) != (P, "sld"):
                raise ValueError("Relationship target is not a slide")
            tree, = slide.getElementsByTagNameNS(P, "spTree")
            ids = [int(node.getAttribute("id")) for node in slide.getElementsByTagNameNS(P, "cNvPr")]
            shape.setAttribute("xmlns:p", P)
            shape.setAttribute("xmlns:a", A)
            replacement = slide.importNode(shape, True)
            if replace_id is None:
                identity, = replacement.getElementsByTagNameNS(P, "cNvPr")
                identity.setAttribute("id", str(max(ids, default=0) + 1))
                extensions = next((node for node in tree.childNodes if node.namespaceURI == P and node.localName == "extLst"), None)
                tree.insertBefore(replacement, extensions)
            else:
                matches = [node for node in slide.getElementsByTagNameNS(P, "cNvPr")
                           if int(node.getAttribute("id")) == replace_id]
                if len(matches) != 1:
                    raise ValueError("Expected one existing shape with the requested ID")
                metadata = matches[0].parentNode
                target = metadata.parentNode
                if target.parentNode != tree or target.namespaceURI != P or target.localName != "sp":
                    raise ValueError("Replacement requires a top-level native shape")
                incoming, = replacement.getElementsByTagNameNS(P, "nvSpPr")
                replacement.replaceChild(metadata.cloneNode(True), incoming)
                tree.replaceChild(replacement, target)
            for member in original.infolist():
                data = slide.toxml(encoding="utf-8") if member.filename == part else original.read(member)
                staged.writestr(member, data)
        os.link(candidate, output)


def render_pair(source, slide_id, fragment, destination, replace_id):
    """Render both states from one baseline, without taking focus from PowerPoint."""
    office = shutil.which("soffice") or "/Applications/LibreOffice.app/Contents/MacOS/soffice"
    with tempfile.TemporaryDirectory(dir=destination.parent) as folder:
        scratch = Path(folder).resolve()
        baseline = scratch / "before.pptx"
        shutil.copyfile(source, baseline)
        with ZipFile(baseline) as package:
            presentation = ElementTree.fromstring(package.read("ppt/presentation.xml"))
            entries = presentation.findall(f"{{{P}}}sldIdLst/{{{P}}}sldId")
            pages = [i for i, entry in enumerate(entries, 1) if entry.get("id") == slide_id]
            if len(pages) != 1:
                raise ValueError("Preview requires the live slide ID")
        result = scratch / "result"
        result.mkdir()
        candidate = result / "after.pptx"
        stage(baseline, slide_id, fragment, candidate, replace_id)
        settings = {"ExportHiddenSlides": {"type": "boolean", "value": "true"}}
        subprocess.run([office, "-env:UserInstallation=" + (scratch / "profile").as_uri(),
                        "--headless", "--convert-to", "pdf:impress_pdf_Export:" + json.dumps(settings),
                        "--outdir", str(scratch), str(baseline), str(candidate)], check=True, timeout=90)
        for name in ("before", "after"):
            subprocess.run(["pdftoppm", "-f", str(pages[0]), "-l", str(pages[0]), "-singlefile",
                            "-scale-to", "1600", "-png", str(scratch / (name + ".pdf")),
                            str(result / name)], check=True, timeout=30)
        destination.mkdir()
        try:
            for item in result.iterdir():
                item.rename(destination / item.name)
        except BaseException:
            shutil.rmtree(destination)
            raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("slide_part", help="Live PowerPoint slideID or explicit PPTX slide part")
    parser.add_argument("fragment", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--replace-id", type=int, help="Replace this native shape while preserving its identity and layer")
    parser.add_argument("--render-pair", action="store_true", help="Write before.png, after.png and after.pptx to a new output directory (LibreOffice and pdftoppm required)")
    args = parser.parse_args()
    operation = render_pair if args.render_pair else stage
    operation(args.source, args.slide_part, args.fragment, args.output, args.replace_id)
