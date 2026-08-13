# Audio credits and licensing

Required by android_release_plan.md §3.4. Unlicensed sound effects are the
single most common takedown cause for indie games, so every audio file that
ships must have a recorded source and a licence that permits **commercial** use
and **redistribution inside an application**.

**Status: ✅ cleared for commercial release.**

## Shipped sound effects

All three were generated with **Adobe Firefly** (Generate Sound Effects) from
the prompts in `game.md` §P.7, and committed 2026-08-09 in `c13820e`.

| File | Size | Source | Licence |
| --- | --- | --- | --- |
| `block_settle.wav` | 201 KB | Adobe Firefly — Generate Sound Effects | Commercial use permitted |
| `block_spawn.wav` | 201 KB | Adobe Firefly — Generate Sound Effects | Commercial use permitted |
| `wood_crush.wav` | 201 KB | Adobe Firefly — Generate Sound Effects | Commercial use permitted |

## Why this is clean

Adobe trains Firefly only on Adobe Stock, openly licensed and public domain
content, and states that output is commercially safe as a result — which is the
whole reason Firefly is a materially safer route here than a general-purpose
generator. Specifically:

- **Commercial use is granted on the free plan as well as paid.** The tiers
  differ in generation credits and advanced features, **not in usage rights**.
  This is the distinction that catches people out elsewhere: ElevenLabs' free
  tier is non-commercial and Meta's AudioCraft is research-licensed, so neither
  could have been used here without a licence breach.
- **No attribution is required**, so nothing needs to appear in-app. This file
  is the record, not a notice.
- **Redistribution inside an application is fine** — the output is royalty-free
  and is not resold as audio; it plays as part of the game.

Reference:
[Adobe Firefly — AI sound effect generator](https://www.adobe.com/products/firefly/features/sound-effect-generator.html).

## Two caveats, both satisfied

1. **Output must come from the commercially released Firefly, not a beta.**
   Adobe excluded beta output from commercial use. Generate Sound Effects was
   generally available well before these were made on **2026-08-09**, so this is
   satisfied. It would only matter if sounds were regenerated using a feature
   still labelled beta.
2. **Adobe's Generative AI User Guidelines still apply** to how the output is
   used — they prohibit unlawful and infringing uses, none of which a wooden
   block sound in a puzzle game comes near.

## If you regenerate or add sounds

Keep the whole set on Firefly rather than mixing routes — §P.7's point about
coherence applies to licensing too, and one file from a non-commercial
generator would put the whole build at risk. Add the file to the table above
with its generation date, and re-check caveat 1 if the feature you use is
labelled beta.

Worth doing while it is cheap: save a PDF or screenshot of Adobe's current terms
alongside your records. Generative-AI terms change often, and being able to
prove what they said on the day you generated is the entire point of this file.

## Music

`assets/audio/music/` ships **no** audio — see the README there. When loops are
added, add them to the table above with the same columns filled in, and re-check
§3.5: keep well clear of the Korobeiniki melody, which is the most recognisable
Tetris signal there is.

## Fonts

Handled separately and already compliant: Nunito and Baloo 2 are under the SIL
Open Font License, the `OFL.txt` files are bundled as assets, and `main()`
registers both with `LicenseRegistry` so they appear under Settings → Open
source licences. Covered by `test/font_licenses_test.dart`.
