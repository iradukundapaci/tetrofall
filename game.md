# Tetrofall — Game Build Plan (Flutter + Flame)

Companion to `screens.md`. That document defines the **UI**; this one defines the **game** — mechanics, animation, architecture, and the phased build order.

Rule of precedence: **mechanics ship before UI polish.** Phases 1–7 are the game. Phase 8 ports the HTML mockups 1:1. Nothing in Phase 8+ may alter a rule defined in Section 1.

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
```

**Rise pausing.** The rise timer is frozen during `RESOLVING` (clear + cascade). It is *not* frozen while a piece is merely falling — the two pressures must overlap.

## 1.5 Line clear

After a lock (or after any cascade settle), scan for full rows.

- A row is full when all `COLS` cells are occupied.
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
```

## 1.8 Difficulty timeline

| Elapsed | dropInterval | riseInterval | fillRatio | Notes |
|---|---|---|---|---|
| 0:00 | 800 ms | 14 s | 0.40 | gaps clustered, tutorial-easy |
| 1:00 | 700 ms | 11 s | 0.50 | denser rows |
| 2:00 | 600 ms | 9 s | 0.60 | gaps scattered, harder patterns |
| 3:00 | 480 ms | 7 s | 0.65 | gaps fully scattered |
| 5:00 | 320 ms | 5 s | 0.70 | fast phase |
| 8:00+ | 200 ms (floor) | 4 s (floor) | 0.75 (cap) | endurance plateau |

Interpolate **linearly between checkpoints** — never step. The player should never feel a discrete jolt of difficulty.

## 1.9 Game over

Triggered by:

1. **Top-out** — `commitRise()` would push a settled block above row 0.
2. **Block-out** — a newly spawned piece overlaps settled blocks.

Sequence: freeze board → desaturate → blocks crumble top-to-bottom (400ms) → `game-over.html` overlay with score, best, Watch-Ad-To-Continue. Continue clears the spawn buffer, then wipes the board in two stages: rows fill in bottom-to-top until it's completely full, hold a beat, then rows clear top-to-bottom — one row per step, each firing the standard per-row shatter effect. None of it is scored — the player keeps exactly the score they had — and the run resumes at the current difficulty on a clean board.

## 1.10 Controls

| Input | Action |
|---|---|
| Swipe left / right | Move one column (hold to auto-repeat: DAS 170 ms, ARR 50 ms) |
| Tap (board) | Rotate clockwise |
| Two-finger tap | Rotate counter-clockwise |
| Swipe down (short) | Soft drop |
| Swipe down (fast/long) | Hard drop |
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
color         active theme's tint
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

Communication is one-way plus events: UI/render **reads** engine state and **sends** intents (`MoveLeft`, `Rotate`, `HardDrop`); the engine emits domain events (`RowsCleared`, `RiseCommitted`, `BlocksFell`, `GameOver`) that the render layer turns into animation.

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
      difficulty.dart            the §1.8 timeline
    engine/                      ← PURE DART, NO FLAME
      grid.dart
      cell.dart                  block type + state
      tetromino.dart             shapes, SRS kicks, 7-bag
      piece_controller.dart      move/rotate/lock/lock-delay
      rise_controller.dart       riseProgress, commitRise, generateRow
      gravity_resolver.dart      GravityResolver interface
        column_cascade.dart      ← default
        sticky_group.dart        ← alternate, debug-swappable
      clear_detector.dart
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
      splash_screen.dart         boot screen 1 — code-drawn game logo
      loading_screen.dart        boot screen 2 — asset/save preload progress bar
      main_menu_screen.dart
      gameplay_screen.dart       hosts GameWidget + HUD overlays
      pause_overlay.dart
      game_over_overlay.dart
      settings_screen.dart
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
    storage_service.dart         high score, settings
    audio_service.dart
    ads_service.dart             stubbed until Phase 11

  models/
    player_profile.dart
    theme_definition.dart

  debug/
    debug_screen.dart            ASCII grid, steppers, sliders, stampers
    debug_fixtures.dart          preset boards for triggering cascades
    debug_flags.dart             single kill-switch, stripped in Phase 10

