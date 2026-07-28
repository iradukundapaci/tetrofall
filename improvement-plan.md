# Tetrofall — Improvement Plan (post Phase 0–8)

Fixes for issues found after the Phase 0–8 build. Each item below was root-caused in the current code, not guessed. Work through the steps in order — I1 and D1 first, since they change files every other step touches.

Rule of precedence (unchanged from `game.md`): the rules engine stays pure Dart; every fix here lives in `input/`, `render/`, `ui/`, or asset files — except the two small engine safety guards in I1.

---

## I1 — Hard drop permanently speeds up all following pieces (BUG, highest priority)

**Symptom:** after the first hard drop, every subsequent piece falls ~20× too fast.

**Root cause:** a downward swipe crosses `softDropDistance` (24 px) *before* it crosses `hardDropDistance` (150 px). At 24 px `GestureHandler._handlePrimaryMove` enqueues `softDropStart` → `pieceController.softDropActive = true`. At 150 px it enqueues `hardDrop` and calls `_resetPrimary()`, which clears the handler's local `_softDropEngaged` flag **but never enqueues `softDropEnd`**. The engine's `softDropActive` stays `true` forever, so every later piece ticks at `dropInterval / softDropDivisor` (÷20).

**Fix (both layers — belt and suspenders):**

1. `gesture_handler.dart` — in `_handlePrimaryMove`, when the hard-drop threshold is reached and `_softDropEngaged` is true, enqueue `softDropEnd` *before* `hardDrop`.
2. `game_engine.dart` — defensive reset at the piece boundary: set `pieceController.softDropActive = false` (and `softDropRowsAccrued = 0`) in `_lockAndResolve()` (or in `PieceController.spawn()`). Soft drop is a per-piece input state; it must never survive a lock.

**Verify:** hard-drop 10 pieces in a row; each new piece must fall at the normal `dropInterval` for the current difficulty. Also cancel-test: swipe down 30 px, lift — next piece must be normal speed.

---

## I2 — General input reliability

Four concrete defects in the current input path:

1. **Long-press hijacks gameplay.** `app.dart` wraps `GameWidget` in `GestureDetector(onLongPress: → DebugScreen)`. Holding a finger ~500 ms (any DAS hold, any hesitation) navigates away from the game. Removed entirely by D1.
2. **Horizontal moves use per-event deltas.** `_handlePrimaryMove` compares a *single pointer event's* `dx` against `swipeColumnThreshold` (26 px). Pointer events arrive every few px, so slow/medium drags never cross 26 px in one event and the piece doesn't move — only fast flicks register. **Fix:** accumulate horizontal drag distance since the last emitted move (`_accumDx += dx`), emit one move per full `swipeColumnThreshold` consumed (`_accumDx -= threshold`), supporting multi-column drags. Reset the accumulator when direction reverses.
3. **Soft drop disables horizontal movement and engages too easily.** Once `_softDropEngaged`, the `!_softDropEngaged` guard blocks all horizontal moves for the rest of the gesture, and 24 px of downward drift (easy during a horizontal swipe) triggers it. **Fix:** engage soft drop only when the gesture is *predominantly vertical* (`totalDown > |totalDx|`), raise `softDropDistance` to ~40 px, and allow horizontal moves while soft-dropping (standard stacker behaviour).
4. **Hard drop is distance-only.** 150 px fixed means a slow deliberate drag hard-drops accidentally, while spec §1.12 says "swipe down (fast/long)". **Fix:** trigger hard drop on distance ≥ threshold **or** downward velocity ≥ ~1000 px/s over the last few events; keep a slow long drag as soft drop.

All thresholds stay in `InputTuning`, and per R3 they become cell-relative (e.g. `swipeColumnThreshold = cellSize * 0.6`) instead of fixed px, so input feels identical on phone and tablet.

**Verify:** the Phase 2 checklist again — quick swipes, slow drags (must now move), diagonal swipes (must not soft-drop), hold for DAS/ARR, tap rotate, two-finger rotate, deliberate fast flick down (hard drop) vs slow drag down (soft drop only).

---

## D1 — Remove all debug logic completely

Phase 12 scheduled this; doing it now per request. Delete, don't gate — `DebugFlags` goes too.

**Delete files:**

- `lib/debug/debug_screen.dart`
- `lib/debug/debug_overlay.dart`
- `lib/debug/debug_fixtures.dart`
- `lib/debug/debug_flags.dart` (remove the whole `lib/debug/` folder)

**Strip references:**

