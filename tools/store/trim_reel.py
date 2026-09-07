#!/usr/bin/env python3
"""Trim a reel to end before the game-over screen.

A reel dense enough to look good for two minutes is, by construction, one
where the rising floor is out-pacing the bot — and a floor that out-paces the
bot eventually reaches the top. Reel 6 sits on that side deliberately: at
`riseSpeed: 2.0` it holds a full board for the whole take and then tops out
around t=114, and the alternative (1.8 and below) is a board that survives by
being empty. So the take is cut before the overlay lands.

Detection is by mean luma, the same read the density check uses. The game
board is dark blocks on light wood and never goes below ~140, while the
game-over overlay dims the whole screen to ~50, so the two are not close.

    tools/store/trim_reel.py gameplay/video/06_endurance_2min.mp4 --in-place

With no game-over found the file is left exactly as it is, so this is safe to
run over any reel.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageStat

# The overlay reads ~50; live play stays above ~140. 100 is nowhere near
# either, which is the point — this is not a threshold that needs tuning.
DEAD_LUMA = 100

# Seconds of live play to drop along with the overlay. The frames immediately
# before a top-out are a board pressed against the ceiling, which is the best
# ending this reel has; this only trims the moment of death itself.
LEAD = 1.5


def duration(path: Path) -> float:
    return float(subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
        capture_output=True, text=True, check=True).stdout.strip())


def first_dead_frame(path: Path, step: float) -> float | None:
    """Timestamp of the first sampled frame that is the game-over overlay."""
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(path),
             "-vf", f"fps=1/{step},scale=160:-1", f"{tmp}/f_%04d.png"],
            check=True)
        for f in sorted(Path(tmp).glob("f_*.png")):
            with Image.open(f) as im:
                luma = ImageStat.Stat(im.convert("RGB")).mean[0]
            if luma < DEAD_LUMA:
                return (int(f.stem.split("_")[1]) - 1) * step
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("video", type=Path)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--in-place", action="store_true")
    ap.add_argument("--step", type=float, default=0.5,
                    help="sampling interval, seconds")
    a = ap.parse_args()
    if not a.out and not a.in_place:
        print("pass --out or --in-place", file=sys.stderr)
        return 2

    dead = first_dead_frame(a.video, a.step)
    if dead is None:
        print(f"no game-over found in {a.video} ({duration(a.video):.1f}s) — "
              f"left unchanged")
        return 0

    keep = max(1.0, dead - LEAD)
    out = a.out or a.video.with_name(a.video.stem + ".trimmed.mp4")
    # Re-encode rather than stream-copy: a keyframe cut would land up to a
    # second early or late, and the whole point is a precise ending.
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-i", str(a.video), "-t", f"{keep}",
         "-c:v", "libx264", "-preset", "medium", "-crf", "20",
         "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(out)],
        check=True)

    if a.in_place:
        shutil.move(str(out), str(a.video))
        out = a.video
    print(f"→ {out}  game over at ~{dead:.1f}s, kept {duration(out):.2f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
