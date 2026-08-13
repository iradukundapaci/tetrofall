# Trademark review — "Tetrofall" vs. the Tetris Company

Phase 3.5. Reviewed 2026-08-13 against the shipped build and the draft listing
copy in `android_release_plan.md` §4.

**This is a documented engineering review, not legal advice.** If you want
certainty before spending money on marketing, an IP lawyer's opinion is the only
thing that provides it.

## Why this needs a deliberate look

The Tetris Company enforces aggressively and routinely files Play takedowns
against falling-block games. They have historically pursued not just the word
"Tetris" but trade dress — the look and feel — and names built on the "-tris"
/ "tetr-" stem. Takedowns arrive as a Play removal first and a conversation
second, so the cost of a hit is the listing, not just a rename.

## Where the risk actually sits

| Surface | Assessment |
| --- | --- |
| **The name** | ⚠️ **The one real exposure.** "Tetrofall" opens on `Tetr-`, shared with Tetris and with the tetromino vocabulary generally. Mitigating: "tetromino" is the standard geometric term and predates the game, the second element is "fall" rather than "-tris", and the compound reads as a coined word rather than a near-miss of a mark. |
| **The gameplay** | ✅ Mechanically differentiated. The rising floor is the core loop, and `ColumnCascade` — blocks falling independently after a clear rather than the stack shifting down as a unit — is not Tetris behaviour. |
| **The art direction** | ✅ **This is the strongest defence, and it is already built.** Warm wood blocks on a wood board is the opposite of the classic trade dress. |
| **The icon** | ✅ A gold T-tetromino on wood grain. It is a T-piece, which is unavoidable in the genre, but nothing about the palette or styling evokes Tetris. |
| **The listing copy** | ✅ The §4.5 draft never uses the word, and describes the rise mechanic as the hook. |

## The trade-dress checklist — all clear

The look most likely to draw attention is the classic one. Confirmed absent:

- [x] No cyan/yellow/purple/green/red/blue/orange **7-colour tetromino palette**
      — one wood tile, tinted per theme (`ThemeDefinition.classicWood`).
- [x] No **black or dark-blue field** with a bright grid. The board is
      `#1F140C` wood on a wood surround.
- [x] No **"TETRIS" logo styling** — no chunky 3-D bevelled block letters, no
      Cyrillic-styled type. The wordmark is Baloo 2.
- [x] No **Russian / Korobeiniki musical reference.** `assets/audio/music/` is
      empty; if loops are ever added, keep them off that melody — it is public
      domain as a folk song, but its use in this genre is the single most
      recognisable Tetris signal there is.
- [x] No use of **"Tetris"** anywhere in the app, the repo's user-facing strings,
      the website, or the draft listing.

## Rules to hold to

- [ ] Never write "Tetris" in the title, short description, full description,
      tags, or screenshot captions — including as a comparison
      ("better than…", "like Tetris but…"). Comparative use is still use, and
      it is also a Play keyword-policy violation.
- [ ] Do not buy or target "tetris" as a search keyword if you ever run ads.
- [ ] Keep the wood art direction. It is doing real legal work, not just
      aesthetic work — **lean into it in the listing**, as §4.5 already does.
- [ ] If you ever add a theme with a neon-on-black palette, this review needs
      redoing. That single change would move the trade-dress row from ✅ to ⚠️.

## Verdict

**Proceed with "Tetrofall".** The differentiation is real and mechanical, not
cosmetic, and the art direction is genuinely distinct. The name carries residual
risk that cannot be reduced to zero without renaming.

Worth knowing before you commit: the package name
`com.nosleepstudios.tetrofall` is **frozen at first upload and can never be
changed**, whereas the *store display name* is editable at any time. So if a
complaint ever arrives, you can rebrand the listing without republishing as a new
app — the expensive, irreversible half of the identity is the package name, and
it is not the half that carries the trademark risk.
