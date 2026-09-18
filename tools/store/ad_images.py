#!/usr/bin/env python3
"""Build the Google Ads App campaign images from real Tetrofall gameplay.

An App campaign ad group takes up to 20 images, which Google mixes into
YouTube, Discover, Display and AdMob placements. The shot list lives in
`tools/store/ads.json`; this renders it.

    python3 tools/store/ad_images.py            # everything
    python3 tools/store/ad_images.py --only 18_where_does_it_go
    python3 tools/store/ad_images.py --verify
    python3 tools/store/ad_images.py --pick gameplay/video/07_cascade_2min.mp4

Every board in every image is a capture from `gameplay/` or a frame decoded
out of a capture reel. The tool crops, scales, blurs and frames — it never
draws on a board, and it adds no arrows-at-blocks, play buttons or install
buttons. That is what keeps "no fake ads" true of the paid creative and not
just the store page (see gameplay/README.md), and fake UI in an image is a
misleading-creative rejection in its own right.

Layouts:

  crop      Full-bleed crop around `focus`, grown to the ratio. Stays inside
            the board, so the HUD and pause button drop out.
  panel     The board, sharp, in a gold-rimmed panel over its own blurred wood.
  headline  A panel plus copy. Left column in landscape, top band otherwise.

`focus` is [x0, y0, x1, y1] as fractions of the source frame: the region
that must survive the crop (crop) or that the panel shows (panel/headline).

There is deliberately no before/after layout. The `tetrofall_clear` and
`shatter` captures look like one moment 250ms apart but are different boards,
and an arrow between them would claim a sequence that never happened.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from outro import (  # noqa: E402  - same palette, same fonts, same mark
    BODY_FONT, DISPLAY_FONT, GOLD, GOLD_LIGHT, MARK, NAME, TEXT_MUTED,
    _block, _fit,
)
from yt_thumb import BG_DEEP, frame_at, score  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
GAMEPLAY = ROOT / "gameplay"
OUT = GAMEPLAY / "ads"
SPEC = Path(__file__).with_name("ads.json")

# Google Ads App campaign image slots.
SIZES = {
    "landscape": (1200, 628),   # 1.91:1
    "square": (1200, 1200),     # 1:1
    "portrait": (1200, 1500),   # 4:5
}
COUNTS = {"landscape": 7, "square": 6, "portrait": 7}
WITH_TEXT = 5
MAX_BYTES = 5120 * 1024

# The board's vertical extent, as fractions of the frame. The iOS stills carry
# a HUD bar above and the home-indicator bar below; the reels are immersive,
# with the score floating over the top rows.
STILL_BAND = (0.09, 0.91)
VIDEO_BAND = (0.06, 1.0)


def load(src: str):
    """A source frame and its board band, or (None, None) if it is missing."""
    if "@" in src:
        path, t = src.rsplit("@", 1)
        video = GAMEPLAY / path
        if not video.exists():
            return None, None
        return frame_at(video, float(t)), VIDEO_BAND
    path = GAMEPLAY / src
    if not path.exists():
        return None, None
    with Image.open(path) as im:
        return im.convert("RGB"), STILL_BAND


def fit_crop(src: Image.Image, box, w: int, h: int) -> Image.Image:
    """Crop `src` to w:h around `box`, then scale to w x h.

    The box grows from its centre until it is the target ratio. If that is
    bigger than the source, both sides shrink together — the ratio is kept
    and the box edges are trimmed, rather than the frame being stretched.
    """
    x0, y0, x1, y1 = box
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    bw, bh = x1 - x0, y1 - y0
    if bw / bh < w / h:
        bw = bh * w / h
    else:
        bh = bw * h / w
    k = min(1.0, src.width / bw, src.height / bh)
    bw, bh = bw * k, bh * k
    cx = min(max(cx, bw / 2), src.width - bw / 2)
    cy = min(max(cy, bh / 2), src.height - bh / 2)
    crop = src.crop((round(cx - bw / 2), round(cy - bh / 2),
                     round(cx + bw / 2), round(cy + bh / 2)))
    return crop.resize((w, h), Image.LANCZOS)


def board_of(shot: Image.Image, band) -> tuple[Image.Image, int]:
    top = round(shot.height * band[0])
    bottom = round(shot.height * band[1])
    return shot.crop((0, top, shot.width, bottom)), top


def focus_px(shot: Image.Image, board: Image.Image, top: int, focus):
    x0, y0, x1, y1 = focus
    return (x0 * shot.width,
            max(0, y0 * shot.height - top),
            x1 * shot.width,
            min(board.height, y1 * shot.height - top))


def ground(shot: Image.Image, band, w: int, h: int) -> Image.Image:
    """The frame's own lower board, blown up, defocused and darkened."""
    board, _ = board_of(shot, band)
    bg = fit_crop(board, (0, board.height * 0.45, board.width, board.height),
                  w, h)
    bg = bg.filter(ImageFilter.GaussianBlur(round(max(w, h) * 0.014)))
    bg = Image.blend(bg, Image.new("RGB", (w, h), BG_DEEP), 0.52)

    # Warm corner falloff, as yt_thumb and the feature graphic do. Applied to
    # the ground only, so the boards on top stay exactly as captured.
    vig = Image.new("L", (w, h), 0)
    ImageDraw.Draw(vig).ellipse([-w * 0.28, -h * 0.40, w * 1.28, h * 1.40],
                                fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(round(max(w, h) * 0.11)))
    return Image.composite(
        bg, Image.blend(bg, Image.new("RGB", (w, h), BG_DEEP), 0.42), vig
    )


