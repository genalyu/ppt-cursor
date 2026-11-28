"""Session-scoped renderer profiles: reuse, isolation, cleanup and failure recovery."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from urllib.parse import urlsplit, unquote

spec = importlib.util.spec_from_file_location('staging', Path(__file__).with_name('stage-drawing.py'))
staging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(staging)


class RenderWorkspaceTests(unittest.TestCase):
    def test_nested_exports_reuse_profile_but_sessions_are_isolated(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            seen = []
            def renderer(command, timeout):
                profile = Path(unquote(urlsplit(command[1].split('=', 1)[1]).path))
                seen.append(profile)
                self.assertEqual(profile.stat().st_mode & 0o777, 0o700)
                out = Path(command[command.index('--outdir')+1])
                for source in command[command.index('--outdir')+2:]:
                    (out / (Path(source).stem+'.pdf')).write_bytes(b'fixture')
            with patch.object(staging, 'run_renderer', side_effect=renderer):
                with staging.render_workspace(root) as session:
                    first_root = session.root
                    staging.export_page(root, 1, [root/'before.pptx'])
                    with staging.render_workspace(root) as nested:
                        self.assertIs(nested, session)
                        staging.export_page(root, 1, [root/'after.pptx'])
                self.assertFalse(first_root.exists())
                self.assertIsNone(staging._render_workspace.get())
                with staging.render_workspace(root):
                    staging.export_page(root, 1, [root/'again.pptx'])
            self.assertEqual(seen[0], seen[1])
            self.assertNotEqual(seen[1], seen[2])
            self.assertFalse(seen[2].exists())

    def test_failed_export_rotates_profile_and_does_not_poison_next_export(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for failure in ('timeout', 'missing', 'oserror'):
                with self.subTest(failure=failure), staging.render_workspace(root) as session:
                    previous = session.profile
                    effect = (ValueError('页面渲染超时') if failure == 'timeout' else
                              OSError('Cannot start renderer') if failure == 'oserror' else None)
                    with patch.object(staging, 'run_renderer', side_effect=effect), self.assertRaises((ValueError,OSError)):
                        staging.export_page(root, 1, [root/'missing.pptx'])
                    self.assertNotEqual(session.profile, previous)
                    self.assertFalse(previous.exists())
                    def success(command, timeout):
                        self.assertIn(session.profile.as_uri(), command[1])
                        (root/'recovered.pdf').write_bytes(b'recovered')
                    with patch.object(staging, 'run_renderer', side_effect=success):
                        staging.export_page(root, 1, [root/'recovered.pptx'])

    def test_exception_cleans_profile_and_restores_context(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(RuntimeError, 'cancelled'):
                with staging.render_workspace(Path(folder)) as session:
                    owned = session.root
                    raise RuntimeError('cancelled')
            self.assertFalse(owned.exists())
            self.assertIsNone(staging._render_workspace.get())


def benchmark():
    from PIL import Image, ImageChops
    from zipfile import ZipFile
    source = Path(__file__).resolve().parents[1] / 'Examples/Tab-Demo.pptx'
    records = []
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        objects = [dict(id=json.dumps([f'TextBox {i}',1], separators=(',',':')), text=text,
                        x=60+(i-1)*190,y=200,width=145,height=45,rotation=0,fontSize=22)
                   for i,text in enumerate(('Research','Design','Deliver'),1)]
        state=dict(document=str(source),slideID=256,width=720,height=540,objects=objects)
        baseline=root/'baseline.pptx'
        tree=staging.copy_live_geometry(source,'256',state,baseline)
        shape=staging.model_shapes(tree,state)[0]
        proposal=dict(drawing='',replaceID=shape['replaceID'],textEdit=dict(text='Discover',fontSize=None))
        fragment=root/'fragment.xml';fragment.write_text(staging.expand_text_edit(proposal,[shape]))
        with staging.render_workspace(root):
            for index in range(3):
                output=root/f'shared-{index}'
                started=time.monotonic()
                staging.render_pair(baseline,'256',fragment,output,shape['replaceID'],require_visible=True)
                records.append(dict(mode='session-cold' if index==0 else 'session-warm',seconds=round(time.monotonic()-started,3)))
        for index in range(2):
            output=root/f'isolated-{index}'
            started=time.monotonic()
            staging.render_pair(baseline,'256',fragment,output,shape['replaceID'],require_visible=True)
            records.append(dict(mode='isolated',seconds=round(time.monotonic()-started,3)))
        for output in [root/'shared-1',root/'shared-2',root/'isolated-0',root/'isolated-1']:
            for name in ('before.png','after.png','overlay.png'):
                with Image.open(root/'shared-0'/name) as a, Image.open(output/name) as b:
                    assert a.size==b.size, name
                    assert all(high==0 for low,high in ImageChops.difference(a.convert('RGBA'),b.convert('RGBA')).getextrema()), name
            with ZipFile(root/'shared-0/after.pptx') as a, ZipFile(output/'after.pptx') as b:
                assert a.namelist()==b.namelist() and all(a.read(name)==b.read(name) for name in a.namelist())
    print(json.dumps({'samples':records,'identicalPreviewPixelsAndPPTXParts':True},indent=2))


if __name__=='__main__':
    if '--benchmark' in sys.argv:
        benchmark()
    else:
        unittest.main()
