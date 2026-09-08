#!/usr/bin/env python3
"""Build the YouTube thumbnail for a Tetrofall capture reel.

The frame is real gameplay pulled straight out of the video, not a render:
the whole point of `08_listing_40_outro.mp4` is its end card reading NO FAKE
ADS / *That was all real gameplay*, and a thumbnail that promised a glossier
game than the one on the other side of the click would undo that.

    tools/store/yt_thumb.py gameplay/video/08_listing_40_outro.mp4

Writes a 1280x720 PNG (YouTube's spec; well under the 2MB limit) next to the
video. `--at` picks the source second, `--keep` how much of the board the panel
holds, `--pick` prints the busiest candidates instead of rendering, and
`--headline` overrides the words.

Layout: the frame again as a defocused ground, the board sharp in a panel on
the right, headline and mark on the left. Text stays inside the centre 80% -
YouTube crops thumbnails differently across home, search and the end-screen
grid, and a headline losing its first letter is worse than a smaller one.
"""
import argparse
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from outro import (  # noqa: E402  - same palette, same fonts, same mark
    BODY_FONT, DISPLAY_FONT, GOLD, GOLD_LIGHT, MARK, NAME, TEXT_MUTED,
    _block,
)

W, H = 1280, 720
HEADLINE = ["NO FAKE", "ADS"]
SUBLINE = "One take of real gameplay."
BG_DEEP = (0x1A, 0x0F, 0x08)


def frame_at(video: Path, t: float) -> Image.Image:
    """One decoded frame, as PNG on stdout so nothing hits the disk."""
    png = subprocess.run(
        ["ffmpeg", "-v", "error", "-ss", f"{t}", "-i", str(video),
         "-frames:v", "1", "-f", "image2pipe", "-c:v", "png", "-"],
        capture_output=True, check=True,
    ).stdout
    import io
    return Image.open(io.BytesIO(png)).convert("RGB")


def score(video: Path, upto: float = 35.5, fps: int = 4):
    """Rank seconds by how much is happening: burst particles, then density.

    The reel's own end card is excluded - `upto` stops before the crossfade,
    since a thumbnail of the card would just be the card.
    """
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(video), "-t", f"{upto}",
         "-vf", f"fps={fps},scale=180:320", "-f", "rawvideo",
         "-pix_fmt", "rgb24", "-"],
        capture_output=True, check=True,
    ).stdout
    a = np.frombuffer(raw, np.uint8).reshape(-1, 320, 180, 3).astype(np.float32)
    lum = a @ np.array([0.35, 0.45, 0.20])
    board = lum[:, 32:301]                      # drop the HUD and the base bar
    bright = (board > 205).mean(axis=(1, 2))    # shatter debris, cracked cells
    fill = (board < 110).mean(axis=(1, 2))      # how much stack is on screen
    return sorted(
        ((i / fps, float(bright[i]), float(fill[i])) for i in range(len(bright))),
        key=lambda r: -(r[1] * 60 + r[2]),
    )


def _fit(draw, text, font_path, max_width, start):
    size = start
    while size > 24:
        font = ImageFont.truetype(str(font_path), size)
        if draw.textlength(text, font=font) <= max_width:
            return font
        size -= 2
    return ImageFont.truetype(str(font_path), 24)


def _cover(src: Image.Image, box: tuple[int, int, int, int]) -> Image.Image:
    """Crop `src` to 16:9 around `box`, then scale to the full canvas.

    `box` is the region worth keeping - the stack and the well. The crop grows
    from its centre until it is 16:9, so nothing in the box is ever cut.
    """
    x0, y0, x1, y1 = box
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    bw, bh = x1 - x0, y1 - y0
    if bw / bh < W / H:
        bw = bh * W / H
    else:
        bh = bw * H / W
    bw = min(bw, src.width)
    bh = min(bh, src.height)
    cx = min(max(cx, bw / 2), src.width - bw / 2)
    cy = min(max(cy, bh / 2), src.height - bh / 2)
    crop = src.crop((round(cx - bw / 2), round(cy - bh / 2),
                     round(cx + bw / 2), round(cy + bh / 2)))
    return crop.resize((W, H), Image.LANCZOS)


