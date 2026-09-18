#!/usr/bin/env python3
"""Verify and caption the Play Store captures in `gameplay/`.

Two jobs:

  --verify   Check every file against the Play slot it is destined for.
             Play rejects an out-of-spec asset at upload time with a generic
             message, after the emulator has been torn down; this fails
             immediately and says which rule and by how much.

  --caption  Build the android_release_plan.md §4.9 framed variants: a wood
             band carrying a gold Baloo 2 headline, with the raw capture
             inset below it under a border and a soft drop shadow.

ImageMagick is not installed on this machine, so this is Pillow. The fonts
are the app's own TTFs, read straight out of `assets/fonts/`, so a caption is
set in the same type the game uses.
"""
import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
GAMEPLAY = ROOT / "gameplay"

DISPLAY_FONT = ROOT / "assets/fonts/Baloo_2/static/Baloo2-ExtraBold.ttf"
BODY_FONT = ROOT / "assets/fonts/Nunito/static/Nunito-Bold.ttf"

# lib/ui/theme/tokens.dart
WOOD_DARK = (0x4A, 0x2F, 0x1C)
WOOD_MID = (0x7A, 0x52, 0x30)
BG = (0x2B, 0x1C, 0x12)
GOLD = (0xF2, 0xB6, 0x32)
TEXT = (0xF5, 0xEA, 0xD9)

MAX_BYTES = 8 * 1024 * 1024

# Play's rules per slot, from android_release_plan.md §4.6.
SLOTS = {
    "feature": dict(exact=(1024, 500), label="Feature graphic"),
    "phone": dict(side=(320, 3840), ratios=("9:16", "16:9"), label="Phone"),
    "phone_captioned": dict(side=(320, 3840), ratios=("9:16", "16:9"),
                            label="Phone (captioned)"),
    "tablet7": dict(side=(320, 3840), ratios=("9:16", "16:9"),
                    label='7" tablet'),
    "tablet10": dict(side=(1080, 7680), ratios=("9:16", "16:9"),
                     label='10" tablet'),
}

RATIOS = {"9:16": 9 / 16, "16:9": 16 / 9}


def verify() -> int:
    failures = 0
    checked = 0
    for name, rule in SLOTS.items():
        folder = GAMEPLAY / name
        if not folder.is_dir():
            continue
        for path in sorted(folder.glob("*.png")) + sorted(folder.glob("*.jpg")):
            checked += 1
            problems = []
            size = path.stat().st_size
            if size > MAX_BYTES:
                problems.append(f"{size / 1e6:.1f}MB exceeds the 8MB limit")
            with Image.open(path) as im:
                w, h = im.size
            if "exact" in rule and (w, h) != rule["exact"]:
                ew, eh = rule["exact"]
                problems.append(f"is {w}x{h}, must be exactly {ew}x{eh}")
            if "side" in rule:
                lo, hi = rule["side"]
                for edge, v in (("width", w), ("height", h)):
                    if not lo <= v <= hi:
                        problems.append(f"{edge} {v} outside {lo}-{hi}px")
            if "ratios" in rule:
                actual = w / h
                if not any(
                    abs(actual - RATIOS[r]) < 0.005 for r in rule["ratios"]
                ):
                    want = " or ".join(rule["ratios"])
                    problems.append(
                        f"aspect {actual:.4f} ({w}x{h}) is not {want}"
                    )
            if problems:
                failures += 1
                print(f"FAIL  {path.relative_to(ROOT)}")
                for p in problems:
                    print(f"        {p}")
            else:
                print(
                    f"ok    {path.relative_to(ROOT)}  "
                    f"{w}x{h}  {size / 1e3:.0f}KB  [{rule['label']}]"
                )

    print(f"\n{checked} files checked, {failures} rejected")
    return 1 if failures else 0


def _wood_band(width: int, height: int) -> Image.Image:
    """A vertical wood gradient, matching `Tokens.bgWoodGradient`."""
    band = Image.new("RGB", (1, height))
    px = band.load()
    for y in range(height):
        t = y / max(1, height - 1)
        px[0, y] = tuple(
            round(a + (b - a) * t) for a, b in zip(WOOD_DARK, BG)
        )
    return band.resize((width, height), Image.BILINEAR)


def _fit_text(draw, text, font_path, max_width, start):
    """Largest size at which the headline still fits the band."""
    size = start
    while size > 24:
        font = ImageFont.truetype(str(font_path), size)
        if draw.textlength(text, font=font) <= max_width:
            return font
        size -= 2
    return ImageFont.truetype(str(font_path), 24)


