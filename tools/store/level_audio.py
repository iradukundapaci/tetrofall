#!/usr/bin/env python3
"""Bring a reel's soundtrack up to a usable level.

A reel mirrored off the device with scrcpy lands around -30dBFS: the SFX play
at the 0.85 slider's amplitude into an otherwise digitally silent capture.
`outro.py` already normalises the cut it builds, but reels that go out as
themselves — `06_endurance_2min`, `07_cascade_2min` — never pass through it,
so they need the same pass applied on their own.

    tools/store/level_audio.py gameplay/video/06_endurance_2min.mp4 --in-place

The picture is stream-copied, so this costs no quality and only the audio is
re-encoded. A file with no audio is left exactly as it is, which makes this
safe to run across the whole directory.

The measurement and the target both come from `outro.py`, so a reel levelled
here and a cut levelled there land on the same peak.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from outro import PEAK_TARGET, has_audio, peak_dbfs  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("video", type=Path)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--in-place", action="store_true")
    ap.add_argument("--peak", type=float, default=PEAK_TARGET,
                    help=f"peak to normalise to, in dBFS (default {PEAK_TARGET})")
    a = ap.parse_args()
    if not a.out and not a.in_place:
        print("pass --out or --in-place", file=sys.stderr)
        return 2

    if not has_audio(a.video):
        print(f"{a.video} has no audio — left unchanged")
        return 0

    was = peak_dbfs(a.video)
    gain = a.peak - was
    out = a.out or a.video.with_name(a.video.stem + ".levelled.mp4")
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-i", str(a.video),
         "-map", "0:v", "-map", "0:a", "-c:v", "copy",
         "-af", f"volume={gain:.2f}dB", "-c:a", "aac", "-b:a", "192k",
         "-movflags", "+faststart", str(out)],
        check=True)

    if a.in_place:
        shutil.move(str(out), str(a.video))
        out = a.video
    print(f"→ {out}  {was:.1f} {gain:+.1f}dB → {peak_dbfs(out):.1f}dBFS peak")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