def build(shot: Image.Image, headline=HEADLINE, subline=SUBLINE,
          keep=1.0) -> Image.Image:
    # Background: the same frame, blown up and thrown out of focus, so the
    # thumbnail is the game's own wood all the way to the edges without
    # competing with the panel that carries the actual read.
    bg = _cover(shot, (0, round(shot.height * 0.60), shot.width, shot.height))
    bg = bg.filter(ImageFilter.GaussianBlur(16))
    bg = Image.blend(bg, Image.new("RGB", (W, H), BG_DEEP), 0.52)

    # The panel is the whole portrait frame, uncropped: the score, the well and
    # both stacks in one shape a viewer recognises as a phone game at grid size.
    # `keep` trims empty headroom off the top of the board. At 1.0 the panel is
    # the untouched frame, HUD included; below that the score goes but the
    # blocks get bigger, which is the trade that matters at grid size.
    shot = shot.crop((0, round(shot.height * (1 - keep)), shot.width,
                      shot.height))
    ph = round(H * 0.94)
    pw = round(ph * shot.width / shot.height)
    px0, py0 = W - pw - round(W * 0.055), round((H - ph) / 2)
    panel = shot.resize((pw, ph), Image.LANCZOS)

    radius = round(pw * 0.055)
    mask = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, pw - 1, ph - 1],
                                           radius=radius, fill=255)
    shadow = Image.new("L", (W, H), 0)
    shadow.paste(mask.point(lambda v: round(v * 0.75)), (px0, py0 + 14))
    bg = Image.composite(Image.new("RGB", (W, H), (0, 0, 0)), bg,
                         shadow.filter(ImageFilter.GaussianBlur(26)))

    panel.putalpha(mask)
    card = bg.convert("RGBA")
    card.alpha_composite(panel, (px0, py0))
    rim = ImageDraw.Draw(card)
    rim.rounded_rectangle([px0, py0, px0 + pw - 1, py0 + ph - 1],
                          radius=radius, outline=GOLD + (190,), width=3)
    card = card.convert("RGB")

    # A warm corner falloff, the same trick the feature graphic uses to stop
    # the frame reading as a flat screenshot.
    vig = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vig).ellipse(
        [-W * 0.28, -H * 0.40, W * 1.28, H * 1.40], fill=255
    )
    vig = vig.filter(ImageFilter.GaussianBlur(140))
    card = Image.composite(
        card, Image.blend(card, Image.new("RGB", (W, H), BG_DEEP), 0.42), vig
    )

    draw = ImageDraw.Draw(card)
    left = round(W * 0.10)          # centre 80%, per the note above
    col = px0 - left - round(W * 0.04)

    size = min(_fit(draw, line, DISPLAY_FONT, col, 165).size for line in headline)
    fonts = [ImageFont.truetype(str(DISPLAY_FONT), size)] * len(headline)
    line_h = round(size * 0.92)

    sub_font = _fit(draw, subline, BODY_FONT, col, 34)
    cell = 30
    gap = 3
    mark_h = 2 * cell + gap

    total = line_h * len(headline) + round(H * 0.05) + mark_h
    y = round((H - total) / 2) - round(H * 0.04)

    for line, font in zip(headline, fonts):
        # A drop shadow rather than an outline: the ground is already dark, and
        # an outline at this weight closes up the counters in Baloo.
        draw.text((left + 4, y + 6), line, font=font, fill=(0, 0, 0))
        draw.text((left, y), line, font=font, fill=GOLD_LIGHT)
        y += line_h

    y += round(H * 0.05)
    block = _block(cell)
    for cx, cy in MARK:
        card.paste(block, (left + cx * (cell + gap), y + cy * (cell + gap)),
                   block)
    name_font = ImageFont.truetype(str(DISPLAY_FONT), 54)
    nx = left + 3 * (cell + gap) + round(cell * 0.7)
    ny = y + mark_h - draw.textbbox((0, 0), NAME, font=name_font)[3] - 4
    draw.text((nx, ny), NAME, font=name_font, fill=GOLD)

    draw.text((left, y + mark_h + round(H * 0.038)), subline,
              font=sub_font, fill=TEXT_MUTED)
    return card


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("video", type=Path)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--at", type=float, default=2.75,
                    help="source second to grab the frame from")
    ap.add_argument("--pick", action="store_true",
                    help="print the busiest seconds and stop")
    ap.add_argument("--headline", nargs="*", default=HEADLINE,
                    help="one argument per line of the headline")
    ap.add_argument("--subline", default=SUBLINE)
    ap.add_argument("--keep", type=float, default=0.72,
                    help="fraction of the frame height to keep, from the "
                         "bottom up (1.0 = whole screen, HUD included)")
    a = ap.parse_args()

    if a.pick:
        for t, bright, fill in score(a.video)[:15]:
            print(f"  --at {t:5.2f}   burst={bright:.4f}  fill={fill:.2f}")
        return 0

    out = a.out or a.video.with_name(a.video.stem + "_thumb.png")
    build(frame_at(a.video, a.at), list(a.headline), a.subline,
          a.keep).save(out)
    kb = out.stat().st_size / 1024
    print(f"→ {out}  {W}x{H}  {kb:.0f}KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
