# Tetrofall Playable Ad — Production Plan

## Context

Tetrofall needs a "playable ad" — a small interactive HTML5 demo distributed through ad networks for user acquisition — so prospective players can try the game's core hook before installing. The shipped game is Flutter + Flame, native Android/iOS only, with no web target and no ad-network mediation beyond AdMob inside the app itself. None of that is directly reusable for a playable: Flutter web's runtime is too heavy for ad-network sandboxes, and the real game's assets (fonts ~5.3MB, textures ~2MB) individually exceed a typical playable's entire size budget.

Decisions made with the user before planning:
- **Target networks (v1)**: Meta (Audience Network / Ads Manager) and Google Ads (Google Ad Manager / App Campaigns) only.
- **Tech approach**: hand-rolled vanilla JS + Canvas, single self-contained file — not Flutter Web, not a no-code playable builder. A fresh, separate mini-implementation that ports tuned *values* (board size, scoring, difficulty numbers, palette) from the Dart source rather than sharing code.
- **This session's deliverable**: a written production plan only. No starter code/scaffold is created now.

Numeric/palette values below were cross-checked directly against `lib/game/engine/scoring.dart`, `lib/game/config/difficulty.dart`, and `lib/ui/theme/tokens.dart` and are accurate as of this writing.

## Grounding facts to port (not re-derive)

- **Board**: 18 cols × 32 rows (`BoardConfig`), plus 2 hidden spawn rows.
- **Scoring** (`lib/game/engine/scoring.dart`): base clear values `1→100, 2→300, 3→500, 4→800` (5+ lines: `800 + (n-4)*300`); chain multiplier `1.0 + 0.5 * min(chainIndex, 8)` (an 8-link chain caps at 5.0x); slow level multiplier `1.0 + (elapsedSeconds/60)*0.1`.
- **Difficulty curve** (`lib/game/config/difficulty.dart`): 6 checkpoints, `t=0` → `t=12min`, linearly interpolated between them. At `t=0`: drop interval 1000ms, rise interval 22s/row, fill ratio 0.35, plus a 12s rise grace period before the floor starts climbing at all.
- **Rise mechanic** (`RiseController`): a new "wood" row generates below with `gapCount = cols*(1-fillRatio)` gaps; game over when row 0 has any block.
- **Brand palette** (`lib/ui/theme/tokens.dart`): wood dark `#4A2F1C`, wood mid `#7A5230`, wood light `#C89B6A`, background `#2B1C12`, gold `#F2B632`, red `#D9432E`, blue `#3AA0D9`, purple `#9B5CD6`, green `#4CAF6B`, text `#F5EAD9`. Display font "Baloo 2" (~672KB variable), body "Nunito" (~272KB variable) — both far too heavy to ship in a playable.
- **Existing scripted-demo precedent**: `TutorialController` (`_rigCascade`, `_rigClearRow`, `_rigRiseDemo`, `engine.queuePieces([...])`) already rigs the grid and a piece queue to guarantee a specific clear/cascade on cue, holding each result on screen 700–1600ms before advancing so the player reads the consequence. This is the exact authoring pattern the playable's script should reuse.
- **Attract-mode precedent**: `DemoBot` (`lib/game/ai/demo_bot.dart`) is a heuristic best-placement bot already used for the menu's idle attract loop and store-screenshot capture — a good structural model for an idle-timeout auto-play safety net during the playable's free-play beat.
- **Marketing copy already in circulation**: tagline "A falling-block puzzle with a floor that rises from below. Clear rows to buy back space and survive as long as you can. Plays offline." Studio: NoSleep Studios. Pillars: "Easy to Learn. Hard to Master. Relaxing to Play. Satisfying to Watch. One More Run."
- **Brand art available as color/shape reference only** (too large to import directly): `branding/store/feature_graphic.png`, `branding/store/shots/` (4 screenshots), `branding/icon_master.png`.

## 1. Creative concept & core loop