def fit_into(img: Image.Image, rw: int, rh: int) -> Image.Image:
    k = min(rw / img.width, rh / img.height)
    return img.resize((round(img.width * k), round(img.height * k)),
                      Image.LANCZOS)


def paste_panel(card: Image.Image, img: Image.Image, x: int, y: int):
    W, H = card.size
    pw, ph = img.size
    radius = round(min(pw, ph) * 0.05)
    mask = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, pw - 1, ph - 1],
                                           radius=radius, fill=255)
    shadow = Image.new("L", (W, H), 0)
    shadow.paste(mask.point(lambda v: round(v * 0.75)),
                 (x, y + round(ph * 0.02)))
    card = Image.composite(Image.new("RGB", (W, H), (0, 0, 0)), card,
                           shadow.filter(ImageFilter.GaussianBlur(
                               round(max(W, H) * 0.02))))
    card.paste(img, (x, y), mask)
    ImageDraw.Draw(card).rounded_rectangle(
        [x, y, x + pw - 1, y + ph - 1], radius=radius, outline=GOLD,
        width=max(3, round(max(W, H) * 0.003)),
    )
    return card


def headline_column(card, lines, subline, x0, x1):
    """Landscape copy: headline, mark and name, subline — left of the panel."""
    W, H = card.size
    draw = ImageDraw.Draw(card)
    col = x1 - x0
    size = min(_fit(draw, line, DISPLAY_FONT, col, round(H * 0.23)).size
               for line in lines)
    font = ImageFont.truetype(str(DISPLAY_FONT), size)
    line_h = round(size * 0.92)

    cell = round(H * 0.042)
    gap = max(2, round(cell * 0.1))
    mark_h = 2 * cell + gap
    sub_font = _fit(draw, subline, BODY_FONT, col, round(H * 0.047)) \
        if subline else None
    sub_h = draw.textbbox((0, 0), subline, font=sub_font)[3] if subline else 0

    total = line_h * len(lines) + round(H * 0.05) + mark_h
    if subline:
        total += round(H * 0.038) + sub_h
    y = round((H - total) / 2)

    for line in lines:
        draw.text((x0 + 4, y + 6), line, font=font, fill=(0, 0, 0))
        draw.text((x0, y), line, font=font, fill=GOLD_LIGHT)
        y += line_h

    y += round(H * 0.05)
    block = _block(cell)
    for cx, cy in MARK:
        card.paste(block, (x0 + cx * (cell + gap), y + cy * (cell + gap)),
                   block)
    name_font = ImageFont.truetype(str(DISPLAY_FONT), round(H * 0.075))
    nx = x0 + 3 * (cell + gap) + round(cell * 0.7)
    ny = y + mark_h - draw.textbbox((0, 0), NAME, font=name_font)[3] - 4
    draw.text((nx, ny), NAME, font=name_font, fill=GOLD)

    if subline:
        draw.text((x0, y + mark_h + round(H * 0.038)), subline,
                  font=sub_font, fill=TEXT_MUTED)


