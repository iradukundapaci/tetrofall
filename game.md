# Tetrofall — Game Build Plan (Flutter + Flame)

Companion to `screens.md`. That document defines the **UI**; this one defines the **game** — mechanics, animation, architecture, and the phased build order.

Rule of precedence: **mechanics ship before UI polish.** Phases 1–9 are the game. Phase 10 ports the HTML mockups 1:1. Nothing in Phase 10+ may alter a rule defined in Section 1.

---

## 0. Concept

Tetrofall inverts Tetris. Two forces fight over the same board:

```text
        ↓ tetrominoes fall from the top (player-controlled)
   ┌──────────────┐
   │              │
   │   ▓▓         │
   │ ▓▓▓▓▓▓  ▓▓   │
   │ ▓▓▓▓▓▓▓▓▓▓   │
   └──────────────┘
        ↑ partial rows push up from the bottom (automatic, relentless)
```

The stack grows from below on a timer. The player drops pieces to complete rows, which clear and buy back space. Lose when the stack is pushed above the top of the board.

Design pillars, inherited from the GDD:

```text
Easy to Learn. Hard to Master. Relaxing to Play. Satisfying to Watch. One More Run.
```

---

# 1. Core Mechanic Specification

This section is the **single source of truth**. Code disagreeing with it is a bug.

## 1.1 Board geometry

```text
COLS = 10
ROWS = 20            visible rows, index 0 = top, 19 = bottom
SPAWN_ROWS = 2       hidden buffer above row 0, used ONLY for piece spawn
```

Coordinates are `(row, col)`, origin top-left. Settled blocks may never occupy a row `< 0`; the buffer holds the active piece only.

Cell rendering size is derived from the available board rect at layout time, never hardcoded:

```text
cell = min(boardWidth / COLS, boardHeight / ROWS)
```

## 1.2 Piece system

Standard 7 tetrominoes: `I O T S Z J L`.

- **Randomizer:** 7-bag. Shuffle all seven, deal, reshuffle. Prevents drought frustration.
- **Rotation:** SRS (Super Rotation System) with standard wall kicks. `O` does not rotate.
- **Spawn:** top-center, in the hidden buffer, oriented flat-side-down. If the spawn position collides with settled blocks → **game over** (block-out).
- **Ghost piece:** a translucent outline showing where the piece will land. This is a **Settings option**, stored in the player profile and **enabled by default**. It gets its own row on `settings.html` alongside Sound and Music, using the same toggle component. Turning it off hides the outline immediately, mid-run, with no other rule change.
- **Hold:** *not in v1.* Reserved — the rise mechanic already supplies the pressure that Hold normally relieves.

## 1.3 Falling & locking

```text
gravity          piece descends 1 row every dropInterval ms
soft drop        descend at dropInterval / 20, awards 1 pt per row
hard drop        instant descend to landing row, awards 2 pts per row, locks immediately
lock delay       500 ms after first touching the stack
lock resets      max 15 move/rotate resets, then force-lock (prevents infinite stalling)
```

Locking writes the piece's four cells into the grid and advances the state machine to `RESOLVING`.

## 1.4 Rise system — the core twist

A new partially-filled row is staged **below** the board and slides continuously upward. This is the defining mechanic; it must feel like a slow physical push, never a snap.

**State:**

```text
pendingRow     List<Cell?> of length COLS, generated in advance and visible below the board
riseProgress   double in [0.0, 1.0) — fraction of one cell height the board is offset upward
riseInterval   seconds for one full row to arrive (decreases with difficulty)
```

**Per-frame update** (only while `phase == PLAYING`):

```dart
riseProgress += dt / riseInterval;
if (riseProgress >= 1.0) {
  commitRise();
  riseProgress -= 1.0;          // carry remainder, never reset to 0 — avoids stutter
  pendingRow = generateRow();
}
```

**`commitRise()`:**

1. If any settled block occupies row `0` → **game over** (top-out). Do not commit.
2. Shift every settled block up one row: `grid[r-1] = grid[r]` for `r = 1..ROWS-1`.
3. Write `pendingRow` into `grid[ROWS-1]`.
4. **Active piece is carried with the board**: decrement its row by 1 so it keeps its position relative to the stack.
   - If the shifted stack now overlaps the active piece, push the piece up 1 more row.
   - If the piece cannot be pushed (would exit the buffer), force-lock it in place immediately.
5. Emit `RiseCommitted` event → audio (low wooden groan), subtle screen shake (2px, 120ms).

**Row generation** (`generateRow()`), difficulty-scaled:

```text
fillRatio     0.40 → 0.75 over 5 minutes
gaps          COLS * (1 - fillRatio), clamped to [1, 4]  — never a full row (it would auto-clear)
gap placement early game: gaps adjacent, forming an easy well
              late game:  gaps scattered, and shifted ≥2 columns from the previous row's gaps
specials      after 3 min, each generated cell has a chance to be a special block (§1.8)
```

**Rise pausing.** The rise timer is frozen during `RESOLVING` (clear + cascade) and during the Time Freeze booster. It is *not* frozen while a piece is merely falling — the two pressures must overlap.

## 1.5 Line clear

After a lock (or after any cascade settle), scan for full rows.

- A row is full when all `COLS` cells are occupied **and clearable**. Stone blocks are not clearable and will block a row (§1.8).
- Multiple simultaneous full rows are cleared as one group, in one animation.
- Clearing plays the shatter sequence (§2.3) — this is a **blocking** phase for game logic, but particles themselves are non-blocking and outlive it.

## 1.6 Cascade gravity — the "middle row" rule

This is where Tetrofall departs from Tetris. Tetris shifts the entire field down by the number of cleared rows. Tetrofall lets blocks **fall independently** until they hit something.

```text
Before clear            Row 17 clears           After cascade
(row 17 is a middle     (blocks above are       (each block falls until it
 row — stack above it)   now unsupported)        lands on a block or the floor)

  . . ▓ . .               . . ▓ . .               . . . . .
  . ▓ ▓ ▓ .               . ▓ ▓ ▓ .               . . . . .
  ▓ ▓ ▓ ▓ ▓   ← clears    · · · · ·               . . . . .
  ▓ . . . ▓               ▓ . . . ▓               ▓ . ▓ ▓ ▓
  ▓ . . ▓ ▓               ▓ . . ▓ ▓               ▓ ▓ ▓ ▓ ▓
```

**A block never stops in mid-air.** It falls until one of two things stops it:

1. the cell directly below it in its own column is occupied, or
2. it reaches the **board floor** (row `ROWS-1`).

There is no third case. In the diagram above, the lone block in column 1 falls all the way to the floor because nothing in its column is below it; columns 0 and 4 don't move at all because they were already resting on the floor and on each other.

**Interaction with the rise.** The `pendingRow` is *not* part of the grid until `commitRise()` runs, so it is not a landing surface. A block falling while a row is halfway risen settles on the **current** floor, row `ROWS-1` — it never lands on, or sinks into, the partially-emerged row. When that row later commits, it pushes the settled block up along with everything else (§1.4), which keeps the two systems fully independent: cascade resolves against the committed grid only.

**Default resolver: `ColumnCascade`.**

```dart
for (final col in columns) {
  final survivors = cellsInColumn(col).where((c) => !c.cleared).toList();
  // repack bottom-up
  int write = ROWS - 1;
  for (final cell in survivors.reversed) {
    if (cell.row != write) emitFallAnimation(cell, from: cell.row, to: write);
    grid[write][col] = cell;
    write--;
  }
  clearAbove(write, col);
}
```

Each column resolves independently, so a block only falls as far as the next block *in its own column* — exactly "falls until it collides with another block in the rows below."

**Alternate resolver: `StickyGroup`** — flood-fill 4-connected components and drop each as a rigid body. Implemented behind the same `GravityResolver` interface and swappable via a debug flag, so both can be play-tested. `ColumnCascade` is the shipping default: it produces more clears, more chains, and reads more clearly in motion.

**Chain loop.** After a cascade settles, rescan for full rows. If any exist, clear them too and increment the chain counter. Repeat until stable. Each chain link raises the score multiplier (§1.7).

## 1.7 Scoring & combos

Base line score:

```text
1 line   = 100
2 lines  = 300
3 lines  = 500
4 lines  = 800   ("TETROFALL!")
```

Multipliers, applied in order:

```text
chainMultiplier   = 1.0 + (0.5 * chainIndex)     cascade chains, chainIndex starts at 0
levelMultiplier   = 1.0 + (elapsedMinutes * 0.1)
boosterMultiplier = 2.0 while Score Multiplier booster is active
```

Blocks-destroyed banner thresholds, per the GDD, counted across a single resolve (all chains included):

```text
  5 blocks  →  GOOD!            ×1
 20 blocks  →  AWESOME!         ×2
 50 blocks  →  INCREDIBLE!      ×5
100 blocks  →  UNBELIEVABLE!    ×10
```

Banner renders in the reserved space above the board (`gameplay.html`, Phase 4), purple accent per the color-coding rule, scale-pop + fade.

## 1.8 Special blocks

Special blocks arrive **only inside rising rows**, starting at the 3-minute mark. Falling tetrominoes are always plain wood — the player's tools stay predictable; the threat gets weirder.