def _split_headline(text: str) -> list[str]:
    if ". " in text:
        head, tail = text.split(". ", 1)
        return [head + ".", tail]
    words = text.split()
    if len(words) <= 3:
        return [text]
    mid = (len(words) + 1) // 2
    return [" ".join(words[:mid]), " ".join(words[mid:])]


def caption(captions: dict[str, str], src=None, out=None) -> int:
    src = src or GAMEPLAY / "phone"
    out = out or GAMEPLAY / "phone_captioned"
    out.mkdir(parents=True, exist_ok=True)

    made = 0
    for name, text in captions.items():
        path = src / f"{name}.png"
        if not path.exists():
            print(f"skip  {name}: no capture at {path.relative_to(ROOT)}")
            continue

        with Image.open(path) as shot:
            shot = shot.convert("RGB")
            W, H = shot.size

        canvas = _wood_band(W, H).convert("RGB")
        draw = ImageDraw.Draw(canvas)

        # §4.9: caption band across the top fifth, the capture below it.
        #
        # The inset is bound by height, not width. The capture is the same
        # 9:16 as the canvas, so scaling it to 86% of the *width* makes it
        # 86% of the height too — which, under a 20% band, runs 115 pixels
        # off the bottom of the frame.
        band_h = round(H * 0.20)
        margin = round(H * 0.022)
        scale = min(0.86, (H - band_h - margin * 2) / H)
        inset_w = round(W * scale)
        inset_h = round(H * scale)
        inset = shot.resize((inset_w, inset_h), Image.LANCZOS)

        x = (W - inset_w) // 2
        y = band_h + round((H - band_h - inset_h) / 2)

        # Soft drop shadow, then a gold keyline — the same gold the board
        # frame and the wordmark use.
        pad = 26
        shadow = Image.new("RGBA", (inset_w + pad * 2, inset_h + pad * 2), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle(
            [pad, pad, pad + inset_w, pad + inset_h], radius=24, fill=(0, 0, 0, 150)
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(16))
        canvas.paste(
            Image.alpha_composite(
                canvas.crop(
                    (x - pad, y - pad, x - pad + shadow.width, y - pad + shadow.height)
                ).convert("RGBA"),
                shadow,
            ).convert("RGB"),
            (x - pad, y - pad),
        )

        rounded = Image.new("L", (inset_w, inset_h), 0)
        ImageDraw.Draw(rounded).rounded_rectangle(
            [0, 0, inset_w - 1, inset_h - 1], radius=22, fill=255
        )
        canvas.paste(inset, (x, y), rounded)
        draw.rounded_rectangle(
            [x - 4, y - 4, x + inset_w + 3, y + inset_h + 3],
            radius=26,
            outline=GOLD,
            width=5,
        )

        # The headline. Two lines at most — §4.9 caps it at five words
        # because it has to survive Play's 120px search thumbnail.
        #
        # Break on the sentence boundary where there is one: "Clear rows. /
        # Watch them shatter." reads as two beats, where an even word split
        # gives "Clear rows. Watch / them shatter." and reads as a mistake.
        lines = _split_headline(text)

        max_w = round(W * 0.86)
        font = min(
            (_fit_text(draw, line, DISPLAY_FONT, max_w, 84) for line in lines),
            key=lambda f: f.size,
        )
        line_h = font.size * 1.16
        total = line_h * len(lines)
        ty = (band_h - total) / 2
        for line in lines:
            tw = draw.textlength(line, font=font)
            draw.text(
                ((W - tw) / 2 + 3, ty + 3), line, font=font, fill=(0, 0, 0, 160)
            )
            draw.text(((W - tw) / 2, ty), line, font=font, fill=GOLD)
            ty += line_h

        dest = out / f"{name}.png"
        canvas.save(dest, "PNG", optimize=True)
        made += 1
        print(f"wrote {dest.relative_to(ROOT)}  {W}x{H}")

    print(f"\n{made} captioned shots")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--verify", action="store_true")
    ap.add_argument("--caption", metavar="JSON",
                    help="path to {scene: caption} JSON")
    ap.add_argument("--src", metavar="DIR", help="raw captures (default gameplay/phone)")
    ap.add_argument("--out", metavar="DIR", help="captioned output (default gameplay/phone_captioned)")
    args = ap.parse_args()

    if args.caption:
        src = Path(args.src).resolve() if args.src else None
        out = Path(args.out).resolve() if args.out else None
        return caption(json.loads(Path(args.caption).read_text()), src=src, out=out)
    if args.verify:
        return verify()
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