- `app.dart` — remove `DebugOverlay(game: _game)`, the `DebugScreen` import/route, and the `GestureDetector(onLongPress: …)` wrapper (fixes I2‑1). Remove the stamper branches (`debugStampType != null`) from all four pointer callbacks.
- `tetrofall_game.dart` — remove `debugStampType`, `debugStampAt()`, and the `HasTimeScale` mixin + `timeScale` usage in `update()` (debug-only per its own doc comment; pass raw `dt`).
- `game_engine.dart` — keep `resolver` swappable via constructor if desired, but remove any debug-screen setter path. `StickyGroup` stays in the engine (it's a legit alternate resolver), just no debug UI reaches it.
- Grep for `DebugFlags`, `debugStamp`, `DebugOverlay`, `DebugScreen`, `timeScale` — zero hits when done.

**Verify:** `flutter analyze` clean; long-press on the board does nothing; app builds with no `lib/debug/` directory.

---

## R1 — Board corners: perfect square, no rounding

**Root cause:** `board_frame.dart` builds `outerRRect` / `wellRRect` with `Radius.circular(Tokens.radiusLg)` (24) and the warning pulse reuses the rounded rect.

**Fix:** draw the frame, well fill, inner shadow, and warning pulse with plain `Rect`s (or `Radius.zero`). Also update `ClipComponent.rectangle` in `board_component.dart` if it inherited any rounding (it's already rectangular — confirm). Keep `Tokens.radiusLg` for UI panels; only the board geometry changes. Blocks keep their own small rounding — this item is board boundary only.

**Verify:** screenshot the empty board; all four corners are sharp 90°; warning pulse hugs the square frame.

---

## R2 — White glow/border around blocks

**Root cause (measured, not cosmetic guesswork):** `assets/images/blocks/tile_classic_wood.png` has an **opaque white background with a ~30 px white margin on every side** (at 1024×1024) — it violates the P.3 spec ("no background outside the tile"). `BlockComponent` draws the *full* source rect into the cell, so that 3% white border renders inside the clip around every plain wood block — which is nearly every block on the board. The special-block tiles are edge-to-edge (margin 0) and unaffected. The near-white ghost outline (`theme.text` at 50%) can amplify the impression but is by design.

**Fix (asset first, code as backstop):**

1. Reprocess `tile_classic_wood.png`: crop the white margin so the wood reaches edge-to-edge, and convert remaining white corner pixels to transparent. One-off script (PIL/ImageMagick), commit the fixed PNG.
2. Backstop in `block_component.dart`: draw from an inset source rect (`Rect.fromLTWH(m, m, w-2m, h-2m)` with `m ≈ 3%` of the image) so any future tile with baked margins can't leak. Cheap, permanent.
3. Re-run the P-phase check: tile it 10×20 over the dark board background and inspect at arm's length — no light halo anywhere.

**Verify:** full board of wood blocks against `boardBg`; zero white fringing between blocks, including at cell corners.

---

## R3 — Score (HUD) missing from the gameplay screen

**Root cause:** the engine tracks `scoring.score` etc., but the only surface that displayed it was the debug overlay — now deleted. `lib/ui/screens/` is empty; the Phase 10 `gameplay_screen.dart` port hasn't happened.

**Fix (minimal HUD now, full Phase 10 port unchanged later):** add a top bar overlay in `app.dart`'s `Stack`, laid out per `gameplay.html`: coin counter left, **score + best** centre, pause slot right. Values read from `engine.scoring` (score, coins) refreshed via a lightweight ticker or by making `Scoring` a `ChangeNotifier`-style listenable — do *not* poll with `Timer.periodic` + `setState` at 5 Hz like the old debug overlay. All colors/type from `tokens.dart` (Baloo 2 for the score, per the mockups). Best score is in-memory until Phase 11's `StorageService`.

**Verify:** score visibly increments on soft drop (1/row), hard drop (2/row), and line clears (100/300/500/800 × multipliers); coin counter moves on Diamond/Treasure clears; nothing overlaps the combo banner space or the board.

---

## R4 — Everything scales with screen size and available space

**Root cause:** layout is a patchwork of magic numbers. `BoardComponent._layout` carves the board from `gameSize.x * 0.9` / `gameSize.y * 0.78` with no knowledge of what actually surrounds it; the ghost toggle sits at `top: 40, right: 12`; `BoosterHud` and the new HUD are positioned independently. On tall/short/wide screens these fight — the board can collide with HUD elements or waste space.

**Fix — one layout budget, everything derived from it:**

1. Define the vertical budget explicitly in one place (screen-space, inside `SafeArea`):
   `topBar (HUD) → comboBanner strip → board → pendingRow reveal margin → boosterPanel`.
   Compute the board's available rect as *screen minus the measured HUD/booster/banner heights*, not as fixed fractions.
2. Keep the §1.1 rule as the only cell-size source: `cell = min(availW / COLS, availH / ROWS)`; board centred in the leftover space. Frame thickness already scales with `cellSize` — good; audit every other render component for stray fixed px (`comboBanner` font size, ghost stroke width `2`, grid line width, HUD paddings) and re-express them as `cellSize`- or token-relative.
3. HUD and booster panel size from `MediaQuery` + tokens (min 44 px tap targets), not absolute `Positioned` offsets.
4. Input thresholds become cell-relative (see I2) so gesture feel scales with the board.

**Verify:** run at phone (375×812), small phone (320×568), tablet (768×1024), and a resized desktop window: board always fully visible, square cells, no overlap between HUD / banner / board / boosters, no dead zones; frame thickness visibly proportional.

---

## Suggested order & scope

| Step | Item | Files touched | Size |
|---|---|---|---|
| 1 | I1 hard-drop/soft-drop bug | `gesture_handler.dart`, `game_engine.dart` | XS |
| 2 | D1 debug removal | `lib/debug/*` (delete), `app.dart`, `tetrofall_game.dart` | S |
| 3 | R1 square corners | `board_frame.dart` | XS |
| 4 | R2 white glow | asset reprocess, `block_component.dart` | S |
| 5 | I2 input reliability | `gesture_handler.dart`, `input_tuning.dart` | M |
| 6 | R3 score HUD | `app.dart` (+ small HUD widget) | M |
| 7 | R4 responsive layout | `board_component.dart`, `app.dart`, render components | M |

Final check after step 7: replay the Phase 2, 4, and 6 "What you check" lists from `game.md` end-to-end on two screen sizes — they cover input feel, rise smoothness, and scoring, which are exactly the systems these fixes touch.
