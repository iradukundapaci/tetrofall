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

## Google Ads playables (5 concepts)

```
python3 build_ads.py
node tests/engine_test.js
```

A second, separate build for Google Ads / AdMob App campaigns. The HTML5
spec is a `.zip` per creative, ≤5 MB, ≤512 files, 320x480 or 480x320. Each
ad is a single responsive `index.html` declaring
`ad.orientation="portrait,landscape"`. It has Google's `exitapi.js` tag in
`<head>` and opens the store only through `ExitApi.exit()` on a tap.

| Slug | Hook | What the viewer plays |
|---|---|---|
| `deep_well` | SEE THAT GAP? | Rotate, drag and flick two I pieces into an 8-deep well, then 20s of free play |
| `chain_reaction` | CLEAR ONE ROW… AND THE STACK COMES DOWN | One I sets off a x3 ripple chain, then a x4 on a second board, then 20s of free play |
| `floor_rises` | THE FLOOR IS RISING | Survive 25s on a half-full board with a fast rise (idle viewers get crushed) |
| `where_does_it_go` | WHERE DOES THE I GO? 3-2-1 | Three countdown puzzles (I, T, S); idle viewers get steered into the decoy slot |
| `real_game` | NO FAKE ADS. | The unscripted engine at its 3-minute difficulty checkpoint, 45s |

The build writes to `dist/ads/`:
- `tetrofall_<slug>.zip`: upload these.
- `<slug>/index.html`
- `preview.html`: iframes every ad at both sizes. Serve `dist/ads/` with `python3 -m http.server` to use it.

`build_ads.py` fails if a zip breaks Google's upload rules:
- size or file count over the limit, or an unsupported file type;
- a missing orientation meta tag or exitapi tag;
- any external URL;
- storage, MRAID or iframe use.

Sources live in `src/ads/`:
- **`core/engine.js`:** a headless port of the real engine (SRS kicks, 7-bag, lock delay, ripple cascade, rise, scoring), with a node-tested `DemoBot` port for autopilot.
- **`core/input.js`:** a port of `gesture_handler.dart`: tap rotates, drag moves, a slow drag down soft drops, and a flick hard drops.
- **`core/render.js`, `core/director.js`:** canvas and show logic shared by every ad.
- **`ads/<slug>.js`:** the rig and script for each concept.

The board is 18 columns like the game, but only 20 rows tall so it fits the ad frame.

The captions are set in Baloo 2 ExtraBold, subset to `assets/display.woff2` by `python3 tools/prepare_assets.py display_font`.

Before submitting, run each zip through Google's HTML5 validator
(h5validator.appspot.com/adwords/asset) or the Google Ads asset upload
preview.

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
