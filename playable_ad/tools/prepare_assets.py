#!/usr/bin/env python3
"""One-time (re-run only when the source game art changes) asset prep for
the playable ad. Reads the REAL game's assets (read-only) and writes small
derived files into playable_ad/assets/, which build.py base64-inlines.

Not run by build.py itself — build.py has zero extra runtime dependencies.
This script needs: ffmpeg, and fontTools (pip3 install fonttools).

See playable_ad_plan.md's "visual/audio fidelity upgrade" plan for why each
asset is cropped/encoded the way it is.

Usage: python3 tools/prepare_assets.py
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PLAYABLE_AD = os.path.dirname(HERE)
REPO_ROOT = os.path.dirname(PLAYABLE_AD)
OUT = os.path.join(PLAYABLE_AD, "assets")

GAME_ASSETS = os.path.join(REPO_ROOT, "assets")
GAME_FONTS = os.path.join(REPO_ROOT, "assets", "fonts")


def run(cmd):
    print("$ " + " ".join(cmd))
    subprocess.run(cmd, check=True)


def block_tile():
    src = os.path.join(GAME_ASSETS, "images", "blocks", "tile_classic_wood.png")
    dst = os.path.join(OUT, "block_tile.jpg")
    # Real source is 500x500 with a rounded-corner border and a small
    # diamond watermark baked in near the bottom-right — crop a centered
    # 320x320 interior region to avoid both, then downscale (blocks render
    # at ~18px on screen, so 96x96 is already overkill) and lighten/
    # desaturate slightly so the runtime multiply-tint (see game.js
    # drawBlock) colorizes cleanly instead of crushing shadows on this
    # fairly dark walnut photo.
    run([
        "ffmpeg", "-y", "-i", src,
        "-vf", "crop=320:320:90:90,scale=96:96,eq=brightness=0.12:saturation=0.55",
        "-q:v", "5",
        dst,
    ])


def board_tile():
    src = os.path.join(GAME_ASSETS, "images", "textures", "bg_wood.png")
    dst = os.path.join(OUT, "board_tile.jpg")
    # This photo is already close to Tokens.colorWoodLight (the real game
    # treats its own tint as a near no-op for the shipped theme), so no
    # color grading here — just crop a seamless-looking interior patch and
    # downscale for tiling via ctx.createPattern in game.js.
    run([
        "ffmpeg", "-y", "-i", src,
        "-vf", "crop=700:700:277:277,scale=160:160",
        "-q:v", "6",
        dst,
    ])


def sfx(name, src_name, dst_name):
    src = os.path.join(GAME_ASSETS, "audio", "sfx", src_name)
    dst = os.path.join(OUT, dst_name)
    # Source is uncompressed 48kHz stereo WAV (~201KB). Mono + 64kbps mp3
    # is plenty for a ~1s UI sound effect and lands around 8-12KB.
    run(["ffmpeg", "-y", "-i", src, "-ac", "1", "-b:a", "64k", dst])


def wordmark_font():
    src = os.path.join(GAME_FONTS, "Baloo_2", "static", "Baloo2-ExtraBold.ttf")
    dst = os.path.join(OUT, "wordmark.woff2")
    # Only the glyphs actually drawn in this font in the ad: the wordmark
    # "TETROFALL", digits for the score/chain readout, and the punctuation
    # toLocaleString()/the "xN" chain label use. Captions stay in the
    # system font stack, so no lowercase letters are needed here.
    text = "TETROFALL0123456789x, "
    run([
        sys.executable, "-m", "fontTools.subset", src,
        f"--output-file={dst}",
        f"--text={text}",
        "--flavor=woff2",
        "--layout-features=*",
    ])


def display_font():
    src = os.path.join(GAME_FONTS, "Baloo_2", "static", "Baloo2-ExtraBold.ttf")
    dst = os.path.join(OUT, "display.woff2")
    # The five Google Ads playables (build_ads.py) set every caption, hook
    # and button in Baloo 2, so they get printable ASCII plus the ellipsis
    # and multiplication sign rather than the wordmark's handful of glyphs.
    run([
        sys.executable, "-m", "fontTools.subset", src,
        f"--output-file={dst}",
        "--unicodes=U+0020-007E,U+00D7,U+2026",
        "--flavor=woff2",
        "--layout-features=kern,liga",
    ])


STEPS = {
    "block_tile": block_tile,
    "board_tile": board_tile,
    "sfx": lambda: (
        sfx("lock", "block_settle.wav", "sfx_lock.mp3"),
        sfx("clear", "wood_crush.wav", "sfx_clear.mp3"),
    ),
    "wordmark_font": wordmark_font,
    "display_font": display_font,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    # `python3 tools/prepare_assets.py display_font` regenerates one asset
    # without re-encoding (and re-diffing) the rest.
    for name in sys.argv[1:] or STEPS.keys():
        STEPS[name]()

    print("\nOutput sizes:")
    for f in sorted(os.listdir(OUT)):
        p = os.path.join(OUT, f)
        print(f"  {f}: {os.path.getsize(p):,} bytes")


if __name__ == "__main__":
    main()
