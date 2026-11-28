# Media provenance and reproduction

- `hero.svg`: original, code-authored workflow illustration, not an application screenshot.
- `promo.mp4`: 18-second promotional overview.
- `demo.mp4`: 74-second walkthrough of real model-generated previews and accepted changes.
- `demo.gif`: lightweight README preview of the promotional overview.
- `*.vtt`: English captions; all substantive copy is also visible in the video.
- `source/process-00.png`: rendered public `Examples/Tab-Demo.pptx` baseline.
- `source/process-01.png` through `process-05.png`: previews corresponding to five actual accepted edits in PowerPoint on 2026-11-28, using qwen4-max. The first image was preserved as the next round's before-render; the remaining images are their respective after-renders.
- `source/solar-before.png` and `solar-after.png`: a public test slide before and after the model autonomously searched, selected and inserted an image. No user reference images were supplied.
- `source/request-before.png` and `request-after.png`: the real qwen4-max preview of an explicit request to change Research to Discover while retaining the remaining text and formatting; the control-window acceptance and actual PowerPoint result were verified.

**These videos are edited preview replays, not real-time screen recordings.** Every scene is labelled accordingly. Process scenes zoom into the diagram; the solar and requested-edit slides are shown in full. Scene durations are editorial and must not be used as latency measurements. No generated mock screenshot is presented as native application footage. See the [live verification report](../QA-2026-11-28.md) for actual timings, writeback and limitations.

The solar image is [Topaz Solar Farm, California Valley](https://commons.wikimedia.org/wiki/File:Topaz_Solar_Farm,_California_Valley.jpg), marked public domain by Commons. Credit: Earth Observatory image by Jesse Allen, using EO-1 ALI data provided courtesy of the NASA EO-1 team; caption by Adam Voiland. Original attribution metadata is in `source/solar-credit.json` and is retained in the inserted picture's alternative text.

Rebuild using FFmpeg with `drawtext` support:

```sh
python3 Scripts/build-demo-media.py
```

The default font is macOS Arial. On other platforms set `PPT_CURSOR_VIDEO_FONT` to an installed TrueType font. There is no paid-media or model dependency in the media build. Rendered frames remain available so the public media can be reproduced without accessing a private presentation or provider account.
