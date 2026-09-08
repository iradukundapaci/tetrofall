# Tetrofall playable ad

Implements `playable_ad_plan.md` (repo root): a hand-rolled vanilla JS/Canvas
playable ad for Meta and Google Ad Manager. Not Flutter, not related to the
`lib/` app — a separate, self-contained build.

## Build

```
python3 build.py
```

Writes to `dist/` (gitignored, regenerate anytime):

- `dist/local/index.html` — no network shim, `TF.exitToStore()` just
  console.logs. Use this for everyday local testing.
- `dist/meta/index.html` + `dist/tetrofall_playable_meta.zip`
- `dist/google/index.html` + `dist/tetrofall_playable_google.zip`
  (includes the mandatory `ad.size`/`ad.orientation` meta tags)

Each zip has `index.html` at its root, per both networks' packaging specs.
`build.py` itself has zero extra dependencies (standard library only) — it
just base64-inlines the small files already checked into `assets/`. Current
sizes: ~70KB per `index.html`, ~35KB zipped — still far under Meta's ~2MB
soft target and Google's ~5MB cap.

## Regenerating assets (occasional — not part of every build)

`assets/` (block/board textures, sfx, subsetted wordmark font) is derived
from the real game's source assets by `tools/prepare_assets.py`, and is
git-tracked since it's tiny and build.py needs it. Re-run it only if the
source game art changes:

```
pip3 install fonttools brotli   # one-time, for font subsetting to WOFF2
python3 tools/prepare_assets.py
```

Needs `ffmpeg` (image/audio processing) and `fontTools` (font subsetting)
on PATH/importable. See the script for exactly what it crops/re-encodes and
why (corner-radius/watermark avoidance on the block texture, bitrate/mono
choices on the audio, the exact glyph subset for the wordmark font).

## Local testing

Open `dist/local/index.html` directly in a browser, or serve the folder
(`python3 -m http.server` from inside `dist/`) — the plan's QA section
(playable_ad_plan.md Section 7) asks for both `file://` and served testing.
Tap anywhere to skip the cold open; the whole beat sequence (A→G) also
auto-plays itself via the idle-timeout safety net if you never touch it, so
you can just watch it once to see the full loop.

## What's implemented vs. what still needs verification

Implemented per the plan: the full beat sequence (cold open → guided ×2 →
free-play → payoff → end-card), ripple/chain clearing with the ported
scoring formula, Meta safe-zone layout, tap-zone input with a misplay
snap-safeguard on guided beats, high-DPI canvas scaling, no external
requests, Google's mandatory meta tags, and the `ExitApi`-only Google shim.

Visual/audio fidelity pass (see `playable_ad_plan.md`'s "visual/audio
fidelity upgrade" section): blocks and the board background use the real
game's own wood-grain photos (`assets/images/blocks/tile_classic_wood.png`,
`assets/images/textures/bg_wood.png`), cropped/recompressed to a few KB
each and tinted at runtime with the same colors the real `TileCache`/
`BoardFrame` use; the logo mark and "TETROFALL" wordmark are redrawn
pixel-for-pixel from `lib/ui/widgets/logo_mark.dart` /
`logo_wordmark.dart`'s own gradient/shadow values (no raster asset — the
real game doesn't have one either); the wordmark/score digits use a
subsetted copy of the real Baloo 2 ExtraBold; piece-lock and row-clear
sounds are the real game's own `block_settle.wav`/`wood_crush.wav`,
re-encoded small. Blocks are no longer color-coded per tetromino type —
the real game renders the falling piece with the exact same tinted tile as
locked blocks (`block_component.dart`), so this ad now matches that; the
falling piece gets a light gold outline instead, so it's still easy to
tell apart from what's already locked.

Still needs real verification before submission (the plan flags these
explicitly — they're not oversights, they're things only a live spec check
or a real network preview tool can confirm):

- **Meta's exact CTA symbol** (`src/shims/meta.js` uses
  `window.FbPlayableAd.onCTAClick()` as a best-effort placeholder) —
  confirm against Meta's current published Playable Ads spec.
- **Google's `ad.size` dimensions** (`src/template.html` via `build.py`,
  currently `360x640`) — confirm against whatever size the actual campaign
  expects.
- Run both zips through Meta's Playable Preview tool and Google Web
  Designer / Ad Manager's preview tool (mandatory gates per the plan).
- Real device pass (low/mid Android WebView, iOS WKWebView) — only tested
  in desktop Chrome so far. The block/board tint relies on the canvas
  `'color'` composite operation (broadly supported in evergreen mobile
  browsers, but worth confirming on the actual low-end device lab pass).
- No background music (none exists in the real game either — see
  `assets/audio/music/README.md` in the main repo).

## Files

```
src/
  template.html      HTML shell with {{NETWORK_META}}/{{FONT_FACE}}/{{ASSETS_JS}}/{{GAME_JS}}/{{SHIM_JS}} placeholders
  game.js             shared core: grid, pieces, scripted beats, rendering, audio, input
  shims/meta.js        Meta exit shim
  shims/google.js       Google Ad Manager exit shim (ExitApi.exit())
build.py              assembles + zips the three variants, base64-inlines assets/
tools/prepare_assets.py  one-time asset derivation from the real game's source assets
assets/               small derived textures/sfx/font (git-tracked, see above)
```