def headline_band(card, lines, subline, band_h):
    """Square/portrait copy: centred in a band across the top. No mark — Google
    shows the app name and icon beside the image, and the band stays small."""
    W, _ = card.size
    draw = ImageDraw.Draw(card)
    col = round(W * 0.84)
    size = min(_fit(draw, line, DISPLAY_FONT, col, round(band_h * 0.40)).size
               for line in lines)
    font = ImageFont.truetype(str(DISPLAY_FONT), size)
    line_h = round(size * 1.0)
    sub_font = _fit(draw, subline, BODY_FONT, col, round(band_h * 0.15)) \
        if subline else None
    sub_gap = round(band_h * 0.04)
    sub_h = draw.textbbox((0, 0), subline, font=sub_font)[3] if subline else 0

    # Baloo's line box carries a tall ascent above the caps; bbox the real ink
    # so the block centres on what the eye sees.
    ink_top = draw.textbbox((0, 0), lines[0], font=font)[1]
    total = line_h * len(lines) + (sub_gap + sub_h if subline else 0) - ink_top
    y = round((band_h - total) / 2) - ink_top

    for line in lines:
        tw = draw.textlength(line, font=font)
        draw.text(((W - tw) / 2 + 4, y + 6), line, font=font, fill=(0, 0, 0))
        draw.text(((W - tw) / 2, y), line, font=font, fill=GOLD_LIGHT)
        y += line_h
    if subline:
        tw = draw.textlength(subline, font=sub_font)
        draw.text(((W - tw) / 2, y + sub_gap), subline, font=sub_font,
                  fill=TEXT_MUTED)