| Block | Behaviour in Tetrofall |
|---|---|
| **Wood** | Baseline. Clears normally. |
| **Stone** | Not clearable by line completion. A row containing stone can never complete — it must be removed with Hammer/Bomb/Drill/Lightning. The primary late-game threat. |
| **Ice** | Requires 2 hits. First line completion cracks it and clears the *rest* of the row, leaving the cracked ice behind; second completion clears it. |
| **Bomb** | On clear, destroys the 3×3 neighbourhood, which can trigger further clears/cascades. |
| **Gold** | On clear, +250 bonus points. |
| **Diamond** | On clear, +5 coins. |
| **Treasure** | On clear, rolls the reward table (coins / booster charge). |
| **Locked** | Clears only if a Key block is cleared in the same resolve. Keys spawn in the same row. |
| **Rainbow** | On clear, destroys all blocks within radius 2 regardless of type — including Stone. The pressure-release valve. |

Every special must be distinguishable by **shape/icon, not just tint** (accessibility rule from `screens.md` Phase 12). Reuse the styling cheatsheet in `screens.md` Phase 4.

## 1.9 Boosters

Four on the HUD (`gameplay.html` bottom panel), matching the mockup exactly.

| Booster | Effect | Input |
|---|---|---|
| **Hammer** | Destroy one block | arm → tap target cell |
| **Bomb** | Destroy 3×3 area | arm → tap center cell |
| **Drill** | Destroy an entire column | arm → tap column |
| **Lightning** | Destroy an entire row | arm → tap row |

Reserved (not on the 4-slot HUD; see the Stopwatch gap noted in `screens.md` Phase 11):

- **Time Freeze** — halts the rise timer for 8s.
- **Score Multiplier** — ×2 points for 30s.

Rules: arming pauses gravity but **not** the rise. Tapping outside a valid target disarms. Every booster removal triggers a normal cascade + clear check, so boosters can start chains. Charges are consumed on use and earned via drops, achievements, and the shop.

## 1.10 Difficulty timeline

| Elapsed | dropInterval | riseInterval | fillRatio | Notes |
|---|---|---|---|---|
| 0:00 | 800 ms | 14 s | 0.40 | gaps clustered, tutorial-easy |
| 1:00 | 700 ms | 11 s | 0.50 | denser rows |
| 2:00 | 600 ms | 9 s | 0.60 | gaps scattered, harder patterns |
| 3:00 | 480 ms | 7 s | 0.65 | special blocks begin |
| 5:00 | 320 ms | 5 s | 0.70 | fast phase |
| 8:00+ | 200 ms (floor) | 4 s (floor) | 0.75 (cap) | endurance plateau |

Interpolate **linearly between checkpoints** — never step. The player should never feel a discrete jolt of difficulty.

## 1.11 Game over

Triggered by:

1. **Top-out** — `commitRise()` would push a settled block above row 0.
2. **Block-out** — a newly spawned piece overlaps settled blocks.

Sequence: freeze board → desaturate → blocks crumble top-to-bottom (400ms) → `game-over.html` overlay with score, best, coins earned, Watch-Ad-To-Continue. Continue clears the bottom 6 rows and resumes at the current difficulty.

## 1.12 Controls

| Input | Action |
|---|---|
| Swipe left / right | Move one column (hold to auto-repeat: DAS 170 ms, ARR 50 ms) |
| Tap (board) | Rotate clockwise |
| Two-finger tap | Rotate counter-clockwise |
| Swipe down (short) | Soft drop |
| Swipe down (fast/long) | Hard drop |
| Tap booster slot | Arm booster |
| Tap pause | Pause |

All thresholds live in one `InputTuning` class so they can be tuned without touching gesture code.

---

# 2. Animation Specification

The GDD says *"Satisfying to Watch."* These three animations carry that promise. **No block may ever teleport.** Every position change is interpolated.

The golden rule of the architecture: **the logical grid is the truth; the render layer lags behind it and catches up.** Logic commits instantly; visuals animate toward the committed state.

## 2.1 Rising rows — continuous, never sudden

The board is rendered with a **sub-cell vertical offset**. Nothing snaps.

```dart
// Board render transform
final yOffset = -riseProgress * cellSize;   // whole board drifts up continuously
```

- The `pendingRow` is drawn **below** the board floor, inside a clip rect, so it emerges gradually from behind the board's bottom edge — a physical push, not a pop-in.
- Emerging cells fade in opacity `0.5 → 1.0` across the first 30% of their travel, and carry a faint dust-particle wisp at the board's bottom lip.
- On `commitRise()`, `riseProgress` **carries its remainder** (`-= 1.0`, not `= 0`). Resetting to zero causes a visible 1-frame stutter every cycle.
- Warning state: when the stack top reaches row 3, the top edge of the board pulses red at 1 Hz and the rise sound gains a strained overtone.

```text
frame 0.00   frame 0.33   frame 0.66   frame 1.00 → commit
┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐
│        │   │        │   │        │   │        │
│  ▓▓▓   │   │  ▓▓▓   │   │  ▓▓▓   │   │  ▓▓▓   │  ← stack drifts up smoothly
│ ▓▓▓▓▓  │   │ ▓▓▓▓▓  │   │ ▓▓▓▓▓  │   │ ▓▓▓▓▓  │
└────────┘   │▒▒ ▒▒▒▒ │   │▒▒ ▒▒▒▒ │   │▒▒ ▒▒▒▒ │  ← new row emerging
 ▒▒ ▒▒▒▒     └────────┘   └────────┘   └────────┘
 (hidden)     (30% up)     (66% up)     (arrived)
```

## 2.2 Cascading fall — visible travel

When `ColumnCascade` moves a block from `fromRow` to `toRow`, the logical grid updates immediately, but the sprite animates.

```dart
final distance = toRow - fromRow;                       // in cells
final duration = sqrt(2 * distance / GRAVITY_CELLS_S2); // real free-fall timing
// GRAVITY_CELLS_S2 = 60.0  → 1 cell ≈ 180ms, 8 cells ≈ 520ms
```

- Easing: **`Curves.easeInQuad`** on the way down (accelerating), then a 60 ms squash-and-stretch on impact (scale Y ×0.85 → ×1.0).
- Blocks in different columns start together but land at different times, because travel distance differs. This staggering is the effect — do not normalize durations.
- A small dust puff spawns at each landing point.
- The state machine does not leave `RESOLVING` until the **longest** fall completes, then the chain rescan runs.

## 2.3 Shatter clear — center-out

The signature animation. When a row clears, each cell explodes into wooden splinters that fall and fade.

**Sequencing.** The clear propagates outward from the middle of the row, left and right simultaneously:

```dart
final center = (COLS - 1) / 2.0;          // 4.5 for COLS = 10
final delay  = (col - center).abs() * SHATTER_STEP;   // SHATTER_STEP = 28 ms
```

For an even column count the two middle cells (4 and 5) fire together, then 3 and 6, then 2 and 7, and so on:

```text
col   0    1    2    3    4    5    6    7    8    9
t    126  98   70   42   14   14   42   70   98  126   (ms)
                          ╲   ╱
                        starts here, spreads outward →
                                                    ← and outward
```

Total sequence duration for `COLS = 10`: `126 ms + 120 ms beat = ~250 ms` before the cascade begins.

**Per-cell shatter:**

```text
particles     10–14 per cell, 3–6 px wooden shards
color         plain blocks → active theme's tint; special blocks → that type's
              own fixed shard palette (stone grey, diamond blue, gold amber…)
initial vel   upward-biased cone: vy ∈ [-140, -40] px/s, vx ∈ [-90, 90] px/s
gravity       900 px/s²  — they arc up briefly, then fall
lifetime      600–900 ms, randomized per particle
fade          opacity 1.0 → 0.0 over the last 40% of lifetime
rotation      random spin, 1–3 rad/s
```

Particles fall toward the bottom of the board and disappear. They are **purely decorative** — never blocking, never colliding, and they outlive the `RESOLVING` phase.

**Performance:** particles are drawn on a **single dedicated layer** with a pooled allocator (pre-allocate 600 shards; recycle, never `new` mid-frame). A 4-line clear at `COLS = 10` is 40 cells ≈ 500 particles — the pool must absorb that without a GC hitch. Target: no frame over 16 ms on a mid-range Android device.

## 2.4 Motion constants — one file

Every value above lives in `lib/game/config/motion.dart`. Tuning happens there, nowhere else.

```dart
class Motion {
  static const shatterStep       = Duration(milliseconds: 28);
  static const shatterBeat       = Duration(milliseconds: 120);
  static const gravityCellsPerS2 = 60.0;
  static const particleGravity   = 900.0;
  static const impactSquash      = Duration(milliseconds: 60);
  static const lockDelay         = Duration(milliseconds: 500);
  static const riseWarnRow       = 3;
  // ...
}
```

---

# 3. Architecture

## 3.1 Layer separation

The hard rule: **the rules engine is pure Dart with zero Flame imports.** It can be unit-tested headlessly at thousands of ticks per second. Flame only draws what the engine reports.

```text
┌─────────────────────────────────────────────────┐
│  Flutter UI (widgets)                           │
│  menus, HUD overlays, modals — ports of         │
│  screens/*.html, pixel-matched                  │
├─────────────────────────────────────────────────┤
│  Flame render layer (components, effects)       │
│  BoardComponent, PieceComponent, ParticleLayer  │
│  interpolates toward engine state               │
├─────────────────────────────────────────────────┤
│  Rules engine (pure Dart, no Flame, no Flutter) │
│  Grid, Tetromino, RiseController, Resolver,     │
│  Scoring, Difficulty — fully unit-tested        │
├─────────────────────────────────────────────────┤
│  Services: persistence, audio, economy, ads     │
└─────────────────────────────────────────────────┘
```

