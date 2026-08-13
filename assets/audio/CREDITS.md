# Audio credits and licensing

Required by android_release_plan.md §3.4. Unlicensed sound effects are the
single most common takedown cause for indie games, so every audio file that
ships must have a recorded source and a licence that permits **commercial**
use and **redistribution inside an application**.

> ⚠️ **BLOCKING — route known, licence not yet verified.**
> The three files were **generated with an AI text-to-sound-effect tool**
> (confirmed by the developer, 2026-08-13), following the generation prompts in
> `game.md` §P.7. The specific tool is **not yet recorded**, and that is the one
> fact this file still needs — because with generative audio the tool and the
> plan, not the act of generating, decide whether commercial rights exist.
>
> **Do not submit to Play until the tool and plan are recorded below and their
> terms confirmed to permit commercial use.** Why it matters concretely:
>
> | Tool / tier | Commercial use of output? |
> | --- | --- |
> | ElevenLabs, paid tier | ✅ Granted, no attribution required |
> | ElevenLabs, free tier | ❌ Non-commercial only, attribution required |
> | Meta AudioCraft / AudioGen | ❌ Research licence — commercial use forbidden |
> | Adobe Firefly (paid) | ✅ Granted, indemnified |
> | Stable Audio | ⚠️ Depends on tier — free is non-commercial |
>
> An ad-supported Play release **is** commercial use. If the tool turns out to
> be one of the ❌ rows, the fix is cheap and total: regenerate the same three
> prompts on a route that does grant rights. That is far cheaper than a takedown
> after launch.

## Shipped sound effects

| File | Size | Source | Licence |
| --- | --- | --- | --- |
| `block_settle.wav` | 201 KB | AI text-to-SFX generator — ❓ **which tool?** | ❓ **pending the tool** |
| `block_spawn.wav` | 201 KB | AI text-to-SFX generator — ❓ **which tool?** | ❓ **pending the tool** |
| `wood_crush.wav` | 201 KB | AI text-to-SFX generator — ❓ **which tool?** | ❓ **pending the tool** |

## Music

`assets/audio/music/` ships **no** audio — see the README there. When loops are
added, add them to the table above with the same two columns filled in, and
re-check §3.5: keep well clear of the Korobeiniki melody.

## What "filled in" looks like

Record enough that a stranger could verify it without asking you:

1. **Tool name and plan** at the time of generation (e.g. "ElevenLabs Sound
   Effects, Creator plan"). The plan matters as much as the tool.
2. **Date generated**, so it can be matched against the account's billing
   history if the plan is ever queried.
3. **A link to the terms** that grant commercial rights, plus a **saved copy**
   (PDF or screenshot) — generative-AI terms change often, and being able to
   prove what they said on the day you generated is the entire point of this
   file.
4. **The prompts**, which §P.7 already contains — keep them, so the set can be
   regenerated coherently if the licence ever has to be re-established.

## Fonts

Fonts are handled separately and are **already compliant**: Nunito and Baloo 2
are under the SIL Open Font License, the `OFL.txt` files are bundled as assets,
and `main()` registers both with `LicenseRegistry` so they appear under
Settings → Open source licences.
