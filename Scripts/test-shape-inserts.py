"""Compact diagram proposals must compile to editable, bounded native additions."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from xml.etree import ElementTree as ET
from zipfile import ZipFile

spec=importlib.util.spec_from_file_location('staging',Path(__file__).with_name('stage-drawing.py'))
staging=importlib.util.module_from_spec(spec);spec.loader.exec_module(staging)
compiler=staging.shape_insert_module()
P,A=compiler.P,compiler.A


def labels():
    return dict(name='Stage numbers',fill=None,line=None,textColor='287589',fontFace='Arial',fontSize=12,
                bold=False,align='left',textInset=7.2,items=[dict(kind='text',box=[x,175,145,20],text=text)
                    for x,text in zip((60,250,440),('01','02','03'))])


def proposal(insertion):
    return dict(summary='Add numbered labels',replaceID=None,drawing='',textEdit=None,
                referenceID=None,placement=None,imageSearch=None,shapeInsert=insertion)


class ShapeInsertTests(unittest.TestCase):
    def test_native_group_geometry_styles_and_untouched_package_parts(self):
        insertion=labels();drawing=compiler.expand(insertion,dict(width=720,height=540))
        tree=ET.fromstring(drawing)
        self.assertEqual(tree.tag,f'{{{P}}}grpSp')
        group=tree.find(f'{{{P}}}grpSpPr/{{{A}}}xfrm')
        self.assertEqual(group.find(f'{{{A}}}off').attrib,dict(x='762000',y='2222500'))
        self.assertEqual(group.find(f'{{{A}}}chOff').attrib,group.find(f'{{{A}}}off').attrib)
        self.assertEqual(group.find(f'{{{A}}}chExt').attrib,group.find(f'{{{A}}}ext').attrib)
        self.assertEqual([node.text for node in tree.iter(f'{{{A}}}t')],['01','02','03'])
        for body in tree.iter(f'{{{A}}}bodyPr'):
            self.assertEqual((body.get('lIns'),body.get('rIns')),('91440','91440'))
        for font in tree.iter(f'{{{A}}}rPr'):
            self.assertEqual(font.attrib,dict(sz='1200',b='0',i='0'))
            self.assertEqual(font.find(f'{{{A}}}solidFill/{{{A}}}srgbClr').get('val'),'287589')
            self.assertEqual(font.find(f'{{{A}}}latin').get('typeface'),'Arial')
        with tempfile.TemporaryDirectory() as folder:
            folder=Path(folder);fragment=folder/'insert.xml';fragment.write_text(drawing)
            source=Path(__file__).resolve().parents[1]/'Examples/Tab-Demo.pptx'
            out=folder/'after.pptx';target=staging.stage(source,'256',fragment,out)
            self.assertEqual(target['operation'],'insert')
            self.assertEqual(target['name'],'Stage numbers')
            with ZipFile(source) as old,ZipFile(out) as new:
                for name in old.namelist():
                    if name!='ppt/slides/slide1.xml':self.assertEqual(old.read(name),new.read(name))
                before=ET.fromstring(old.read('ppt/slides/slide1.xml'))
                after=ET.fromstring(new.read('ppt/slides/slide1.xml'))
                path=f'{{{P}}}cSld/{{{P}}}spTree'
                self.assertEqual([staging.drawing_signature(n) for n in before.find(path)],
                                 [staging.drawing_signature(n) for n in after.find(path)][:-1])
                ids=[n.get('id') for n in after.iter(f'{{{P}}}cNvPr')]
                self.assertEqual(len(ids),len(set(ids)))
        compact=len(json.dumps(proposal(insertion),ensure_ascii=False).encode())
        full=len(json.dumps(dict(proposal(None),drawing=drawing),ensure_ascii=False).encode())
        self.assertLess(compact,full/2)
        print(f'Identical numbered-label content: compact {compact} bytes vs DrawingML {full} bytes')

    def test_shapes_and_xml_escaping(self):
        for kind in compiler.KINDS:
            with self.subTest(kind=kind):
                insertion=labels();insertion.update(fill='aAbBcC',line='123456',name='A & <B> "C"')
                insertion['items']=[dict(kind=kind,box=[10,20,100,40],text='A & <B> "C"')]
                tree=ET.fromstring(compiler.expand(insertion,dict(width=720,height=540)))
                self.assertEqual(tree.tag,f'{{{P}}}sp')
                self.assertEqual(tree.find(f'{{{P}}}spPr/{{{A}}}prstGeom').get('prst'),'rect' if kind=='text' else kind)
                self.assertEqual(tree.find(f'.//{{{A}}}t').text,'A & <B> "C"')
                self.assertEqual(tree.find(f'{{{P}}}nvSpPr/{{{P}}}cNvPr').get('name'),'A & <B> "C"')
                self.assertEqual(tree.find(f'{{{P}}}spPr/{{{A}}}solidFill/{{{A}}}srgbClr').get('val'),'AABBCC')

    def test_invalid_and_unsupported_content_is_rejected(self):
        changes=[dict(extra=True),dict(items=[]),dict(items=labels()['items']*5),dict(fill='red'),dict(line='FF000000'),
                 dict(textColor=None),dict(fontFace=''),dict(fontFace='bad\x00font'),dict(name=''),dict(bold=1),dict(align='justify'),dict(textInset=True),dict(textInset=-1),dict(textInset=2001),dict(textInset=100)]
        changes += [dict(fontSize=size) for size in (True,0,4001,float('nan'),float('inf'),'12')]
        changes += [dict(items=[dict(kind='text',box=box,text='X')]) for box in
                    ([0,0,1],[0,0,0,5],[0,0,1e-10,5],[0,0,3000,5],[800,0,20,20],[0,0,True,20],[0,float('nan'),20,20])]
        changes += [dict(items=[dict(kind=kind,box=[0,0,20,20],text='X')]) for kind in ('script','image','line')]
        changes += [dict(items=[dict(kind='text',box=[0,0,20,20],text=text)]) for text in ('','a\nb','bad\x00','x'*2001)]
        for change in changes:
            with self.subTest(change=change),self.assertRaises(ValueError):
                compiler.expand(dict(labels(),**change),dict(width=720,height=540))
        for field,value in [('drawing','<p:sp/>'),('replaceID',1),('textEdit',{}),('referenceID','reference-0'),
                            ('placement',{}),('imageSearch','photos')]:
            with self.subTest(field=field),self.assertRaises(ValueError):
                staging.expand_shape_insert(dict(proposal(labels()),**{field:value}),dict(width=720,height=540))

    def test_prediction_routes_compact_insertion_through_normal_staging(self):
        with tempfile.TemporaryDirectory() as folder:
            folder=Path(folder);source=Path(__file__).resolve().parents[1]/'Examples/Tab-Demo.pptx'
            state=dict(document=str(source),slideID=256,width=720,height=540,objects=[
                dict(id=json.dumps([f'TextBox {i}',1],separators=(',',':')),x=x,y=200,width=145,height=45,rotation=0,text=text)
                for i,x,text in zip((1,2,3),(60,250,440),('Research','Design','Deliver'))])
            history=folder/'history.json';history.write_text(json.dumps([state]));out=folder/'preview'
            def render(baseline,selector,fragment,destination,replace_id,**kwargs):
                self.assertIsNone(replace_id);self.assertIsNone(kwargs.get('geometry_state'))
                destination.mkdir();target=staging.stage(baseline,selector,fragment,destination/'after.pptx')
                (destination/'target.json').write_text(json.dumps(target));return True
            with patch.object(staging,'api_proposal',return_value=proposal(labels())) as model,patch.object(staging,'render_pair',side_effect=render):
                staging.predict_preview(source,'256',history,out,api={'model':'test'})
            schema=model.call_args.args[-1]
            self.assertIn('shapeInsert',schema['required'])
            self.assertFalse(schema['properties']['shapeInsert']['additionalProperties'])
            self.assertEqual(json.loads((out/'metrics.json').read_text())['proposalKind'],'shapeInsert')
            self.assertEqual(json.loads((out/'target.json').read_text())['operation'],'insert')
            self.assertFalse((out/'accept.json').exists())  # Existing native staged-shape insertion path.


if __name__=='__main__':unittest.main()