Communication is one-way plus events: UI/render **reads** engine state and **sends** intents (`MoveLeft`, `Rotate`, `HardDrop`, `UseBooster`); the engine emits domain events (`RowsCleared`, `RiseCommitted`, `BlocksFell`, `GameOver`) that the render layer turns into animation.

## 3.2 Folder structure

```text
lib/
  main.dart
  app.dart                       routes, theme, providers

  game/
    tetrofall_game.dart          FlameGame root
    config/
      board_config.dart          COLS, ROWS, spawn buffer
      motion.dart                all animation constants
      difficulty.dart            the §1.10 timeline
    engine/                      ← PURE DART, NO FLAME
      grid.dart
      cell.dart                  block type + state (ice hits, etc.)
      tetromino.dart             shapes, SRS kicks, 7-bag
      piece_controller.dart      move/rotate/lock/lock-delay
      rise_controller.dart       riseProgress, commitRise, generateRow
      gravity_resolver.dart      GravityResolver interface
        column_cascade.dart      ← default
        sticky_group.dart        ← alternate, debug-swappable
      clear_detector.dart
      special_blocks.dart
      booster_engine.dart
      scoring.dart
      game_engine.dart           state machine + tick order
      events.dart                domain event definitions
    render/
      board_component.dart       grid draw + rise offset transform
      board_frame.dart           frame, well, inner shadow, grid lines — all canvas-drawn
      block_component.dart       one block, theme-aware
      piece_component.dart       active piece + ghost
      pending_row_component.dart the emerging row, clipped
      shatter_layer.dart         pooled particle system
      fall_animator.dart         drives §2.2 tweens from BlocksFell
      combo_banner.dart          GOOD!/AWESOME!/… overlay
      effects/                   dust, shake, impact squash
    input/
      gesture_handler.dart
      input_tuning.dart

  ui/
    theme/
      tokens.dart                1:1 port of screens/tokens.css
      components.dart            1:1 port of screens/components.css
      device_frame.dart          portrait lock helper
    screens/
      studio_logo_screen.dart    boot screen 1 — the only branded image
      splash_screen.dart         boot screen 2 — code-drawn game logo
      main_menu_screen.dart
      gameplay_screen.dart       hosts GameWidget + HUD overlays
      pause_overlay.dart
      game_over_overlay.dart
      daily_reward_screen.dart
      themes_screen.dart
      achievements_screen.dart
      settings_screen.dart
      shop_screen.dart
    widgets/
      logo_mark.dart             code-drawn T-tetromino mark
      logo_wordmark.dart         gradient TETROFALL text
      primary_button.dart
      icon_button.dart
      counter_pill.dart
      panel.dart
      progress_bar.dart
      nav_bar.dart

  services/
    storage_service.dart         high score, coins, unlocks
    audio_service.dart
    economy_service.dart
    achievements_service.dart
    daily_reward_service.dart
    ads_service.dart             stubbed until Phase 13

  models/
    player_profile.dart
    theme_definition.dart

  debug/
    debug_screen.dart            ASCII grid, steppers, sliders, stampers
    debug_fixtures.dart          preset boards for triggering cascades
    debug_flags.dart             single kill-switch, stripped in Phase 12

assets/
  fonts/                         Baloo2-*.ttf, Nunito-*.ttf
  images/
    blocks/                      tile_<theme>.png, block_<type>.png
    textures/                    bg_wood.png  (frame is canvas-drawn, no asset)
    ui/                          studio_logo.png, badges
                                 (game logo is code-drawn — no asset)
    icons/                       SVGs extracted from screens/*.html
  audio/
    sfx/                         short .wav one-shots
    music/                       .mp3 loops
```

See **Phase P** for the full asset list, formats, and generation prompts.

## 3.3 State machine

```text
        ┌──────────┐
        │  READY   │
        └────┬─────┘
             ↓ start
        ┌──────────┐  spawn collides  ┌────────────┐
   ┌───▶│ SPAWNING ├─────────────────▶│ GAME_OVER  │
   │    └────┬─────┘                  └────────────┘
   │         ↓                              ▲
   │    ┌──────────┐   rise pushes past 0   │
   │    │ PLAYING  ├────────────────────────┘
   │    └────┬─────┘
   │         ↓ lock
   │    ┌───────────┐
   │    │ RESOLVING │◀──┐  clear → shatter → cascade → rescan
   │    └────┬──────┘   │  (chain loop; rise frozen throughout)
   │         │          │
   │         └──────────┘  chain found
   │         ↓ stable
   └─────────┘

   PAUSED and BOOSTER_ARMED are orthogonal sub-states that suspend
   gravity; only PAUSED and Time Freeze suspend the rise.
```

## 3.4 Frame tick order

Order matters. Getting it wrong produces one-frame visual desyncs.

```text
1. drain input intents          (move / rotate / drop / booster)
2. advance difficulty clock
3. tick rise                    (skip if RESOLVING / PAUSED / frozen)
4. tick gravity + lock delay    (skip if RESOLVING / PAUSED / armed)
5. run engine transitions       (lock, clear detect, cascade, chain)
6. flush domain events → render layer
7. advance render tweens        (falls, squash, banner, shake)
8. advance particle system
9. draw
```

## 3.5 Dependencies

```yaml
dependencies:
  flame: ^1.18.0
  flame_audio: ^2.10.0
  flutter_svg: ^2.0.10        # icons extracted from the HTML mockups
  shared_preferences: ^2.2.3  # profile persistence
  provider: ^6.1.2            # or riverpod — lightweight state for UI only
dev_dependencies:
  flutter_lints: ^6.0.0
```

Fonts are **bundled `.ttf` files** (Phase P.1), declared in `pubspec.yaml`'s `fonts:` section — not fetched at runtime via `google_fonts`, which would flash fallback type on the splash screen.

Portrait is locked at boot (`SystemChrome.setPreferredOrientations`), matching `screens.md`'s portrait-only rule.

---

# 4. Build Phases

Mechanics first. Every phase below states two things:

- **Output** — what concretely exists and runs when the phase is finished.
- **What you check** — the hands-on steps *you* perform to confirm it's done. No automated tests are written; you are the verification.

**Do not start a phase until you've checked off the previous one.**

---

## Phase P — Asset Preparation (do this before Phase 0)

Gather everything here *first*. Nothing below blocks engine work, but a missing texture halfway through Phase 5 stalls the fun part, and audio missing at Phase 9 means re-tuning animation timing after the fact.

**Where things go:**

```text
assets/
  fonts/          Baloo2-*.ttf, Nunito-*.ttf
  images/
    blocks/       base tile per theme + 8 shared special-block tiles
    textures/     backgrounds, board frame
    ui/           logo, badges, ribbons
    icons/        extracted SVGs
  audio/
    sfx/          short one-shots
    music/        loops
```

Register all of it in `pubspec.yaml` under `flutter: assets:` and `fonts:`.

---

### P.1 — Fonts (source, don't generate)

`tokens.css` already commits to two families. Download the actual `.ttf` files from Google Fonts and bundle them rather than fetching at runtime — a splash screen that flashes fallback type looks broken.

| Family | Weights needed | Files |
|---|---|---|
| **Baloo 2** (display: scores, titles, combo banner) | 500, 600, 700, 800 | `Baloo2-Medium.ttf`, `-SemiBold`, `-Bold`, `-ExtraBold` |
| **Nunito** (body: buttons, labels) | 400, 600, 700, 800 | `Nunito-Regular.ttf`, `-SemiBold`, `-Bold`, `-ExtraBold` |

Source: fonts.google.com → "Get font" → extract the static `.ttf` files (not variable fonts — Flutter handles static weights more predictably). Both are Open Font License, so commercial release is fine.

---

### P.2 — Logo & brand

There are **two separate brand moments** at boot, in this order:

```text
1. Studio logo screen   →  your studio's mark. IMAGE ASSET.
2. Splash screen        →  the Tetrofall game logo. NO IMAGE — built in code.
```

---

#### Screen 1 — Studio logo (the only image needed here)

Maps to `logo.html`. This is where `assets/logo.svg` belongs — it's the studio mark, not the game mark.

**One problem to fix:** `screens.md` notes the source SVG is dark ink on a flat white rectangle, worked around in the mockup with `mix-blend-mode: multiply`. **That trick does not exist in Flutter.** Painting it as-is puts a hard white box on the wood background.

| Asset | Format | Size | Notes |
|---|---|---|---|
| `studio_logo.png` | PNG, **genuinely transparent** | 1024×1024 (or wider if it's a wordmark) | Or keep it SVG and render with `flutter_svg` |

Fastest fix, no generation needed: open `logo.svg`, delete the white background `<rect>`, recolor the ink to `#f5ead9` (`--color-text`), re-export. Verify the transparency by opening it over a dark background before you ship it — a white halo is easy to miss on a white canvas.

Presentation: centred, `min(60vw, 320px)` wide, on the plain wood background, no other UI. Suggested timing — fade in 400 ms, hold 1200 ms, fade out 400 ms, then hand off to the splash. Tap anywhere to skip.

---

#### Screen 2 — Game logo (no asset — drawn in code)

`splash.html` already builds the Tetrofall mark out of CSS block cells rather than a raster, specifically so it sits flush on the wood grain with no halo to mask out. **Port that behaviour directly.** There is no `logo_full.png`, no `game-logo.png` — the mark is widgets and canvas.

Two pieces:

**a) The block mark** — a **T-tetromino**, in the same wood-block language as the board:

```text
  . ▓ .        3 columns × 2 rows
  ▓ ▓ ▓        cell 40px @ 375px-wide frame (≈10.7% of screen width,
               clamp 40–72px so it scales up on tablet), 5px gap,
               8px corner radius
```

| Property | Value (from `splash.html`) |
|---|---|
| Fill | Linear gradient ≈160°: `--color-wood-light` 0% → `--color-wood-mid` 55% → `--color-wood-dark` 100% |
| Border | 1px `rgba(0,0,0,0.35)` |
| Outer shadow | `--shadow-soft` (0 4px 12px rgba(0,0,0,0.35)) |
| Inner highlight | inset 0 2px 3px `rgba(255,255,255,0.28)` |
| Inner shade | inset 0 −3px 4px `rgba(0,0,0,0.30)` |

⚠️ **Flutter has no inset box-shadow.** Those last two rows are what give the block its carved look, and `BoxDecoration` can't do them. Paint them the same way as the board frame (P.4): `MaskFilter.blur(BlurStyle.inner, …)` on a clipped `RRect`, or a top-to-bottom overlay gradient. Skipping them leaves flat rectangles that look nothing like the mockup.

**b) The wordmark** — the text `TETROFALL`:

| Property | Value |
|---|---|
| Font | Baloo 2 (`--font-display`), weight 800 |
| Size | `clamp(1.75rem, 8vw, 2.5rem)` → 28–40px, tracking `0.03em` |
| Fill | Vertical gradient `#ffe9b0` 0% → `--color-gold` (#f2b632) 55% → `#c9821a` 100%, applied with a `ShaderMask` |
| Shadows | Hard: offset (0, 3), blur 0, `rgba(0,0,0,0.35)`. Soft: offset (0, 4), blur 8, `rgba(0,0,0,0.45)` |

**c) The splash sequence** — port the timing exactly; it's the game's first impression and it's already tuned:

| t | Event |
|---|---|
| 0 ms | Block mark begins falling from −420px, easing **in** (accelerating — `cubic-bezier(0.55, 0, 0.85, 0.15)`), over 550 ms. Landing shadow simultaneously grows `scaleX 0.3 → 1.0` and fades in. |
| 550 ms | **Land.** Squash keyframes over 400 ms: `scaleY` 1 → 0.7 → 1.1 → 0.96 → 1, with `scaleX` inverse. Wordmark fades in and rises 6px. Loader fades in. |
| 850 ms | Progress bar fills over 1800 ms, `cubic-bezier(0.3, 0.6, 0.3, 1)`. |
| 3100 ms | Whole stage fades out over 600 ms. |
| 3700 ms | Main menu. |

The falling mark uses an **ease-in** curve, not ease-out — it's a tetromino under gravity, and it must accelerate. Getting this backwards makes the whole thing feel floaty and wrong.

**d) Supporting detail:** 14 dust particles, 4px gold circles, drifting upward ~820px with ±20px horizontal drift, 4–8s durations and 0–6s staggered delays, opacity ramping 0 → 0.7 → 0.4 → 0. Loader bar is `min(55vw, 220px)` with an uppercase muted "LOADING…" label in Nunito 700, tracking `0.04em`.

**Real loading vs. the animation:** drive the bar from actual asset preloading, but enforce a **minimum 2.5s** so the drop-and-land sequence always completes. Never cut the animation short because the assets happened to load fast — and never leave the player staring at a full bar because they didn't.

**Where this lives:** `lib/ui/widgets/logo_mark.dart` (block mark) and `logo_wordmark.dart` (gradient text), so the main menu can reuse both at a smaller scale instead of re-implementing them.

---

### P.3 — Block sprites (the important one)

> **MVP scope: one theme — `classic_wood`.** The other eight are post-MVP, but the structure below makes each one cost a single PNG and zero code. Build the seam now; don't fill it yet.

Naive approach: 9 block types × 9 themes = 81 sprites. **Don't do that.** Instead:

- **One base tile per theme** — the material surface, used for plain blocks. *MVP: one file.*
- **Eight complete special-block tiles**, shared across every theme and never re-drawn per theme. Nine files, since Ice needs a cracked state.

For MVP that's **10 files**. At nine themes it's 18 — never 81.

### Why complete tiles, not overlays

The alternative — an 8-glyph overlay set composited onto whatever base tile the active theme provides — costs the *same* 8 files, so the budget doesn't decide this. Three things do:

**1. Readability is gameplay, and it shouldn't shift per theme.** Special blocks carry rules: *this one can't be cleared, this one explodes, this one needs two hits.* If a Stone block is grey granite in Classic Wood but grey-tinted candy in Candy, the player relearns the board every time they change skin. Shared tiles mean one visual vocabulary, learned once, permanent.

**2. Overlays have to survive nine backgrounds; tiles have to survive none.** A dark padlock glyph reads fine on oak and disappears on the Snow tile. Every overlay would need contrast-checking against every future theme material — 8 × 9 = 72 combinations, each a chance to ship something illegible. A complete tile controls its own contrast once, forever.

**3. Complete tiles can break the square.** Ice can be genuinely translucent with the board showing through. Rainbow can bleed a soft glow past its cell. Bomb can sit slightly proud of the grid. Overlays are stuck inside whatever silhouette the base tile has.

The cost is **cohesion**: in Candy theme, eight wooden-looking special blocks among pink candy tiles. Mitigate it by designing all eight in a deliberately material-neutral style — they should read as *objects embedded in the board*, not as the board's material. Give each one the same subtle recessed inner border so it looks inset into whatever surrounds it.

**Keep the escape hatch:** `ThemeDefinition` holds an optional sprite override map, `Map<BlockType, String>`, empty by default. If Halloween later wants its own carved-pumpkin bomb, it supplies one entry and everything else keeps falling back to the shared set. Costs nothing to build now; costs a refactor to add later.

---

**Base tiles** — `assets/images/blocks/tile_<theme>.png`

| Spec | Value |
|---|---|
| Format | PNG, 24-bit + alpha |
| Size | 256×256 (downscales cleanly to any cell size) |
| Content | A single square block, filling the canvas edge-to-edge with ~6px rounded corners |
| Lighting | Soft top-left light source. Note the exact direction you use — every future theme tile must match it, or the board will look assembled from different games |
| Edges | Slightly darker bevel on bottom/right, lighter on top/left |

**MVP needs exactly one:** `tile_classic_wood.png`.

> **Prompt:** "A single square game tile viewed straight-on, filling the entire square canvas edge to edge, with slightly rounded corners. Material: warm polished oak with visible horizontal grain, amber-brown (#7a5230 to #c89b6a). Soft top-left lighting with a subtle bevel — lighter on the top and left edges, darker on the bottom and right. Clean mobile-game asset, no text, no icons, no background, no shadow outside the tile, flat orthographic view, high detail texture, 256×256."

Since this is the only tile in the MVP, it carries the entire look of the game — it's worth generating several variants and picking carefully rather than taking the first result. Check it **tiled 10×20 on a full board**, not in isolation: grain that reads nicely at 256px can turn into visual noise when repeated 200 times.

<details>
<summary>Post-MVP theme materials (for later, same prompt template)</summary>

> - `marble` → "cool white marble with fine grey veining"
> - `candy` → "glossy pastel hard candy with a glassy highlight"
> - `snow` → "packed snow and pale blue ice, soft matte surface"
> - `space` → "dark starfield resin with faint nebula purples and tiny stars"
> - `neon` → "matte black panel with a glowing cyan edge outline"
> - `halloween` → "weathered dark wood with a faint carved pumpkin grain, deep orange accents"
> - `ancient_temple` → "carved sandstone with worn hieroglyph-like etching, tan and ochre"
> - `golden_wood` → "lacquered wood inlaid with gold leaf, rich metallic sheen"

</details>

**Special-block tiles** — `assets/images/blocks/block_<type>.png`

Same geometry as the base tiles so they sit flush in the grid, but each is a finished block in its own right. Built once, shared by every theme.

| Spec | Value |
|---|---|
| Format | PNG, 24-bit + alpha (alpha only where a block is deliberately translucent, e.g. ice) |
| Size | 256×256, edge-to-edge, ~6px rounded corners |
| Lighting | **Same top-left light source as the base tiles** — this is what makes them look like they belong on the same board |
| Inner border | A subtle recessed inner edge on all eight, so they read as inset objects against any theme material |
| Readability | Silhouette and value must be distinct at 32px. Check them greyscale — if two are hard to tell apart with color removed, they're relying on hue alone, which fails the accessibility rule |

Needed: `stone`, `ice`, `ice_cracked`, `bomb`, `gold`, `diamond`, `treasure`, `locked`, `rainbow`. Plain blocks use the theme's base tile.

