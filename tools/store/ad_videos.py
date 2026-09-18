#!/usr/bin/env python3
"""Build the Google Ads App campaign videos from real Tetrofall gameplay.

An App campaign ad group takes up to 20 videos (YouTube-hosted). The cut list
lives in `tools/store/ad_videos.json`; this renders it into
`gameplay/ads_video/{portrait,square,landscape}/`.

    python3 tools/store/ad_videos.py                 # everything
    python3 tools/store/ad_videos.py --only 01_why_flat
    python3 tools/store/ad_videos.py --verify
    python3 tools/store/ad_videos.py --sheet         # contact sheet only

Same rules as `ad_images.py`: every board on screen is a capture reel from
`gameplay/video/`. The tool cuts, crops, holds a frame, slows a labelled
replay and lays captions *around* the play — it never draws on a board, never
speeds footage up and adds no fake buttons or install arrows. The blunders are
the shipped game played badly on purpose by the capture bot
(`tools/capture/reels.dart`), which is what keeps the "no fake ads" claim true
of the paid video as well as the store page.

Sound: the captured game audio, levelled, plus stingers synthesised by
`ad_sfx.py`. No music.

A cut is a list of shots, joined with hard cuts:

  {"src": "08_edge_hover", "in": 2.0, "out": 9.5}     play, with game sound
  {"src": ..., "freeze": 9.6, "dur": 1.2,
   "zoom": 1.35, "focus": [0.8, 0.55]}                  held frame, punch-in
  {"src": ..., "in": 9.0, "out": 10.5, "replay": 0.5}   slowed, labelled REPLAY
  {"left": {...}, "right": {...}, "dur": 6}             split layout only
  {"card": true, "dur": 3.0}                            the end card

Shots may carry their own `captions` and `stingers`, timed from the shot's
start; cut-level ones are timed from the start of the file.
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ad_sfx  # noqa: E402
from outro import (  # noqa: E402
    BG, BODY_FONT, DISPLAY_FONT, GOLD, GOLD_LIGHT, MARK, NAME, PEAK_TARGET,
    TEXT, _block, _wood, build_card, has_audio, peak_dbfs,
)

ROOT = Path(__file__).resolve().parents[2]
GAMEPLAY = ROOT / "gameplay"
REELS = GAMEPLAY / "video"
OUT = GAMEPLAY / "ads_video"
SPEC = Path(__file__).with_name("ad_videos.json")
BLACK_FONT = ROOT / "assets/fonts/Nunito/static/Nunito-Black.ttf"

SIZES = {
    "portrait": (1080, 1920),
    "square": (1080, 1080),
    "landscape": (1920, 1080),
}
COUNTS = {"portrait": 10, "square": 5, "landscape": 5}
FPS = 30
MIN_S, MAX_S = 10.0, 30.5

# Game sound sits under the stingers rather than level with them.
GAME_PEAK = -6.0

RED = (0xE8, 0x4A, 0x3C)
GREEN = (0x4C, 0xC0, 0x6A)
DARK = (0x14, 0x0C, 0x08)
COLORS = {"red": RED, "green": GREEN, "gold": GOLD, "dark": DARK,
          "white": (255, 255, 255)}


def run(cmd: list[str]) -> None:
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.stderr.write(r.stderr[-4000:])
        raise SystemExit(f"ffmpeg failed: {' '.join(cmd[:8])} …")


def probe(path: Path) -> dict:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries",
         "stream=codec_type,width,height,duration:format=duration",
         "-of", "json", str(path)],
        capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def reel(name: str) -> Path:
    path = REELS / (name if name.endswith(".mp4") else f"{name}.mp4")
    if not path.exists():
        raise FileNotFoundError(path)
    return path


_gain_cache: dict[Path, float] = {}


def game_gain(src: Path) -> float | None:
    if not has_audio(src):
        return None
    if src not in _gain_cache:
        _gain_cache[src] = GAME_PEAK - peak_dbfs(src)
    return _gain_cache[src]


# ─── picture: how a 1080x1920 reel lands in each layout ──────────────────


def panel_geometry(cut: dict, w: int, h: int):
    """Landscape: the board band, sharp, on the right; copy column on the left."""
    y0, y1 = cut.get("band", [0.30, 1.0])
    ph = round(h * 0.92)
    pw = round(1080 * ph / (1920 * (y1 - y0)))
    pw -= pw % 2
    px = round(w * cut.get("panel_x", 0.74) - pw / 2)
    px = min(px, w - pw - round(w * 0.03))
    py = (h - ph) // 2
    return y0, y1, pw, ph, px, py


def layout_chain(cut: dict, label_in: str, label_out: str, focus_y=None) -> str:
    """A filter chain turning one 1080x1920 stream into the cut's frame."""
    ratio = cut["ratio"]
    w, h = SIZES[ratio]
    layout = cut["layout"]
    pre = f"[{label_in}]scale=1080:1920,setsar=1"
    if layout == "full":
        return f"{pre}[{label_out}]"
    if layout == "crop":
        z = cut.get("crop_zoom", 1.0)
        fy = focus_y if focus_y is not None else cut.get("focus_y", 0.62)
        sw = round(1080 * z)
        sh = round(1920 * z)
        sh -= sh % 2
        return (f"{pre},scale={sw}:{sh},"
                f"crop={w}:{h}:{(sw - w) // 2}:"
                f"{min(max(round(fy * sh - h / 2), 0), sh - h)}[{label_out}]")
    if layout == "pillar":
        # Square: the whole portrait board, full height, centred over a
        # blurred copy of itself. A crop loses the top of the board, which is
        # where a hovering piece spends the beat the cut is built on.
        pw = round(1080 * h / 1920)
        pw -= pw % 2
        bg_h = round(1920 * w / 1080)
        bg_h -= bg_h % 2
        return (
            f"{pre},split[{label_out}_a][{label_out}_b];"
            f"[{label_out}_a]scale={w}:{bg_h},crop={w}:{h}:0:{(bg_h - h) // 2},"
            f"boxblur=28:2,eq=brightness=-0.22:saturation=0.75[{label_out}_bg];"
            f"[{label_out}_b]scale={pw}:{h}[{label_out}_fg];"
            f"[{label_out}_bg][{label_out}_fg]overlay={(w - pw) // 2}:0[{label_out}]"
        )
    if layout == "panel":
        y0, y1, pw, ph, px, py = panel_geometry(cut, w, h)
        bg_h = round(1920 * w / 1080)
        bg_h -= bg_h % 2
        bg_y = round((bg_h - h) * cut.get("bg_y", 0.70))
        return (
            f"{pre},split[{label_out}_a][{label_out}_b];"
            f"[{label_out}_a]scale={w}:{bg_h},crop={w}:{h}:0:{bg_y},"
            f"boxblur=28:2,eq=brightness=-0.20:saturation=0.75[{label_out}_bg];"
            f"[{label_out}_b]crop=1080:{round(1920 * (y1 - y0))}:0:"
            f"{round(1920 * y0)},scale={pw}:{ph}[{label_out}_fg];"
            f"[{label_out}_bg][{label_out}_fg]overlay={px}:{py}[{label_out}]"
        )
    raise ValueError(f"layout {layout} has no single-stream chain")