The thing that differentiates Tetrofall from every other block-stacker in an ad rotation is **ripple gravity**: cleared rows shatter individually and gravity ripples upward, so one piece can trigger a multi-row chain with a compounding multiplier (up to 5.0x at 8 links). That chain moment — caused by the player's own finger — is the entire sale. Everything else (rising floor, endless survival) is texture.

**Input scheme (deliberate departure from the shipped game)**: replace swipe/flick/drag with four discrete tap zones — tap left third / right third to move, a dedicated rotate button, a dedicated hard-drop button. Ad-network webviews handle gesture deltas and multi-touch inconsistently; discrete tap hit-testing is far more reliable across Meta's and Google's sandboxed hosts. This is a named tradeoff (see Risks), not an oversight — the real app's own tutorial already teaches swipe/flick/drag on first launch, so the gap is covered.

**Canvas safe zone (Meta 9:16 placements)**: when a Tetrofall playable runs inside Instagram Stories/Reels or Facebook Feed, Meta overlays native UI on top of the webview — roughly the top ~14% (account handle, story progress bar, exit button) and bottom ~20–35% (native CTA bar, swipe-up indicator, social buttons) are not reliably tappable, since Meta's own chrome can capture the touch instead of the canvas. All interactive tap zones (move/rotate/drop) and any persistent score/multiplier readout must stay within the middle ~60% of the vertical frame. Beat G's end-card CTA button should also sit inside that safe band, not flush to the bottom edge, even though the end-card is otherwise full-bleed.

**Rigged, not random**: do not use true RNG piece sequencing or floor generation. Pre-author grid state + a fixed piece queue (mirroring `TutorialController._rigClearRow`/`_rigCascade`) so the guided beats are unambiguous and the payoff chain is deterministic. If the player idles, a `DemoBot`-style auto-play finishes the placement so the demo can never stall before the CTA. During guided beats C and D specifically, the script must also tolerate a wrong tap: either ignore input outside the one valid action (only the correct column/button responds) or silently correct the board back onto the scripted path without a visible failure state, so a stray tap can never break the rig and orphan the planned Beat F payoff.

## 2. Ad structure & beats (~22–28s total)

| Beat | Time | Input | Content |
|---|---|---|---|
| A. Cold open | 0–3s | none | Non-interactive pre-baked ripple/chain animation with escalating multiplier callout — payoff before any ask |
| B. Title card | 3–5s | tap/auto | Logo + one-line promise, fades into gameplay frame |
| C. Guided beat 1 | 5–10s | tap drop | Rigged single-gap row; hint arrow; drop clears it; "Row cleared! +300" |
| D. Guided beat 2 | 10–16s | tap move + drop | Rigged lateral move then drop triggers a 2–3 row cascade; "Chain x2!" → "Chain x3!" with escalating juice |
| E. Free-play window | 16–22s | full tap zones | Curated piece queue, floor biased so any reasonable play clears something; idle-timeout auto-play safety net |
| F. Engineered big chain | 22–26s | one final guided/auto drop | Biggest chain of the demo (4+ links), attributed to the player |
| G. End-card / CTA | 26s+ | persistent | Icon, tagline from existing brand copy, store badge, large Install button, Replay, full end-card tappable as click-through |

A persistent skip/CTA affordance should be available a few seconds in — never force the full runtime before allowing an exit to store. The loop must be replayable in place from the end-card without a reload.

**Beat A autoplay-suspend edge case**: some ad-network webviews pause all `requestAnimationFrame`/canvas activity until the first user gesture, which would otherwise leave the non-interactive cold open hung on frame 0 with nothing on screen to tap. Any tap anywhere during beats A or B must both (a) act as the gesture that unsuspends rendering/audio and (b) instantly skip straight into guided beat C, rather than waiting for A/B's own timers — a player who taps early should never be stuck watching a frozen frame.

## 3. Technical architecture