> **Prompt template:** "A single square game block viewed straight-on, filling the entire square canvas edge to edge, with slightly rounded corners and a subtle recessed inner border. **{SUBJECT}**. Soft top-left lighting with a bevel — lighter on the top and left edges, darker on the bottom and right. Clean mobile-game asset, bold readable shapes, no text, no background outside the block, no drop shadow, flat orthographic view, 256×256."
>
> Substitute `{SUBJECT}`:
> - `stone` → "Rough grey granite with a chipped, pitted surface and no grain — visibly heavier and colder than wood"
> - `ice` → "Translucent pale-blue ice, frosted edges, semi-transparent centre so the board shows faintly through"
> - `ice_cracked` → "The same translucent pale-blue ice block, now split by deep white fracture lines radiating from the centre"
> - `bomb` → "A dark charcoal block with a round black bomb set into its face and a short lit fuse, deep red accent glow (#d9432e)"
> - `gold` → "Polished gold metal with a bright diagonal shine streak and warm amber highlights (#f2b632)"
> - `diamond` → "Deep blue crystal with sharp geometric facets catching light (#3aa0d9)"
> - `treasure` → "A small closed treasure chest with gold bands and a round clasp, set into the block face"
> - `locked` → "A darkened block with heavy iron banding and a closed padlock at its centre"
> - `rainbow` → "Smooth swirling multicolor gradient — magenta, cyan, gold, violet — with a soft inner glow"

**Shard colors.** Each special tile also needs a shard color entry in code (§2.3): stone shatters grey, diamond blue, gold amber, and so on. Sample two or three colors off each finished sprite and record them next to the block type — the shatter is far more satisfying when a diamond bursts blue instead of brown.

---

### P.4 — Backgrounds & textures

`tokens.css` fakes the wood background with a CSS `repeating-linear-gradient`. That's fine as a fallback, but a real texture reads far better.

| Asset | Format | Size | Notes |
|---|---|---|---|
| `bg_wood.png` | PNG | 1024×1024, **seamlessly tileable** | Full-screen background |

> **Prompt (background):** "A seamless tileable dark wood texture, deep walnut brown (#2b1c12 to #4a2f1c), fine vertical grain, subtle and low-contrast so UI text stays readable on top, evenly lit with no visible light source or shadows, no knots or strong features, 1024×1024, tiles seamlessly on all four edges."

**The board frame is drawn in code — no image.** Good call: a 9-patch frame stretches badly across the phone/tablet range, needs re-exporting per theme, and pins you to whatever radius the artwork baked in. Canvas drawing is resolution-independent, recolors from `ThemeDefinition` for free, and costs a handful of draw calls per frame.

Implementation lives in `lib/game/render/board_frame.dart`, rendered beneath the blocks. All values come from `tokens.dart` / the active theme — no literals:

```dart
// 1. Outer frame — rounded rect stroke with a two-tone bevel
//    LinearGradient topLeft → bottomRight: theme.frameLight → theme.frameDark
//    strokeWidth ≈ cellSize * 0.35, radius = Tokens.radiusLg (24)

// 2. Well interior — fill with theme.boardBg, slightly darker than the
//    page background so the board reads as recessed

// 3. Inner shadow — drawRRect with Paint()..maskFilter = MaskFilter.blur(
//    BlurStyle.inner, 8), color black at ~25% alpha. This is what sells
//    the depth the image version was going to provide.

// 4. Grid lines — 1px, theme.gridLine at ~8% alpha, on cell boundaries.
//    Subtle enough that an empty board looks calm, present enough that
//    the player can judge column alignment while a piece is falling.

// 5. Outer drop shadow — Tokens.shadowSoft, offset (0, 4), blur 12.
```

Two things to get right: the frame thickness must scale with `cellSize` (not a fixed pixel value) so it looks the same on phone and tablet, and the bevel light direction must match the block tiles' top-left source from P.3 — otherwise the frame looks lit from a different sun than the blocks sitting in it.

---

### P.5 — Icons (extract, don't generate)

**No generation needed.** All 20+ icons from `screens.md` Phase 11 already exist as inline `<svg>` markup inside your HTML mockups (`shop.html` alone has 24). Extracting them guarantees the Flutter build matches the mockups exactly — regenerating would guarantee it doesn't.

Process: for each `.html` file, copy each `<svg>…</svg>` block into its own file in `assets/images/icons/`, add an `xmlns` attribute if missing, and render with `flutter_svg`.

Checklist (from the `screens.md` Phase 11 audit):

```text
Gameplay:  coin, trophy, pause, play, restart, home, settings, sound, music
Boosters:  hammer, bomb, drill, lightning, stopwatch*, star
Rewards:   treasure-chest, gift-box, diamond, coin-stack, crown, medal

* stopwatch has no mockup source yet (reserved for Time Freeze) — draw or
  generate this one only if you add the 5th booster slot.
```

Add `flutter_svg: ^2.0.10` to dependencies for this.

---

### P.6 — Particles

**Nothing to gather.** The shatter shards (§2.3) are drawn procedurally as small rounded rectangles tinted from the block's own palette. This is deliberate: procedural shards inherit theme colors for free, and pooling raw shapes is far cheaper than pooling textured sprites at ~500 particles per 4-line clear.

Optional upgrade later: 4 hand-drawn splinter silhouettes (`shard_01..04.png`, 64×64, transparent) used as alpha masks so the tint still applies.

---

### P.7 — Audio (source or commission)

**Formats:** SFX as `.wav`, 44.1 kHz, 16-bit, **mono** — short files with no decode latency, which matters because a lock click that arrives 80 ms late feels broken. Music as `.mp3`, 128 kbps, stereo.

Keep every SFX under 1 second unless noted. Sources: freesound.org (check licenses), Kenney.nl (CC0), or a commissioned pack.

| File | Description | Length |
|---|---|---|
| `lock.wav` | Dry wooden click as a piece locks | 0.1 s |
| `move.wav` | Very quiet tick on horizontal move | 0.05 s |
| `rotate.wav` | Soft wooden pivot | 0.08 s |
| `hard_drop.wav` | Heavy thud with a little air | 0.3 s |
| `wood_crack.wav` | **The signature sound** — dry timber snapping, on row clear | 0.4 s |
| `wood_fall.wav` | Blocks landing after cascade, hollow knock | 0.25 s |
| `rise_groan.wav` | Low wooden strain as a row commits | 0.5 s |
| `rise_warning.wav` | Tense creak, loops while stack is near the top | 1.0 s, loopable |
| `combo_1..4.wav` | Four ascending stings for GOOD!/AWESOME!/INCREDIBLE!/UNBELIEVABLE! | 0.5–1.2 s |
| `booster_hammer.wav` | Sharp mallet strike | 0.3 s |
| `booster_bomb.wav` | Muffled wooden explosion | 0.6 s |
| `booster_drill.wav` | Fast descending whirr | 0.5 s |
| `booster_lightning.wav` | Crackling horizontal zap | 0.5 s |
| `coin.wav` | Bright coin chime | 0.2 s |
| `button.wav` | Soft UI tap | 0.08 s |
| `reward.wav` | Warm ascending flourish | 1.0 s |
| `unlock.wav` | Theme/achievement unlock fanfare | 1.5 s |
| `treasure.wav` | Chest creaking open | 0.8 s |
| `game_over.wav` | Descending wooden collapse | 1.5 s |

**Music:**

| File | Description |
|---|---|
| `menu_loop.mp3` | Calm acoustic — soft guitar/marimba, warm, unhurried. 60–90 s seamless loop. |
| `game_loop.mp3` | Relaxing but with forward motion; light percussion. 90–120 s seamless loop. |
| `game_loop_intense.mp3` | *Optional.* Same key/tempo as `game_loop`, denser instrumentation — crossfade in when the stack nears the top. |

Both loops must be **seam-checked**: play on repeat for two minutes and listen for the click at the loop point.

---

### P.8 — Theme palette (data, not files)

**MVP: one palette, `classic_wood`** — and it's already written. `tokens.css` *is* the classic wood palette, so `ThemeDefinition.classicWood` reads its values straight from `tokens.dart` rather than defining new ones.

Fields: `background`, `boardBg`, `frameLight`, `frameDark`, `gridLine`, `blockTint`, `text`, `accent` — plus the optional per-type sprite override map from P.3. The frame colors are here rather than in an image because the frame is canvas-drawn (P.4). Nothing to gather.

The one thing that matters here: **define the `ThemeDefinition` type properly even though there's only one instance of it.** Every color the board renders must come from the active `ThemeDefinition`, never from a `tokens.dart` constant read directly by a render component. Skip that and adding theme #2 later means auditing every draw call.

---

### P.9 — Store & launch assets (needed at Phase 13, gather early if convenient)

| Asset | Format | Size |
|---|---|---|
| App icon | PNG, no alpha, no rounded corners | 1024×1024 |
| Android adaptive icon | Foreground PNG w/ alpha + background color | 432×432 foreground, safe zone centre 66% |
| Native splash | PNG, transparent | 512×512 mark on `--color-bg` |
| Feature graphic (Play Store) | PNG/JPG | 1024×500 |
| Screenshots | PNG | 6 per platform, portrait, from real gameplay |

**The app icon and native splash still need rasters** — the OS can't render a Flutter widget before the app starts. Don't redraw the mark by hand: run the app with the logo mark scaled up on a transparent background, screenshot it at high resolution, and export from that. The store icon and the in-app splash then show the same object, which is the whole point of having a mark.

Note the native splash (the OS-level one, shown before Flutter boots) is a **third** thing, distinct from the two boot screens in P.2. Keep it minimal — just the mark on `--color-bg` — so the handoff into the studio logo screen isn't jarring.

---

**Output of Phase P:** a populated `assets/` tree and a `pubspec.yaml` that registers every file.