def zoom_chain(label_in: str, label_out: str, dur: float, zoom: float,
               focus) -> str:
    """A held frame that punches in over 0.25s and then sits still."""
    frames = max(1, round(dur * FPS))
    ramp = max(1, round(0.25 * FPS))
    fx, fy = focus
    return (
        f"[{label_in}]scale=2160:3840,"
        f"zoompan=z='1+({zoom}-1)*min(on/{ramp},1)':"
        f"x='max(0,min(iw-iw/zoom,{fx}*iw-iw/zoom/2))':"
        f"y='max(0,min(ih-ih/zoom,{fy}*ih-ih/zoom/2))':"
        f"d={frames}:s=1080x1920:fps={FPS}[{label_out}]"
    )


def render_shot(cut: dict, shot: dict, path: Path, tmp: Path) -> float:
    """One shot to an intermediate MKV: the cut's frame size, 30fps, PCM."""
    w, h = SIZES[cut["ratio"]]
    enc = ["-c:v", "libx264", "-preset", "veryfast", "-crf", "14",
           "-pix_fmt", "yuv420p", "-r", str(FPS),
           "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2"]
    silence = f"anullsrc=r=48000:cl=stereo"

    if shot.get("card"):
        dur = shot["dur"]
        png = tmp / f"{path.stem}_card.png"
        card = build_card(w, h, shot.get("tagline", cut_tagline(cut)),
                          shot.get("kicker"))
        card.save(png)
        run(["ffmpeg", "-y", "-v", "error", "-loop", "1", "-t", f"{dur}",
             "-i", str(png), "-f", "lavfi", "-t", f"{dur}", "-i", silence,
             "-filter_complex",
             f"[0:v]fps={FPS},format=yuv420p,fade=t=in:st=0:d=0.3[v]",
             "-map", "[v]", "-map", "1:a", *enc, "-t", f"{dur}", str(path)])
        return dur

    if "left" in shot:
        return render_split(cut, shot, path, tmp, enc)

    src = reel(shot["src"])
    if "freeze" in shot:
        dur = shot["dur"]
        graph = zoom_chain("0:v", "z", dur, shot.get("zoom", 1.0),
                           shot.get("focus", [0.5, 0.5]))
        graph += ";" + layout_chain(cut, "z", "v", shot.get("focus_y"))
        run(["ffmpeg", "-y", "-v", "error", "-ss", f"{shot['freeze']}",
             "-i", str(src), "-f", "lavfi", "-t", f"{dur}", "-i", silence,
             "-filter_complex", graph, "-map", "[v]", "-map", "1:a",
             "-frames:v", str(round(dur * FPS)), *enc, "-t", f"{dur}",
             str(path)])
        return dur

    t_in, t_out = shot["in"], shot["out"]
    speed = shot.get("replay", 1.0)
    dur = (t_out - t_in) / speed
    vpre = (f"[0:v]setpts=(PTS-STARTPTS)/{speed},fps={FPS},"
            f"trim=duration={dur}[s]")
    graph = vpre + ";" + layout_chain(cut, "s", "v", shot.get("focus_y"))
    gain = game_gain(src)
    if speed == 1.0 and gain is not None and not shot.get("mute"):
        graph += (f";[0:a]aresample=48000,aformat=channel_layouts=stereo,"
                  f"volume={gain + shot.get('gain', 0):.2f}dB,"
                  f"atrim=0:{dur},apad=whole_dur={dur}[a]")
        amap = ["-map", "[a]"]
        extra = []
    else:
        amap = ["-map", "1:a"]
        extra = ["-f", "lavfi", "-t", f"{dur}", "-i", silence]
    run(["ffmpeg", "-y", "-v", "error", "-ss", f"{t_in}", "-t",
         f"{t_out - t_in}", "-i", str(src), *extra,
         "-filter_complex", graph, "-map", "[v]", *amap, *enc,
         "-t", f"{dur}", str(path)])
    return dur