assets/
  fonts/                         Baloo2-*.ttf, Nunito-*.ttf
  images/
    blocks/                      tile_<theme>.png
    textures/                    bg_wood.png  (frame is canvas-drawn, no asset)
    icons/                       SVGs extracted from screens/*.html
                                 (game logo is code-drawn — no asset)
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

   PAUSED is an orthogonal sub-state that suspends both gravity
   and the rise.
```

## 3.4 Frame tick order

Order matters. Getting it wrong produces one-frame visual desyncs.

```text
1. drain input intents          (move / rotate / drop)
2. advance difficulty clock
3. tick rise                    (skip if RESOLVING / PAUSED)
4. tick gravity + lock delay    (skip if RESOLVING / PAUSED)
5. run engine transitions       (lock, clear detect, cascade, chain)
6. flush domain events → render layer
7. advance render tweens        (falls, squash, shake)
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

Gather everything here *first*. Nothing below blocks engine work, but a missing texture halfway through Phase 5 stalls the fun part, and audio missing at Phase 7 means re-tuning animation timing after the fact.

**Where things go:**

```text
assets/
  fonts/          Baloo2-*.ttf, Nunito-*.ttf
  images/
    blocks/       base tile per theme
    textures/     backgrounds, board frame
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
| **Baloo 2** (display: scores, titles) | 500, 600, 700, 800 | `Baloo2-Medium.ttf`, `-SemiBold`, `-Bold`, `-ExtraBold` |
| **Nunito** (body: buttons, labels) | 400, 600, 700, 800 | `Nunito-Regular.ttf`, `-SemiBold`, `-Bold`, `-ExtraBold` |

Source: fonts.google.com → "Get font" → extract the static `.ttf` files (not variable fonts — Flutter handles static weights more predictably). Both are Open Font License, so commercial release is fine.

---

### P.2 — Logo & brand

Boot flow is **two screens**, in this order:

```text
1. Splash screen    →  the Tetrofall game logo. NO IMAGE — built in code.
2. Loading screen   →  progress bar while assets/save data finish loading.
```

There is no separate studio-logo screen — the splash screen is the game's only branded boot moment, and it hands off directly to the loading screen, then the main menu.

---

#### Screen 1 — Splash screen (no asset — drawn in code)

`splash.html` already builds the Tetrofall mark out of CSS block cells rather than a raster, specifically so it sits flush on the wood grain with no halo to mask out. **Port that behaviour directly.** There is no `logo_full.png`, no `game-logo.png`, no studio-logo asset — the mark is widgets and canvas.

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
| 550 ms | **Land.** Squash keyframes over 400 ms: `scaleY` 1 → 0.7 → 1.1 → 0.96 → 1, with `scaleX` inverse. Wordmark fades in and rises 6px. |
| 950 ms | Hold. |
| 1350 ms | Whole stage fades out over 400 ms, handing off to the loading screen. |

The falling mark uses an **ease-in** curve, not ease-out — it's a tetromino under gravity, and it must accelerate. Getting this backwards makes the whole thing feel floaty and wrong.

**Supporting detail:** 14 dust particles, 4px gold circles, drifting upward ~820px with ±20px horizontal drift, 4–8s durations and 0–6s staggered delays, opacity ramping 0 → 0.7 → 0.4 → 0.

**Where this lives:** `lib/ui/widgets/logo_mark.dart` (block mark) and `logo_wordmark.dart` (gradient text), so the main menu can reuse both at a smaller scale instead of re-implementing them.

---

#### Screen 2 — Loading screen

Follows the splash immediately. Plain wood background, the block mark and wordmark held at small scale near the top (reuses `logo_mark.dart` / `logo_wordmark.dart`), and a progress bar below.

| Property | Value |
|---|---|
| Loader bar | `min(55vw, 220px)` wide |
| Label | Uppercase muted "LOADING…", Nunito 700, tracking `0.04em` |
| Fill animation | `cubic-bezier(0.3, 0.6, 0.3, 1)` |

**Real loading vs. the animation:** drive the bar from actual asset preloading and save-data restore, but enforce a **minimum 1.5s** so the screen never flashes. Never cut it short because assets happened to load fast — and never leave the player staring at a full bar because they didn't.

**Handoff:** once the bar completes, fade out over 400 ms into the main menu.

---

### P.3 — Block sprites

> **MVP scope: one theme — `classic_wood`.** Post-MVP themes each cost a single PNG and zero code. Build the seam now; don't fill it yet.

One base tile per theme is all that's needed — plain wood blocks only, no special-block variants. MVP needs exactly one file; at nine themes it's nine — one PNG per theme, never more.

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

### P.5 — Icons ✅ DONE

**No generation was needed** — every icon already existed as inline `<svg>` inside the mockups. Extracting rather than redrawing means the Flutter build matches the design by construction.

**Delivered:**

```text
tools/extract_icons.py             re-runnable extractor
tools/ICONS.md                     full inventory, variants, deviations, gaps
tools/icon_contact_sheet.png       all 38 files rendered for eyeballing
assets/images/icons/*.svg          35 UI icons
assets/images/icons/blocks-reference/   3 files, drawing reference only
lib/ui/theme/app_icons.dart        generated const paths + multicolor set
pubspec.yaml                       flutter_svg dep + assets/images/icons/
```

**How it works.** The mockups let CSS supply `fill` / `stroke` / `stroke-width`, and those don't travel with an extracted file, so the script bakes them in. It groups by **path geometry rather than markup**, which collapses state variants (gold medal vs. muted outline medal) into one file — 60 raw `<svg>` blocks → 41 shapes → 35 files. `var(--color-gold)` is resolved to literal hex, since CSS custom properties don't resolve in Flutter either.

Monochrome icons emit `currentColor` and tint at the call site:

```dart
SvgPicture.asset(AppIcons.hammer, width: 22,
  colorFilter: ColorFilter.mode(Tokens.text, BlendMode.srcIn));
```

**One is deliberately multicolor** — `medal` — and must render *without* a `colorFilter` or it flattens to a silhouette. `AppIcons.multicolor` holds that set.

**One deliberate deviation:** `trophy` is stroked, not filled. `main-menu.html` sets `fill: gold`, but its stem and base are zero-area line paths that render as nothing under fill — the mockup's trophy is a cup with no stem. The extracted file strokes it, which is what the drawing intends. Everything else is a faithful port.

**Gaps:** no standalone `play` glyph (PLAY is a text button; the only play triangle lives inside `video`), and `restart` is text-only by design.

**If the mockups change,** edit the HTML and re-run `python3 tools/extract_icons.py` — never hand-edit the SVGs, or the two will drift.

---

### P.6 — Particles

**Nothing to gather.** The shatter shards (§2.3) are drawn procedurally as small rounded rectangles tinted from the block's own palette. This is deliberate: procedural shards inherit theme colors for free, and pooling raw shapes is far cheaper than pooling textured sprites at ~500 particles per 4-line clear.

Optional upgrade later: 4 hand-drawn splinter silhouettes (`shard_01..04.png`, 64×64, transparent) used as alpha masks so the tint still applies.

---

### P.7 — Audio (source or commission)

**Formats:** SFX as `.wav`, 44.1 kHz, 16-bit, **mono** — short files with no decode latency, which matters because a lock click that arrives 80 ms late feels broken. Music as `.mp3`, 128 kbps, stereo.

Keep every SFX under 1 second unless noted. Either generate them (prompts below), pull from a CC0/royalty-free library, or commission a pack — but don't mix approaches per-sound, or the set won't cohere.

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
| `button.wav` | Soft UI tap | 0.08 s |
| `game_over.wav` | Descending wooden collapse | 1.5 s |

**Music:**

| File | Description |
|---|---|
| `menu_loop.mp3` | Calm acoustic — soft guitar/marimba, warm, unhurried. 60–90 s seamless loop. |
| `game_loop.mp3` | Relaxing but with forward motion; light percussion. 90–120 s seamless loop. |
| `game_loop_intense.mp3` | *Optional.* Same key/tempo as `game_loop`, denser instrumentation — crossfade in when the stack nears the top. |

Both loops must be **seam-checked**: play on repeat for two minutes and listen for the click at the loop point.

---

#### Generation prompts

For any text-to-sound-effect generator. Three rules run through all of them:

1. **Everything is wood.** The whole palette should sound like it came off one physical object — dry seasoned timber. That coherence is what makes a sound set feel designed rather than assembled.
2. **Always say "dry, close mic, no reverb, no music, no room tone."** A reverb tail baked into a sound that plays 500 times an hour turns the mix to mud, and you can't remove it later.
3. **Generate 3–5 takes of each and pick.** These are cheap to regenerate and expensive to live with.

**Piece handling** — these fire constantly, so they must be small and unobtrusive:

> `lock` — "A single short dry wooden click, like a small oak block being set firmly down onto a thick wooden table. Very close mic, tight and percussive, fast decay, no reverb, no music, no room tone. 0.1 seconds."

> `move` — "An extremely quiet tiny wooden tick, a fingernail tapping once on a hollow wooden box. Barely audible, dry, close mic, no reverb, no music. 0.05 seconds."

> `rotate` — "A soft muted wooden pivot, a wooden peg turning once inside a snug wooden socket, a short low friction creak. Dry, close mic, no reverb, no music. 0.08 seconds."

> `hard_drop` — "A heavy wooden thud, a solid oak block dropped from height onto a thick wooden board, brief low-end impact with a fast decay and a hint of air movement. Dry, close mic, no reverb tail, no music. 0.3 seconds."

**The core loop** — `wood_crack` is the signature sound of the game; spend the most takes here:

> `wood_crack` — "A dry timber snap: a thin piece of seasoned oak splintering and breaking cleanly in one sharp crack, with a scatter of tiny wood fragments in the tail. Crisp and satisfying, close mic, no reverb, no music. 0.4 seconds."

> `wood_fall` — "Hollow wooden knocks: two or three wooden blocks tumbling a short distance and landing on a wooden surface. Warm and hollow, dry, close mic, no reverb, no music. 0.25 seconds."

> `rise_groan` — "A low wooden strain: a thick timber beam slowly taking on weight, a deep slow creak with a subtle groan underneath. Ominous but soft, dry, close mic, no music. 0.5 seconds."

> `rise_warning` — "A tense sustained wooden creak, old timber under steadily increasing pressure, straining slowly. Uneasy, continuous, with no obvious start or end so it loops seamlessly. Dry, no music, no percussion. 1 second."

**UI & feedback:**

> `button` — "A soft muted wooden tap, a fingertip pressing a small wooden button once. Gentle and warm, dry, very short, no reverb, no music. 0.08 seconds."

> `game_over` — "A wooden collapse: a stack of wooden blocks tumbling down and settling into stillness, ending on a low descending wooden tone. Deflating but gentle, not harsh or comedic. Dry, close mic, no music. 1.5 seconds."

**Music** — worth knowing that generators are consistently weak at seamless loops. Generate ~30 seconds longer than you need, then cut the loop point yourself on a zero-crossing in an audio editor:

> `menu_loop` — "Calm relaxing acoustic instrumental. Soft nylon-string guitar and warm marimba, gentle and unhurried, around 70 BPM, major key. No drums, no vocals, no build, no climax. Cozy and welcoming background music for a wooden puzzle game menu. 90 seconds."

> `game_loop` — "Relaxing but forward-moving acoustic instrumental. Warm marimba with light hand percussion, steady gentle pulse around 95 BPM, major key. No vocals, no dramatic build, no attention-grabbing melody — designed to sit under gameplay for long stretches without becoming tiring. 120 seconds."

> `game_loop_intense` — "Warm marimba puzzle-game instrumental at 95 BPM in a major key, same instrumentation as a calm version but denser: added low wooden percussion, faster subdivisions, subtle underlying tension. No vocals, no climax, no orchestral swell. 120 seconds."

#### Post-processing

Generated audio arrives at inconsistent levels, in stereo, with leading silence — all three are problems. **Leading silence matters most:** a `lock` sound with 40 ms of padding makes the whole game feel laggy no matter how tight the code is.

```bash
# one-shots: trim leading silence, mono, 44.1k, 16-bit, peak-normalize
for f in raw/*.wav; do
  ffmpeg -i "$f" -af "silenceremove=start_periods=1:start_threshold=-50dB,\
loudnorm=I=-16:TP=-1.5,aformat=s16:44100" -ac 1 "assets/audio/sfx/$(basename $f)"
done
```

Then pull `move`, `lock`, and `rotate` down another 6 dB by hand. They fire many times per second, and anything mixed to sit comfortably on a single play becomes exhausting at speed.

---

### P.8 — Theme palette (data, not files)

**MVP: one palette, `classic_wood`** — and it's already written. `tokens.css` *is* the classic wood palette, so `ThemeDefinition.classicWood` reads its values straight from `tokens.dart` rather than defining new ones.

Fields: `background`, `boardBg`, `frameLight`, `frameDark`, `gridLine`, `blockTint`, `text`, `accent`. The frame colors are here rather than in an image because the frame is canvas-drawn (P.4). Nothing to gather.

The one thing that matters here: **define the `ThemeDefinition` type properly even though there's only one instance of it.** Every color the board renders must come from the active `ThemeDefinition`, never from a `tokens.dart` constant read directly by a render component. Skip that and adding theme #2 later means auditing every draw call.

---

### P.9 — Store & launch assets (needed at Phase 11, gather early if convenient)

| Asset | Format | Size |
|---|---|---|
| App icon | PNG, no alpha, no rounded corners | 1024×1024 |
| Android adaptive icon | Foreground PNG w/ alpha + background color | 432×432 foreground, safe zone centre 66% |
| Native splash | PNG, transparent | 512×512 mark on `--color-bg` |
| Feature graphic (Play Store) | PNG/JPG | 1024×500 |
| Screenshots | PNG | 6 per platform, portrait, from real gameplay |

**The app icon and native splash still need rasters** — the OS can't render a Flutter widget before the app starts. Don't redraw the mark by hand: run the app with the logo mark scaled up on a transparent background, screenshot it at high resolution, and export from that. The store icon and the in-app splash then show the same object, which is the whole point of having a mark.

Note the native splash (the OS-level one, shown before Flutter boots) is a **third** thing, distinct from the splash and loading screens in P.2. Keep it minimal — just the mark on `--color-bg` — so the handoff into the in-app splash screen isn't jarring.

---

**Output of Phase P:** a populated `assets/` tree and a `pubspec.yaml` that registers every file.

**What you check:**

1. `flutter pub get` runs clean with no missing-asset warnings.
2. Tile `tile_classic_wood.png` across a full 10×20 grid on a scratch screen. It's the only tile in the MVP, so it has to hold up repeated 200 times — check for grain that turns into noise, or a highlight that creates a visible repeating pattern across the board.
3. Play each SFX once. Anything that makes you wince now will make you wince 500 times an hour later.
4. Loop both music tracks for two minutes each and listen for the seam.

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
- **Debug screen** (reachable by a long-press on the board, kept until Phase 10): renders the grid as ASCII text, plus buttons for Step-One-Tick, Move L/R, Rotate CW/CCW, Hard Drop, and a readout of current phase / piece / bag contents.

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
- `GestureHandler` implementing §1.10, with `InputTuning`.
- Ghost piece rendering, wired to a temporary in-memory toggle (the real Settings row lands in Phase 8).
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
5. **Clear four rows at once on your slowest test device.** Watch for a hitch at the moment of impact. Then do it repeatedly for a couple of minutes — if the frame rate degrades over time, the particle pool is leaking instead of recycling.
6. Confirm the blocks above start falling right after the shatter begins — the cascade shouldn't wait for the last shard to land.

---

## Phase 6 — Scoring, combos, difficulty

- `Scoring` with base values, chain/level multipliers.
- `Difficulty` interpolation across the §1.8 table, linear between checkpoints.
- Session stats collection (blocks destroyed, max chain, time survived) for achievements later.
- **Debug helper:** an on-screen overlay showing elapsed time, current `dropInterval`, `riseInterval`, `fillRatio`, chain index, and blocks destroyed this resolve.

**Output:** a scoring game with a difficulty curve.

**What you check:**

1. Play a full 5-minute run watching the debug overlay. The numbers should slide continuously — if `riseInterval` jumps from 11 to 9 in one frame at the 2:00 mark, it's stepping instead of interpolating.
2. More importantly: play it *without* looking at the overlay. Did you feel a sudden difficulty jump anywhere? You shouldn't.
3. Confirm a cascade chain scores more than the same number of rows cleared separately.
4. Let the run reach 8:00+ and confirm the speed stops increasing rather than becoming impossible.

---

## Phase 7 — Juice pass

- Audio via `flame_audio`: wood crack, wood fall, rise groan, lock click, game over.
- Screen shake (hard drop, rise commit, big clear), dust particles, subtle board breathing.
- Game-over crumble sequence (§1.9).

**Output:** the game with full audio and tactile feedback.

**What you check:**

1. Play with sound on, then with it off. The difference should be obvious — if it isn't, the mix is wrong.
2. Listen specifically for the wood crack on clears. It's the signature sound; it should land at the exact moment the shatter starts, not before or after.
3. Play a 5-minute run and notice whether any sound has started to annoy you. Replace it now.
4. Clear four rows at once — the shake and shatter should feel like one event, not two.
5. Confirm the rise groan makes you tense up slightly. That's the point.
6. Check the shake is subtle. If it makes text hard to read, halve it.
7. Play a full run and confirm the frame rate is still solid now that audio and effects are layered on.

---

## Phase 8 — UI screens (1:1 ports)

**Goal:** every screen matches its HTML mockup exactly. The mockups are the spec — this is transcription, not redesign.

Port `screens/components.css` → `lib/ui/widgets/` first (primary button, circular icon button, counter pill, panel, progress bar, nav bar). Then, in `screens.md` phase order:

| Source | Flutter target |
|---|---|
| `splash.html` | `splash_screen.dart` — boot screen 1, code-drawn logo + drop sequence |
| `loading.html` | `loading_screen.dart` — boot screen 2, progress bar |
| `main-menu.html` | `main_menu_screen.dart` |
| `gameplay.html` | `gameplay_screen.dart` — HUD overlays on `GameWidget` |
| `pause.html` | `pause_overlay.dart` — dim + blur the live board |
| `game-over.html` | `game_over_overlay.dart` — NEW BEST! badge |
| `settings.html` | `settings_screen.dart` |

Rules for this phase:

- **No new colors, radii, or spacing.** Everything comes from `tokens.dart`. If a value isn't in tokens, it doesn't belong on screen.
- Gameplay HUD must match `gameplay.html` exactly: score/best left, pause right, board center, and the ad banner slot reserved below the board.
- Tap targets ≥ 44×44 (the `screens.md` accessibility audit found and fixed one violation — don't reintroduce it).
- `settings_screen.dart` gets a **Ghost Piece** toggle row alongside Sound and Music, using the same toggle component, defaulting to on and persisted to the profile.

**Output:** the complete app — every screen built and navigable, wrapping the game from Phases 1–7.

**What you check:** open each mockup in a browser at 375×812 next to the running app on a phone, one screen at a time —

1. Same spacing, same corner radii, same font weights, same colors. Look hardest at the gaps between elements; that's where ports usually drift.
2. Repeat at 768×1024 on a tablet.
3. Walk the full navigation: splash → loading → main menu → gameplay → pause → resume → game over → play again → home.
   - Cold-boot the app several times and watch the splash sequence closely: the block mark must **accelerate** as it falls, land with a visible squash, *then* the wordmark appears. If the mark drifts down and eases to a stop, the curve is inverted.
   - Confirm the loading screen never cuts off early on a fast device, and never sits at 100% waiting on a slow one.
4. On the gameplay screen specifically: score/best left, pause right, and the ad banner slot reserved below the board.
5. Pause mid-run — the board behind should dim and blur, and the game should be genuinely frozen (watch the rise, not just the piece).
6. Beat your best score and confirm the NEW BEST! badge appears.
7. Toggle Ghost Piece off in Settings, start a run — no outline. Toggle it on mid-run — the outline appears immediately.
8. Try to tap every button with your thumb, one-handed. Anything you miss twice is too small.

---

## Phase 9 — Persistence & settings

- `StorageService`: high score and player settings (sound, music, vibrate, Ghost Piece).
- **Theme system**: build the `ThemeDefinition` plumbing — palette + block sprite set, read by the render layer — but ship **one theme, `classic_wood`, equipped by default**. Themes must never require an engine change; the render layer is the only thing that knows a theme exists. There is no in-app theme browser in MVP; the architecture just keeps a future theme cheap to add (one PNG, one palette, no code).

**Output:** progression that survives app restarts — best score and settings — with Classic Wood equipped.

**What you check:**

1. Set your best score and adjust a setting (e.g. turn music off). **Force-quit the app** (swipe it away, don't just background it) and relaunch. Both should still be there.
2. **The theme-plumbing check:** temporarily add a second `ThemeDefinition` — the same tile with a crude color filter — and equip it. The board, blocks, and shatter particles should all change together, with **zero changes to any file under `engine/`**. If you had to touch the engine, the boundary is wrong and it'll cost you when the real themes land. Delete the test theme afterwards.

---

## Phase 10 — Balance & polish

- Full playtest pass: is the rise fair? Does the difficulty ramp land as interesting rather than unfair?
- Tune **only** `motion.dart` and `difficulty.dart` — resist changing rules to fix feel.
- Target metrics: average first-session run ≈ 90–150 s; skilled run 5+ min; the player should lose to a **mistake**, never to something they couldn't see coming.
- Remove the debug screen and all debug helpers added in Phases 1–6.

**Output:** a balanced, shippable game.

**What you check:**

1. Hand the phone to five people who've never played it. Say nothing. Watch where they get confused, and count how many ask to play again without being prompted.
2. Time their first runs. If most last under 60 seconds, the early game is too harsh; over 4 minutes and there's no pressure.
3. Play ten runs yourself and after each loss ask: *did I lose because I made a mistake, or because the game did something I couldn't have prevented?* The second answer means something needs tuning.
4. Leave a run going for 10 minutes on your slowest device with the memory profiler open — the line should be flat. A rising line means the particle pool is leaking.
5. Confirm the debug screen is actually gone from the release build.

---

## Phase 11 — Monetization & release

- `AdsService`: a fixed banner slot below the board on `gameplay.html`/`pause.html`, plus a rewarded ad for continue. **No interstitials mid-run** — that violates the "relaxing" pillar.
- IAP: **Remove Ads** — a single non-consumable purchase that hides the banner and skips the rewarded-continue ad prompt. No coins, no cosmetics, no other SKUs at MVP.
- App icons, store screenshots, privacy policy, build signing (assets from P.9).

**Output:** signed release builds for both platforms.

**What you check:**

1. Install the release build (not debug) on a real device and play a full session. Release builds behave differently — this is where anything that only worked in debug shows up.
2. Confirm the banner slot below the board loads correctly and never overlaps the board or HUD.
3. Watch a rewarded ad for a continue: the run resumes correctly with the whole board cleared, and your score is exactly what it was (the forced clear doesn't add to it).
4. Confirm no ad ever interrupts an active run.
5. Purchase Remove Ads; force-quit and relaunch to confirm the banner stays hidden and the continue prompt no longer offers an ad. Then test Restore Purchases.
6. Play a full run with airplane mode on — no crashes, no hangs waiting on an ad that will never load.

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

Removed in Phase 10, before release.

**2. Seeded RNG.** The engine takes an injectable seeded random source, and the debug screen displays and lets you set the seed. When something goes wrong, you re-enter the seed and watch it happen again instead of trying to reproduce it by feel. This is also the prerequisite for a future replay / leaderboard-validation feature.

**3. Slow motion.** Most animation bugs are invisible at 60 fps and obvious at 6. The time-scale slider is how you check the rise commit, the cascade timing, and the shatter ordering.

**The four checks that matter most**, if you're short on time:

```text
Phase 3  →  no block ever rests above an empty cell
Phase 4  →  no stutter at the rise commit boundary (check at 0.5×)
Phase 5  →  4-line clear on the slowest device without a frame hitch
Phase 8  →  each screen side by side with its .html mockup
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
| Particle system | Pooled, single layer | A 4-line clear is ~500 particles; per-frame allocation would cause GC hitches. |
| Game logo | **Code-drawn, not an image** | `splash.html` already builds it from block cells so it sits flush on the wood grain with no halo to mask. Also means it scales to any density, recolors with the theme, and can animate its own drop-and-squash. There is no separate studio-logo image asset. |
| Themes at MVP | **One — `classic_wood`** | Ships the game sooner. The full `ThemeDefinition` plumbing is still built in Phase 9, so each later theme costs one PNG, one palette, and no code, even though MVP has no in-app theme browser. |

## Open questions for playtest (Phase 10)

1. Does `ColumnCascade` make clears *too* easy once the stack is tall? If runs stretch past 15 minutes, consider a "sticky above the clear line" hybrid.
2. Should hard drop grant brief rise immunity (~200 ms)? It would reward aggressive play but might trivialize the pressure.

---

**Next step:** Phase P. Gather the assets — fonts, the single `classic_wood` tile, the wood background, the extracted icons, and the SFX list. The game logo needs nothing gathered; it's built in Phase 8. Then Phase 0: dependencies, portrait lock, `tokens.css` → `tokens.dart`, empty 10×20 board on screen.