**What you check:**

1. `flutter pub get` runs clean with no missing-asset warnings.
2. Open the studio logo over a **dark** background in any image viewer. Any white box or pale halo around it means the transparency wasn't actually removed — this is invisible on the white canvas most editors default to.
3. Tile `tile_classic_wood.png` across a full 10×20 grid on a scratch screen. It's the only tile in the MVP, so it has to hold up repeated 200 times — check for grain that turns into noise, or a highlight that creates a visible repeating pattern across the board.
4. Scatter the eight special tiles across that tiled board and step back an arm's length. Can you tell all eight apart? Now screenshot it and desaturate the image — if two become hard to distinguish in greyscale, they're leaning on color alone.
5. Play each SFX once. Anything that makes you wince now will make you wince 500 times an hour later.
6. Loop both music tracks for two minutes each and listen for the seam.

---

## Phase 0 — Foundation

**Goal:** a running Flame app with the real board rectangle on screen. No gameplay.

- Add dependencies; lock portrait orientation.
- Create the folder structure from §3.2.
- Port `screens/tokens.css` → `lib/ui/theme/tokens.dart` as `const` values (colors, radii, spacing, type scale) with identical names. This is a mechanical translation — no reinterpretation.
- `TetrofallGame extends FlameGame`; render an empty 10×20 board on the wood-texture background.
- `board_frame.dart` per P.4 — canvas-drawn frame, recessed well, inner shadow, grid lines. Worth doing properly now: it's the container everything else sits in, and it's easier to judge empty than under a full board.
- `BoardConfig`, `Motion`, `Difficulty` constant files stubbed.

**Output:** an app that launches to a single screen showing an empty, framed 10×20 board on the wood background. Nothing moves.

**What you check:**

1. Launch it — the board is centred, cells are square (not stretched), and the grid is 10 wide by 20 tall. Count them.
2. Does the board look **recessed into** the background, or pasted on top? If it looks flat, the inner shadow is too weak.
3. Grid lines should be visible enough to judge column alignment, faint enough that an empty board still looks calm. This is a two-minute tuning job now and a nagging annoyance later.
4. Rotate the device — it stays portrait.
5. Run on a tablet (or resize the emulator) — the board scales and stays centred, and the **frame thickness scales with it**. A frame that stays 12px on a tablet is the tell that it's hardcoded instead of derived from `cellSize`.
6. Compare the background color against `splash.html` in a browser side by side. Same brown.

---

## Phase 1 — Rules engine + debug view

**Goal:** a complete Tetris core. Since you're checking this by hand rather than with tests, the engine ships with a **debug screen** that prints the grid as text — that's what makes it inspectable.

- `Grid`, `Cell`, `Tetromino` (7 shapes + SRS kick tables), 7-bag randomizer.
- `PieceController`: move, rotate + wall kicks, collision, hard/soft drop, lock delay with reset cap.
- `ClearDetector`: full-row detection.
- `GameEngine` state machine + `tick(dt)`.
- **Debug screen** (reachable by a long-press on the board, kept until Phase 12): renders the grid as ASCII text, plus buttons for Step-One-Tick, Move L/R, Rotate CW/CCW, Hard Drop, and a readout of current phase / piece / bag contents.

**Output:** a debug screen where you can drive a piece step by step and watch the grid update as text.

**What you check:**

