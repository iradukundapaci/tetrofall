# Background music

`MusicService` looks for exactly these two files, and the directory is already
registered in `pubspec.yaml` — dropping them in is the only step.

| File | Where it plays |
| --- | --- |
| `menu_loop.mp3` | Splash → main menu |
| `game_loop.mp3` | During a run |

Ship only one and it keeps playing across both screens instead of cutting out
at the boundary.

Ship neither — the state today — and **the Settings "Music" row is hidden
entirely**. `MusicService` probes the asset manifest at boot and exposes the
answer as `MusicService.hasBundledTracks`; `settings_screen.dart` builds the
row only when that is true. Dropping either mp3 in here brings the row back
with no code change. This is deliberate: a volume slider with provably nothing
behind it is a defect a Play reviewer can see, not merely an empty feature
(android_release_plan.md §1.4, gap 14).

Format per game.md §P.7: `.mp3`, 128 kbps, stereo, seamless loop. Generator
prompts for both tracks are in that section.