def render(entry: dict) -> Image.Image | None:
    w, h = SIZES[entry["ratio"]]
    shot, band = load(entry["src"])
    if shot is None:
        print(f"skip  {entry['id']}: missing {entry['src']}")
        return None

    board, top = board_of(shot, band)
    box = focus_px(shot, board, top, entry["focus"])
    if entry["layout"] == "crop":
        return fit_crop(board, box, w, h)

    card = ground(shot, band, w, h)
    lines = entry.get("headline")
    subline = entry.get("subline")
    landscape = w > h
    if lines and landscape:
        region = (round(w * 0.55), round(h * 0.04), round(w * 0.95),
                  round(h * 0.96))
    elif lines:
        band_h = round(h * (0.24 if entry["ratio"] == "square" else 0.22))
        region = (round(w * 0.07), band_h, round(w * 0.93),
                  h - round(h * 0.045))
    else:
        region = (round(w * 0.05), round(h * 0.04), round(w * 0.95),
                  round(h * 0.96))

    rx0, ry0, rx1, ry1 = region
    rw, rh = rx1 - rx0, ry1 - ry0
    img = fit_into(board.crop(tuple(round(v) for v in box)), rw, rh)
    card = paste_panel(card, img, rx0 + (rw - img.width) // 2,
                       ry0 + (rh - img.height) // 2)

    if lines and landscape:
        headline_column(card, lines, subline, round(w * 0.08),
                        rx0 - round(w * 0.03))
    elif lines:
        headline_band(card, lines, subline, ry0)
    return card


def contact_sheet(spec: list[dict]) -> Path:
    cols, tile, pad, label = 5, 360, 16, 26
    rows = (len(spec) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (tile + pad) + pad,
                              rows * (tile + pad + label) + pad), (24, 16, 10))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(str(BODY_FONT), 16)
    for i, entry in enumerate(spec):
        path = OUT / entry["ratio"] / f"{entry['id']}.png"
        x = pad + (i % cols) * (tile + pad)
        y = pad + (i // cols) * (tile + pad + label)
        draw.text((x, y), entry["id"], font=font, fill=TEXT_MUTED)
        if not path.exists():
            continue
        with Image.open(path) as im:
            im = fit_into(im.convert("RGB"), tile, tile)
        sheet.paste(im, (x + (tile - im.width) // 2,
                         y + label + (tile - im.height) // 2))
    dest = OUT / "contact_sheet.png"
    sheet.save(dest, optimize=True)
    return dest


def verify(spec: list[dict]) -> int:
    failures = 0
    counts = {r: 0 for r in SIZES}
    for entry in spec:
        path = OUT / entry["ratio"] / f"{entry['id']}.png"
        rel = path.relative_to(ROOT)
        counts[entry["ratio"]] += 1
        if not path.exists():
            print(f"FAIL  {rel}: not rendered")
            failures += 1
            continue
        with Image.open(path) as im:
            size = im.size
        problems = []
        if size != SIZES[entry["ratio"]]:
            problems.append(f"is {size[0]}x{size[1]}, must be "
                            f"{'x'.join(map(str, SIZES[entry['ratio']]))}")
        nbytes = path.stat().st_size
        if nbytes > MAX_BYTES:
            problems.append(f"{nbytes / 1024:.0f}KB exceeds 5120KB")
        if problems:
            failures += 1
            print(f"FAIL  {rel}")
            for p in problems:
                print(f"        {p}")
        else:
            text = "text" if entry.get("headline") else "    "
            print(f"ok    {rel}  {size[0]}x{size[1]}  "
                  f"{nbytes / 1024:.0f}KB  {text}")

    listed = {(e["ratio"], e["id"]) for e in spec}
    for ratio in SIZES:
        for stray in sorted((OUT / ratio).glob("*.png")):
            if (ratio, stray.stem) not in listed:
                print(f"warn  {stray.relative_to(ROOT)}: not in ads.json")

    texted = sum(1 for e in spec if e.get("headline"))
    for label, got, want in [("total", len(spec), sum(COUNTS.values())),
                             *((r, counts[r], COUNTS[r]) for r in SIZES),
                             ("with text", texted, WITH_TEXT)]:
        if got != want:
            failures += 1
            print(f"FAIL  {label}: {got}, want {want}")

    print(f"\n{len(spec)} images checked, {failures} problems")
    return 1 if failures else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", nargs="+", metavar="ID")
    ap.add_argument("--verify", action="store_true")
    ap.add_argument("--pick", type=Path, metavar="VIDEO",
                    help="print the busiest seconds of a reel and stop")
    args = ap.parse_args()

    spec = json.loads(SPEC.read_text())

    if args.pick:
        for t, bright, fill in score(args.pick)[:15]:
            print(f"  @{t:5.2f}   burst={bright:.4f}  fill={fill:.2f}")
        return 0
    if args.verify:
        return verify(spec)

    wanted = set(args.only or [])
    made = 0
    for entry in spec:
        if wanted and entry["id"] not in wanted:
            continue
        card = render(entry)
        if card is None:
            continue
        dest = OUT / entry["ratio"] / f"{entry['id']}.png"
        dest.parent.mkdir(parents=True, exist_ok=True)
        card.save(dest, "PNG", optimize=True)
        made += 1
        print(f"wrote {dest.relative_to(ROOT)}  {card.width}x{card.height}  "
              f"{dest.stat().st_size / 1024:.0f}KB")

    sheet = contact_sheet(spec)
    print(f"\n{made} images, contact sheet {sheet.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
