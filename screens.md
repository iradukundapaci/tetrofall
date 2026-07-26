# Tetrofall — UI Screens Guide (HTML Build Phases)

This guide breaks the Tetrofall UI into phases for building static HTML/CSS mockups of every screen. Each phase produces one or more `.html` files. Build in order — later screens reuse tokens and components from earlier phases.

## Core Mechanic

Tetrofall inverts classic Tetris: the stack of blocks rises from the bottom of the board toward the top, growing on its own over time. Falling tetrominoes drop from above and are placed by the player to complete rows/shapes within that rising stack. Completed sections clear, which removes material and buys time — the goal is to keep clearing fast enough that the rising stack never reaches the top of the board (which ends the game).

Recommended file structure:

```text
/screens
  /assets
    /fonts
    /icons
    /textures
    logo.svg
  tokens.css
  components.css
  logo.html
  splash.html
  main-menu.html
  gameplay.html
  pause.html
  game-over.html
  daily-reward.html
  themes.html
  achievements.html
  shop.html
```

---

## Phase 0 — Design Tokens & Base Setup

Before building any screen, define the shared visual language in `tokens.css`.

Colors:

```css
--color-wood-dark: #4a2f1c;
--color-wood-mid: #7a5230;
--color-wood-light: #c89b6a;
--color-bg: #2b1c12;
--color-panel: rgba(255,255,255,0.06);
--color-gold: #f2b632;
--color-red: #d9432e;
--color-blue: #3aa0d9;
--color-purple: #9b5cd6;
--color-green: #4caf6b;
--color-text: #f5ead9;
--color-text-muted: #b9a889;
```

Typography: one rounded/soft display font for scores and titles, one clean sans for body text and buttons.

Shadows and shape: soft drop shadows (`0 4px 12px rgba(0,0,0,0.35)`), large corner radii (16–24px) on panels and buttons, subtle wood-grain texture as background fill.

Base components to define once in `components.css` and reuse everywhere: primary button, icon button (circular), counter pill (icon + number, used for coins/score), modal/panel container, progress bar.

Verification: open `tokens.css` alone against a blank page and confirm colors/fonts render — this is the palette every later screen inherits.

---

## Device Frame & Orientation (Phase 1 onward)

From Phase 1 on, every screen renders inside a shared device-frame instead of stretching full-bleed to the browser window — this keeps every mockup honest about real on-device proportions.

```text
.device-frame            – mobile portrait, 375×812 (default)
.device-frame.is-tablet  – tablet portrait, 768×1024 (toggled)
.device-toggle           – small Mobile/Tablet pill switcher above the frame
```

Build notes: define `.device-stage`, `.device-toggle`, `.device-frame`, and `.device-frame__screen` once in `components.css` (Phase 0) and wrap every phase's existing screen markup in `.device-frame > .device-frame__screen`. The toggle just adds/removes the `is-tablet` class on the frame — no separate tablet HTML file needed. Orientation is locked to upright/portrait only: there is no landscape variant, and the frame keeps its portrait width/height regardless of how wide the actual browser window is — it sits centered, letterboxed, on wider viewports rather than rotating or reflowing.

---

## Phase 1 — Logo Screen (`logo.html`)

Purpose: standalone brand moment showing the Tetrofall mark on its own, decoupled from load-progress logic — useful for app-icon/store-asset preview and as the static reference every other screen's header logo pulls from.

Layout:

```text
Full-bleed wood-texture background (or solid --color-bg)
Centered `assets/logo.svg`, scaled responsively (clamp width, preserve aspect ratio)
No UI chrome, no text, no buttons
```

Build notes: import the actual `assets/logo.svg` file rather than redrawing it — copy it into `/screens/assets/logo.svg` so the mockup renders the real asset. Center it with flex/grid, cap its max-width (e.g. `min(60vw, 320px)`) so it scales cleanly across phone and tablet aspect ratios. This screen has no transition logic of its own; Phase 2's splash screen reuses this same logo markup and adds the loading state on top. Render inside the shared `.device-frame` (mobile default, tablet toggle), portrait only.