def render_split(cut, shot, path, tmp, enc) -> float:
    """Square: two boards side by side under BAD / GOOD labels."""
    w, h = SIZES[cut["ratio"]]
    dur = shot["dur"]
    ground = tmp / f"{path.stem}_ground.png"
    _wood(w, h).save(ground)
    bw, bh = 520, 924
    gap = (w - 2 * bw) // 3
    top = h - bh - round(gap * 0.6)
    parts = []
    inputs = ["-loop", "1", "-t", f"{dur}", "-i", str(ground)]
    for i, side in enumerate(("left", "right"), start=1):
        s = shot[side]
        inputs += ["-ss", f"{s['in']}", "-t", f"{dur}", "-i",
                   str(reel(s["src"]))]
        parts.append(f"[{i}:v]setpts=PTS-STARTPTS,fps={FPS},"
                     f"scale={bw}:{bh},setsar=1[{side}]")
    graph = ";".join(parts) + (
        f";[0:v]fps={FPS},format=yuv420p[g];"
        f"[g][left]overlay={gap}:{top}:shortest=1[gl];"
        f"[gl][right]overlay={2 * gap + bw}:{top}:shortest=1[v]")
    # Sound from whichever side is marked as carrying it.
    side = shot.get("audio", "left")
    idx = 1 if side == "left" else 2
    gain = game_gain(reel(shot[side]["src"])) or 0.0
    graph += (f";[{idx}:a]aresample=48000,aformat=channel_layouts=stereo,"
              f"volume={gain:.2f}dB,atrim=0:{dur},apad=whole_dur={dur}[a]")
    run(["ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex", graph,
         "-map", "[v]", "-map", "[a]", *enc, "-t", f"{dur}", str(path)])
    return dur


