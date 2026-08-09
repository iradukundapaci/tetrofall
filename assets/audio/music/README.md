# Background music

`MusicService` looks for exactly these two files, and the directory is already
registered in `pubspec.yaml` — dropping them in is the only step.

| File | Where it plays |
| --- | --- |
| `menu_loop.mp3` | Splash → main menu |
| `game_loop.mp3` | During a run |

Ship only one and it keeps playing across both screens instead of cutting out
at the boundary. Ship neither — the state today — and the Settings "Music"
slider persists its value but has nothing to turn up.

Format per game.md §P.7: `.mp3`, 128 kbps, stereo, seamless loop. Generator
prompts for both tracks are in that section.