The source `logo.svg` is black ink on a flat white rectangle, which reads as a harsh box against the wood-dark background if placed as-is. Apply `mix-blend-mode: multiply;` on the `<img>` — this drops the white field out entirely (white × background = background) while keeping the ink black (black × anything = black), so only the black linework shows against the page with no visible edge. Reuse this same treatment anywhere else the logo appears.

---

## Phase 2 — Splash Screen (`splash.html`)

Purpose: first thing the player sees while assets load.

Layout:

```text
Full-bleed wood-texture background
Centered game logo ("Tetrofall")
Loading spinner or progress bar beneath logo
Optional: soft dust-particle animation drifting upward
```

Build notes: logo(game logo) should be the single focal point, vertically and horizontally centered. Keep it on screen only a few seconds — no interactive elements needed, just a fade-to-menu transition placeholder (CSS `@keyframes fadeOut`). Render inside the shared `.device-frame` (mobile default, tablet toggle), portrait only.

---

## Phase 3 — Main Menu (`main-menu.html`)

Layout (top to bottom):

```text
Highest Score display (top, small)
Game logo (smaller than splash)
PLAY button (large, primary, center)
Row of secondary icon buttons: Daily Reward, Themes, Achievements, Settings, Shop
```

Build notes: PLAY is the only large/bright button on the screen — everything else is a secondary icon button so the eye goes straight to it. Daily Reward icon should show a small notification badge when a reward is available. Use the counter pill component for Highest Score with a trophy icon. Render inside the shared `.device-frame` (mobile default, tablet toggle), portrait only.

---

## Phase 4 — Gameplay Screen (`gameplay.html`)

This is the most complex screen — build it in three stacked sections.

Top bar:

```text
Coin Counter (left)
Current Score / Highest Score (center)
Pause Button (right)
```

Game board (center, largest area):

```text
Grid of wooden blocks (CSS grid, e.g. 8x8)
Each cell: block sprite (wood/stone/ice/bomb/gold/diamond/treasure/locked/rainbow)
Reserve space above the board for floating combo text (GOOD! / AWESOME! / INCREDIBLE! / UNBELIEVABLE!)
```

Booster panel (bottom):

```text
Hammer | Bomb | Drill | Lightning
```

Build notes: each block cell should be a square with consistent padding so the grid reads cleanly at any board size. Booster icons sit in equal-width slots with a small coin-cost or charge-count badge. Combo text should be styled as large, bold, centered overlay text with a scale/fade animation on trigger — mock the resting state and one "triggered" state as two static frames. Render inside the shared `.device-frame` (mobile default, tablet toggle), portrait only.

Special block styling cheatsheet:

```text
Wood Block     – base wood texture
Stone Block    – grey, heavier texture, no crack lines
Ice Block      – semi-transparent blue overlay, crack lines appear after 1 hit
Bomb Block     – red accent, fuse icon
Gold Block     – gold accent, shine highlight
Diamond Block  – blue accent, faceted icon
Treasure Block – chest icon overlay
Locked Block   – darkened, lock icon, paired key indicator
Rainbow Block  – multicolor gradient fill
```

---

## Phase 5 — Pause Screen (`pause.html`)

Layout: modal overlay on top of a dimmed/blurred gameplay screen.

```text
Resume (primary button)
Restart
Settings
Quit
```

Build notes: dim the background board to ~40% opacity with a blur filter so the modal reads as "on top." Stack buttons vertically, Resume visually heaviest (largest/brightest), Quit visually lightest (text-only or outlined). Render inside the shared `.device-frame` (mobile default, tablet toggle), portrait only.

---

## Phase 6 — Game Over Screen (`game-over.html`)

Layout:

```text
Current Score (large, top)
Highest Score (smaller, below — highlight if it's a new best)
Coins Earned (counter pill with coin icon)
Watch Ad To Continue (secondary button, ad icon)
Play Again (primary button)
Home (tertiary/icon button)
```

Build notes: if current score beats highest score, show a "NEW BEST!" badge in gold. Play Again should be the visually dominant action. Render inside the shared `.device-frame` (mobile default, tablet toggle), portrait only.