def cut_tagline(cut: dict) -> str:
    return cut.get("tagline", "The floor rises. Clear rows or get crushed.")


# ─── captions ────────────────────────────────────────────────────────────

STYLES = {
    #            font          size  fill        stroke  pill
    "hook":     (DISPLAY_FONT, 118, (255, 255, 255), DARK, None),
    "shout":    (DISPLAY_FONT, 200, GOLD_LIGHT, DARK, None),
    "alarm":    (DISPLAY_FONT, 200, RED, (255, 255, 255), None),
    "question": (DISPLAY_FONT, 100, (255, 255, 255), None, (20, 12, 8, 215)),
    "label":    (BLACK_FONT, 62, (255, 255, 255), None, RED + (240,)),
    "sub":      (BLACK_FONT, 60, TEXT, DARK, None),
    "big":      (DISPLAY_FONT, 150, (255, 255, 255), DARK, None),
}

POS = {"top": 0.12, "upper": 0.26, "middle": 0.50, "lower": 0.70,
       "bottom": 0.86}


def text_area(cut: dict, pos) -> tuple[int, int, float]:
    """Horizontal extent and vertical centre (fraction) for a caption."""
    w, h = SIZES[cut["ratio"]]
    if cut["layout"] == "panel" and pos != "full":
        _, _, pw, ph, px, py = panel_geometry(cut, w, h)
        return round(w * 0.04), px - round(w * 0.03), None
    return round(w * 0.06), round(w * 0.94), None


def render_caption(cut: dict, cap: dict) -> Image.Image:
    w, h = SIZES[cut["ratio"]]
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    style = STYLES[cap.get("style", "hook")]
    font_path, size, fill, stroke, pill = style
    if "color" in cap:
        c = COLORS[cap["color"]]
        if pill:
            pill = c + (240,)
        else:
            fill = c
    x0, x1, _ = text_area(cut, cap.get("pos", "top"))
    col = x1 - x0
    # Sizes are authored for a 1080-wide frame; a landscape column is
    # narrower than that, and the fit below shrinks further if a line needs.
    scale = min(1.0, col / 972) if cut["layout"] == "panel" else w / 1080
    size = round(size * scale * cap.get("scale", 1.0))
    lines = cap["text"].split("\n")
    draw = ImageDraw.Draw(layer)
    pad = round(size * 0.35) if pill else 0
    while size > 24:
        font = ImageFont.truetype(str(font_path), size)
        sw = max(2, round(size * 0.075)) if stroke else 0
        widths = [draw.textlength(ln, font=font) + 2 * sw for ln in lines]
        if max(widths) + 2 * pad <= col:
            break
        size -= 4
        pad = round(size * 0.35) if pill else 0
    font = ImageFont.truetype(str(font_path), size)
    sw = max(2, round(size * 0.075)) if stroke else 0
    asc, desc = font.getmetrics()
    line_h = round((asc + desc) * 0.86)
    ink_top = draw.textbbox((0, 0), lines[0], font=font)[1]
    block_h = line_h * (len(lines) - 1) + (
        draw.textbbox((0, 0), lines[-1], font=font)[3]) - ink_top

    pos = cap.get("pos", "top")
    fy = pos[1] if isinstance(pos, list) else POS.get(pos, 0.5)
    if "y" in cap:
        fy = cap["y"]
    cy = round(h * fy)
    y = cy - block_h // 2 - ink_top
    cx = (x0 + x1) / 2
    if "x" in cap:
        # Split layout: a label centred over one of the two boards.
        cx = w * cap["x"]

    if pill:
        bw = max(draw.textlength(ln, font=font) for ln in lines) + 2 * pad
        draw.rounded_rectangle(
            [cx - bw / 2, cy - block_h / 2 - pad * 0.6,
             cx + bw / 2, cy + block_h / 2 + pad * 0.6],
            radius=round(size * 0.35), fill=pill)
    for ln in lines:
        tw = draw.textlength(ln, font=font)
        if stroke:
            # A hard drop shadow under the stroke, so white copy still reads
            # over the light wood of the board.
            draw.text((cx - tw / 2 + sw * 0.6, y + sw * 1.1), ln, font=font,
                      fill=(0, 0, 0, 150), stroke_width=sw,
                      stroke_fill=(0, 0, 0, 150))
        draw.text((cx - tw / 2, y), ln, font=font, fill=fill,
                  stroke_width=sw, stroke_fill=stroke)
        y += line_h

    tilt = cap.get("tilt", 0)
    if tilt:
        layer = layer.rotate(tilt, resample=Image.BICUBIC, center=(cx, cy))
    return layer


