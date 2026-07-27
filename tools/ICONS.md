# Icon Inventory — P.5

Extracted from `screens/*.html` by `tools/extract_icons.py`. **Do not hand-edit the SVGs** — change the mockup and re-run the script, or the two will drift apart.

```bash
python3 tools/extract_icons.py
```

## What the script does

The mockups carry their icons as inline `<svg>` with the presentational attributes (`fill`, `stroke`, `stroke-width`) supplied by CSS. Those don't travel with an extracted file, so the script bakes them in. It also:

- **Groups by geometry, not by markup.** The same icon appears in several visual states (a gold medal vs. a muted outline medal) that differ only in fill. Grouping on path data alone collapses 60 raw `<svg>` blocks into 41 distinct shapes, then into 35 files.
- **Resolves CSS variables.** `var(--color-gold)` doesn't resolve in Flutter; it's replaced with the literal hex from `tokens.css`.
- **Emits `currentColor`** for monochrome icons so they tint at the call site.

## Files

35 UI icons in `assets/images/icons/`, plus 3 reference files.

| Group | Icons |
|---|---|
| Gameplay & navigation | `pause` `home` `chevron_right` `settings` `trophy` `star` |
| Currency | `coin` `coin_detailed` `coin_simple` `coin_stack` |
| Boosters | `hammer` `bomb` `drill` `lightning` |
| Rewards & progress | `treasure_chest` `gift` `gift_simple` `medal` `medal_outline` `check_circle` `check_circle_light` `lock` `video` |
| Settings | `music` `sound` `sound_low` `sound_off` `vibrate` `message` `bell` `restore` `shield` `document` `palette` `shop` |

Access them through `lib/ui/theme/app_icons.dart`, which is generated alongside:

```dart
SvgPicture.asset(
  AppIcons.hammer,
  width: 22,
  colorFilter: ColorFilter.mode(Tokens.text, BlendMode.srcIn),
)
```

**Three icons are deliberately multicolor** and must be rendered *without* a `colorFilter`, or they'll flatten to a silhouette: `medal` (red ribbons + gold disc), `coin_detailed` (gold + shine + rim), `coin_stack` (three-tone stack). `AppIcons.multicolor` holds this set so it can be asserted in code.

## Variants worth knowing

- `coin` / `coin_detailed` / `coin_simple` — three coins by design, not duplicates. `coin_simple` is a bare disc used at ~14px in price rows where the currency symbol would turn to mush; `coin_detailed` has a rim and shine and is used large in the gameplay/main-menu top bar; `coin` is the mid-detail default.
- `check_circle` / `check_circle_light` — same shape, different tick color. The standard one has a dark tick for gold/light discs; the `_light` variant has a white tick for the green "claimed" state on daily-reward cards.
- `medal` / `medal_outline` — earned vs. in-progress achievement rows.
- `sound` / `sound_low` / `sound_off` — full, single-arc, and muted speaker.

## `blocks-reference/`

`block_bomb`, `block_locked`, `block_diamond` — the glyphs the HTML board drew inside its cells. **Not runtime assets, and deliberately excluded from `pubspec.yaml`.** Per P.3 the special blocks ship as complete 256×256 tiles, so these are kept only as drawing reference so the tile art matches what the mockup showed. They render nearly invisible on a dark background because they were drawn to sit on a colored block face.

## Deviations from the mockups

**`trophy` is stroked, not filled.** `main-menu.html` sets `fill: var(--color-gold)` on it, but two of its four paths (`M12 16v2`, `M9 20h6` — the stem and base) are zero-area lines that render as *nothing* under a fill-only rule. The mockup's trophy is therefore a floating cup with no stem. The extracted file strokes it instead, which is what the drawing intends.

**Four truncated duplicates were folded into their full versions.** `shop.html`'s bundle strip draws simplified hammer/bomb/drill glyphs missing their last path, and `main-menu.html`'s medal uses `r=2.5` where `achievements.html` uses `r=3`. Shipping near-identical files would invite using the wrong one; the full icon at small size looks the same.

## Gaps

| Icon | Status |
|---|---|
| **Play** | No standalone glyph exists — `PLAY` is a text button, and the only play triangle is inside `video` (the watch-ad button). Extract or draw one if a play glyph is ever needed on its own. |
| **Restart** | Text-only by design (`screens.md` Phase 5/6 build notes). |
| **Stopwatch** | Doesn't exist. Reserved for the Time Freeze booster, which needs a 5th booster slot that Phase 4 fixes at 4. See the open question in `game.md` §6. |

These match the audit already recorded in `screens.md` Phase 11 — no new gaps were introduced.

## Verifying

`tools/icon_contact_sheet.png` shows all 38 files rendered at 64px on the wood background, with the three block references drawn on their tile colors. Regenerate it after any change and eyeball it before committing.
