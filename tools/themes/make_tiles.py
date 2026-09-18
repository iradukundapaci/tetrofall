"""Generates the block tiles for the Coin-shop themes.

    python3 tools/themes/make_tiles.py

PLACEHOLDER ART. These exist so the three purchasable themes are real and
playable while proper tiles are drawn; replace each PNG with a hand-made one at
the same path and size and nothing else needs to change.

Every tile reuses the exact silhouette (alpha) of `tile_classic_wood.png`, so
the rounded corners and inset match the shipped theme pixel for pixel. Only
luminance really matters: `TileCache` tints with `BlendMode.color`, which keeps
the tile's lightness and takes hue and saturation from the theme's `blockTint`.
So each surface here is designed as a lightness pattern — veins, frost,
stripes — and the colour comes from `ThemeDefinition`.
"""

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
BLOCKS = ROOT / "assets/images/blocks"
SIZE = 500
BEVEL = 24


def value_noise(rng, octaves=5, base=4):
    """Fractal value noise in [0, 1], bilinear-upsampled grids summed."""
    out = np.zeros((SIZE, SIZE))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        cells = base * 2**o
        grid = rng.random((cells + 1, cells + 1))
        img = Image.fromarray((grid * 255).astype(np.uint8)).resize(
            (SIZE, SIZE), Image.BICUBIC
        )
        out += amp * np.asarray(img) / 255.0
        total += amp
        amp *= 0.5
    return out / total


def marble(rng):
    y, x = np.mgrid[0:SIZE, 0:SIZE] / SIZE
    turb = value_noise(rng, octaves=6, base=3)
    veins = np.abs(np.sin((x * 3.0 + y * 1.4 + turb * 4.5) * np.pi))
    veins = veins**0.35  # thin, dark veins on a bright field
    fine = value_noise(rng, octaves=4, base=16)
    return 150 + 85 * veins + 15 * (fine - 0.5)


def snow(rng):
    soft = value_noise(rng, octaves=5, base=3)
    lum = 205 + 30 * soft
    # Sparse bright flakes.
    flakes = rng.random((SIZE, SIZE)) > 0.9965
    lum[flakes] = 255
    img = Image.fromarray(lum.clip(0, 255).astype(np.uint8)).resize(
        (SIZE, SIZE)
    )
    return np.asarray(img).astype(float)


def candy(rng):
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    stripes = ((x + y) // 42) % 2
    lum = np.where(stripes == 0, 150.0, 205.0)
    # Glossy highlight across the top third.
    gloss = np.clip(1 - y / (SIZE * 0.4), 0, 1) ** 2
    lum += 40 * gloss
    lum += 8 * (value_noise(rng, octaves=3, base=8) - 0.5)
    return lum


def bevel(lum, alpha):
    """Light top-left rim, dark bottom-right rim, like the wood tile."""
    inside = alpha > 0
    ys, xs = np.where(inside)
    top, bottom, left, right = ys.min(), ys.max(), xs.min(), xs.max()
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    d_top, d_left = y - top, x - left
    d_bottom, d_right = bottom - y, right - x
    light = np.clip(1 - np.minimum(d_top, d_left) / BEVEL, 0, 1)
    dark = np.clip(1 - np.minimum(d_bottom, d_right) / BEVEL, 0, 1)
    return lum + 45 * light - 60 * dark


def sparkle(lum):
    """The four-point glint in the bottom-right corner of the wood tile."""
    cx, cy, r = 440, 440, 14
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    dx, dy = np.abs(x - cx), np.abs(y - cy)
    star = (dx * dy < 6) & (dx + dy < r)
    lum[star] = 255
    return lum


def main():
    wood = Image.open(BLOCKS / "tile_classic_wood.png").convert("RGBA")
    alpha = np.asarray(wood)[..., 3]
    for name, surface, seed in (
        ("marble", marble, 11),
        ("snow", snow, 23),
        ("candy", candy, 37),
    ):
        rng = np.random.default_rng(seed)
        lum = sparkle(bevel(surface(rng), alpha)).clip(0, 255).astype(np.uint8)
        rgba = np.dstack([lum, lum, lum, alpha])
        out = BLOCKS / f"tile_{name}.png"
        Image.fromarray(rgba).save(out, optimize=True)
        print("wrote", out.relative_to(ROOT))


if __name__ == "__main__":
    main()