def render_meter(cut: dict, cap: dict) -> Image.Image:
    """The rage bar: a labelled gauge in the copy column, never on a board."""
    w, h = SIZES[cut["ratio"]]
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    x0, x1, _ = text_area(cut, "side")
    draw = ImageDraw.Draw(layer)
    bx0, bx1 = x0 + 40, x1 - 40
    by = round(h * cap.get("y", 0.66))
    bh = 64
    draw.rounded_rectangle([bx0, by, bx1, by + bh], radius=bh // 2,
                           fill=(20, 12, 8, 220), outline=GOLD, width=5)
    level = max(0.0, min(1.0, cap["level"]))
    if level > 0:
        fx = bx0 + 10 + round((bx1 - bx0 - 20) * level)
        color = GREEN if level < 0.4 else (GOLD if level < 0.75 else RED)
        draw.rounded_rectangle([bx0 + 10, by + 10, max(fx, bx0 + 54),
                                by + bh - 10], radius=(bh - 20) // 2,
                               fill=color)
    font = ImageFont.truetype(str(BLACK_FONT), 56)
    label = cap.get("text", "RAGE METER")
    tw = draw.textlength(label, font=font)
    draw.text(((bx0 + bx1) / 2 - tw / 2, by - 84), label, font=font,
              fill=TEXT, stroke_width=4, stroke_fill=DARK)
    return layer


def render_chrome(cut: dict) -> Image.Image | None:
    """Landscape only: the panel's gold rim and the name under the copy."""
    if cut["layout"] != "panel":
        return None
    w, h = SIZES[cut["ratio"]]
    _, _, pw, ph, px, py = panel_geometry(cut, w, h)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle([px - 3, py - 3, px + pw + 2, py + ph + 2],
                           radius=18, outline=GOLD, width=6)
    x0, x1, _ = text_area(cut, "side")
    cell = 34
    gap = 4
    name_font = ImageFont.truetype(str(DISPLAY_FONT), 78)
    name_w = draw.textlength(NAME, font=name_font)
    total = 3 * (cell + gap) + 24 + name_w
    mx = round((x0 + x1) / 2 - total / 2)
    my = h - 150
    block = _block(cell)
    for bx, by in MARK:
        layer.alpha_composite(block, (mx + bx * (cell + gap),
                                      my + by * (cell + gap)))
    ny = my + 2 * cell + gap - draw.textbbox((0, 0), NAME, font=name_font)[3]
    draw.text((mx + 3 * (cell + gap) + 24, ny), NAME, font=name_font,
              fill=GOLD)
    return layer


# ─── assembly ────────────────────────────────────────────────────────────


def out_path(cut: dict) -> Path:
    return OUT / cut["ratio"] / f"{cut['id']}.mp4"


