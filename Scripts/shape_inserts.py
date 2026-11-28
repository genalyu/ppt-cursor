"""Compile compact diagram additions into self-contained editable DrawingML."""
import math
import re
from xml.dom import minidom

P = 'http://schemas.openxmlformats.org/presentationml/2006/main'
A = 'http://schemas.openxmlformats.org/drawingml/2006/main'
KINDS = ('text', 'rect', 'roundRect', 'ellipse', 'rightArrow', 'leftArrow', 'upArrow', 'downArrow', 'chevron')
FIELDS = ('name', 'fill', 'line', 'textColor', 'fontFace', 'fontSize', 'bold', 'align', 'textInset', 'items')


def schema():
    return {
        'type': ['object', 'null'], 'additionalProperties': False, 'required': list(FIELDS),
        'properties': {
            'name': {'type': 'string'},
            'fill': {'type': ['string', 'null']}, 'line': {'type': ['string', 'null']},
            'textColor': {'type': 'string'}, 'fontFace': {'type': 'string'},
            'fontSize': {'type': 'number'}, 'bold': {'type': 'boolean'},
            'textInset': {'type': 'number'},
            'align': {'type': 'string', 'enum': ['left', 'center', 'right']},
            'items': {'type': 'array', 'items': {
                'type': 'object', 'additionalProperties': False, 'required': ['kind', 'box', 'text'],
                'properties': {'kind': {'type': 'string', 'enum': list(KINDS)},
                               'box': {'type': 'array', 'items': {'type': 'number'}},
                               'text': {'type': 'string'}}}}
        }
    }


def valid_text(value, limit, empty=True):
    return (isinstance(value, str) and (empty or bool(value.strip())) and len(value) <= limit
            and not re.search(r'[\x00-\x08\x0a-\x1f\ud800-\udfff\ufffe\uffff]', value))


def expand(insertion, slide):
    if not isinstance(insertion, dict) or set(insertion) != set(FIELDS):
        raise ValueError('图形指令字段无效')
    if not valid_text(insertion['name'], 80, empty=False) or not valid_text(insertion['fontFace'], 100, empty=False):
        raise ValueError('图形名称或字体无效')
    for field in ('fill', 'line', 'textColor'):
        value = insertion[field]
        if value is None and field != 'textColor':
            continue
        if not isinstance(value, str) or not re.fullmatch(r'[0-9a-fA-F]{6}', value):
            raise ValueError('图形颜色必须是六位 RGB 值')
    size = insertion['fontSize']
    if type(size) not in (int, float) or not math.isfinite(size) or not 1 <= size <= 4000:
        raise ValueError('图形字号超出范围')
    if type(insertion['bold']) is not bool or insertion['align'] not in ('left', 'center', 'right'):
        raise ValueError('图形文字样式无效')
    inset = insertion['textInset']
    if type(inset) not in (int, float) or not math.isfinite(inset) or not 0 <= inset <= 2000:
        raise ValueError('文字水平内边距无效')
    items = insertion['items']
    if not isinstance(items, list) or not 1 <= len(items) <= 12:
        raise ValueError('一次图形指令需要 1–12 个图形')
    for item in items:
        if (not isinstance(item, dict) or set(item) != {'kind', 'box', 'text'}
                or item['kind'] not in KINDS or not valid_text(item['text'], 2000)):
            raise ValueError('图形内容无效')
        box = item['box']
        if not isinstance(box, list) or len(box) != 4 or any(type(v) not in (int, float) or not math.isfinite(v) for v in box):
            raise ValueError('图形位置必须为 x、y、宽、高四个数值')
        x, y, width, height = box
        if not (0 < width <= slide['width'] * 4 and 0 < height <= slide['height'] * 4
                and x < slide['width'] and y < slide['height'] and x+width > 0 and y+height > 0
                and round(width*12700) > 0 and round(height*12700) > 0):
            raise ValueError('图形尺寸或位置超出页面范围')
        if item['text'] and inset * 2 >= width:
            raise ValueError('文字内边距不能占满图形宽度')
        if item['kind'] == 'text' and not item['text'].strip():
            raise ValueError('文字图形不能为空')
    doc = minidom.Document()
    def node(tag, parent=None, **attrs):
        value = doc.createElementNS(P if tag.startswith('p:') else A, tag)
        for key, data in attrs.items():
            value.setAttribute(key, str(data))
        if parent is not None:
            parent.appendChild(value)
        return value
    def color(parent, value):
        if value is None:
            node('a:noFill', parent)
        else:
            node('a:srgbClr', node('a:solidFill', parent), val=value.upper())
    def transform(parent, box, group=False):
        x,y,w,h = [round(v*12700) for v in box]
        xf=node('a:xfrm', parent)
        node('a:off', xf, x=x,y=y);node('a:ext',xf,cx=w,cy=h)
        if group:
            node('a:chOff',xf,x=x,y=y);node('a:chExt',xf,cx=w,cy=h)
    def shape(item, index):
        sp=node('p:sp');nv=node('p:nvSpPr',sp)
        node('p:cNvPr',nv,id=index,name=insertion['name'] if len(items)==1 else f"{insertion['name']} {index-1}")
        node('p:cNvSpPr',nv,**({'txBox':'1'} if item['kind']=='text' else {}));node('p:nvPr',nv)
        props=node('p:spPr',sp);transform(props,item['box'])
        node('a:avLst',node('a:prstGeom',props,prst='rect' if item['kind']=='text' else item['kind']))
        color(props,insertion['fill']);color(node('a:ln',props,w=12700),insertion['line'])
        if item['text'] or item['kind']=='text':
            body=node('p:txBody',sp)
            node('a:bodyPr',body,wrap='square',anchor='ctr',lIns=round(inset*12700),tIns=0,rIns=round(inset*12700),bIns=0)
            node('a:lstStyle',body);paragraph=node('a:p',body)
            node('a:pPr',paragraph,algn={'left':'l','center':'ctr','right':'r'}[insertion['align']])
            run=node('a:r',paragraph)
            props=node('a:rPr',run,sz=round(size*100),b=int(insertion['bold']),i=0)
            color(props,insertion['textColor']);node('a:latin',props,typeface=insertion['fontFace'])
            node('a:ea',props,typeface=insertion['fontFace']);node('a:cs',props,typeface=insertion['fontFace'])
            node('a:t',run).appendChild(doc.createTextNode(item['text']))
        return sp
    if len(items)==1:
        result=shape(items[0],1)
    else:
        result=node('p:grpSp');nv=node('p:nvGrpSpPr',result)
        node('p:cNvPr',nv,id=1,name=insertion['name']);node('p:cNvGrpSpPr',nv);node('p:nvPr',nv)
        left=min(item['box'][0] for item in items);top=min(item['box'][1] for item in items)
        right=max(item['box'][0]+item['box'][2] for item in items)
        bottom=max(item['box'][1]+item['box'][3] for item in items)
        transform(node('p:grpSpPr',result),[left,top,right-left,bottom-top],group=True)
        for index,item in enumerate(items,2):
            result.appendChild(shape(item,index))
    result.setAttribute('xmlns:p',P);result.setAttribute('xmlns:a',A)
    return result.toxml()