- **Single self-contained `index.html`**: inlined CSS/JS, zero external requests (no CDN fonts, no fetches, no analytics beacons) — required for Meta's sandbox, strongly recommended for Google Ad Manager reliability.
- **Art**: procedurally drawn on canvas (flat-shaded rects/gradients from the `Tokens` palette) rather than imported bitmaps. This is the single highest-leverage size decision — the real app's textures alone would blow the entire Meta budget.
- **Fonts**: system font stack by default; if the display face is wanted for a couple of headline words, a hand-subsetted WOFF2 of only those glyphs, inlined, budgeted at a few KB — never the full 5.3MB Baloo2+Nunito family.
- **Game loop**: `requestAnimationFrame` with a fixed-timestep accumulator. Port only what the script exercises — piece shapes actually used, row-completion detection, the ripple/cascade visual (deserves the most polish, it's the whole sell), and a score/chain accumulator using the Section "Grounding facts" constants. Do **not** port the full 6-checkpoint difficulty curve, 7-bag randomizer, or SRS wall-kick tables — none of it is visible in a 25s scripted demo and each is extra bytes/risk.
- **Script data**: an inline JS array of rig steps (grid snapshot + queued piece + target placement + expected outcome), directly analogous to `TutorialController`'s rig methods.
- **Input**: `pointerdown` hit-testing on generous tap zones, `touch-action: none` + `-webkit-user-select: none` on the canvas element (and viewport meta) to block scroll/zoom/bounce/text-selection/double-tap-zoom during fast free-play tapping, debounce rapid double-taps.
- **Google mandatory `<head>` meta tags**: Google App Campaigns validate HTML5 creatives with an automated tool (`h5validator`) before any human/algorithmic review; a ZIP missing either of these two tags is rejected outright, regardless of how the game itself behaves:
  ```html
  <meta name="ad.size" content="width=320,height=480">
  <meta name="ad.orientation" content="portrait"> <!-- or "both" -->
  ```
- **Per-network exit handling — one shared core, two thin shims**: internal `TF.exitToStore()` call, with a Meta shim (Meta's playable JS integration point / CTA hook, confirmed against Meta's current published spec at build time) and a Google Ad Manager shim that calls **`ExitApi.exit()` only**. Google App Campaigns do not support or inject MRAID — do not load `mraid.js` or call `mraid.open()` on this path; that combination causes broken or unpredictable CTA behavior rather than a clean fallback. (MRAID would only be relevant if a future, different Google buy type explicitly required it — treat that as a separate campaign-type decision, not the default.) Both shims no-op gracefully with no host SDK present, so local QA works without a fake harness. Output: two zips, `tetrofall_playable_meta.zip` and `tetrofall_playable_google.zip`, from one shared source.
- **No autoplay audio**: Google rejects playable creatives that produce sound without an explicit user gesture, and iOS WKWebView starts any `AudioContext` in a `suspended` state regardless of network policy. If sound effects are included at all (Section 4 already recommends omitting audio for v1), the `AudioContext` must be created suspended and only `resume()`d inside the handler for the first `pointerdown` — practically, the same first tap that unsuspends beat C's rendering (see Section 2's autoplay-suspend note). Beat A's cold open must stay silent by construction.
- **High-DPI canvas rendering**: hand-rolled canvas games render blurry on Retina/3x-DPR mobile screens if the canvas backing store matches CSS pixels 1:1. Set the canvas's internal `width`/`height` attributes to CSS size × `window.devicePixelRatio` (scaling the drawing context accordingly) while keeping CSS width/height at the intended display size — do this once at init and account for it in all hit-testing math.
- **Orientation**: portrait-primary, fixed-aspect canvas scaled to fit the host frame with letterboxing; no landscape redesign needed, just a non-crashing centered fallback if a host forces landscape.

## 4. Asset budget

| | Meta | Google Ad Manager |
|---|---|---|
| Soft target | ~1–1.5MB actual payload | ~2–3MB actual payload |
| Hard cap (confirm at submission — specs move) | ≤5MB | ~5MB |

- Code: low hundreds of KB before minification.
- Art: near-zero (canvas-drawn), versus the real app's `bg_wood.png` (1.7MB) / `tile_classic_wood.png` (320KB), which are individually disqualifying if reused.
- Logo/icon: one small re-exported or redrawn mark, budget <30–50KB, versus the source `icon_master.png` (~972KB).
- Font: $0–few KB, versus 5.3MB combined family.
- Audio: recommend omitting for v1 (many sandboxes autoplay-block/mute anyway); if included, one <1s chain-impact sound only.