---

## Phase 7 — Daily Reward Screen (`daily-reward.html`)

Layout: horizontal or wrapped grid of day cards.

```text
Day 1 – Coins
Day 2 – Bomb Booster
Day 3 – Theme Unlock
...
```

Build notes: each day is a card with icon + label. Today's card is highlighted (border glow or scale-up); past days show a checkmark/dimmed state; future days are locked/greyed out. Include a single "Claim" button tied to the active day's card. Render inside the shared `.device-frame` (mobile default, tablet toggle), portrait only.

---

## Phase 8 — Theme Screen (`themes.html`)

Layout: scrollable grid of theme preview cards.

```text
Classic Wood | Marble | Candy | Snow | Space | Neon | Halloween | Ancient Temple | Golden Wood
```

Build notes: each card shows a thumbnail preview of the board texture, theme name, and either "Equipped," "Unlock (coin cost)," or a lock icon. Currently equipped theme gets a colored border/checkmark. Render inside the shared `.device-frame` (mobile default, tablet toggle), portrait only.

---

## Phase 9 — Achievements Screen (`achievements.html`)

Layout: vertical list of achievement rows.

```text
Destroy 1000 blocks       [progress bar]  [medal icon]
Destroy 5000 blocks       [progress bar]
Reach 10000 points        [progress bar]
Create a 50 combo         [progress bar]
Unlock all themes         [progress bar]
```

Build notes: each row = icon + title + progress bar + reward indicator. Completed achievements show a filled crown/medal icon and a "Claimed" or "Claim" state; incomplete ones show a fraction (e.g. "320 / 1000"). Render inside the shared `.device-frame` (mobile default, tablet toggle), portrait only.

---

## Phase 10 — Shop Screen (`shop.html`)

Layout: sectioned scroll page.

```text
Coins (packs, priced)
Boosters (individual + bundles)
Themes (link to Theme Screen or inline preview)
Remove Ads (one-time purchase, prominent)
Starter Pack (best-value, visually distinct)
```

Build notes: Starter Pack should stand out with a banner/ribbon ("Best Value"). Group items into cards within labeled sections; keep pricing consistent (coin icon + amount, or currency + price for real-money items). Render inside the shared `.device-frame` (mobile default, tablet toggle), portrait only.

---

## Phase 11 — Shared Icon & Sound Reference

Keep this as a living checklist while building screens — not a separate HTML file, just a reference section.

Gameplay icons: Coin, Trophy, Pause, Play, Restart, Home, Settings, Sound, Music.

Booster icons: Hammer, Bomb, Drill, Lightning, Stopwatch, Star.

Reward icons: Treasure Chest, Gift Box, Diamond, Coin Stack, Crown, Medal.

Color-coding rule across all screens: gold = rewards, red = bombs, blue = diamonds, purple = combo effects, green = success messages. Everything else stays neutral wood/beige tones so these accents pop.

---

## Phase 12 — Polish Pass (applies to all screens)

Once every screen exists as static HTML, do one pass across all of them for:

Consistency: same button component, same corner radius, same spacing scale used everywhere.

Motion: add CSS transitions for button press (scale down slightly), modal open/close (fade + scale), combo text (pop + fade), coin counter (tick-up animation on change).

Responsiveness: confirm every screen's `.device-frame` toggle correctly swaps between mobile (375×812) and tablet (768×1024) sizes with no layout breakage in either state, and that nothing attempts to reflow into landscape — portrait is the only supported orientation.

Accessibility: confirm text contrast against wood textures, tap targets at least 44x44px, and that color is never the only signal (e.g. locked blocks also show a lock icon, not just a darker tint).

Verification checklist:

```text
[ ] All 10 screens built and linked via nav for click-through testing
[ ] Shared tokens.css/components.css used with no one-off hardcoded colors
[ ] All icons from Phase 11 reference accounted for
[ ] Every screen wrapped in `.device-frame`, mobile-to-tablet toggle verified, portrait-only (no landscape variant)
[ ] Animations mocked at least as before/after states
```
