# Tetrofall — Boosters Spec

Companion to `game.md` (the rules) and `screens.md` (the UI). This document defines **boosters**: how a run's four boosters are chosen, how each one is used, what it does to the grid, how it animates, and how its icon looks inside the active theme.

Rule of precedence: **`game.md` §1 still wins.** Boosters are an *addition* layered on top of the core rules. Where a booster deliberately breaks one of those rules (Earthquake and Tilt ignore the "gravity only above the cleared line" rule), this document says so explicitly. Anything not called out here follows `game.md`.

Verification is manual, as in `game.md` §5. Each build phase in §12 ends with a **What you check** list. No automated test files are part of this spec.

---

## 0. Summary

```text
  MAIN MENU / GAME OVER
          │  Play
          ▼
  ┌──────────────────┐   4 wooden reels spin, stop one by one
  │  LOADOUT ROLL    │   1 free re-spin (single slot)
  │  (pre-run)       │   then: rewarded ad per extra re-spin
  │                  │   "Same boosters" on replay
  └────────┬─────────┘
           │  Start
           ▼
  ┌──────────────────┐   booster bar under the board (no banner)
  │  RUN             │   tap slot → aim (if needed) → fire
  │                  │   1 charge per booster per run
  │                  │   spent slot greys out → rewarded ad brings it back
  └────────┬─────────┘
           │  booster fired
           ▼
  ┌──────────────────┐   edit grid → gravity → clears → chains
  │  BOOSTER RESOLVE │   uses the normal RESOLVING machinery
  └──────────────────┘
```

Design pillars applied:

- **Board-only.** Every booster changes blocks. No booster touches score multipliers, the rise timer, or the piece queue.
- **Everything goes through the cascade.** A booster edits the grid, then the standard ripple / clear / chain loop takes over. One shared pipeline, twelve small effect functions.
- **No teleporting.** Logic commits instantly; the render layer animates toward it (`game.md` §2 golden rule). Boosters add one new kind of motion — sideways travel — for Slide and Tilt.
- **Theme-owned color.** Booster icons and effects read colors from `ThemeDefinition` only (§9). No hue may contradict the active theme.

---

## 1. Board size note

`game.md` §1.1 still says 10 × 20. The shipped board is **`BoardConfig.cols = 18`, `BoardConfig.rows = 32`**. Every booster rule below is written against `BoardConfig`, never a literal. Area sizes and caps (Bomb radius, Lightning bolts, Wildfire cap) live in `BoosterTuning` (§11) so they can be retuned if the board size changes again.

Coordinates follow `game.md`: `(row, col)`, row `0` is the top, `BoardConfig.rows - 1` is the floor. "Lower" means a **larger** row index.

---

## 2. The roster (test set — 12 boosters)

Four slots, three boosters each. Slots are grouped by **how much of the board a booster touches**. Classes describe **what it does to blocks**.

**Class never reaches the UI.** It shapes the pools, the effect language and the tuning conversation; the player only ever sees the icon and the name. An earlier draft engraved a class mark in the corner of every slot — it was noise on a 50 px button and taught nobody anything, so it is gone. `BoosterClass` stays in the model.

| Slot | Booster | Class | Input | One-line effect |
|---|---|---|---|---|
| **Small** | Hammer | Breaker | Aim cell | Smash one block |
| | Bomb | Breaker | Aim cell | Blast a 3 × 3 area |
| | Patch | Builder | Aim cell | Plug one gap |
| **Line** | Drill | Breaker | Aim row | Bore out a whole row |
| | Slide | Mover | Aim row + swipe | Shift a row one column, wrapping at the edge |
| | Pillar | Builder | Aim column | Fill every hole in a column |
| **Area** | Sweep | Breaker | Instant | Clear the top 2 rows of the stack |
| | Lightning | Builder | Instant | 4 bolts fill the gaps of the most-complete rows |
| | Mortar | Builder | Instant | Fill every single-cell hole under an overhang |
| **Board** | Earthquake | Mover | Instant | Every block falls straight down until supported |
| | Tilt | Mover | Swipe direction | Board tilts; blocks slide sideways and drop through holes |
| | Wildfire | Breaker | Aim cell | Fire spreads through connected blocks, up first, then burns out |

Class totals: **5 Breakers** (Hammer, Bomb, Drill, Sweep, Wildfire), **3 Movers** (Slide, Earthquake, Tilt), **4 Builders** (Patch, Pillar, Lightning, Mortar).

```dart
enum BoosterSlot { small, line, area, board }
enum BoosterClass { breaker, mover, builder }
enum BoosterInput { aimCell, aimRow, aimColumn, aimRowSwipe, swipeDirection, instant }

enum BoosterType {
  hammer(BoosterSlot.small, BoosterClass.breaker, BoosterInput.aimCell),
  bomb(BoosterSlot.small, BoosterClass.breaker, BoosterInput.aimCell),
  patch(BoosterSlot.small, BoosterClass.builder, BoosterInput.aimCell),
  drill(BoosterSlot.line, BoosterClass.breaker, BoosterInput.aimRow),
  slide(BoosterSlot.line, BoosterClass.mover, BoosterInput.aimRowSwipe),
  pillar(BoosterSlot.line, BoosterClass.builder, BoosterInput.aimColumn),
  sweep(BoosterSlot.area, BoosterClass.breaker, BoosterInput.instant),
  lightning(BoosterSlot.area, BoosterClass.builder, BoosterInput.instant),
  mortar(BoosterSlot.area, BoosterClass.builder, BoosterInput.instant),
  earthquake(BoosterSlot.board, BoosterClass.mover, BoosterInput.instant),
  tilt(BoosterSlot.board, BoosterClass.mover, BoosterInput.swipeDirection),
  wildfire(BoosterSlot.board, BoosterClass.breaker, BoosterInput.aimCell);

  const BoosterType(this.slot, this.boosterClass, this.input);
  final BoosterSlot slot;
  final BoosterClass boosterClass;
  final BoosterInput input;
}
```

---

## 3. Loadout roll — before the run

### 3.1 Where it lives

The roll is an overlay on `GameplayScreen`, shown while the engine sits in `GamePhase.ready` — the board is already laid out behind it (dimmed, like the pause treatment), so the player sees the arena they're about to play in. `engine.start()` is called only when the overlay closes.

```text
MainMenu ──Play──▶ GameplayScreen
                     ├─ tutorial not seen? → tutorial run (NO boosters, NO roll)
                     └─ otherwise          → LoadoutOverlay → engine.start()

GameOverOverlay ──Play again──▶ LoadoutOverlay (with "Same boosters" option)
```

The main-menu attract-mode demo (`DemoBot`) and the store-capture reels never show the roll and never use boosters.

### 3.2 Layout

```text
┌──────────────────────────────┐
│        YOUR BOOSTERS         │
│                              │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐ │   four reel windows, equal width
│  │ ▲  │ │ ▲  │ │ ▲  │ │ ▲  │ │   (previous icon, blurred)
│  │[ic]│ │[ic]│ │[ic]│ │[ic]│ │   ← landed icon
│  │ ▼  │ │ ▼  │ │ ▼  │ │ ▼  │ │   (next icon, blurred)
│  └────┘ └────┘ └────┘ └────┘ │
│  Hammer  Drill  Mortar Tilt  │   booster names — nothing else
│                              │
│   ↻ Tap a booster to re-spin │   (1 left)
│                              │
│   [   START   ]              │   primary button
│   [ Same boosters ]          │   only on replay
└──────────────────────────────┘
```

Uses the shared `ModalOverlay` / `Panel` widgets and `Tokens.panelWidth`. Reel windows are drawn as recessed wood (see §9.4). **One line under each drum: the booster's name.** The slot it came from is clear from the order, left to right, and the labels only competed with the names for the same 60 px of width.

### 3.3 Roll rules

```text
1. Each slot rolls independently from its own pool of 3.
2. Weights: EQUAL for the test build (every booster needs data).
   Rarity tiers are applied after the test — see §13.
3. A re-spin never lands on the booster the slot already shows.
4. A slot can hold only its own slot's boosters.
```

**Randomness is isolated.** The roll uses its own `Random` instance (`LoadoutRoller._random`), never the engine's. The engine's seeded source deals pieces and pending rows; if the roll drew from it, a re-spin would shift every piece that follows, and a seed would stop reproducing a run. This is also the prerequisite for a fair Daily Challenge later (§10.3).

### 3.4 Spin animation

```text
t = 0 ms       all four reels start scrolling (icons stream downward)
t = 500 ms     reel 1 decelerates and stops
t = 750 ms     reel 2 stops
t = 1000 ms    reel 3 stops
t = 1250 ms    reel 4 stops
t ≈ 1500 ms    START becomes active
```

- Scroll speed starts at ~14 icons/s and eases out (`Curves.easeOutCubic`) over the last 300 ms of each reel, overshooting by 6 % and settling back (`Curves.easeOutBack` feel) — a physical wooden-drum stop.
- Each stop: a short gold rim flash (§9.3 `accent`, 180 ms), `Sfx.reelStop`, `haptics.selection()`.
- While scrolling: `Sfx.reelTick` once per icon passing the window, volume-capped so it reads as a ratchet, not noise.
- **Tap anywhere during the spin → all reels stop immediately** on their already-decided results. The result is chosen before the animation starts; the animation only reveals it.
- Total spin ≤ 1.5 s. The roll must never feel like a gate in front of "one more run".

### 3.5 Re-spins

| Source | Amount | Test build |
|---|---|---|
| Free | 1 per run | **On** |
| Coins | `EconomyTuning.respinPrice` (30) each, max `adRespinsPerRun` (3), once the free one is gone | **On** (`BoosterTuning.tokenRespinEnabled`) |
| ~~Rewarded ad~~ | — | **Removed.** Rewarded video is only ever the Coin faucet (`phase11_monetization_plan.md` §0), never the price of anything. |

Flow:

```text
Tap a landed reel ─▶ free re-spin left?
                       │
                       yes ─▶ that reel alone spins (500 ms) ─▶ new booster
                       │        line: "↻ Tap a booster to re-spin (1 left)"
                       │
                       no  ─▶ coin sheet: "Re-spin the <slot> slot?"
                                │  Spend 30   ─▶ reel spins
                                │  Earn Coins ─▶ Coin Vault (only when short), then back
                                └─ Not now    ─▶ nothing spent, nothing changes
```

