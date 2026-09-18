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
Small | Line | Area | Board     — one rolled booster per slot
```

The panel is the booster bar from `boosters.md` §4: four equal-width slots at a
fixed `--booster-bar-height`, each a 50 px round button showing the booster that
slot rolled before the run with a single badge on its rim (bottom-right). It is
the bottom row of the screen — **there is no banner ad slot any more**, and the
50 px it used to hold is play area (`boosters.md` §4.1). The five slot states —
ready, armed, no target, busy, spent — are mocked on the reference sheet below
the device frame, together with all twelve glyphs; the state toggle above the
frame switches the screen between playing, aiming (board dimmed to 70 %, preview
row outlined, first-use tip above the bar) and a late run where spent slots are
greyed out and offer themselves back for a rewarded video. See Phase 13.

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
Get Coins (earn card → Coin Vault; rewarded video is the only source)
Clear Skies (timed ad-free play: 30 min / 2 h / 6 h of game time)
Boosters (all 12, one charge or a 3-pack, priced by slot tier)
Mystery Chest
Themes (link to Theme Screen)
```

Build notes: **everything is priced in Coins — no real-money prices anywhere** (`phase11_monetization_plan.md` §0). The earn card leads, because an empty wallet should always be one tap from a fix. Clear Skies replaces Remove Ads and must say that rewarded videos stay available. Any item the player cannot afford opens the same confirm sheet as in-game purchases, whose primary becomes **Earn Coins**. Built as `lib/ui/screens/shop_screen.dart`, with the earn loop in `coin_vault_screen.dart`. Render inside the shared `.device-frame` (mobile default, tablet toggle), portrait only.

---

## Phase 11 — Shared Icon & Sound Reference

Keep this as a living checklist while building screens — not a separate HTML file, just a reference section.

Gameplay icons: Coin, Trophy, Pause, Play, Restart, Home, Settings, Sound, Music.

Booster icons: Hammer, Bomb, Drill, Lightning, Stopwatch, Star. The test roster
in `boosters.md` §2 adds eight more — Patch, Slide, Pillar, Sweep, Mortar,
Earthquake, Tilt, Wildfire. All twelve now come from **Lucide (ISC)** rather
than being drawn per brief, at 24 × 24 with a 1.8 stroke, and they are laid out
on `gameplay.html`'s reference sheet (Phase 13). `shop.html` and
`daily-reward.html` use the same paths for the boosters they hand out.

Reward icons: Treasure Chest, Gift Box, Diamond, Coin Stack, Crown, Medal.

Color-coding rule across all screens: gold = rewards, red = bombs, blue = diamonds, purple = combo effects, green = success messages. Everything else stays neutral wood/beige tones so these accents pop.

Audit against the built screens:

```text
[x] Coin      – topbar/header pills on main-menu, gameplay, game-over, themes, shop
[x] Trophy    – main-menu BEST score pill
[x] Pause     – gameplay topbar
[x] Play      – game-over "Watch Ad" icon (video/play glyph); PLAY itself is a text button
[x] Restart   – text-only per Phase 5/6 build notes, no icon required
[x] Home      – game-over.html icon button
[x] Settings  – gear icon (main-menu, pause, nav bar)
[x] Sound     – settings.html mute buttons (speaker glyph)
[x] Music     – settings.html Music row (music-note glyph)
[x] Hammer / Bomb / Drill / Lightning – gameplay booster panel + shop
      (all four replaced with their Lucide equivalents; the old Lightning was
      a filled gold shape that couldn't take the muted or greyed states, and
      the old hammer read as a pencil at bar size — boosters.md §9.5)
[ ] Stopwatch – not used anywhere yet; reserved for a future time-freeze
      booster (would need a 5th booster slot, which Phase 4's spec fixes
      at 4 — revisit if a time-based booster is added to the design)
[x] Star      – repurposed as the "NEW BEST!" sparkle on game-over.html
      rather than a booster; no Star-type booster exists yet (see Stopwatch)
[x] Treasure Chest – gameplay treasure block, daily-reward Day 7 hero card
[x] Gift Box  – daily-reward icon (nav bar + main-menu)
[x] Diamond   – gameplay diamond block
[x] Coin Stack – shop.html's two largest coin packs use a stacked-coin
      glyph; smaller packs keep the single-coin icon for hierarchy
[x] Crown / Medal – achievements.html uses medal (spec allows either);
      no separate crown icon in use
```

Color-coding note: achievements.html's claimed state uses gold instead of
green (an explicit design decision, since green read as out of place next
to the wood/gold palette) — every other screen still follows the rule
above as written.

---

## Phase 12 — Polish Pass (applies to all screens)

Once every screen exists as static HTML, do one pass across all of them for:

Consistency: same button component, same corner radius, same spacing scale used everywhere.

Motion: add CSS transitions for button press (scale down slightly), modal open/close (fade + scale), combo text (pop + fade), coin counter (tick-up animation on change).