## 5. Branding without importing heavy source files

Use `Tokens` hex values directly in the playable's code. Redraw tetromino cells as rounded-rect/beveled shapes with a two-stop gradient echoing the wood-plank read visible in `branding/store/shots/` — sample a couple of extra accent tones from those screenshots if needed, but never embed the bitmaps. Board background: a flat gradient matching `Tokens.bgWoodGradient` instead of the tiled texture. Reuse the shipped tagline/pillar copy verbatim in the end-card rather than inventing new positioning, so the promise stays consistent with the store listing the player lands on.

## 6. Per-network packaging checklists

**Meta**: entry filename per current spec (commonly `index.html`) at zip root · size at/under current cap · zero external network calls of any kind · Meta's playable readiness/CTA-exit JS hook implemented against their *current* published spec · tested in Meta's Playable Preview tool (mandatory gate) · full-bleed tappable end-card · no unprompted autoplay audio · canvas UI (tap zones, score/multiplier readout, CTA) respects the top ~14% / bottom ~20–35% native-overlay safe zones on 9:16 placements.

**Google Ad Manager**: `index.html` at zip root · size at/under current cap · `<meta name="ad.size" content="width=320,height=480">` and `<meta name="ad.orientation" content="portrait">` (or `"both"`) present in `<head>` — the automated `h5validator` rejects the ZIP on sight without both · exit mechanism hardcoded to `ExitApi.exit()` only, zero MRAID (`mraid.js`/`mraid.open()`) injected anywhere on this path · fully self-contained, no external calls · no audio playback without a prior user gesture (`AudioContext` created suspended, `resume()`d only on first `pointerdown`) · tested in Google Web Designer / Ad Manager preview (mandatory gate) · both end-card and in-unit click wired to the same exit call.

**Both**: high-DPI canvas scaling (`devicePixelRatio`) implemented so the build isn't blurry on Retina/3x devices · misplay safeguard active during guided beats C and D (invalid taps ignored or silently corrected, never a visible failure state) · a tap during beats A/B both unsuspends rendering/audio and skips straight to beat C, so a webview that pauses `rAf`/audio until first gesture can never show a hung frame.

**Treat Meta and Google as two export shims over one shared core, not "build once, zip twice."** Each has its own exit API, preview tool, and size cap that move independently — confirm current live specs at implementation time rather than trusting numbers frozen in this plan.

## 7. QA / testing plan