1. Hold Move-Right — the piece stops at the wall and doesn't slide off or wrap around.
2. Rotate an `I` piece flat against the left wall — it should kick away from the wall instead of refusing to rotate. Try the same with `T`, `S`, `Z`, `J`, `L`. `O` should never change shape.
3. Hard-drop a piece — it lands instantly on the stack, not one row short and not one row into it.
4. Land a piece on the stack, then rapidly move it left and right — it should hover briefly (lock delay), then lock anyway after about 15 nudges rather than hovering forever.
5. Watch the bag readout across ~20 pieces: you should see all seven appear before any repeats, then a fresh set.
6. Fill a bottom row completely — it vanishes. (It'll disappear instantly for now; the animation is Phase 5.)

---

## Phase 2 — Render layer & input

**Goal:** the player can actually drop pieces. Motion is smooth.

- `BoardComponent`, `BlockComponent`, `PieceComponent` + ghost piece.
- Interpolated piece movement — horizontal moves ease over 60 ms, they do not snap between columns.
- `GestureHandler` implementing §1.12, with `InputTuning`.
- Ghost piece rendering, wired to a temporary in-memory toggle (the real Settings row lands in Phase 10).
- Full rows disappear instantly for now (placeholder — animation comes in Phase 5).

**Output:** playable ordinary Tetris on a real device. No rise, no cascade, no score yet.

**What you check:**

1. Play three or four minutes. Does it feel *good*? This is the phase where responsiveness is decided — if input feels mushy here, it will feel mushy forever.
2. Swipe left/right quickly — the piece keeps up with your thumb, no lag, no dropped inputs.
3. Hold a swipe — it moves one column, pauses, then repeats smoothly (DAS/ARR). Tune `InputTuning` now if the pause feels wrong.
4. Watch a piece move sideways closely — it slides between columns, it doesn't teleport.
5. Toggle the ghost piece off and on mid-game — the outline appears/disappears immediately and nothing else changes.
6. Watch for stutter. Anything that isn't buttery here gets worse once particles land in Phase 5.

---

## Phase 3 — Cascade gravity

**Goal:** the middle-row rule from §1.6, animated per §2.2.

- `GravityResolver` interface; implement `ColumnCascade`; stub `StickyGroup` behind a debug flag.
- `BlocksFell` event carrying `(cell, fromRow, toRow)` tuples.
- `FallAnimator`: per-block tweens with real free-fall timing, `easeInQuad`, impact squash, dust puff.
- Chain rescan loop with `chainIndex`.

- **Debug helper:** a "Load Fixture" button on the debug screen that stamps a preset board (tall stack with holes and one nearly-complete middle row) so you can trigger a cascade on demand instead of playing toward one.

**Output:** clearing a middle row visibly drops everything above it, block by block.

**What you check:**

1. Load the fixture, complete the middle row, and watch. **The single most important check in this phase: scan the board afterwards for any block sitting above an empty cell.** There should be none, ever — every block lands on another block or on the floor.
2. Watch a lone block in an otherwise-empty column — it should fall all the way to the bottom, not stop partway.
3. Watch the timing: blocks that fall further should take visibly longer and arrive later. If everything lands at once, the duration isn't distance-based.
4. Look for the squash on impact and the little dust puff.
5. Set up a board where the cascade completes a second row — the chain should fire on its own and clear again.
6. Make a deliberately nasty stack and clear into it repeatedly — the game must never freeze in an endless cascade.

---

## Phase 4 — The rise mechanic

**Goal:** the defining twist, with the continuous animation from §2.1.

- `RiseController`: `riseProgress`, `commitRise()` with remainder carry, `generateRow()` with difficulty-scaled fill.
- `PendingRowComponent` — clipped below the board floor, emerging gradually, fade-in over first 30% of travel.
- Board render offset transform.
- Active-piece carry + push-up + force-lock rules from §1.4.
- Top-out detection → `GameOver` event.
- Warning pulse at row 3.

- **Debug helper:** a rise-speed slider (0.5×–10×) so you can inspect the motion slowly and stress-test it quickly.

**Output:** the actual game. Rows push up from the bottom, you drop pieces to fight them, and you lose when the stack reaches the top.

**What you check:**

1. **Watch one full rise cycle at 0.5× speed with your face close to the screen.** The moment a row finishes arriving is where a one-frame hitch hides — this is the most likely bug in the whole project, caused by resetting `riseProgress` to `0` instead of carrying the remainder. If you see a tiny jump every cycle, that's it.
2. The emerging row should slide out from behind the board's bottom edge gradually and fade in — not pop into existence.
3. Let the stack climb near the top — the warning pulse should appear at row 3.
4. Let it top out — the game should end the instant a block would be pushed above the top row, not a beat late.
5. Leave a piece resting low on the stack and let a row commit underneath it — the piece should get carried up with everything else, not get swallowed or overlap a block.
6. Crank the slider to 10× and let it run — nothing should desync, and the game should end cleanly.
7. Trigger a clear while a row is halfway up — the rise should visibly pause during the cascade, then resume from where it stopped.

---

## Phase 5 — Shatter clear animation

**Goal:** §2.3, exactly.

- `ShatterLayer` with a pooled particle allocator (600 shards pre-allocated).
- Center-out delay scheduling; shard colors resolved per block — theme tint for plain blocks, the type's own palette for specials.
- `RESOLVING` gating: cascade waits for the sequence, particles do not.

- **Debug helper:** a global time-scale slider (0.1×–1×) for inspecting the sequence frame by frame.

**Output:** row clears shatter into falling wooden splinters, spreading outward from the centre.

**What you check:**

1. At 0.1× speed, watch a clear: columns 4 and 5 must shatter **together**, then 3 and 6 together, then 2 and 7, out to the edges. If one side leads the other, the delay formula is using the wrong centre.
2. At normal speed, is the outward spread still readable? It should feel like a ripple, not a single flash.
3. Shards should arc upward slightly before falling, tumble as they fall, fade out, and disappear near the bottom.
4. Temporarily swap the tint in `ThemeDefinition.classicWood` to something garish — plain-block shards should turn garish too. If they stay brown, they're reading a hardcoded color instead of the theme, which will block theme #2 later.
5. Once specials exist (Phase 7), come back and confirm a diamond bursts blue and a stone bursts grey — special shards use their own palette, *not* the theme tint.
6. **Clear four rows at once on your slowest test device.** Watch for a hitch at the moment of impact. Then do it repeatedly for a couple of minutes — if the frame rate degrades over time, the particle pool is leaking instead of recycling.
7. Confirm the blocks above start falling right after the shatter begins — the cascade shouldn't wait for the last shard to land.

---

## Phase 6 — Scoring, combos, difficulty

- `Scoring` with base values, chain/level/booster multipliers.
- Blocks-destroyed banner thresholds and text (`GOOD!` → `UNBELIEVABLE!`), purple accent, pop + fade in the reserved space above the board.
- `Difficulty` interpolation across the §1.10 table, linear between checkpoints.
- Session stats collection (blocks destroyed, max chain, time survived) for achievements later.
- **Debug helper:** an on-screen overlay showing elapsed time, current `dropInterval`, `riseInterval`, `fillRatio`, chain index, and blocks destroyed this resolve.

**Output:** a scoring game with a difficulty curve and combo banners.

**What you check:**

1. Play a full 5-minute run watching the debug overlay. The numbers should slide continuously — if `riseInterval` jumps from 11 to 9 in one frame at the 2:00 mark, it's stepping instead of interpolating.
2. More importantly: play it *without* looking at the overlay. Did you feel a sudden difficulty jump anywhere? You shouldn't.
3. Trigger each of the four banners (`GOOD!` at 5 blocks, up to `UNBELIEVABLE!` at 100) — check the text is correct, purple, centred in the space above the board, and doesn't overlap the board or the top bar.
4. Confirm a cascade chain scores more than the same number of rows cleared separately.
5. Let the run reach 8:00+ and confirm the speed stops increasing rather than becoming impossible.

---

## Phase 7 — Special blocks

- `special_blocks.dart`: behaviour for all nine types per §1.8.
- Ice hit-tracking; Bomb 3×3 detonation feeding back into the clear/cascade loop; Rainbow radius-2 including Stone; Locked/Key pairing; Gold/Diamond/Treasure payouts.
- Spawn weighting in `generateRow()` after the 3-minute mark.
- Render each special using its own complete tile from P.3 — one sprite lookup per cell, no compositing. Plain blocks use the active theme's base tile.
- Per-type shard palettes wired into the Phase 5 shatter.
- **Debug helper:** a block-type picker that stamps any special block onto any cell you tap, so each behaviour can be triggered on demand instead of waiting for a spawn.

**Output:** all nine block types appear in rising rows after the 3-minute mark and behave per §1.8.

**What you check:** stamp each type and trigger it —

1. **Stone** — complete a row containing it. The row must *not* clear. Confirm a Drill or Hammer removes it.
2. **Ice** — complete its row once: the rest of the row clears, the ice stays and looks visibly cracked. Complete it again: it clears.
3. **Bomb** — clear it and confirm the surrounding 3×3 goes with it, and that this can trigger a follow-on clear and bump the chain counter.
4. **Gold** — score jumps by 250.
5. **Diamond** — coin counter goes up by 5.
6. **Treasure** — a reward appears (coins or a booster charge).
7. **Locked / Key** — locked block survives a clear on its own; clears when a key goes in the same resolve.
8. **Rainbow** — wipes everything within 2 cells *including stone*.
9. Then step back and look at a full board: can you tell all nine apart at a glance, at real size, without relying on color? Squint at it.
10. Play past 3:00 in a normal run and confirm specials actually start appearing — and that they arrive at a rate that's interesting rather than overwhelming.

---

## Phase 8 — Boosters

- `BoosterEngine`: arm → target → apply → cascade → clear-check.
- Hammer / Bomb / Drill / Lightning with targeting overlays (highlight the affected cells before commit).
- Charge inventory + consumption.
- Time Freeze and Score Multiplier implemented but not surfaced on the 4-slot HUD.
- **Debug helper:** a "give 99 charges" button.

**Output:** four working boosters on the bottom panel.

**What you check:**

1. Arm each booster — the affected cells should highlight *before* you commit, so you can see what you're about to destroy.
2. Tap somewhere invalid — it disarms cleanly and doesn't consume a charge.
3. Fire each one: Hammer takes exactly one block, Bomb a 3×3, Drill a full column, Lightning a full row.
4. After each, confirm blocks above fall correctly (Phase 3 rules still apply) and that a resulting full row clears.
5. Arm a booster and wait — gravity should pause, but the rise should keep coming. You don't get to stop the clock by hovering.
6. Confirm charges decrement on use and that you can't fire with zero.
7. Try to break it: fire boosters repeatedly into a cascading board and confirm nothing locks up.

---

## Phase 9 — Juice pass

- Audio via `flame_audio`: wood crack, wood fall, rise groan, combo sting, lock click, booster fire, game over, reward.
- Screen shake (hard drop, rise commit, big clear), dust particles, subtle board breathing, coin fly-to-counter.
- Game-over crumble sequence (§1.11).

**Output:** the game with full audio and tactile feedback.

**What you check:**

1. Play with sound on, then with it off. The difference should be obvious — if it isn't, the mix is wrong.
2. Listen specifically for the wood crack on clears. It's the signature sound; it should land at the exact moment the shatter starts, not before or after.
3. Play a 5-minute run and notice whether any sound has started to annoy you. Replace it now.
4. Clear four rows at once — the sting, shake, and shatter should feel like one event, not three.
5. Confirm the rise groan makes you tense up slightly. That's the point.
6. Check the shake is subtle. If it makes text hard to read, halve it.
7. Play a full run and confirm the frame rate is still solid now that audio and effects are layered on.

---

## Phase 10 — UI screens (1:1 ports)

**Goal:** every screen matches its HTML mockup exactly. The mockups are the spec — this is transcription, not redesign.

Port `screens/components.css` → `lib/ui/widgets/` first (primary button, circular icon button, counter pill, panel, progress bar, nav bar). Then, in `screens.md` phase order:

| Source | Flutter target |
|---|---|
| `logo.html` | `studio_logo_screen.dart` — boot screen 1, studio mark |
| `splash.html` | `splash_screen.dart` — boot screen 2, code-drawn logo + drop sequence |
| `main-menu.html` | `main_menu_screen.dart` |
| `gameplay.html` | `gameplay_screen.dart` — HUD overlays on `GameWidget` |
| `pause.html` | `pause_overlay.dart` — dim + blur the live board |
| `game-over.html` | `game_over_overlay.dart` — NEW BEST! badge |
| `daily-reward.html` | `daily_reward_screen.dart` |
| `themes.html` | `themes_screen.dart` |
| `achievements.html` | `achievements_screen.dart` |
| `settings.html` | `settings_screen.dart` |
| `shop.html` | `shop_screen.dart` |

Rules for this phase:

- **No new colors, radii, or spacing.** Everything comes from `tokens.dart`. If a value isn't in tokens, it doesn't belong on screen.
- Gameplay HUD must match `gameplay.html` exactly: coin counter left, score/best center, pause right, board center with combo space reserved above, four booster slots in equal-width bottom slots with charge badges.
- Tap targets ≥ 44×44 (the `screens.md` accessibility audit found and fixed one violation — don't reintroduce it).
- `settings_screen.dart` gets a **Ghost Piece** toggle row alongside Sound and Music, using the same toggle component, defaulting to on and persisted to the profile.

**Output:** the complete app — every screen built and navigable, wrapping the game from Phases 1–9.

**What you check:** open each mockup in a browser at 375×812 next to the running app on a phone, one screen at a time —

1. Same spacing, same corner radii, same font weights, same colors. Look hardest at the gaps between elements; that's where ports usually drift.
2. Repeat at 768×1024 on a tablet.
3. Walk the full navigation: studio logo → splash → main menu → gameplay → pause → resume → game over → play again → home. Then every hub screen via the bottom nav, and back.
   - Cold-boot the app several times and watch the splash sequence closely: the block mark must **accelerate** as it falls, land with a visible squash, *then* the wordmark and loader appear. If the mark drifts down and eases to a stop, the curve is inverted.
   - Confirm the studio logo has no white box around it on the wood background.
   - Confirm the splash never cuts off early on a fast device, and never sits at 100% waiting on a slow one.
4. On the gameplay screen specifically: coin counter left, score/best centre, pause right, four booster slots with charge badges, and the combo banner space reserved above the board so the banner never covers blocks.
5. Pause mid-run — the board behind should dim and blur, and the game should be genuinely frozen (watch the rise, not just the piece).
6. Beat your best score and confirm the NEW BEST! badge appears.
7. Toggle Ghost Piece off in Settings, start a run — no outline. Toggle it on mid-run — the outline appears immediately.
8. Try to tap every button with your thumb, one-handed. Anything you miss twice is too small.

---

## Phase 11 — Persistence, economy, meta

- `StorageService`: high score, coins, unlocked themes, booster inventory, achievement progress, daily-reward streak.
- `EconomyService`: coin earning (runs, combos, diamonds, treasure, achievements, daily) and spending (themes, boosters, continues).
- `AchievementsService`: five achievements, progress-tracked and claimable — the GDD's four block/score/combo goals plus an MVP substitute for "Unlock all themes" (see below).
- `DailyRewardService`: 7-day streak, midnight rollover, streak-break handling. The GDD's Day 3 "Theme Unlock" reward becomes coins or a booster for MVP.
- **Theme system**: build the full `ThemeDefinition` plumbing — palette + block sprite set, read by the render layer, swappable at runtime — but ship **one theme, `classic_wood`, unlocked and equipped by default**. Themes must never require an engine change; the render layer is the only thing that knows a theme exists.
- `themes_screen.dart` renders Classic Wood as equipped, and the remaining eight as **"Coming Soon"** cards (locked state, no coin price, not purchasable). Same layout as `themes.html` — a screen with one card looks broken, and the empty slots communicate that more are coming.
- Correspondingly: the Shop's theme section links to the Themes screen but sells nothing yet, and the "Unlock all themes" achievement from the GDD is **replaced for MVP** — it's meaningless with one theme. Substitute something the MVP can actually deliver, e.g. *"Survive 5 minutes in a single run."*

**Output:** progression that survives app restarts — coins, best score, unlocks, streaks — with Classic Wood equipped.

**What you check:**

1. Earn coins and bump your best score. **Force-quit the app** (swipe it away, don't just background it) and relaunch. Everything should still be there.
2. Open the Themes screen: Classic Wood shows as equipped, the other eight as Coming Soon, and tapping a locked card does nothing (no purchase flow, no error).
3. **The theme-plumbing check:** temporarily add a second `ThemeDefinition` — the same tile with a crude color filter — and equip it. The board, blocks, and shatter particles should all change together, with **zero changes to any file under `engine/`**. If you had to touch the engine, the boundary is wrong and it'll cost you when the real themes land. Delete the test theme afterwards.
4. Spend coins on a booster, then force-quit and relaunch — the charge should still be spent, not refunded.
5. Claim a daily reward, then relaunch — it should stay claimed, and the next day's card shouldn't be claimable yet.
6. Change your device clock forward one day, reopen the app — the next reward unlocks and the streak increments. Set it forward three days instead — the streak should break and reset to Day 1.
7. Play until an achievement completes, claim it, confirm the coins arrive and it can't be claimed twice. Confirm no achievement in the list is unreachable (nothing should still reference unlocking all themes).
8. Check the Day 3 daily reward — the GDD lists it as a Theme Unlock, which the MVP can't grant. It should hand out coins or a booster instead.

---

## Phase 12 — Balance & polish

- Full playtest pass: is the rise fair? Is Stone too punishing without boosters? Does the 3-minute special-block introduction land as interesting rather than unfair?
- Tune **only** `motion.dart` and `difficulty.dart` — resist changing rules to fix feel.
- Target metrics: average first-session run ≈ 90–150 s; skilled run 5+ min; the player should lose to a **mistake**, never to something they couldn't see coming.
- Remove the debug screen and all debug helpers added in Phases 1–8.

**Output:** a balanced, shippable game.

**What you check:**

1. Hand the phone to five people who've never played it. Say nothing. Watch where they get confused, and count how many ask to play again without being prompted.
2. Time their first runs. If most last under 60 seconds, the early game is too harsh; over 4 minutes and there's no pressure.
3. Play ten runs yourself and after each loss ask: *did I lose because I made a mistake, or because the game did something I couldn't have prevented?* The second answer means something needs tuning.
4. Check that Stone doesn't feel like a death sentence when you're out of booster charges.
5. Leave a run going for 10 minutes on your slowest device with the memory profiler open — the line should be flat. A rising line means the particle pool is leaking.
6. Confirm the debug screen is actually gone from the release build.

---

## Phase 13 — Monetization & release

- `AdsService`: rewarded ad for continue, rewarded ad for coins. **No interstitials mid-run** — that violates the "relaxing" pillar.
- IAP: coin packs, Remove Ads, Starter Pack. Cosmetics only — **no pay-to-win**, per the GDD. Boosters must remain fully earnable.
- App icons, store screenshots, privacy policy, build signing (assets from P.9).

**Output:** signed release builds for both platforms.

**What you check:**

1. Install the release build (not debug) on a real device and play a full session. Release builds behave differently — this is where anything that only worked in debug shows up.
2. Watch a rewarded ad for a continue: the run resumes correctly with the bottom 6 rows cleared, and you don't lose your score.
3. Confirm no ad ever interrupts an active run.
4. Make a test purchase of each IAP; force-quit and relaunch to confirm it persisted. Then test Restore Purchases.
5. Play a full run with airplane mode on — no crashes, no hangs waiting on an ad that will never load.
6. Sanity check the promise: could a player who spends nothing reach the same high score as one who spends? If not, something is pay-to-win and needs to change.

---

# 5. Verification Approach

Verification is **manual and hands-on** — you play each phase and confirm it yourself against that phase's "What you check" list. No automated test suite is written. Three things make that practical:

**1. The debug screen.** Introduced in Phase 1 and extended each phase, it's the tool that makes manual checking fast instead of tedious:

| Phase | Adds |
|---|---|
| 1 | ASCII grid view, step-one-tick, manual move/rotate/drop, bag readout |
| 3 | Load-fixture button (preset boards for triggering cascades on demand) |
| 4 | Rise-speed slider (0.5×–10×) |
| 5 | Global time-scale slider (0.1×–1×) |
| 6 | Live overlay: elapsed time, drop/rise interval, fill ratio, chain index |
| 7 | Block-type stamper (place any special block on any cell) |
| 8 | Give-99-charges button |

Removed in Phase 12, before release.

**2. Seeded RNG.** The engine takes an injectable seeded random source, and the debug screen displays and lets you set the seed. When something goes wrong, you re-enter the seed and watch it happen again instead of trying to reproduce it by feel. This is also the prerequisite for a future replay / leaderboard-validation feature.

**3. Slow motion.** Most animation bugs are invisible at 60 fps and obvious at 6. The time-scale slider is how you check the rise commit, the cascade timing, and the shatter ordering.

**The four checks that matter most**, if you're short on time:

```text
Phase 3  →  no block ever rests above an empty cell
Phase 4  →  no stutter at the rise commit boundary (check at 0.5×)
Phase 5  →  4-line clear on the slowest device without a frame hitch
Phase 10 →  each screen side by side with its .html mockup
```

Everything else is recoverable later. These four are structural.

---

# 6. Decisions Already Made (and why)

| Decision | Choice | Rationale |
|---|---|---|
| Board size | 10 × 20 | Tetris-standard; fits portrait `375×812` cleanly. |
| Gravity resolver | `ColumnCascade` default | Produces more chains and reads more clearly in motion than sticky groups. `StickyGroup` stays implemented behind a flag for play-testing. |
| Rotation | SRS + wall kicks | Players carry muscle memory from other stackers; deviating feels broken. |
| Randomizer | 7-bag | Eliminates drought frustration — important when a timer is already applying pressure. |
| Hold piece | Deferred | The rise mechanic already supplies the pressure Hold would relieve; adding both dilutes the twist. |
| Rise during piece fall | Not frozen | Overlapping the two pressures *is* the game. Freezing it would make the game a slower Tetris. |
| Rise during resolve | Frozen | Otherwise the player is punished for a good clear. |
| Specials in rising rows only | Yes | Keeps the player's own tools predictable; the threat evolves instead. |
| Combo thresholds | Blocks destroyed, per GDD | Preserves the GDD's four banner tiers verbatim. |
| Particle system | Pooled, single layer | A 4-line clear is ~500 particles; per-frame allocation would cause GC hitches. |
| Special blocks | **Complete shared tiles**, not overlays on the theme tile | Identical asset count either way, so cost doesn't decide it. Shared tiles keep gameplay-critical blocks looking the same in every theme (one vocabulary, learned once), avoid contrast-checking 8 glyphs against 9 backgrounds, and let a block break the square silhouette — translucent ice, glowing rainbow. `ThemeDefinition` keeps an optional per-type override map for the rare case a future theme wants its own. |
| Game logo | **Code-drawn, not an image** | `splash.html` already builds it from block cells so it sits flush on the wood grain with no halo to mask. Also means it scales to any density, recolors with the theme, and can animate its own drop-and-squash. The studio logo (screen 1) stays an image. |
| Themes at MVP | **One — `classic_wood`** | Ships the game sooner. The full `ThemeDefinition` plumbing is still built in Phase 11, so each later theme costs one PNG, one palette, and no code. The Themes screen shows the other eight as "Coming Soon" rather than hiding them. |

## Open questions for playtest (Phase 12)

1. Does `ColumnCascade` make clears *too* easy once the stack is tall? If runs stretch past 15 minutes, consider a "sticky above the clear line" hybrid.
2. Is Stone fair before the player has booster charges? Possible fix: guarantee at least one Rainbow within N rows of any Stone spawn.
3. Should hard drop grant brief rise immunity (~200 ms)? It would reward aggressive play but might trivialize the pressure.
4. Is the 4-booster HUD enough, or does Time Freeze deserve a 5th slot? (`screens.md` Phase 11 fixes the count at 4 and flags the Stopwatch icon as an intentional gap — revisit here, and update the mockup if the answer changes.)

---

**Next step:** Phase P. Gather the assets — fonts, the studio logo (transparent, no white box), the single `classic_wood` tile, the nine shared special-block tiles, the wood background, the extracted icons, and the SFX list. The game logo needs nothing gathered; it's built in Phase 10. Then Phase 0: dependencies, portrait lock, `tokens.css` → `tokens.dart`, empty 10×20 board on screen.
