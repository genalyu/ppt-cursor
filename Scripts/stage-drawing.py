#!/usr/bin/env python3
"""Place a model-authored DrawingML shape into a disposable PPTX for preview."""
import argparse
import os
from pathlib import Path
import re
import tempfile
from xml.dom import Node, minidom
from zipfile import ZipFile

P = "http://schemas.openxmlformats.org/presentationml/2006/main"
A = "http://schemas.openxmlformats.org/drawingml/2006/main"
XMLNS = "http://www.w3.org/2000/xmlns/"


def stage(source, part, fragment, output, replace_id=None):
    if not re.fullmatch(r"ppt/slides/slide[1-9][0-9]*\.xml", part):
        raise ValueError("Expected a slide part name")
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
            slide = minidom.parseString(original.read(part))
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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("slide_part")
    parser.add_argument("fragment", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--replace-id", type=int, help="Replace this native shape while preserving its identity and layer")
    args = parser.parse_args()
    stage(args.source, args.slide_part, args.fragment, args.output, args.replace_id)