- Local: desktop browser device-emulation for fast iteration, then load the zip's `index.html` via `file://` at least once (closer to actual runtime conditions than a dev server) to catch accidental relative-path/fetch assumptions.
- **Airplane-mode test**: fully disconnect networking and confirm the unzipped build runs the entire loop end-to-end (through the end-card render) with zero network reachability — simulates the sandboxed review conditions.
- File-size verification against each network's cap as an explicit go/no-go gate on the actual zipped artifact.
- Mandatory gates: Meta Playable Preview tool; Google Web Designer / Ad Manager preview tool.
- Device coverage: a low/mid-tier Android device on stock system WebView (least forgiving for canvas perf + touch quirks) and iOS WKWebView (subtly different from desktop Safari), plus at least one older OS/device profile if available.
- Orientation: confirm no crash/blank render if a host frame forces landscape.
- **Autoplay-suspend test**: load the build in a webview configuration that pauses `rAf`/audio until first gesture and confirm beat A doesn't hang on frame 0, and that a tap during A/B both unsuspends playback and jumps to beat C.
- **Audio-unlock test** (if any audio is included): confirm on iOS WKWebView specifically that no sound plays before the first tap and that the chain-impact sound is audible immediately after `resume()` fires on that first `pointerdown`.
- **Misplay test**: deliberately tap the wrong zone/column during guided beats C and D and confirm the rig either ignores the input or silently self-corrects, never breaking or visibly glitching the board.
- **Visual sharpness check**: verify the build isn't blurry on a real Retina/3x-DPR device, confirming the canvas backing-store scaling matches `devicePixelRatio`.
- **Meta safe-zone check**: preview the Meta build inside an actual Stories/Reels-shaped 9:16 frame (not just a bare browser tab) and confirm no tap zone, score readout, or CTA sits under the native top/bottom overlay bands.
- **Google validator check**: run the packaged ZIP through Google's `h5validator` (or equivalent Ad Manager pre-check) before submission and confirm both `ad.size` and `ad.orientation` meta tags are detected, and that no MRAID reference exists anywhere in the bundle.
- **Analytics caveat**: no third-party analytics SDK belongs inside the playable (violates the zero-external-calls requirement and most networks' review policy) — there is no in-playable funnel data. Performance measurement comes from each network's own per-creative dashboard (CTR, install rate), not custom instrumentation. Flag this to stakeholders as a hard format constraint, not a gap to fix later.

## 8. Milestones

1. Concept sign-off & beat wireframe (lock Section 2's storyboard, rough timing/copy) before writing code.
2. Core loop prototype — board, tap-zone input, minimal ported logic, one scripted rig, running in a plain browser. Prove the input scheme and ripple visual read well.
3. Full scripted sequence & chain-moment tuning — author all rig steps, tune juice until beat F clearly outshines beat A's teaser. Give this the most iteration time; it's the make-or-break pass.
4. Branding & end-card pass.
5. Per-network packaging & shim integration, verify size budgets.
6. QA pass against Section 7's full checklist — a real gate, not a formality.
7. Submit to Meta and Google Ad Manager separately (independent review timelines); budget at least one revision cycle per network.

No calendar dates proposed — none were given, and milestone 3's iteration time matters more than a fixed schedule.

## 9. Open risks & tradeoffs to flag

- **Tap-zone input vs. shipped swipe controls**: deliberate reliability tradeoff, not an oversight — accepted because the real app's tutorial covers the real controls on first launch.
- **Scripted/rigged demo vs. true random play**: guarantees the ad always lands its best moment but isn't organic footage — a long-accepted norm in this genre's UA creative, worth naming so it's not mistaken for an oversight.
- **Second codebase, not shared code**: a from-scratch reimplementation. If `lib/game/config/difficulty.dart` or `lib/game/engine/scoring.dart` values change later, the playable silently drifts out of sync unless someone manually re-ports them. Recommend commenting the ported-constant provenance in the JS source (pointing back at the Dart file/value) and treating a future core-loop rebalance as a trigger to re-check the playable.
- **Network spec drift**: exact caps, filenames, exit-API symbols, and preview tools for both networks are maintained externally and revise over time — several checklist items intentionally say "confirm current spec at submission time."
- **No in-flight behavioral analytics**: only whole-creative CTR/install metrics from each network's dashboard; finer funnel visibility would require a network-specific first-party allowance, not something solvable in this build.
- **Two variants to maintain going forward**: any future creative change (copy, tuning, end-card) must be re-exported and re-verified against both networks' caps and preview tools, not shipped once — real ongoing production cost to plan capacity for.

## Reference files (read-only sources for the new build; not files the new build touches)

- `lib/ui/screens/tutorial/tutorial_controller.dart` — rig/scripting pattern to reuse
- `lib/game/engine/scoring.dart` — scoring/chain-multiplier constants to port
- `lib/game/config/difficulty.dart` — checkpoint values (only t=0 state is relevant to the demo)
- `lib/game/config/board_config.dart` — board dimensions
- `lib/ui/theme/tokens.dart` — palette to port
- `lib/game/ai/demo_bot.dart` — idle-timeout auto-play model
- `branding/store/` — color/shape reference only, not for direct import

## Verification

This is a planning/document deliverable — no code to run. Verification is: (1) walk through Section 2's beat table with the creative/marketing stakeholder to confirm it lands the intended hook, (2) confirm current Meta and Google Ad Manager playable specs against their live docs before implementation starts, since several numbers here (size caps, exit-API names) are called out as needing reconfirmation at build time.
