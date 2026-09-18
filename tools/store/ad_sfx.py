#!/usr/bin/env python3
"""Synthesise the stingers the Google Ads video cuts are scored with.

The game ships three wooden-block sounds and no music, and the ad set is
deliberately music-free, so everything a cut needs beyond the captured SFX —
the buzzer on a blunder, the tick under a hover, the riser into the drop —
is built here from sine, square and filtered noise. Nothing is sampled, so
there is no licence to track (see assets/audio/CREDITS.md for why that
matters), and the horn figure is an original four notes, nowhere near
Korobeiniki.

    python3 tools/store/ad_sfx.py              # writes gameplay/ads_video/_sfx/
    python3 tools/store/ad_sfx.py --list

Deterministic: the noise is seeded, so a rebuild produces identical WAVs.
"""
from __future__ import annotations

import argparse
import math
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "gameplay" / "ads_video" / "_sfx"
SR = 48_000
PEAK_DBFS = -3.0


def _t(seconds: float) -> np.ndarray:
    return np.arange(int(SR * seconds)) / SR


def _noise(seconds: float, seed: int) -> np.ndarray:
    return np.random.default_rng(seed).uniform(-1, 1, int(SR * seconds))


def _env(n: int, attack: float, release: float) -> np.ndarray:
    """Linear attack, exponential tail — the shape of nearly every hit."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) / max(release, 1e-4))


def _phase(freq: np.ndarray) -> np.ndarray:
    """Integrate an instantaneous frequency track into phase."""
    return 2 * math.pi * np.cumsum(freq) / SR


def _bandpass(x: np.ndarray, centre: np.ndarray, q: float) -> np.ndarray:
    """Time-varying RBJ band-pass, one biquad recomputed per sample."""
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        w0 = 2 * math.pi * min(float(centre[i]), SR * 0.45) / SR
        alpha = math.sin(w0) / (2 * q)
        cw = math.cos(w0)
        a0 = 1 + alpha
        b0, b2 = alpha / a0, -alpha / a0
        a1, a2 = -2 * cw / a0, (1 - alpha) / a0
        out = b0 * x[i] + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, x[i]
        y2, y1 = y1, out
        y[i] = out
    return y


def _saw(phase: np.ndarray, harmonics: int = 12) -> np.ndarray:
    """Band-limited-ish sawtooth: a few harmonics, so it reads as brass."""
    return sum(np.sin(k * phase) / k for k in range(1, harmonics + 1))


# ─── the sounds ──────────────────────────────────────────────────────────


def tick() -> np.ndarray:
    n = int(SR * 0.09)
    t = _t(0.09)
    body = np.sin(2 * math.pi * 1900 * t) * _env(n, 0.0005, 0.012)
    click = _noise(0.09, 1) * _env(n, 0.0002, 0.003)
    return body + 0.6 * click


def heartbeat() -> np.ndarray:
    out = np.zeros(int(SR * 0.9))
    for start, gain in ((0.0, 1.0), (0.22, 0.75)):
        t = _t(0.3)
        freq = 70 * np.exp(-t * 6) + 42
        thump = np.sin(_phase(freq)) * _env(len(t), 0.004, 0.07) * gain
        i = int(start * SR)
        out[i:i + len(thump)] += thump
    return out


def riser() -> np.ndarray:
    dur = 1.8
    t = _t(dur)
    centre = 300 * (12 ** (t / dur))
    air = _bandpass(_noise(dur, 2), centre, 4.0)
    tone = np.sin(_phase(180 * (4 ** (t / dur)))) * 0.25
    swell = (t / dur) ** 2.2
    return (air * 3.0 + tone) * swell


def buzzer() -> np.ndarray:
    dur = 0.75
    t = _t(dur)
    sq = np.sign(np.sin(2 * math.pi * 98 * t)) + np.sign(
        np.sin(2 * math.pi * 103.5 * t))
    grit = np.tanh(sq * 1.4)
    env = np.clip(t / 0.01, 0, 1) * np.clip((dur - t) / 0.08, 0, 1)
    return grit * env


def record_scratch() -> np.ndarray:
    dur = 0.55
    t = _t(dur)
    # A platter dragged back and forth: speed swings through zero twice.
    speed = np.sin(2 * math.pi * 3.6 * t + 0.4)
    freq = 380 + 1400 * np.abs(speed)
    scratch = _bandpass(_noise(dur, 3), freq, 2.5) * 4.0
    whine = np.sin(_phase(freq * 0.5)) * 0.18
    env = np.abs(speed) ** 0.6 * np.clip((dur - t) / 0.05, 0, 1)
    return (scratch + whine) * env


def sad_horn() -> np.ndarray:
    # A3 → G3 → E3 → a long D3 with a sagging wobble. Original, and chosen to
    # be falling rather than recognisable.
    notes = [(220.0, 0.26), (196.0, 0.26), (164.8, 0.30), (146.8, 1.05)]
    parts = []
    for i, (f, d) in enumerate(notes):
        t = _t(d)
        last = i == len(notes) - 1
        vib = 1 + (0.03 * np.sin(2 * math.pi * 5.5 * t) * (t / d) if last else 0)
        sag = (1 - 0.04 * (t / d)) if last else 1
        tone = _saw(_phase(f * vib * sag), 10)
        env = np.clip(t / 0.03, 0, 1) * np.clip((d - t) / 0.06, 0, 1)
        parts.append(tone * env)
    return np.concatenate(parts)


def whoosh() -> np.ndarray:
    dur = 0.6
    t = _t(dur)
    centre = 500 + 2600 * np.sin(math.pi * t / dur)
    bell = np.sin(math.pi * t / dur) ** 2
    return _bandpass(_noise(dur, 4), centre, 1.6) * bell * 3.5


def impact() -> np.ndarray:
    dur = 1.0
    t = _t(dur)
    boom = np.sin(_phase(38 + 70 * np.exp(-t * 9))) * _env(len(t), 0.002, 0.28)
    crack = _bandpass(_noise(dur, 5), np.full(len(t), 1800.0), 0.8) \
        * _env(len(t), 0.0005, 0.03) * 3
    return boom + crack


def chime() -> np.ndarray:
    dur = 1.3
    t = _t(dur)
    partials = [(1318.5, 1.0, 0.45), (1760.0, 0.6, 0.35),
                (2637.0, 0.35, 0.22), (3520.0, 0.18, 0.15)]
    return sum(a * np.sin(2 * math.pi * f * t) * _env(len(t), 0.002, r)
               for f, a, r in partials)


def pop() -> np.ndarray:
    dur = 0.13
    t = _t(dur)
    return np.sin(_phase(260 + 900 * np.exp(-t * 40))) * _env(len(t), 0.001, 0.035)


def beep() -> np.ndarray:
    dur = 0.16
    t = _t(dur)
    env = np.clip(t / 0.005, 0, 1) * np.clip((dur - t) / 0.02, 0, 1)
    return np.sin(2 * math.pi * 880 * t) * env


def beep_long() -> np.ndarray:
    dur = 0.5
    t = _t(dur)
    env = np.clip(t / 0.005, 0, 1) * np.clip((dur - t) / 0.08, 0, 1)
    return np.sin(2 * math.pi * 1320 * t) * env


SOUNDS = {
    "tick": tick, "heartbeat": heartbeat, "riser": riser,
    "buzzer": buzzer, "record_scratch": record_scratch, "sad_horn": sad_horn,
    "whoosh": whoosh, "impact": impact, "chime": chime, "pop": pop,
    "beep": beep, "beep_long": beep_long,
}


def write(name: str, x: np.ndarray) -> Path:
    peak = float(np.max(np.abs(x))) or 1.0
    x = x / peak * (10 ** (PEAK_DBFS / 20))
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return path


def build(names=None) -> dict[str, Path]:
    return {n: write(n, SOUNDS[n]()) for n in (names or SOUNDS)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    if a.list:
        print("\n".join(SOUNDS))
        return 0
    for name, path in build().items():
        with wave.open(str(path)) as w:
            secs = w.getnframes() / w.getframerate()
        print(f"→ {path.relative_to(ROOT)}  {secs:.2f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
