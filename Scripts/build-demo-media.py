#!/usr/bin/env python3
"""Build captioned, explicitly labelled replays from real model preview renders.

Requires ffmpeg with drawtext. No keys, model requests, UI automation or private decks.
Use PPT_CURSOR_VIDEO_FONT to override the system font.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / 'docs/media'
SOURCE = MEDIA / 'source'
FONT = Path(os.environ.get('PPT_CURSOR_VIDEO_FONT', '/System/Library/Fonts/Supplemental/Arial.ttf'))
if not FONT.is_file():
    raise SystemExit('Set PPT_CURSOR_VIDEO_FONT to an installed TrueType font.')

SCENES = [
    ('process-00.png', 'PPT Cursor', 'Your next slide edit.\nMade together.', 'An open-source companion\nfor PowerPoint on macOS.', 5),
    ('process-00.png', '01 / YOU EDIT', 'Start where\nyou already work.', 'This public test slide has\nthree editable text boxes.\nNo prompt or upload required.', 6),
    ('process-01.png', '02 / AI SUGGESTS', 'Make the\nnext step visible.', 'The model proposes two arrows.\nReview first. Accept when ready.', 6),
    ('process-02.png', '03 / CONTINUE', 'One accepted edit.\nThen the next.', 'The next real suggestion adds\nnumbered steps to the process.', 6),
    ('process-03.png', '04 / REFINE', 'Build on\nyour decisions.', 'A third suggestion groups\nthe stages into outlined cards.', 6),
    ('process-04.png', '05 / ADD HIERARCHY', 'Keep going\nbeyond three.', 'A fourth accepted suggestion\nadds a heading to the slide.', 6),
    ('process-05.png', '06 / FIVE REAL WRITES', 'Preview. Accept.\nContinue.', 'Five consecutive accepted edits.\nPause and resume were tested\nwith the original file unsaved.', 7),
    ('request-before.png', '07 / GIVE DIRECTION', 'Tell AI exactly\nwhat to change.', 'Request: change Research to\nDiscover. Keep the other text\nand formatting unchanged.', 6),
    ('request-after.png', '08 / YOUR REQUEST', 'The exact words.\nThe same styling.', 'The requested text was changed\nand accepted in PowerPoint.\nAutomatic suggestions continued.', 6),
    ('solar-before.png', '09 / FIND A REAL IMAGE', 'No image upload\nrequired.', 'The model chooses search terms\nfrom the solar-energy slide.', 6),
    ('solar-after.png', '10 / WEB ASSETS', 'Search. Review.\nInsert.', 'A Commons public-domain photo\nwas inserted into PowerPoint.\nSource and credit stayed attached.', 8),
    ('process-05.png', 'PPT CURSOR / OPEN SOURCE', 'Your slides.\nYour final say.', 'macOS preview / MIT\ngithub.com/genalyu/ppt-cursor\nSetup and limitations in README.', 6),
]


def run(command):
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def timestamp(seconds):
    return f'{seconds//3600:02}:{seconds%3600//60:02}:{seconds%60:02}.000'


def render(name, scenes, scratch):
    clips=[]
    captions=['WEBVTT', '']
    elapsed=0
    for index,(asset,kicker,title,body,duration) in enumerate(scenes):
        folder=scratch/f'{name}-{index}';folder.mkdir()
        for label,copy in [('kicker',kicker),('title',title),('body',body)]:
            (folder/f'{label}.txt').write_text(copy)
        full = asset.startswith(('solar', 'request'))
        art = 'scale=624:468,pad=760:470:68:1:color=white' if full else 'crop=1320:620:60:100,scale=740:348,pad=760:470:10:61:color=white'
        # Product labels surround unaltered preview pixels; process scenes zoom in.
        drawing=(f'[0:v]{art}[slide];[1:v][slide]overlay=470:140,'
                 'drawbox=x=48:y=65:w=40:h=4:color=0x78e0cf:t=fill,')
        for label,y,size,color in [('kicker',91,15,'0x78e0cf'),('title',163,38,'white'),('body',350,20,'0xc4d4db')]:
            drawing+=f"drawtext=fontfile='{FONT}':textfile='{folder/str(label+'.txt')}':x=48:y={y}:fontsize={size}:fontcolor={color}:line_spacing=12,"
        drawing+=(f"drawtext=fontfile='{FONT}':text='REAL MODEL PREVIEWS / EDITED REPLAY - NOT REAL-TIME':x=48:y=660:fontsize=15:fontcolor=0x9eb6c0,"
                  f"drawtext=fontfile='{FONT}':text='{index+1:02} / {len(scenes):02}':x=1140:y=660:fontsize=15:fontcolor=0x9eb6c0,"
                  'fade=t=in:st=0:d=0.2,format=yuv420p[out]')
        clip=folder/'clip.mp4'
        run(['ffmpeg','-y','-hide_banner','-loglevel','error','-loop','1','-framerate','24','-i',str(SOURCE/asset),
             '-f','lavfi','-i','color=c=0x102539:s=1280x720:r=24',
             '-filter_complex',drawing,'-map','[out]','-t',str(duration),'-an','-c:v','libx264','-preset','fast','-crf','21',str(clip)])
        clips.append(clip)
        captions += [f'{timestamp(elapsed)} --> {timestamp(elapsed+duration)}', title.replace('\n',' ')+' '+body.replace('\n',' '), '']
        elapsed+=duration
    listing=scratch/f'{name}.txt';listing.write_text(''.join(f"file '{p}'\n" for p in clips))
    run(['ffmpeg','-y','-hide_banner','-loglevel','error','-f','concat','-safe','0','-i',str(listing),'-c','copy','-movflags','+faststart',str(MEDIA/f'{name}.mp4')])
    (MEDIA/f'{name}.vtt').write_text('\n'.join(captions))
    print(f'{name}: {elapsed}s, {len(scenes)} scenes',flush=True)


with tempfile.TemporaryDirectory(prefix='ppt-media-') as temp:
    scratch=Path(temp)
    render('demo',SCENES,scratch)
    promo=[(*SCENES[index][:4],3) for index in [0,2,6,8,10,11]]
    render('promo',promo,scratch)
    run(['ffmpeg','-y','-hide_banner','-loglevel','error','-ss','0.5','-i',str(MEDIA/'promo.mp4'),'-frames:v','1',str(MEDIA/'poster.png')])
    run(['ffmpeg','-y','-hide_banner','-loglevel','error','-i',str(MEDIA/'promo.mp4'),'-filter_complex',
         'fps=6,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse=dither=bayer',
         '-loop','0',str(MEDIA/'demo.gif')])
print('Media saved in docs/media. Review before publication.')
