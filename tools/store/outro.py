#!/usr/bin/env python3
"""Append a Tetrofall end card to a capture reel.

The app has no outro screen — nothing in `lib/` draws one, and adding one
just to photograph it would mean shipping a screen the player can never
reach. So the card is composited on afterwards, from the same fonts and the
same palette the game uses, and the join is a crossfade rather than a cut.

    tools/store/outro.py gameplay/video/01_skilled_run.mp4 \
        --out gameplay/video/01_skilled_run_outro.mp4 --total 40

`--total` is the length of the *finished* file: the source is trimmed so the
gameplay, the crossfade and the card add up to exactly that, which is why a
40-second cut with a 4-second card holds ~36.6s of play. `--card-only`
writes just the PNG, for checking the layout without re-encoding a video.
"""
import argparse
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
DISPLAY_FONT = ROOT / "assets/fonts/Baloo_2/static/Baloo2-ExtraBold.ttf"
BODY_FONT = ROOT / "assets/fonts/Nunito/static/Nunito-Bold.ttf"

# lib/ui/theme/tokens.dart
WOOD_DARK = (0x4A, 0x2F, 0x1C)
BG = (0x2B, 0x1C, 0x12)
GOLD = (0xF2, 0xB6, 0x32)
GOLD_LIGHT = (0xFF, 0xD4, 0x6B)
GOLD_DEEP = (0xD9, 0x93, 0x1C)
TEXT = (0xF5, 0xEA, 0xD9)

NAME = "TETROFALL"
# tools/branding/forge_test.dart — the same line the feature graphic carries.
TAGLINE = "The floor rises. Clear rows or get crushed."

# The T-tetromino, as the mark uses it: one block over three.
MARK = [(1, 0), (0, 1), (1, 1), (2, 1)]


def _wood(w: int, h: int) -> Image.Image:
    """Vertical wood gradient, matching `Tokens.bgWoodGradient`."""
    strip = Image.new("RGB", (1, h))
    px = strip.load()
    for y in range(h):
        t = y / max(1, h - 1)
        px[0, y] = tuple(round(a + (b - a) * t) for a, b in zip(WOOD_DARK, BG))
    return strip.resize((w, h), Image.BILINEAR)


def _block(size: int) -> Image.Image:
    """One gold block: vertical gradient, rounded, with a top highlight."""
    grad = Image.new("RGB", (1, size))
    px = grad.load()
    for y in range(size):
        t = y / max(1, size - 1)
        px[0, y] = tuple(
            round(a + (b - a) * t) for a, b in zip(GOLD_LIGHT, GOLD_DEEP)
        )
    tile = grad.resize((size, size), Image.BILINEAR).convert("RGBA")

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=round(size * 0.18), fill=255
    )
    tile.putalpha(mask)

    # A soft inner highlight along the top edge, so the block reads as lit
    # from above the way the in-game cells do.
    gloss = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).rounded_rectangle(
        [round(size * 0.12), round(size * 0.10),
         round(size * 0.88), round(size * 0.42)],
        radius=round(size * 0.12), fill=(255, 255, 255, 46),
    )
    tile.alpha_composite(gloss.filter(ImageFilter.GaussianBlur(size * 0.05)))
    return tile


def _fit(draw, text, font_path, max_width, start):
    size = start
    while size > 20:
        font = ImageFont.truetype(str(font_path), size)
        if draw.textlength(text, font=font) <= max_width:
            return font
        size -= 2
    return ImageFont.truetype(str(font_path), 20)


def build_card(w: int, h: int) -> Image.Image:
    card = _wood(w, h)
    draw = ImageDraw.Draw(card)

    # Everything sits inside the centre 80%: several Play and YouTube
    # surfaces crop the margins, and a wordmark clipped in half is worse
    # than a small one.
    safe = round(w * 0.80)

    cell = round(w * 0.088)
    gap = round(cell * 0.09)
    mark_w = 3 * cell + 2 * gap
    mark_h = 2 * cell + gap
    name_font = _fit(draw, NAME, DISPLAY_FONT, safe, round(w * 0.20))
    name_h = draw.textbbox((0, 0), NAME, font=name_font)[3]
    tag_font = _fit(draw, TAGLINE, BODY_FONT, safe, round(w * 0.048))
    tag_h = draw.textbbox((0, 0), TAGLINE, font=tag_font)[3]

    pad_a = round(h * 0.045)   # mark -> name
    pad_b = round(h * 0.022)   # name -> tagline
    total = mark_h + pad_a + name_h + pad_b + tag_h
    y = (h - total) // 2

    block = _block(cell)
    mx = (w - mark_w) // 2
    for cx, cy in MARK:
        card.paste(
            block,
            (mx + cx * (cell + gap), y + cy * (cell + gap)),
            block,
        )
    y += mark_h + pad_a

    nx = (w - draw.textlength(NAME, font=name_font)) / 2
    draw.text((nx, y), NAME, font=name_font, fill=GOLD)
    y += name_h + pad_b

    tx = (w - draw.textlength(TAGLINE, font=tag_font)) / 2
    draw.text((tx, y), TAGLINE, font=tag_font, fill=TEXT)
    return card


def probe(path: Path) -> tuple[int, int, float]:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height",
         "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
        capture_output=True, text=True, check=True,
    ).stdout.split()
    return int(out[0]), int(out[1]), float(out[2])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("video", type=Path)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--total", type=float, default=40.0,
                    help="length of the finished file, in seconds")
    ap.add_argument("--card", type=float, default=4.0,
                    help="seconds the end card holds")
    ap.add_argument("--fade", type=float, default=0.6)
    ap.add_argument("--card-only", type=Path,
                    help="write just the card PNG here and stop")
    a = ap.parse_args()

    if a.card_only:
        build_card(1080, 1920).save(a.card_only)
        print(f"→ {a.card_only}  1080x1920")
        return 0

    w, h, dur = probe(a.video)
    play = a.total - a.card + a.fade
    if play <= a.fade:
        print(f"--total {a.total}s leaves no room for a {a.card}s card",
              file=sys.stderr)
        return 2
    if play > dur + 0.05:
        print(f"source is {dur:.1f}s but {play:.1f}s of play is needed for a "
              f"{a.total}s cut with a {a.card}s card", file=sys.stderr)
        return 2

    card_png = a.video.with_suffix(".card.png")
    build_card(w, h).save(card_png)

    out = a.out or a.video.with_name(a.video.stem + "_outro.mp4")
    # The card is a still, so it costs almost nothing to encode; the gameplay
    # half has to be re-encoded regardless because xfade cannot stream-copy.
    subprocess.run([
        "ffmpeg", "-y", "-v", "error",
        "-i", str(a.video),
        "-loop", "1", "-t", str(a.card), "-i", str(card_png),
        "-filter_complex",
        f"[0:v]trim=0:{play},setpts=PTS-STARTPTS,fps=60,format=yuv420p[a];"
        f"[1:v]scale={w}:{h},setsar=1,fps=60,format=yuv420p[b];"
        f"[a][b]xfade=transition=fade:duration={a.fade}:"
        f"offset={play - a.fade}[v]",
        "-map", "[v]", "-c:v", "libx264", "-preset", "medium", "-crf", "20",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(out),
    ], check=True)
    card_png.unlink()

    _, _, got = probe(out)
    print(f"→ {out}  {w}x{h}  {got:.2f}s  "
          f"({play:.1f}s play + {a.fade}s fade + card)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