def build(cut: dict) -> Path:
    w, h = SIZES[cut["ratio"]]
    sfx = ad_sfx.OUT
    if not sfx.exists() or len(list(sfx.glob("*.wav"))) < len(ad_sfx.SOUNDS):
        ad_sfx.build()

    with tempfile.TemporaryDirectory() as tmp_s:
        tmp = Path(tmp_s)
        clips, captions, stingers = [], list(cut.get("captions", [])), \
            list(cut.get("stingers", []))
        t = 0.0
        for i, shot in enumerate(cut["shots"]):
            clip = tmp / f"shot_{i:02d}.mkv"
            dur = render_shot(cut, shot, clip, tmp)
            clips.append(clip)
            for c in shot.get("captions", []):
                captions.append({**c, "t0": t + c["t0"], "t1": t + c["t1"]})
            for s in shot.get("stingers", []):
                stingers.append({**s, "t": t + s["t"]})
            if shot.get("replay"):
                captions.append({"text": "REPLAY", "style": "label",
                                 "pos": shot.get("replay_pos", "top"),
                                 "color": "red", "t0": t, "t1": t + dur})
            t += dur
        total = t

        # Pass 1: join the shots.
        joined = tmp / "joined.mkv"
        ins = []
        for c in clips:
            ins += ["-i", str(c)]
        n = len(clips)
        # Scaling and overlaying can leave a shot with a 2559:2560 sample
        # aspect, and concat refuses to join clips whose SAR disagrees.
        graph = "".join(f"[{i}:v]setsar=1[n{i}];" for i in range(n)) + \
            "".join(f"[n{i}][{i}:a]" for i in range(n)) + \
            f"concat=n={n}:v=1:a=1[v][a]"
        run(["ffmpeg", "-y", "-v", "error", *ins, "-filter_complex", graph,
             "-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-preset",
             "veryfast", "-crf", "14", "-pix_fmt", "yuv420p",
             "-c:a", "pcm_s16le", str(joined)])

        # Pass 2: captions over the picture, stingers into the sound.
        inputs = ["-i", str(joined)]
        vgraph, agraph = [], []
        idx = 1
        cur = "0:v"
        chrome = render_chrome(cut)
        layers = []
        if chrome is not None:
            layers.append(({"t0": 0, "t1": total, "fade": 0,
                            "until_card": True}, chrome))
        for cap in captions:
            img = render_meter(cut, cap) if cap.get("style") == "meter" \
                else render_caption(cut, cap)
            layers.append((cap, img))
        card_start = total - sum(s["dur"] for s in cut["shots"][-1:]
                                 if s.get("card"))
        for k, (cap, img) in enumerate(layers):
            png = tmp / f"cap_{k:02d}.png"
            img.save(png)
            t0 = cap["t0"]
            t1 = card_start if cap.get("until_card") else cap["t1"]
            fade = cap.get("fade", 0.08)
            inputs += ["-loop", "1", "-t", f"{total}", "-i", str(png)]
            chain = f"[{idx}:v]format=rgba"
            if fade:
                chain += (f",fade=t=in:st={t0}:d={fade}:alpha=1,"
                          f"fade=t=out:st={max(t0, t1 - fade)}:d={fade}:alpha=1")
            vgraph.append(chain + f"[c{k}]")
            vgraph.append(f"[{cur}][c{k}]overlay=0:0:"
                          f"enable='between(t,{t0},{t1})'[o{k}]")
            cur = f"o{k}"
            idx += 1
        vgraph.append(f"[{cur}]format=yuv420p[v]")

        mix = ["[0:a]"]
        for k, st in enumerate(stingers):
            wav = sfx / f"{st['sound']}.wav"
            inputs += ["-i", str(wav)]
            ms = round(st["t"] * 1000)
            agraph.append(f"[{idx}:a]aformat=channel_layouts=stereo,"
                          f"aresample=48000,volume={st.get('gain', 0)}dB,"
                          f"adelay={ms}|{ms}[s{k}]")
            mix.append(f"[s{k}]")
            idx += 1
        agraph.append("".join(mix) + f"amix=inputs={len(mix)}:normalize=0:"
                      f"duration=first,alimiter=limit=0.9:level=disabled,"
                      f"apad=whole_dur={total}[a]")

        mixed = tmp / "mixed.mp4"
        run(["ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex",
             ";".join(vgraph + agraph), "-map", "[v]", "-map", "[a]",
             "-c:v", "libx264", "-profile:v", "high", "-preset", "medium",
             "-crf", "19", "-pix_fmt", "yuv420p", "-r", str(FPS),
             "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2",
             "-t", f"{total}", "-movflags", "+faststart", str(mixed)])

        # Pass 3: land the whole soundtrack on the house peak.
        final = out_path(cut)
        final.parent.mkdir(parents=True, exist_ok=True)
        gain = PEAK_TARGET - peak_dbfs(mixed)
        run(["ffmpeg", "-y", "-v", "error", "-i", str(mixed), "-c:v", "copy",
             "-af", f"volume={gain:.2f}dB", "-c:a", "aac", "-b:a", "192k",
             "-movflags", "+faststart", str(final)])
    print(f"→ {final.relative_to(ROOT)}  {w}x{h}  {total:.2f}s  "
          f"{len(captions)} captions  {len(stingers)} stingers")
    return final


# ─── checks ──────────────────────────────────────────────────────────────