Responsiveness: confirm every screen's `.device-frame` toggle correctly swaps between mobile (375×812) and tablet (768×1024) sizes with no layout breakage in either state, and that nothing attempts to reflow into landscape — portrait is the only supported orientation.

Accessibility: confirm text contrast against wood textures, tap targets at least 44x44px, and that color is never the only signal (e.g. locked blocks also show a lock icon, not just a darker tint).

Verification checklist:

```text
[x] All 10 screens built and linked via nav for click-through testing
      (splash -> main-menu -> gameplay/pause/game-over, and the 5 hub
      screens - daily-reward, themes, achievements, settings, shop -
      all cross-link via a shared persistent bottom nav bar)
[x] Shared tokens.css/components.css used with no one-off hardcoded colors
      (audited via grep for raw hex codes; the one duplicate found,
      stroke="#4a2f1c", was replaced with var(--color-wood-dark) everywhere)
[x] All icons from Phase 11 reference accounted for (see audit above;
      Stopwatch is the sole intentional gap, reserved for a future booster)
[x] Every screen wrapped in `.device-frame`, mobile-to-tablet toggle verified,
      portrait-only (no landscape variant) - all 10 screens confirmed via
      grep, layouts use fr-based grids/flex so nothing breaks on resize
[x] Animations mocked at least as before/after states (button press,
      modal open/close, combo pop, and the coin counter tick-up in
      shop.html are all implemented as CSS transitions/keyframes)
```

Accessibility pass (added alongside the checklist above): text contrast checked
against the wood/bg palette (muted text ~7:1, primary text ~13.6:1, gold ~9:1 -
all comfortably pass WCAG AA); tap targets audited for 44x44px minimum (nav
icons and .btn-icon are 48x48; settings.html's slider-mute-btn was bumped from
32x32 to 44x44 to meet this); color-as-sole-signal checked across
locked/unlocked theme cards and claimed/claimable/in-progress achievement rows
- all pair their color with a distinct icon.


---

## Phase 13 — Boosters (`loadout.html`, booster bar on `gameplay.html`)

Built from `boosters.md`. Two pieces of UI, one shared set of components.

**Loadout roll (`loadout.html`)** — §3. An overlay on the gameplay screen while
the engine sits in `ready`, so the board you're about to play is already behind
it, dimmed the way `pause.html` dims it. Four wooden reels, one per slot, each
rolling only its own pool of three:

```text
YOUR BOOSTERS
[reel][reel][reel][reel]     stop at 500 / 750 / 1000 / 1250 ms
Hammer Drill Mortar Tilt     the landed booster's name, and nothing else
↻ Tap a booster to re-spin (1 left)
[ START ]                    active once the last reel settles
```

The mockup is interactive, because the feel is the point: tapping a landed reel
re-spins that slot alone (never onto the booster it already shows), tapping
anywhere mid-spin snaps every reel to its already-decided result, and the toggle
above the frame switches between the three entry points — a random roll, the
fixed starter kit of the first three runs, and the replay opening with the
previous loadout and a `Same boosters` / `Spin` pair. `PLAY` on the main menu and
`Play Again` on game over now route here rather than straight to gameplay.

**Booster bar (`gameplay.html`, frozen on `pause.html`)** — §4. The bottom row
of the screen, with the banner slot removed and the board grown into it.
Covered in the Phase 4 notes above.

**Rewarded ads.** Both screens share one sheet (`.ad-prompt` in
`components.css`), and it always names what the video buys before it plays:

```text
loadout.html   free re-spin spent → "▶ Watch an ad to re-spin (3 left)"
               tap a reel → "Re-spin the Line slot?" → Watch / Not now
gameplay.html  spent slot greys out, charge badge → ▶ badge
               tap it → "Recharge Hammer?" → Watch / Not now → slot is Ready again
```

Both mockups run the flow end to end with a mocked video, so the pacing can be
felt rather than imagined. The caps (3 bought re-spins, 2 refills) are the ones
in `BoosterTuning`.

**Shared pieces.** `tokens.css` gains the six `--booster-*` / `--effect-*` fields
of `boosters.md` §9.2, which are the only colors booster UI reads, plus
`--booster-bar-height`. `components.css` gains `.booster-bar`, `.booster-slot`
and its five states, the charge and ad badges, the first-use tip and the `.reel`
drum. No blue, purple or green appears anywhere in booster visuals, and
red stays reserved for Wildfire's ember (§9.1) — every state is carried by shape
and engraving, so the bar still reads when desaturated.

**Icons.** All twelve glyphs live on `gameplay.html`'s reference sheet in the
§9.5 style (Lucide paths, 24 × 24, `currentColor`, 1.8 stroke, no fills), which
is what `tools/extract_icons.py` reads. `shop.html` and `daily-reward.html` were
moved onto the same set, so no two screens draw the same booster differently.