- Re-spins are **per slot**, never all four.
- Unused re-spins do not carry over.
- **The line under the reels is the whole state machine**, and it only ever shows one offer: `↻ Tap a booster to re-spin (n left)` while the free re-spin is unspent, then `30 to re-spin (n left)` with the coin glyph in `accent`, then `No re-spins left` at 45 % once `adRespinsPerRun` is used up. Tapping the line itself opens the same sheet and then hands the player back to the reels to pick a slot.
- **The sheet always names what the Coins buy** before anything is spent, and declining costs nothing. This is the same contract the in-run refill uses (§4.9), so the two never feel like different deals.
- An empty wallet is not a dead end: the sheet's primary becomes **Earn Coins**, which opens the Coin Vault over the roll and comes back to it.

### 3.6 Starter kit (first runs)

The first **3 runs after the tutorial** use a fixed loadout, one per slot:

```text
Small: Hammer   Line: Drill   Area: Lightning   Board: Earthquake
```

The reels still spin and land on these, labelled **"Starter kit"**; re-spin is disabled. From run 4 on, rolls are random. These four are the simplest to understand and three of them already have mockup art.

### 3.7 Replay

On **Play again** from the game-over overlay, the roll screen opens with the previous loadout already in the reels (no spin) and two buttons:

- **Same boosters** (default focus) → start immediately.
- **Spin** → normal roll with a fresh free re-spin.

### 3.8 Persistence

New `StorageService` keys, following the existing naming style:

```text
booster_last_loadout        "hammer,drill,lightning,earthquake"
booster_runs_completed      int — drives the starter kit
booster_tip_seen_<id>       bool per booster — first-use tip (§4.8)
booster_respin_tokens       int, 0–3 (deferred, key reserved)
booster_ab_group            "boosters" | "control" (§10.2)
```

A corrupted or unknown id in `booster_last_loadout` (e.g. a booster removed after the test) falls back to a fresh roll.

---

## 4. The booster bar — during the run

### 4.1 Placement

The bar is the **bottom row of the screen, directly under the board**. The banner ad slot is **removed**:

```text
Column(
  ScoreHud,                        // Tokens.hudHeight
  Expanded(board),                 // + the 50 px the banner used to take
  BoosterBar,                      // Tokens.boosterBarHeight  (new, 58)
)
```

**Why the banner goes.** It cost 50 px of play area on every phone, on every run, for the lowest-value ad unit in the build. The boosters replace that income with rewarded video the player opts into and is paid for — a re-spin (§3.5) or a booster brought back mid-run (§4.9) — and the interstitial between runs is untouched. `phase11_monetization_plan.md` needs a matching edit: `BannerAdSlot` is no longer part of the gameplay layout, so its pre-load, its refresh timer and its height reservation all come out, and the rewarded unit takes its place in the revenue model.

`BoosterBar` has a **fixed height token**, for the same reason `ScoreHud` does: `_GameplayBody` computes the board's vertical budget before layout. Swap `bannerHeight` for `boosterBarHeight` in that budget — the board gets the difference. In the immersive layout the bar floats over the bottom of the board, mirroring how the HUD floats over the top.

Four **round** buttons, 50 px across, spaced evenly along the bar rather than stretched to quarter-width tiles. Round and small is deliberate: a disc reads as a control rather than as a second frame under the board, the row fits in a 58 px strip instead of 64, and on a tablet the buttons stay 50 px instead of growing into four slabs. 50 px still clears `Tokens.tapTarget` (48).

The bar is hidden entirely in the tutorial run and in the control group (§10.2).

### 4.2 Slot states

| State | When | Look (§9.3) |
|---|---|---|
| **Ready** | charge left, phase is `playing`, booster has a valid target | glyph `boosterGlyph`, rim `boosterRim`, charge badge |
| **No target** | instant booster that would do nothing right now (e.g. Mortar with no holes) | glyph at 40 %, rim at 30 % — **charge badge stays bright**, because the charge is still there |
| **Armed** | player tapped it and is aiming | glyph `text`, rim pulses `accent` at 2 Hz, countdown ring |
| **Busy** | a resolve (booster or normal clear) is running | 60 % opacity, not tappable |
| **Spent** | charge used, a refill is still available | **greyed out**: face darkens, rim drops to 8 % white, glyph desaturated at 45 %; the charge badge is replaced by the `▶` ad badge. Still tappable — the tap is the offer (§4.9) |
| **Exhausted** | charge used and no refill left this run | the spent look with no ad badge, not tappable |

The old engraved treatment is gone. Engraving read as decoration; the difference that matters mid-run is *dead vs. alive*, and grey says that at a glance. The badge corner then carries the follow-up: a number means the booster is loaded, a `▶` means a video brings it back, nothing means it is done for the run.

"No target" is computed each frame for instant boosters only. The scans are a few hundred cell reads on an 18 × 32 grid — cheap.

### 4.3 Using a booster

```text
READY ──tap──▶ instant?  ──yes──▶ FIRE
                  │
                  no
                  ▼
               ARMED (aim window 4 s)
                  │   press on board  → preview follows finger
                  │   release on board, valid target → FIRE
                  │   release on board, invalid     → shake preview, stay ARMED
                  │   tap same slot / Android back  → CANCEL (charge kept)
                  │   aim window expires            → CANCEL (charge kept)
                  │   pause opened                  → CANCEL (charge kept)
                  ▼
                FIRE ──▶ BUSY ──resolve done──▶ SPENT
```

- Only one booster can be armed or firing at a time. Tapping another slot while armed switches the armed booster.
- Taps on the slot bar are debounced (150 ms) so a double tap can't fire twice.
- A booster can only be armed or fired in `GamePhase.playing`. It is not tappable in `spawning`, `resolving`, `continuing` or `gameOver`.

### 4.4 Aiming mode

While a booster is armed:

- **Rise progress and piece gravity freeze** (`freezeRise`, `freezeGravity`), but **the difficulty clock keeps running** — `riseController.tickElapsedOnly(dt)`. This differs from the tutorial hold, which stops the clock. Without it, aiming would be a free way to slow the difficulty curve.
- The 4 s aim window caps how long the board can stand still. It shows as a ring draining around the armed slot.
- `GestureHandler` routes pointer events to a new `BoosterAimHandler` instead of move/rotate intents. Swipes and taps do **not** move or rotate the piece while armed.
- The ghost piece is hidden; the board dims to 70 % except the preview cells.
- The preview highlights exactly the cells the booster would affect (§5, each booster's **Preview** line), drawn as a 2 px `accent` outline with a 20 % `accent` fill.

### 4.5 The active piece

The falling piece is not part of the grid, so every booster must treat it explicitly:

1. **Its cells count as solid obstacles** for every booster that moves or adds blocks. Blocks can't be slid, dropped or filled into them.
2. **Aimed boosters can't target its cells.**
3. It stays exactly where it is during the resolve — the phase is `resolving`, so `pieceController` doesn't tick.
4. After the resolve, if any grid block now overlaps it (which rule 1 should prevent), apply the rise-overlap rule from `game.md` §1.4: push it up one row, and force-lock if it can't move.

### 4.6 Resolve pipeline (shared by all boosters)

```dart
bool useBooster(BoosterType type, BoosterTarget target) {
  if (phase != GamePhase.playing) return false;
  final effect = BoosterEffects.of(type);
  if (!effect.isValid(grid, target, activePieceCells)) return false;

  final result = effect.apply(grid, target, activePieceCells);
  // result.removed, result.added, result.moved (with paths),
  // result.lowestChangedRow, result.fullBoardSettle

  _emit(BoosterFiredEvent(type, target, result));
  _beginBoosterResolve(result);
  return true;
}
```

`_beginBoosterResolve` enters the existing `resolving` phase with three differences:

1. **Gravity floor.** For Breakers and Slide, `_gravityFloor` starts at `result.lowestChangedRow`, so the ripple releases only the rows above what the booster touched, the same rule as a line clear. Builders don't set a floor (nothing needs to fall unless a row clears). Earthquake and Tilt settle the whole board themselves (`result.fullBoardSettle`) and emit their own fall/slide events. This is their deliberate exception to `game.md` §1.6.
2. **The first clear is forced.** Any row completed **directly** by the booster's edit, or by the gravity it releases before the first clear, is emitted as `RowsClearedEvent(forced: true)`. `Scoring` already declines to score forced clears, and `RunTracker` / analytics already skip them. Any further clears in the chain after that are scored normally, with `chainIndex` advancing as usual.
3. **Timing.** The booster's own animation length (§6) is added as a lead-in before the first ripple step, so blocks don't start falling until the hammer has landed or the fire has burned out.

Everything else — rescans after each release, chain loop, `Motion.rippleBudget`, `Motion.resolveHardCap` flush, input buffering — is inherited unchanged. A booster resolve can never stall the game for the same reason a normal one can't.

**The rise stays frozen for the whole resolve** (existing `game.md` rule). So a booster can never cause a top-out, and game over can't happen during one.

### 4.7 Continue, pause, restart

- **Pause** cancels aiming and keeps the charge. A resolve that has already started keeps running when the pause overlay closes. It doesn't restart.
- **Rewarded continue** keeps the loadout and any unused charges. It does **not** refill spent ones by itself — a spent booster comes back only through its own ad offer (§4.9), and a continue does not reset that offer's per-run counter either. Boosters are unavailable during the `continuing` sweep.
- **Restart / quit** discards the loadout's charges *and* the refill counter. The loadout itself is remembered for "Same boosters".

### 4.8 First-use tip

The first time a player **arms** each booster, a one-line tip appears above the bar for 2.5 s (aim window paused while it shows), then `booster_tip_seen_<id>` is set:

| Booster | Tip |
|---|---|
| Hammer | Tap a block to smash it |
| Bomb | Tap to blast everything around that spot |
| Patch | Tap an empty gap to plug it |
| Drill | Tap a row to bore it out |
| Slide | Hold a row, swipe to shift it |
| Pillar | Tap a column to fill its holes |
| Tilt | Swipe left or right to tilt the board |
| Wildfire | Start the fire in a big pile |

Instant boosters show their tip on first **fire**, as a caption during the effect: Sweep "Clears the top of your stack", Lightning "Fills the rows closest to done", Mortar "Seals holes under overhangs", Earthquake "Everything falls into place".

### 4.9 Bringing a booster back — held charge or Coins

A spent booster is not gone for the run. The greyed slot keeps its badge, and tapping it brings the charge back — from the player's **held charges** first (bought in the shop, or from the login calendar or a chest), and otherwise for Coins at the slot's price (`EconomyTuning.chargePrice`: Small 80, Line 100, Area 150, Board 220).

```text
SPENT ──tap──▶ holds a charge of this booster?
                  │
                  yes ─▶ spent from the inventory, no sheet ─▶ charge = 1, slot READY
                  │
                  no  ─▶ COIN SHEET  "Recharge Hammer?"
                           │  "This booster comes back for the rest of the run.
                           │   2 left this run."
                           ├─ Not now    ─▶ back to the board, nothing spent
                           ├─ Spend 80   ─▶ charge = 1, slot READY
                           └─ Earn Coins ─▶ Coin Vault (run stays held), then back
```

**Rules**

1. **Only in `GamePhase.playing`.** The badge is not tappable while a resolve runs, while another booster is armed, during the `continuing` sweep or after game over — the continue offer owns that moment, and two ad offers must never compete.
2. **The run freezes like a pause.** Opening the sheet stops the rise, the piece and the **difficulty clock** — this is the pause treatment, not the aim hold (§4.4), because the app is about to lose focus to the video. Closing it resumes through the same path the pause overlay uses.
3. **Caps.** `adRefillsPerRun` (2) across the whole bar, and `adRefillsPerBooster` (1) for any single slot, so no one loops one booster all run. When a slot has no offer left it drops the badge and stops being tappable — the **exhausted** look in §4.2.
4. **Never a dead end.** The purchase no longer depends on an ad being loaded, so the badge shows whenever a refill is left under the caps. A player who is short is sent to earn and brought back; the only screen that must hide a button when no ad is loaded is the Coin Vault itself.
5. **A refilled charge is an ordinary charge.** It arms, fires and resolves exactly like the first one, and it counts as a normal use in analytics and in the "unused charges" tally at the end of the run.
6. **The continue does not refill anything** (§4.7). The two purchases stay separate so the player always knows what their Coins buy.

**Copy.** The sheet names the booster and says what it gets back, in that order, and the decline is always one plain word — `Not now`. No countdown, no pre-selected "Watch" focus, no second prompt if they decline.

---

## 5. Booster logic

Each entry lists: **Valid when**, **Preview**, **Apply**, **Gravity**, **Edge cases**. All sizes come from `BoosterTuning` (§11).

### 5.1 Hammer — Breaker, aim cell

- **Valid when:** the target cell holds a block.
- **Preview:** the single cell.
- **Apply:** `grid.set(r, c, null)`.
- **Gravity:** floor = `r`. Everything above it in the column comes down one step as the ripple releases.
- **Edge cases:** tapping an empty cell or a piece cell → invalid (preview shakes).

### 5.2 Bomb — Breaker, aim cell

- **Valid when:** the (2·`bombRadius`+1)² square centred on the target, clipped to the board, contains at least one block. The centre itself may be empty.
- **Preview:** the whole square, clipped.
- **Apply:** clear every block in the square. Active-piece cells inside the square are left alone (they aren't grid cells).
- **Gravity:** floor = the lowest row of the square that lost a block.
- **Edge cases:** targeting an edge or corner clips the blast; nothing wraps.

### 5.3 Patch — Builder, aim cell

- **Valid when:** the target cell is empty, isn't an active-piece cell, and has at least one occupied orthogonal neighbour or sits on the floor. This stops players placing blocks in open air.
- **Preview:** the single cell.
- **Apply:** `grid.set(r, c, Cell(BlockType.wood))`.
- **Gravity:** none. The patch stays where it's placed, even if the cell below is empty. That's allowed, the same way an overhang is.
- **Then:** rescan. If row `r` is now full, it clears (forced) and the chain continues from there.

### 5.4 Drill — Breaker, aim row

- **Valid when:** the target row contains at least one block.
- **Preview:** the whole row.
- **Apply:** `grid.fillRow(r)`, then clear row `r` (forced). The grid ends up the same as removing the row's blocks. Filling first lets it go through the existing clear path and shatter effect, the same technique the continue sweep uses. The fill is never drawn (§6.4).
- **Gravity:** floor = `r`, like any single-row clear.

### 5.5 Slide — Mover, aim row + swipe

- **Input:** press on a row → the row highlights → drag horizontally ≥ ½ cell → the direction arrow locks → release fires. Releasing without enough drag keeps it armed.
- **Valid when:** the row has at least one block and at least one gap.
- **Preview:** the row, with a ghost of where each block ends up.
- **Apply:** shift the row one column in the swipe direction, **wrapping** (conveyor): the block pushed off one edge comes back on the other. It always has a legal result.

```dart
final row = List.of(grid.rowCells(r));
final shifted = dir == left
    ? [...row.sublist(1), row.first]
    : [row.last, ...row.sublist(0, row.length - 1)];
```

- **Active piece:** if any shifted block would land in a piece cell, the move is invalid (preview shows red-free "blocked" shake; see §9.3 — no red).
- **Gravity:** floor = `r + 1`. The ripple releases **row `r` itself** and everything above it, so a slid block that is now over a hole drops into it. That's how Slide completes lower rows.

### 5.6 Pillar — Builder, aim column

- **Valid when:** the column has at least one **hole**: an empty cell with a block somewhere above it in the same column.
- **Preview:** every hole in the column.
- **Apply:** fill every empty cell from the column's top block down to the floor, skipping active-piece cells.
- **Gravity:** none.
- **Then:** rescan. Every row that's now full clears together (forced).

### 5.7 Sweep — Breaker, instant

- **Valid when:** the board has any block.
- **Targets:** the top `sweepRows` (2) rows that contain any block. These are the smallest row indices with a block. They don't have to be next to each other.
- **Apply:** clear every block in those rows.
- **Gravity:** floor = the lower of the two rows. Blocks between the two swept rows (if they're apart) are released. Nothing sits above the top one.
- **No target:** empty board.

### 5.8 Lightning — Builder, instant

- **Valid when:** at least one non-empty row has a gap that isn't an active-piece cell.
- **Targeting:** fixed at the moment of firing, so the order is always the same:

```dart
final candidates = [
  for (var r = 0; r < rows; r++)
    if (grid.rowHasAnyBlock(r)) (row: r, gaps: gapCells(r, excluding: pieceCells))
]..removeWhere((c) => c.gaps.isEmpty)
 ..sort((a, b) => a.gaps.length != b.gaps.length
       ? a.gaps.length.compareTo(b.gaps.length)   // most complete first
       : b.row.compareTo(a.row));                   // tie → lower row first

final strikes = <(int, int)>[];
for (final c in candidates) {
  for (final col in centreOut(c.gaps)) {            // gaps ordered centre-out
    if (strikes.length == lightningBolts) break;
    strikes.add((c.row, col));
  }
}
```

- **Apply:** fill every struck cell.
- **Gravity:** none.
- **Then:** rescan. Completed rows clear together (forced). A row that only got part of the bolts it needed stays partly filled, and that's intentional.

### 5.9 Mortar — Builder, instant

- **Hole definition:** an empty cell whose **upper** neighbour is a block and whose **lower** neighbour is a block or the floor. Side neighbours don't matter.
- **Valid when:** at least one such cell exists (excluding active-piece cells).
- **Apply:** fill all of them in one pass. Cells filled in this pass don't create new qualifying holes. The scan runs once, before filling.
- **Gravity:** none.
- **Then:** rescan and clear full rows (forced).

### 5.10 Earthquake — Mover, instant

- **Valid when:** at least one block has an empty cell directly below it.
- **Apply:** run `ColumnCascade` over the whole board. It's already in the codebase as the reference resolver: each column's blocks compact down to the floor. Active-piece cells are treated as solid for this pass. A block above the piece in the same column stops on top of it.
- **Gravity:** `fullBoardSettle`. The whole board settles at once, ignoring the "only above the cleared line" rule. **This is the booster's whole purpose, and is the one intended exception.**
- **Then:** rescan and clear (forced). The chains that follow use the normal ripple with its normal floor rules.

### 5.11 Tilt — Mover, swipe direction

- **Input:** tap the slot → it arms, showing ← → arrows over the board → swipe left or right anywhere on the board (or on the slot itself) → fire.
- **Valid when:** at least one block can move (down or toward the tilt side).
- **Preview:** a faint arrow overlay. No per-cell preview, since the result depends on the whole settle.
- **Apply — `TiltCascade`:**

```dart
/// dir = -1 for left, +1 for right.
/// Rows are processed bottom-up; within a row, cells nearest the tilt side
/// go first, so they get out of the way of the cells behind them.
/// Down always beats sideways: a block passing over a hole drops into it.
List<BlockPath> tilt(Grid grid, int dir, Set<(int, int)> solid) {
  final paths = <BlockPath>[];
  var moved = true;
  while (moved) {
    moved = false;
    for (var r = grid.maxRow; r >= 0; r--) {
      for (final c in orderTowards(dir, grid.cols)) {
        if (grid.at(r, c) == null) continue;
        final path = [(r, c)];
        var (cr, cc) = (r, c);
        while (true) {
          if (isFree(grid, solid, cr + 1, cc)) { cr++; }
          else if (isFree(grid, solid, cr, cc + dir)) { cc += dir; }
          else break;
          path.add((cr, cc));
        }
        if (path.length > 1) {
          grid.move((r, c), (cr, cc));
          paths.add(BlockPath(path, grid.at(cr, cc)!.type));
          moved = true;
        }
      }
    }
  }
  return paths;
}
```

`isFree` is false outside the board, on any grid block and on any active-piece cell. Each pass moves at least one block to a strictly lower or more-sideways position, so the loop always ends. In practice it takes 1–3 passes.

- **Gravity:** `fullBoardSettle`, the same exception as Earthquake.
- **Then:** rescan and clear (forced). Chains continue normally.
- **Result:** every row ends up packed toward the tilt side, leaving an open well on the opposite side.

### 5.12 Wildfire — Breaker, aim cell

- **Valid when:** the target cell holds a block.
- **Preview:** the full burn set, computed on press so the player sees exactly what will go.
- **Apply:** breadth-first spread through orthogonally connected blocks, neighbour order **up, left, right, down** (fire climbs), capped at `wildfireCap` blocks:

```dart
final burned = <(int, int)>[];
final layers = <List<(int, int)>>[];
var frontier = [start];
final seen = {start};
while (frontier.isNotEmpty && burned.length < wildfireCap) {
  final layer = <(int, int)>[];
  final next = <(int, int)>[];
  for (final cell in frontier) {
    if (burned.length == wildfireCap) break;
    burned.add(cell);
    layer.add(cell);
    for (final n in [up(cell), left(cell), right(cell), down(cell)]) {
      if (grid.isOccupied(n) && seen.add(n)) next.add(n);
    }
  }
  layers.add(layer);
  frontier = next;
}
```

`layers` drives the animation (§6.12). Remove every burned block.

- **Gravity:** floor = the lowest burned row.
- **Edge cases:** a lone block burns only itself. The first-use tip covers that.

---

## 6. Animations

All durations go in `Motion` (the existing single tuning file), under a `// Boosters` block. Effects are drawn on the existing layers. Shards use the pooled `ShatterLayer`, and dust uses `effects/dust_puff.dart`. **No new per-frame allocation.** A Bomb plus a chain clear must still fit in `Motion.particlePoolSize` (1600). Tilt and Slide need one new render feature, listed first. How each effect is actually built (procedural, sprite sheet or shader), the shared primitives, and the performance budget are in §6.14–§6.18.

### 6.0 New: sideways travel

`BlockFallEvent` only carries `col`, `fromRow` and `toRow`, so it can only describe a vertical fall. Add:

```dart
class BlockPathEvent {
  const BlockPathEvent({required this.cells, required this.type, required this.durationSeconds});
  final List<(int row, int col)> cells;   // every cell visited, in order
  final BlockType type;
  final double durationSeconds;
}
class BlocksMovedEvent extends GameEvent {
  const BlocksMovedEvent(this.paths);
  final List<BlockPathEvent> paths;
}
```

`FallAnimator` gets a path mode:

- **Sideways steps:** `Motion.boosterSlideStep` (45 ms per cell), `Curves.linear`, so a slide reads as smooth travel.
- **Downward steps:** the existing gravity curve (`easeInQuad`), with the squash-and-stretch and dust puff on the final landing only.
- Consecutive steps in the same direction merge into one segment, so a 5-cell slide is one motion, not five.

### 6.1 Shared beats

```text
Arm        slot rim pulse starts; board dims 70 % (120 ms fade)
Fire       slot glyph pops ×1.15 → ×1.0 (140 ms, easeOutBack); haptics.medium()
Effect     booster-specific, below
Handoff    standard ripple / shatter / chain from game.md §2
Spent      slot glyph cross-fades to the engraved look (200 ms)
```

Booster clears use the **standard shatter** (center-out, wood shards, `Sfx.woodCrush`) unless the entry below says otherwise. Since `forced: true`, no combo text appears for that clear.

### 6.2 Hammer

1. A hammer glyph (the icon, scaled to 1.6 cells, `boosterGlyph` color) drops in from 2 cells above the target, rotating −30° → 0° (`Motion.boosterHammerSwing` 140 ms, `easeInCubic`).
2. On impact: the target cell shatters (standard shards, 1.5× the usual count), board shake 2 px / 100 ms, `Sfx.hammerHit`.
3. The hammer lifts and fades (120 ms). The ripple begins.

### 6.3 Bomb

1. The bomb glyph drops onto the centre cell and bounces once (180 ms).
2. The fuse sparks: a small `accent`-colored spark flickers along the fuse (`Motion.boosterBombFuse` 300 ms), with `Sfx.bombFuse`.
3. Flash: a white-cream (`text`) disc expands to the blast square in 80 ms and fades out.
4. Cells shatter **ring by ring from the centre outward**, 40 ms per ring. Shard velocity is biased away from the centre rather than upward.
5. Board shake 4 px / 180 ms, then `Sfx.blast` and `haptics.medium()`.

### 6.4 Drill

1. A drill bit (the icon, 1 cell tall) enters from whichever board edge is closer to the tap point.
2. It crosses the row at `Motion.boosterDrillCellStep` (30 ms per cell). Each cell it passes **cracks and shatters immediately**, in sweep order instead of centre-out, with shards thrown back against the direction of travel.
3. `Sfx.drill` loops while it moves. The bit exits the far edge, and the ripple begins.

The engine fills the row for correctness, but the render layer never draws those filled cells. The `BoosterFiredEvent` carries the drilled row, and `BoardBlocksComponent` skips drawing it until the shatter finishes.

### 6.5 Patch

1. A wooden plug grows in the target cell: scale 0 → 1.08 → 1.0 (`Motion.boosterGrow` 180 ms, `easeOutBack`), in the normal block tile.
2. A dust puff plays at its base, with `Sfx.blockSettle`.
3. If the row is now full, the standard shatter follows after a 120 ms beat. The beat lets the player see that the plug is what completed the row.

### 6.6 Slide

1. The row lifts 2 px and gets a soft shadow (80 ms), so it reads as picked up.
2. It moves one cell sideways (`Motion.boosterSlideRow` 160 ms, `easeOutCubic`). The wrapped block slides out of one edge and in the other; it's drawn twice, clipped to the board rect.
3. The row sets down (80 ms), with `Sfx.woodSlide`.
4. Blocks now over a hole fall using the normal fall animation, and the ripple continues.

### 6.7 Pillar

1. Starting at the lowest hole and working upward, each hole grows in a plug (the same grow as Patch, but 90 ms), staggered `Motion.boosterStackStep` (50 ms).
2. Each plug plays a soft `Sfx.blockSettle` with rising pitch (+1 semitone per plug, capped at +6), so the column "builds up" audibly.
3. Full rows then shatter together.

### 6.8 Sweep

1. A gust band (a translucent `text`-colored streak, 2 rows tall) crosses the swept rows left to right in `Motion.boosterSweep` (260 ms), with `Sfx.whoosh`.
2. Cells shatter in the order the gust reaches them. Shards get a strong rightward velocity (+6 cells/s) and little upward lift, so they look blown away.

### 6.9 Lightning

For each bolt, `Motion.boosterBoltStep` (90 ms) apart:

1. A jagged bolt (3-segment polyline, re-randomized each frame for 60 ms, using a **render-only** random source) draws from the board's top edge to the target cell. It's drawn in `effectHot` with a wider, 30 % `accent` glow stroke under it.
2. `Sfx.bolt` plays.
3. The cell fills with a block tinted `accent`, which cools to the normal tile tint over 300 ms (a tint lerp).
4. A small spark burst (6 shards in `accent`, short lifetime) plays.

After the last bolt, a 120 ms beat, then full rows shatter together.

### 6.10 Mortar

1. All target holes fill at once, but visibly: each cell starts as a flattened plug (scale Y 0.2) and rises to full height in 220 ms (`easeOutCubic`). The start is staggered bottom-up by 15 ms per row.
2. The mortar tint begins at `frameLight` and blends to the normal tile over 300 ms.
3. `Sfx.mortar` plays once, with a quiet `blockSettle` per row.
4. Full rows then shatter.

### 6.11 Earthquake

1. The board shakes, decaying from 6 px (`Motion.boosterQuakeShake` 420 ms, damped sine at 14 Hz), with `Sfx.rumble` and `haptics.medium()` at the start.
2. At 180 ms into the shake, every block falls using the standard fall animation. Blocks in different columns land at different times, as in `game.md` §2.2.
3. A dust band runs along the floor on landing.
4. Full rows shatter, then chains follow.

### 6.12 Tilt

1. The board (frame and contents) rotates 4° toward the tilt side (`Motion.boosterTiltLean` 150 ms, `easeOutCubic`).
2. While it's leaning, every block follows its `BlockPath` (§6.0). All blocks start together, so travel distances naturally stagger their arrival.
3. `Sfx.woodSlide` plays long, with volume following how many blocks are moving.
4. When the last block lands, the board rotates back to 0° (150 ms, `easeOutBack`) with a single `Sfx.blockSettle` thud.
5. Full rows shatter, then chains follow.

**Hit testing:** the rotation is visual only. Input is disabled while the board is tilted (the phase is `resolving` anyway), so the rotated frame never needs hit-testing.

### 6.13 Wildfire

For each BFS layer (`Motion.boosterFireLayer` 70 ms apart):

1. **Ignite:** the cell's tint lerps `blockTint` → `effectHot` → `effectEmber` over 160 ms, with a flicker (±10 % brightness at 12 Hz).
2. **Flame:** 3–4 small flame shards rise from the cell (upward velocity, short 400 ms lifetime, colors `effectHot` → `effectEmber`, fading).
3. **Char:** the tint darkens to `frameDark`, then the cell crumbles into shards colored `frameDark`, lighter and drifting up at first like ash, then falling.

`Sfx.fireCrackle` loops for the whole burn and fades out on the last layer. `haptics.light()` fires on each layer, at most 5 times. The ripple starts after the last cell has crumbled.

### 6.14 How each effect is built

The animation beats above say **what** the player sees. This section says **how each piece is made**, so art, code and performance are settled before anyone opens a drawing tool.

Four methods, from cheapest to richest:

| Code | Method | What it is | Theme-safe because |
|---|---|---|---|
| **P** | Procedural | Shapes, strokes, tint lerps and pooled shards drawn by code every frame | Every color is read from `ThemeDefinition` at draw time |
| **W** | Widget animation | Flutter `AnimationController`s on the bar and roll screen | Same: colors come from the theme |
| **S** | Tinted sprite sheet | Frame-by-frame art drawn **white/grayscale on transparent**, tinted at draw time | Multiplying pure white by a theme color gives exactly that color |
| **H** | Shader | A `.frag` fragment program for glow, noise and dissolve | Colors arrive as uniforms from the theme, never hard-coded |

**Rule: ship v1 fully procedural.** Every booster below has a complete **P** version, and that's what the test build uses. **S** and **H** are **v2 upgrades**, added only to the effects that fail the look check in Phase B10. Each v2 effect keeps its **P** version as a fallback (§6.17).

No baked color is allowed in any method: no colored sprite frames, and no color constants inside a shader.

### 6.15 Effect sheet per booster

Each row is one visible part of the effect. **Shards** is the worst-case number of pooled particles that booster asks for (§6.17).

**Hammer** — Shards ≤ 40

| Part | v1 | v2 upgrade | Notes |
|---|---|---|---|
| Hammer prop dropping and swinging | P — the Lucide glyph rasterized once to a cached image (`PropDrop`) | — | Tinted `boosterGlyph` |
| Impact shatter | P — wood shards ×1.5 (`ShardBurst`) | — | Standard shard style |
| Board shake 2 px | P (`ScreenShake`) | — | |

**Bomb** — Shards ≤ 180 at radius 1 (the request scales with `bombRadius` and is clamped)

| Part | v1 | v2 upgrade | Notes |
|---|---|---|---|
| Bomb prop drop and bounce | P (`PropDrop`) | — | |
| Fuse sparks | P — spark shards, additive blend | — | `accent` |
| Flash | P — radial-gradient disc (`FlashDisc`) | **S** `fx_blast` 8 frames, 128 px | Tint `effectHot` → `text` |
| Ring-by-ring shatter | P — wood shards, outward bias | — | |
| Smoke after the blast | none in v1 | **S** `fx_smoke` 8 frames, 96 px | Tint `frameDark` at 60 % |
| Board shake 4 px | P | — | |

**Drill** — Shards ≤ 18 cells × 10 + sawdust 30

| Part | v1 | v2 upgrade | Notes |
|---|---|---|---|
| Drill-bit prop crossing the row | P — glyph image, 1 cell tall, spinning ±8° | — | |
| Crack as the bit passes | P — reuse the existing crack stage (`Motion.crackHold`), shortened | — | |
| Shatter in sweep order | P — wood shards thrown backward | — | |
| Sawdust trail | P — dust shards behind the bit | — | `frameLight` |

**Patch** — Shards ≤ 8

| Part | v1 | v2 upgrade | Notes |
|---|---|---|---|
| Plug grows in | P (`CellGrow`) | — | Normal tile |
| Dust at its base | P — existing `dust_puff` | — | |

**Slide** — Shards ≤ 12

| Part | v1 | v2 upgrade | Notes |
|---|---|---|---|
| Row lifts, with a shadow | P — offset plus a soft shadow rect under the row | — | Shadow is `boardBg` at 40 % |
| Row moves and wraps at the edge | P — path mode (§6.0), drawn twice and clipped | — | |
| Dust at both ends | P — dust shards | — | |

**Pillar** — Shards ≤ 6 per plug

| Part | v1 | v2 upgrade | Notes |
|---|---|---|---|
| Plugs grow in one after another | P (`CellGrow`, staggered) | — | |
| Small dust per plug | P | — | |

**Sweep** — Shards ≤ 36 cells × 10

| Part | v1 | v2 upgrade | Notes |
|---|---|---|---|
| Gust band | P — gradient quad with 5 scrolling streak lines (`Band`) | **H** `gust.frag` — noise streaks | `text` at 25 % |
| Blown-away shatter | P — wood shards, strong sideways velocity | — | |

**Lightning** — Shards ≤ 4 bolts × 6 sparks + cleared rows

| Part | v1 | v2 upgrade | Notes |
|---|---|---|---|
| Bolt | P — jagged polyline, core stroke plus two wider low-alpha strokes for glow (`BoltStroke`) | **H** `glow.frag` — soft bloom | `effectHot` core, `accent` glow |
| Screen flicker | P — full-board `text` overlay at 8 % for 40 ms | — | Turned off in reduced effects |
| Cell heats, then cools | P (`CellTint` `accent` → tile) | — | |
| Spark burst | P — spark shards, additive blend | — | |

**Mortar** — Shards ≤ 2 per filled cell

| Part | v1 | v2 upgrade | Notes |
|---|---|---|---|
| Fill rises into each hole | P (`CellGrow`, Y-axis only) | — | |
| Mortar tint fading to the tile | P (`CellTint` `frameLight` → tile) | — | |
| Dust | P | — | |

**Earthquake** — Shards ≤ 18 columns × 3 dust

| Part | v1 | v2 upgrade | Notes |
|---|---|---|---|
| Damped shake 6 px | P (`ScreenShake`) | — | |
| Blocks falling | P — existing fall animator | — | |
| Dust band along the floor | P — dust shards at the floor | **S** `fx_dust_wave` 8 frames, 128 × 48 | Tint `frameLight` |

**Tilt** — Shards ≤ 1 dust per 3 cells travelled, capped at 60

| Part | v1 | v2 upgrade | Notes |
|---|---|---|---|
| Board lean ±4° | P (`BoardLean` on the `BoardFrame` transform) | — | Everything inside tilts together |
| Blocks sliding and dropping | P — path mode (§6.0) | — | |
| Dust trails at the leading edge | P — dust shards | — | |

**Wildfire** — Shards ≤ 24 cells × (4 flame + 6 ash)

| Part | v1 | v2 upgrade | Notes |
|---|---|---|---|
| Cell ignites and flickers | P (`CellTint` with flicker) | — | `blockTint` → `effectHot` → `effectEmber` |
| Flames | P — teardrop flame shards stretched along velocity, additive blend | **S** `fx_flame_loop` 12 frames, 64 × 96, looping, at most `maxFlameSprites` at once | Tint grades `effectHot` (core) → `effectEmber` (tips) using two sheets: core and edge |
| Char and crumble | P — tint to `frameDark`, then ash shards | **H** `burn_dissolve.frag` — noise-edged dissolve with a glowing rim | Rim color `effectEmber`, uniform |
| Rising embers | P — spark shards, slow and long-lived | — | `effectEmber` |

**Wildfire is the effect most likely to need v2.** Procedural flames read as sparks at small sizes, and fire is exactly what sprite art is good at.

**The UI side of all 12** (bar, slot states, reel spin, ad badge pulse) is **W**, using plain Flutter animations. There's no Rive or Lottie dependency. If a designer joins later, the roll screen is the first candidate to move to Rive, because its states (spinning → landing → re-spin) map directly onto a Rive state machine.

### 6.16 Shared effect primitives

Twelve boosters are built from **ten reusable pieces**. Each booster's effect is a short **script**: a list of timed steps built from its `BoosterFiredEvent` and scaled by `resolveTimeScale`.

```dart
/// lib/game/render/fx/booster_fx_script.dart
class FxStep {
  const FxStep(this.at, this.run);
  final Duration at;                 // offset from the fire moment
  final void Function(FxContext) run;
}

final hammerScript = (BoosterFiredEvent e) => [
  FxStep(Duration.zero, (fx) => fx.propDrop(AppIcons.hammer, e.cell, swing: -30)),
  FxStep(Motion.boosterHammerSwing, (fx) {
    fx.shardBurst(e.cell, ShardKind.wood, countScale: 1.5);
    fx.shake(amplitude: 2, duration: const Duration(milliseconds: 100));
    fx.sfx(Sfx.hammerHit);
  }),
];
```

| Primitive | Does | Used by |
|---|---|---|
| `ScreenShake` | decaying sine offset on the `BoardFrame` transform | Hammer, Bomb, Earthquake |
| `BoardLean` | rotation on the `BoardFrame` transform | Tilt |
| `CellTint` | lerps one cell's tint, with optional flicker | Lightning, Mortar, Wildfire |
| `CellGrow` | scales one cell (both axes or Y only) | Patch, Pillar, Mortar, Lightning |
| `ShardBurst` | spawns pooled shards of a `ShardKind` with a velocity bias | all 12 |
| `PropDrop` | draws a booster glyph as a moving prop | Hammer, Bomb, Drill |
| `BoltStroke` | jagged polyline with a glow stroke | Lightning |
| `Band` | a moving gradient strip | Sweep |
| `FlashDisc` | an expanding, fading radial gradient | Bomb |
| `FxSprite` / `ShaderQuad` | v2: tinted sheet / fragment program | Bomb, Earthquake, Sweep, Lightning, Wildfire |

**Shard kinds.** `ShatterLayer`'s pool gets a `ShardKind` field instead of a second pool. Each kind is one row in a style table, so tuning a kind never touches the burst code:

| Kind | Shape | Color (theme field) | Gravity | Lifetime | Blend |
|---|---|---|---|---|---|
| `wood` | rounded rect (existing) | `blockTint` | existing | existing | normal |
| `spark` | 2 px dot, stretched along velocity | `accent` | 0.3× | 250–450 ms | plus (additive) |
| `flame` | teardrop, stretched | `effectHot` → `effectEmber` over life | −0.4× (rises) | 300–500 ms | plus |
| `ash` | small flake | `frameDark` | 0.5×, drifts up first | 700–1100 ms | normal |
| `dust` | soft circle | `frameLight` at 50 % | 0.1× | 400–700 ms | normal |

### 6.17 Layers, budgets, fallbacks

**Draw order** (bottom to top), all inside the `BoardFrame` transform so shake and lean move everything together:

```text
BoardFrame                       shake / lean transform
 ├─ BoardBlocksComponent         tints, grow, hidden drilled row
 ├─ FallAnimator                 falls and paths
 ├─ BoosterPreviewLayer          aim outlines (§4.4)
 ├─ BoosterPropLayer             hammer, bomb, drill bit
 ├─ ShatterLayer                 all shard kinds, one pool
 └─ BoosterFxLayer               bolts, gust, flash, v2 sprites and shaders
BoosterBar                       Flutter widgets, outside the board
```

**Particle budget.** The pool stays at `Motion.particlePoolSize` (1600). A booster's own effect may request at most `BoosterTuning.maxBoosterShards` (**600**), which leaves room for a full chain clear (`Motion.maxParticlesPerClear`, 800). When the pool runs out, new shards are **skipped, never allocated**. A missing spark is invisible; a garbage-collection hitch is not.

**Frame budget.** No frame over 16 ms on a mid-range Android device, with the booster effect layers taking at most ~3 ms of that. That means:

- **No blur filters in effects.** `MaskFilter.blur` redrawn every frame is expensive on mobile, so glow is made from stacked wide low-alpha strokes (v1) or `glow.frag` (v2).
- **Additive blending only for sparks, flames and bolts.**
- **Prop glyphs are rasterized once** (per size and color) and cached, the same idea as `tile_cache.dart`, not re-parsed from SVG every frame.

**Reduced effects.** `BoosterTuning.reducedEffects` halves every shard request, disables v2 sprites and shaders (falling back to P), and removes the screen flicker. It turns on automatically when the average frame time over 2 s is above 20 ms during a resolve, and stays on for that session. A future *Reduce motion* setting should also switch off shake and lean, since they can cause discomfort.

**Fallbacks.** If a shader fails to load or compile, or a sprite sheet fails to decode, the effect silently uses its P version and logs once through the same failure-logging path audio uses. **Effects never hold up game logic.** The engine waits on its own `Motion` timings, not on an animation finishing, so a skipped or broken effect can't stall a resolve.

### 6.18 Making the v2 assets

Only needed for the upgrades in §6.15, and only after Phase B10's look check shows they're needed.

**Sprite sheets** (`assets/images/fx/`)

```text
fx_blast.png          8 frames  × 128 px  uniform grid, 1 row
fx_smoke.png          8 frames  ×  96 px
fx_dust_wave.png      8 frames  × 128×48
fx_flame_core.png    12 frames  ×  64×96  seamless loop
fx_flame_edge.png    12 frames  ×  64×96  seamless loop, same timing as core
```

- **White and grayscale on transparent only.** Brightness carries the shape; the theme supplies the color at draw time (`Paint.colorFilter` with `BlendMode.modulate`).
- **Uniform grid, one row per file.** That lets Flame's `SpriteSheet` load it directly, with no atlas data file or packer tool.
- **Premultiplied-safe edges:** export with a 2 px transparent margin per frame so frames don't bleed into each other when scaled.
- **Budget:** all fx sheets together under 1 MB.
- **Ways to make them:** hand-draw in Krita (free) or Aseprite; or simulate fire and smoke in Blender (free) or EmberGen and render to frames. In both cases, **convert to grayscale** before export. A small `tools/fx/make_sheet.py` (same spirit as `extract_icons.py`) can do the grayscale conversion and grid packing, so the source frames stay the single source of truth.
- **Credits:** anything not made in-house gets its license recorded, the same way `assets/audio/CREDITS.md` does for sound.

**Shaders** (`assets/shaders/`)

```text
glow.frag            uniforms: uSize, uTime, uColor (effectHot), uGlow (accent)
gust.frag            uniforms: uSize, uTime, uProgress, uColor (text)
burn_dissolve.frag   uniforms: uSize, uProgress, uRim (effectEmber), uChar (frameDark)
```

- Listed under `flutter: shaders:` in `pubspec.yaml` and loaded once with `FragmentProgram.fromAsset` when the game loads, not when a booster fires.
- Every color is a uniform set from `ThemeDefinition`, so a second theme needs no shader changes.
- Noise comes from a hash function in the shader itself. No noise texture file.

---

## 7. Audio

Existing SFX: `block_spawn`, `block_settle`, `wood_crush` (reused for all booster shatters). New files, same format as `game.md` P.7 (`.wav`, 44.1 kHz, 16-bit, mono, trimmed, peak-normalized), added to the `Sfx` enum with voice counts:

| Sfx | File | Voices | Character |
|---|---|---|---|
| `reelTick` | `reel_tick.wav` | 4 | short wooden ratchet click |
| `reelStop` | `reel_stop.wav` | 2 | wooden drum thunk |
| `boosterArm` | `booster_arm.wav` | 1 | soft wooden knock |
| `hammerHit` | `hammer_hit.wav` | 2 | mallet on timber |
| `bombFuse` | `bomb_fuse.wav` | 1 | fizzing fuse, 300 ms |
| `blast` | `blast.wav` | 2 | muffled boom plus splinters |
| `drill` | `drill.wav` | 1 | hand-drill grind, loopable |
| `woodSlide` | `wood_slide.wav` | 2 | plank scraping on plank, loopable |
| `whoosh` | `whoosh.wav` | 1 | gust |
| `bolt` | `bolt.wav` | 4 | crackle-snap, short |
| `mortar` | `mortar.wav` | 1 | wet trowel squelch |
| `rumble` | `rumble.wav` | 1 | low ground rumble, 500 ms |
| `fireCrackle` | `fire_crackle.wav` | 1 | campfire crackle, loopable |

All go through `AudioService` and respect the SFX volume setting. Looping sounds are stopped in `onRemove` and when the pause overlay opens, the same care `gameplay_screen.dart` already takes with the paused frame.

## 8. Haptics

`HapticsService` currently offers `light`, `medium` and `selection`, all gated by the Settings vibration switch.

| Moment | Haptic |
|---|---|
| Reel stops | `selection` |
| Arm a booster | `selection` |
| Fire any booster | `medium` |
| Bomb blast, Earthquake start | `medium` (no heavier tier exists; don't add one just for this) |
| Wildfire layer | `light`, at most 5 per burn |

---

## 9. Icons and theme colors

### 9.1 The rule

**Every booster color comes from the active `ThemeDefinition`.** This is the same rule as `game.md` P.8: no render component or widget reads `Tokens` colors directly for booster visuals. On `classic_wood` that means warm wood, cream and gold only.

**Colors never allowed in booster visuals on `classic_wood`:** `colorBlue`, `colorPurple` and `colorGreen`. These cold or saturated hues fight the wood. That replaces the earlier idea of color-coding classes red / purple / green. **Red** (`colorRed`) appears only as the dying end of Wildfire's ember. It is never a UI state color, because the board's top-edge warning pulse already owns red as the danger signal.

### 9.2 New theme fields

Add to `ThemeDefinition`, and map `classicWood` to existing tokens:

| Field | Used for | `classic_wood` value |
|---|---|---|
| `boosterFace` | slot and reel background | `Tokens.colorPanel` (6 % white) |
| `boosterRim` | slot border, resting | `Tokens.colorWoodLight` at 60 % |
| `boosterGlyph` | icon when ready | `accent` → `Tokens.colorGold` |
| `boosterGlyphMuted` | no-target / busy | `Tokens.colorTextMuted` |
| `effectHot` | bolt core, fire core | `Color(0xFFFFE6A8)` (pale gold, lighter than `colorGold`) |
| `effectEmber` | fire edge, ember | `Tokens.colorRed` |

Everything else reuses fields the theme already has: `accent` (armed pulse, preview outline, reel flash), `text` (armed glyph, flash disc, gust), `frameDark` (spent engraving, char), `frameLight` (mortar tint), `blockTint` (fire start).

A future theme defines these six fields and every booster recolors with no code change.

### 9.3 Icon states in the bar

The slot is a **50 px circle**: `boosterFace` fill, 1.5 px `boosterRim` border, a 25 px glyph centred in it, and one badge sitting on the rim at bottom-right.

```text
READY       glyph boosterGlyph (gold) · rim boosterRim · face boosterFace · charge badge
ARMED       glyph text (cream) · rim pulses accent 2 Hz · draining ring in accent
NO TARGET   glyph at 40 % · rim at 30 % · charge badge stays bright
BUSY        whole slot at 60 %
SPENT       face boardBg at 30 % · rim white 8 % · glyph desaturated at 45 %
            · charge badge replaced by the ▶ ad badge · still tappable
EXHAUSTED   the spent look with no badge at all · not tappable
```

**"Invalid target" feedback is a shake, never a color:** the preview jitters ±3 px horizontally for 150 ms.

**One badge corner.** A 50 px disc has room for the glyph and one badge, nothing more, so bottom-right carries the whole story: a number means loaded, a `▶` means a video brings it back, nothing means it is done for the run. The top-right class marker from the first draft is removed (§2) — it was decoration competing with the glyph for the same small circle.

**Charge badge:** a pill in the bottom-right corner, `boardBg` fill, `text` numeral, `Tokens.fontDisplay`, `Tokens.fontSizeXs`. The test build always shows "1", which keeps the badge ready for multi-charge later.

**Ad badge:** the same corner, so the eye lands in one place whether the slot is loaded or spent — a `boardBg` disc with the `circle-play` glyph in `accent`, 17 px. It pulses once every 2.4 s (scale 1 → 1.18 → 1), enough to read as an offer without nagging. It is drawn **only** when a refill is actually available (§4.9 rule 4).

### 9.4 Reel window (roll screen)

- Recessed wood panel: `frameDark` → `boardBg` vertical gradient, with a 2 px inner shadow (`shadowInset` from `tokens.css`).
- Top and bottom 20 % fade into the panel color, so icons appear to roll over a drum.
- The landed icon draws in `boosterGlyph`, and the blurred neighbours in `boosterGlyphMuted` at 50 %.
- The stop flash is a 2 px `accent` rim for 180 ms.
- Under the drum: the booster's name in `text`, `Tokens.fontDisplay`, 11 px. Nothing else — no slot label, no class mark (§3.2).

### 9.5 Glyph style — one library, not twelve drawings

The booster glyphs come from **[Lucide](https://lucide.dev) (ISC)**, not from hand-drawn paths. Twelve bespoke icons drawn to a brief drift in weight and optical size no matter how careful the brief is, and the first pass proved it: the hand-drawn hammer read as a pencil at bar size. A library gives one hand, one grid and one stroke weight for free, and the eight glyphs that had no art at all are a lookup instead of a drawing job.

```text
source           lucide-static (ISC) — path data pasted inline, one <svg> per use
viewBox          0 0 24 24
stroke           currentColor
stroke-width     1.8   (Lucide draws at 2; 1.8 matches the rest of the UI)
stroke-linecap   round
stroke-linejoin  round
fill             none
optical size     reads at 24 px, used at 30 px in the bar and 26 px in a reel
```

- **Keep the license notice.** Lucide is ISC: the copyright line travels with the copies. It sits in the `components.css` booster block and in `tools/ICONS.md`.
- **Don't nudge the paths.** A glyph that doesn't fit is a different Lucide icon, not an edited one — same rule as the extracted SVGs.
- **No baked fills.** Every path is stroked in `currentColor`, so one glyph takes the ready, muted, greyed and armed tints with no second copy. That also removes the old Lightning problem: the filled gold bolt is gone, replaced by `zap`.
- The shop, the daily reward and the bar all draw from this same set, so the four boosters the shop sells look identical to the ones in the bar.

### 9.6 Glyph map

| Booster | Lucide icon | Why it reads |
|---|---|---|
| Hammer | `hammer` | the tool itself |
| Bomb | `bomb` | round body, lit fuse |
| Patch | `puzzle` | the missing piece that fills the hole |
| Drill | `drill` | the tool itself |
| Slide | `between-horizontal-start` | two rows with a chevron pushing them across |
| Pillar | `stretch-vertical` | two standing columns |
| Sweep | `broom` | sweeping the top off the stack |
| Lightning | `zap` | the bolt |
| Mortar | `brick-wall` | filled courses, holes sealed |
| Earthquake | `chevrons-down` | the whole board coming down at once |
| Tilt | `square-arrow-down-right` | the board, with everything running to the low corner |
| Wildfire | `flame` | fire |

Supporting glyphs from the same set: `circle-play` (the ad badge and both ad sheets) and `rotate-ccw` (the re-spin prompt).

Five of the twelve had to be re-picked. `square-plus`, `columns-3` and `move-horizontal` (Patch, Pillar, Slide) were all correct in the abstract and said nothing at 25 px — a generic plus, a table layout and a bare double arrow. `arrow-down-to-line` (Earthquake) was worse than generic: it is the download glyph. `rotate-cw-square` (Tilt) said *rotate*, and Tilt doesn't rotate anything — the board leans and the blocks run downhill.

Two rules came out of it:

1. **Prefer the glyph that shows the thing being acted on**, not the operation in the abstract. A puzzle piece is a gap being filled, two standing bars are a column, a chevron pushing two rows is a row being shifted, and a board with an arrow into its low corner is a tilt.
2. **Check the set, not just the glyph.** Two boosters that can share a bar must not share a silhouette. Earthquake's obvious pick was `align-vertical-justify-end` — two bars settling onto a floor line — but that is Slide's two bars with the chevron swapped for a baseline, and Slide (Line) and Earthquake (Board) can roll together. `chevrons-down` says the same thing and can't be mistaken for anything else in the set. Nothing else is drawn by hand — with the class marks gone (§2) the booster UI has no bespoke shapes left at all.

### 9.7 Pipeline

Follow `tools/ICONS.md`. **Never hand-edit an extracted SVG, and never hand-edit a Lucide path.**

1. The mockups already carry the set: `screens/gameplay.html` has a reference sheet with all 12 glyphs plus the five slot states, and `shop.html` / `daily-reward.html` draw the same paths for the boosters they hand out.
2. To change or add a glyph, pull it from `lucide-static` and paste the path data in — never redraw it:

```bash
curl -sSL https://unpkg.com/lucide-static@1.47.0/icons/<name>.svg
```

3. Run `python3 tools/extract_icons.py`.
4. Confirm the 12 new files land in `assets/images/icons/` as monochrome (`currentColor`), **not** in `AppIcons.multicolor`, and that `circle-play` lands too — the ad badge needs it at runtime.
5. Use them through `AppIcons.<name>` with a `ColorFilter` from the theme field for the current state.

`app_icons.dart` currently has no booster entries, even though `tools/ICONS.md` lists `hammer`, `bomb`, `drill` and `lightning`. Re-running the extractor fixes that mismatch, and the four old hand-drawn shapes are replaced by their Lucide versions in the same pass — `ICONS.md`'s Boosters row should note the ISC source.

---

## 10. Analytics, experiment, leaderboards

### 10.1 Events

Sent through `AnalyticsService` (Firebase + GameAnalytics). Ids are the `BoosterType` names.

| Event | Fields | When |
|---|---|---|
| `booster_roll` | `small`, `line`, `area`, `board`, `source` (`spin` / `starter` / `same`) | roll screen closes |
| `booster_respin` | `slot`, `from`, `to`, `source` (`free` / `ad` / `token`) | each re-spin |
| `booster_ad_offer` | `placement` (`respin` / `refill`), `id`, `result` (`watched` / `declined` / `dismissed` / `no_fill`) | every time an ad sheet opens |
| `booster_ad_refill` | `id`, `elapsed_s`, `refills_used`, `stack_height` | a refill video completes |
| `booster_used` | `id`, `elapsed_s`, `stack_height`, `rows_cleared_forced`, `chain_links_after`, `score_after_chain` | resolve finishes |
| `booster_cancelled` | `id`, `reason` (`tap` / `timeout` / `pause` / `back`) | aim cancelled |
| `booster_unused` | `id` for each charge still left | run ends |
| `run_end` (existing) | add `loadout`, `boosters_used`, `ad_respins`, `ad_refills` | run ends |

Forced clears stay out of every "player achievement" counter, as `RowsClearedEvent.forced` already requires.

### 10.2 Experiment

> **Retired by the Coin economy** (`phase11_monetization_plan.md` §0). The control arm existed to compare ARPDAU against a banner that no longer ships, and with boosters, re-spins and refills now bought with Coins there is no "no boosters" arm left that is a fair comparison. It was never implemented in code (`booster_ab_group` has no storage key). Kept below for the reasoning; measure the economy by faucet and sink events instead.

On first launch after this ships, assign `booster_ab_group` 50/50 and store it (there's no remote config dependency, so assignment is local). The **control** group sees no roll screen and no bar. Compare by group:

- run length and runs per session
- day-1 and day-7 return rate
- roll-screen skip rate (tap during spin), boosters group only
- **ARPDAU**, because the banner is gone (§4.1). The boosters group has to make back that banner income through rewarded views; the control group still shows the banner, so the two are directly comparable. Watch rewarded views per session, fill rate and the offer decline rate next to it.

Guideline thresholds from the design discussion:

- **Rarely used:** a booster used in under ~50 % of the runs it appears in isn't pulling its weight. Rework it or replace it.
- **Too often re-spun:** if the free re-spin (or, later, the ad re-spin) is used in more than ~60 % of runs, the pools have a weak member. Find it through `booster_respin.from` and fix that booster. Don't add more re-spins.
- **Almost never re-spun:** the free re-spin could go. Check first that the button is easy to see.

### 10.3 Leaderboards (future)

Boosters make scores less comparable. When leaderboards arrive:

| Board | Rules |
|---|---|
| **Classic** | No boosters, no continue. Pure skill. |
| **Daily Challenge** | Same engine seed and the **same fixed loadout** for everyone that day. No re-spins, no continue. |
| **Boosted** | Normal play. Personal best or friends only, not global. |

This depends on §3.3: the roll's random source must stay separate from the engine's seed.

---

## 11. Tuning and files

### 11.1 `lib/game/config/booster_tuning.dart`

```dart
abstract final class BoosterTuning {
  static const chargesPerBooster = 1;   // the test build ships 5 — see below
  static const freeRespinsPerRun = 1;
  static const adRespinEnabled = true;       // rewarded re-spin, after the free one
  static const adRespinsPerRun = 3;
  static const adRefillEnabled = true;       // rewarded refill of a spent booster
  static const adRefillsPerRun = 2;          // across the whole bar
  static const adRefillsPerBooster = 1;      // so one slot can't be looped
  static const tokenRespinEnabled = false;   // deferred
  static const starterKitRuns = 3;

  static const aimWindow = Duration(seconds: 4);
  static const slotTapDebounce = Duration(milliseconds: 150);
  static const tipDuration = Duration(milliseconds: 2500);

  static const bombRadius = 1;       // 3 × 3
  static const sweepRows = 2;
  static const lightningBolts = 4;
  static const wildfireCap = 24;     // see note
  static const slideMinDragCells = 0.5;

  // Effects (§6.14–§6.18)
  static const maxBoosterShards = 600;    // leaves room for a full chain clear
  static const reducedEffects = false;    // also switched on automatically (§6.17)
  static const autoReduceFrameMs = 20;    // average over 2 s during a resolve
  static const v2SpritesEnabled = false;  // flip per effect once assets exist
  static const v2ShadersEnabled = false;
  static const maxFlameSprites = 8;       // Wildfire v2, concurrent loops
}
```

**Charges in the test build are 5, not 1.** One per run is the shipping rule, and it is also a rule that shows a tester each of the twelve effects exactly once before they have to start another run. Five makes an effect repeatable against a board the tester has deliberately set up, which is what every "what you check" list in §12 actually asks for. `booster_tuning.dart` carries the override and the reason; it goes back to 1 before any tuning data in §10.2 is read off a run.

**Wildfire cap:** 16 was proposed with a 10-wide board in mind. On the real 18-wide board, 16 is less than one row, so the default is **24**. Tune it during the test.

**The three ad caps are guesses**, set to keep a run from turning into a video queue: at most 3 bought re-spins before a run and 2 refills during it, and never the same booster twice. They are the first numbers to revisit once §10.2 has data — if the decline rate is low and session length holds, they can rise; if runs start ending with two videos watched and a worse score, they come down.

### 11.2 `Motion` additions

```dart
// Boosters
static const boosterReelSpin = Duration(milliseconds: 500);
static const boosterReelStagger = Duration(milliseconds: 250);
static const boosterRespinSpin = Duration(milliseconds: 500);
static const boosterHammerSwing = Duration(milliseconds: 140);
static const boosterBombFuse = Duration(milliseconds: 300);
static const boosterBombRing = Duration(milliseconds: 40);
static const boosterDrillCellStep = Duration(milliseconds: 30);
static const boosterGrow = Duration(milliseconds: 180);
static const boosterSlideRow = Duration(milliseconds: 160);
static const boosterSlideStep = Duration(milliseconds: 45);
static const boosterStackStep = Duration(milliseconds: 50);
static const boosterSweep = Duration(milliseconds: 260);
static const boosterBoltStep = Duration(milliseconds: 90);
static const boosterQuakeShake = Duration(milliseconds: 420);
static const boosterTiltLean = Duration(milliseconds: 150);
static const boosterFireLayer = Duration(milliseconds: 70);
static const boosterEffectBeat = Duration(milliseconds: 120);
```

All booster durations are multiplied by the current `resolveTimeScale`, like every other resolve animation, so boosters speed up as the game does. The reel animations are the exception: they happen before the run, so they aren't scaled.

### 11.3 New and changed files

```text
lib/game/boosters/
  booster_type.dart          enums (§2)
  booster_target.dart        cell / row / column / direction
  booster_effects.dart       isValid + apply for each booster (§5)
  tilt_cascade.dart          §5.11
  loadout.dart               Loadout model + (de)serialization
  loadout_roller.dart        pools, weights, own Random (§3.3)
lib/game/config/booster_tuning.dart
lib/game/input/booster_aim_handler.dart
lib/game/render/fx/
  booster_fx_script.dart     FxStep + one script per booster (§6.16)
  fx_context.dart            the primitives' entry point
  screen_shake.dart, board_lean.dart, cell_tint.dart, cell_grow.dart
  prop_drop.dart, bolt_stroke.dart, band.dart, flash_disc.dart
  fx_sprite.dart             v2 tinted sheets
  shader_quad.dart           v2 fragment programs
  shard_style.dart           ShardKind table (§6.16)
  frame_budget_monitor.dart  auto reduced-effects (§6.17)
lib/game/render/booster_preview_layer.dart
lib/game/render/booster_prop_layer.dart
lib/game/render/booster_fx_layer.dart        bolts, gust, flash, v2 sprites/shaders
assets/images/fx/                            v2 grayscale sheets (§6.18)
assets/shaders/                              v2 .frag files (§6.18)
tools/fx/make_sheet.py                       v2 grayscale + grid packing
lib/ui/widgets/booster_bar.dart
lib/ui/widgets/booster_slot.dart
lib/ui/widgets/booster_ad_sheet.dart         the one sheet both offers use (§3.5, §4.9)
lib/ui/screens/loadout_overlay.dart

changed:
lib/game/engine/game_engine.dart     useBooster, _beginBoosterResolve, aim hold
lib/game/engine/events.dart          BoosterFiredEvent, BlocksMovedEvent
lib/game/engine/grid.dart            move(), rowCells()
lib/game/render/fall_animator.dart   path mode (§6.0)
lib/game/render/board_blocks_component.dart   hide drilled row, cell tint + grow
lib/game/render/shatter_layer.dart   ShardKind on pooled shards, additive blend for spark/flame
lib/game/render/board_frame.dart     shake + lean transform around the board layers
lib/game/render/tile_cache.dart      cache rasterized prop glyphs
lib/game/input/gesture_handler.dart  route to aim handler while armed
lib/game/config/motion.dart          §11.2
lib/models/theme_definition.dart     §9.2
lib/ui/theme/tokens.dart             boosterBarHeight
lib/ui/screens/gameplay_screen.dart  bar in layout + budget, overlay, banner slot removed
lib/services/ads_service.dart        rewarded placements for re-spin and refill
lib/ui/screens/game_over_overlay.dart  Play again → roll with "Same boosters"
lib/services/audio_service.dart      new Sfx (§7)
lib/services/storage_service.dart    keys (§3.8)
lib/services/analytics_service.dart  events (§10.1)
pubspec.yaml                         assets/images/fx/, flutter: shaders: (v2 only)
screens/gameplay.html, screens/shop.html   icons (§9.7)
```

---

## 12. Build phases

Each phase ends playable. Verification is manual, as in `game.md` §5.

### Phase B1 — Data, roll screen, bar shell

Enums, `Loadout`, `LoadoutRoller`, the roll overlay with spin, re-spin, starter kit and "Same boosters", persistence, and the bar showing the four icons with no effects yet. The ad sheet can be a stub that resolves instantly — B9 wires the real one.

**What you check**
1. The tutorial run shows no roll and no bar.
2. Runs 1–3 after the tutorial land on the starter kit, and re-spin is disabled.
3. Run 4+ rolls one booster per slot. A re-spin changes only that slot and never repeats its previous booster.
4. Tapping during the spin reveals the results instantly.
5. With a fixed debug seed, re-spinning doesn't change the sequence of pieces or rising rows.
6. "Same boosters" on Play again starts with the previous loadout.
7. The board doesn't overlap the bar on a small phone or a tablet, and the space the banner used to take is now board.
8. Once the free re-spin is gone the line turns into the ad offer, the sheet names the slot it would roll, and declining changes nothing. With the stub forced to "no fill", the offer isn't drawn at all.

### Phase B2 — Arming, aiming, shared resolve

`useBooster`, the aim handler, the aim hold (difficulty clock keeps running), previews, cancel paths, the forced first clear, and spent state. Build the effect foundation here too: `FxStep` scripts, `FxContext`, `ScreenShake`, `PropDrop`, `ShardBurst` and the `ShardKind` table (§6.16). Implement **Hammer** as the first effect, fully procedural.

**What you check**
1. While aiming, the piece doesn't fall and rows don't rise, but the on-screen difficulty readout keeps advancing.
2. The aim window runs out at 4 s and the charge is kept. Pause, the Android back button and tapping the slot again all cancel.
3. Swipes don't move the piece while armed.
4. Hammer on an empty cell shakes and doesn't fire.
5. A Hammer that completes nothing still drops the column above. A chain started after a Hammer scores, but the Hammer's own clear doesn't.
6. The slot turns spent — greyed, with the ▶ badge — and a rewarded continue doesn't refill it.
7. Tapping a spent slot opens the refill sheet; the rise, the piece and the difficulty clock all stop while it is open; declining leaves the slot exactly as it was.
8. After `adRefillsPerBooster` refills that slot drops its badge and stops responding, and after `adRefillsPerRun` every spent slot does.

### Phase B3 — Breakers

Bomb, Drill, Sweep and Wildfire, with their v1 procedural effects (§6.15). Adds `FlashDisc`, `Band`, `CellTint` and the `spark`, `flame`, `ash` and `dust` shard kinds.

**What you check**
1. Bomb at a corner clips correctly, and the preview matches exactly what's removed.
2. The drilled row is never drawn as full. The bit crosses and the row breaks behind it.
3. Sweep takes the top two rows **that contain blocks**, even when they aren't next to each other.
4. The Wildfire preview matches the burn exactly, and the burn climbs first.
5. A big Bomb plus a chain doesn't cause a frame hitch (particle pool holds).
6. With the pool deliberately shrunk in a debug build, effects thin out but nothing stutters or crashes.
7. Every effect keeps its colors when the theme fields are swapped for test values: nothing hard-coded shows up.

### Phase B4 — Builders

Patch, Pillar, Lightning and Mortar. Adds `CellGrow` and `BoltStroke`.

**What you check**
1. Patch refuses open-air cells and active-piece cells.
2. Pillar fills from the floor up to the column's top block, and the plug sound rises in pitch.
3. Lightning hits the fullest rows first (lower row on ties), with bolts in the same order every time. Partly filled rows stay partly filled.
4. Mortar fills only holes with a block above and a block (or the floor) below.
5. Mortar and Lightning show the "no target" look when they'd do nothing.
6. The bolt glow looks soft without any blur filter, and the frame time stays flat while 4 bolts fire.

### Phase B5 — Earthquake

**What you check**
1. After Earthquake no block has an empty cell under it (except blocks resting on the active piece).
2. Overhangs below old clear lines also collapse. This is intended.
3. Chains that follow still obey the normal gravity-floor rule.

### Phase B6 — Sideways motion: Slide, Tilt

Path events, the path mode in `FallAnimator`, `BoardLean`, then Slide and Tilt.

**What you check** (the global time-scale slider at 0.25× helps here)
1. Slide wraps the edge block smoothly on both sides, and blocks over holes then drop.
2. Tilt: a block passing over a hole drops into it instead of sliding past.
3. Tilt gives the same result every time from the same board.
4. No block teleports. Every path is animated, with the squash only on final landing.
5. The board leans and returns, and input stays blocked until it's level.

### Phase B7 — Icons, theme fields, audio, haptics, tips

**What you check**
1. All 12 icons come from the extractor, sourced from Lucide, with no hand-edited SVGs and the ISC notice still in place.
2. No blue, purple or green appears anywhere in booster UI or effects.
3. Each state (ready, armed, no target, busy, spent, exhausted) is distinguishable in grayscale (take a screenshot and desaturate it) — spent vs. exhausted comes down to the badge, so check that it reads.
4. The badge sits cleanly on the rim of the disc at every screen density, and the 50 px button is still an easy hit with a thumb at the bottom of a large phone.
5. Every new sound respects the SFX volume setting, and looping sounds stop on pause.
6. First-use tips show once per booster and never again after a restart.

### Phase B8 — Analytics and experiment

**What you check**
1. Every event in §10.1 arrives in GameAnalytics with sensible fields, including both ad events and their `no_fill` path.
2. The control group never sees the roll screen or the bar, across restarts — and still sees the banner, so the two groups can be compared on revenue as well as retention.
3. Airplane mode: no hangs, and events queue as they already do.

### Phase B9 — Rewarded ads for real

Replace the stub with the rewarded unit from `phase11_monetization_plan.md`: pre-fetch on the roll screen and again when the first booster is spent, one placement id per purpose (`booster_respin`, `booster_refill`), and the banner slot deleted from the gameplay layout.

**What you check**
1. The reward lands only when the video completes. Dismissing it early changes nothing and doesn't burn the cap.
2. Offline or unfilled, no offer is ever drawn — no badge, no gold line, no dead button.
3. Backgrounding during the video and coming back leaves the run frozen and resumable, with the rise still stopped.
4. Music ducks for the ad and comes back at the right volume, and no looping booster SFX survives the ad.
5. A run that used an ad re-spin still skips the end-of-run interstitial (§3.5).
6. The banner is gone from every gameplay frame, including the pause snapshot, and the board is taller by that much.

### Phase B10 — Effect look check and v2 upgrades

Play every booster on a real mid-range Android phone, at normal speed and at 0.25×, and decide per effect: **keep P** or **upgrade**. Only the upgrades listed in §6.15 are in scope. Expect Wildfire flames to be the first, then the Bomb blast and smoke.

For each upgrade: make the grayscale sheet or shader (§6.18), add it to `pubspec.yaml`, wire it through `FxSprite` or `ShaderQuad`, and switch it on with `v2SpritesEnabled` / `v2ShadersEnabled`.

**What you check**
1. Each upgraded effect looks better than its P version side by side. If it doesn't, keep P.
2. No sprite frame or shader shows a baked color: swap the theme fields for test values and everything follows.
3. Forcing a shader or sheet to fail loading falls back to the P version with one log line and no stall.
4. On the slowest test device, reduced effects switches on by itself and the game stays smooth.
5. The download size grows by less than 1 MB for all fx assets together.
6. Anything not made in-house has a license entry.

---

## 13. After the test

- **Rarity.** Once the data is in, give the Board slot lower odds than the others (for example: Small and Line common, Area uncommon, Board rare).
- **Pool changes.** Replace boosters that fail the §10.2 thresholds from the reserve list: Saw, Cross, Piston, Level, Chisel, Sand, Melt, Reverse.
- **Mutual exclusions.** If Chisel ever joins the pools, it must never roll in the same loadout as Mortar, because they undo each other.
- **Re-spin sources.** Shipped as Coins (§3.5); rewarded video now only feeds the Coin faucet.
- **Multi-charge.** Shipped as the held-charge inventory (§4.9), filled from the shop, the login calendar and chests. Earning extra charges from chains is still open.
- **Rarity vs. price.** Charges are priced by slot tier, which is also the planned rarity ladder. If Board becomes rare in the roll, check the Board charge price still feels fair against how often one appears to spend it on.

## 14. Open questions

1. Is a 4 s aim window too short on a tall 18 × 32 board, where finding a target takes longer?
2. Should the first scored chain link after a booster start at `chainIndex` 1 (1.5×), or should the chain count restart at 0? The current spec starts at 1.
3. Hammer removes 1 cell out of 576. Is that too weak on this board size, or is precision enough of a reason to keep it?
4. Should Tilt be allowed when the active piece is low and next to the stack, given that it acts as an obstacle and can block the tilt?
5. Does the booster bar's 64 px cost too much board height on small phones? If so, try the immersive-style overlay layout. (It is cheaper than it was: the banner's 50 px came back to the board in §4.1.)
6. Is the refill offer better as a tap on the spent slot, or as one prompt at the moment the last charge is spent? The tap is quieter and never interrupts, but it has to be discovered.
7. Do the ad caps (3 re-spins, 2 refills, 1 per booster) hold up, or does a player who watches every video end up with a worse run and a worse session? §10.2 answers this before any of them move.