def loudness(path: Path) -> tuple[float, float]:
    err = subprocess.run(
        ["ffmpeg", "-hide_banner", "-i", str(path), "-map", "a:0",
         "-af", "volumedetect", "-f", "null", "-"],
        capture_output=True, text=True, check=True).stderr
    mean = peak = -99.0
    for line in err.splitlines():
        if "mean_volume" in line:
            mean = float(line.split(":")[1].split()[0])
        if "max_volume" in line:
            peak = float(line.split(":")[1].split()[0])
    return mean, peak


def verify(spec: list[dict]) -> int:
    bad = 0
    counts = {k: 0 for k in COUNTS}
    for cut in spec:
        path = out_path(cut)
        if not path.exists():
            print(f"✗ {cut['id']}: missing")
            bad += 1
            continue
        counts[cut["ratio"]] += 1
        info = probe(path)
        v = next(s for s in info["streams"] if s["codec_type"] == "video")
        a = [s for s in info["streams"] if s["codec_type"] == "audio"]
        dur = float(info["format"]["duration"])
        problems = []
        if (v["width"], v["height"]) != SIZES[cut["ratio"]]:
            problems.append(f"size {v['width']}x{v['height']}")
        if not MIN_S <= dur <= MAX_S:
            problems.append(f"duration {dur:.1f}s")
        if not a:
            problems.append("no audio stream")
        else:
            adur = float(a[0].get("duration", 0))
            if adur < dur - 0.15:
                problems.append(f"audio ends at {adur:.2f}s of {dur:.2f}s")
            mean, peak = loudness(path)
            if not -3.0 <= peak <= -0.5:
                problems.append(f"peak {peak:.1f}dB")
            if mean < -45:
                problems.append(f"near-silent (mean {mean:.1f}dB)")
        size_mb = path.stat().st_size / 1e6
        mark = "✗" if problems else "✓"
        detail = "; ".join(problems) if problems else \
            f"{dur:.1f}s  {size_mb:.1f}MB  audio ok"
        print(f"{mark} {cut['ratio']:9} {cut['id']:26} {detail}")
        bad += bool(problems)
    for k, want in COUNTS.items():
        if counts[k] != want:
            print(f"✗ {k}: {counts[k]} rendered, want {want}")
            bad += 1
    print("all good" if not bad else f"{bad} problem(s)")
    return 1 if bad else 0


def contact_sheet(spec: list[dict]) -> Path:
    cols, box, pad, label = 5, 360, 16, 30
    rows = math.ceil(len(spec) / cols)
    sheet = Image.new("RGB", (cols * (box + pad) + pad,
                              rows * (box + pad + label) + pad), BG)
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(str(BODY_FONT), 20)
    with tempfile.TemporaryDirectory() as tmp:
        for i, cut in enumerate(spec):
            path = out_path(cut)
            if not path.exists():
                continue
            png = Path(tmp) / f"{i}.png"
            subprocess.run(["ffmpeg", "-y", "-v", "error", "-ss",
                            f"{cut.get('thumb', 1.5)}", "-i", str(path),
                            "-frames:v", "1", str(png)], check=True)
            with Image.open(png) as im:
                im.thumbnail((box, box))
                x = pad + (i % cols) * (box + pad)
                y = pad + (i // cols) * (box + pad + label)
                sheet.paste(im, (x + (box - im.width) // 2,
                                 y + (box - im.height) // 2))
                draw.text((x, y + box + 4), cut["id"], font=font, fill=TEXT)
    dest = OUT / "contact_sheet.png"
    sheet.save(dest)
    print(f"→ {dest.relative_to(ROOT)}")
    return dest


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--verify", action="store_true")
    ap.add_argument("--sheet", action="store_true")
    a = ap.parse_args()
    spec = json.loads(SPEC.read_text())
    if a.verify:
        return verify(spec)
    if a.sheet:
        contact_sheet(spec)
        return 0
    todo = [c for c in spec if not a.only or c["id"] in a.only]
    if a.only and not todo:
        print(f"no cut named {a.only}", file=sys.stderr)
        return 2
    for cut in todo:
        try:
            build(cut)
        except FileNotFoundError as e:
            print(f"skip  {cut['id']}: missing {e}")
    if not a.only:
        contact_sheet(spec)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
