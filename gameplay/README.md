# Play Store assets

Everything the Tetrofall listing needs, generated from the repo. Nothing here
is hand-retouched — regenerate any of it and you get the same file back.

## What to upload where

| Play slot | Folder | Limit | Have |
| --- | --- | --- | --- |
| Feature graphic | `feature/` | 1 (1024×500) | 3 candidates |
| Phone screenshots | `phone/` or `phone_captioned/` | 8 | 12 candidates |
| 7-inch tablet | `tablet7/` | 8 | 8 |
| 10-inch tablet | `tablet10/` | 8 | 8 |
| Promo video | `video/` | 1 YouTube URL | 4 recorded (`01`, `06`, `07`, `08`); 3 social cuts scripted |

`phone/` is the raw capture; `phone_captioned/` is the same shot inside the
§4.9 caption frame. Upload one set or the other, not a mix — the eight have to
read as a sequence.

### Recommended phone order

Play shows the first two or three in search results, so shots 1 and 2 have to
work as a pair. Shots 1–5 are gameplay, which is deliberate: menu and
game-over screenshots convert badly and are the first to drop.

1. `shatter` — the four-row clear bursting centre-out
2. `chain_x3` — the stack in free fall mid-chain, dust on the impact rows
3. `rise_pressure` — stack into the top of the board, floor still coming
4. `deep_well` — the I-piece hanging over the valley it is about to fill
5. `ghost_drop` — ghost outline on the landing row
6. `tetrofall_clear` — the same four rows 250ms earlier, all cracked
7. `late_game` — dense board, top score, endurance pace
8. `game_over` — final score and the continue offer

Held back as alternates: `cascade`, `overhang`, `tutorial`, `main_menu`.
`main_menu` is last for a reason — the menu is a PLAY button over a
deliberately blurred attract board, so it photographs as an out-of-focus
screenshot. Prefer any gameplay shot over it.

### Feature graphic

Three pitches for the slot that, in several Play promo surfaces, plays alone
with no screenshots beside it:

- `01_wordmark.png` — identity. Mark, wordmark, one-line tagline.
- `02_rising_floor.png` — the mechanic, diagrammed: pieces down, floor up.
- `03_shatter.png` — the payoff, mid-burst.

All three keep text and logo inside the centre 80% (Play crops the margins in
some placements) and carry no screenshots, device frames, store badges or
"download now" — each of those is a policy violation.

## Videos

Not tracked in git (see `.gitignore`) — they are large and regenerable.

| File | Length | What it is |
| --- | --- | --- |
| `01_skilled_run.mp4` | 40s | Opens on a built board, takes a four-row clear that chains, then plays against the rising floor with the score climbing 6200 → ~8700. **This is the one for the listing's promo-video slot** — a misleading clip there is a policy problem. |
| `02_blunder_i_well.mp4` | 20s | Nine-deep well, the I arrives, and it goes down flat across the top. |
| `03_blunder_ignore_rise.mp4` | 25s | Stacks one side while the floor climbs; tops out with half the board empty. |
| `04_near_miss.mp4` | 25s | Builds a real chain setup and buries it. |
| `05_long_form.mp4` | 60s | A minute of mixed play for a YouTube URL. |
| `06_endurance_2min.mp4` | 120s | Two minutes of dense survival against the rising floor, score 4800 → ~12000. Holds a full board through the first seventy seconds and thins in the last third. |
| `07_cascade_2min.mp4` | 120s | Two minutes of ripple gravity: clears chain down the stack, a fast floor refills it, repeat. Opens on a 20-row board, score 9100 → ~21000. The showier of the two long cuts. |
| `08_listing_40_outro.mp4` | 40s | `01_skilled_run` trimmed to 36.6s and crossfaded into the end card, which reads **NO FAKE ADS** / TETROFALL / *That was all real gameplay.* Same footage, closing on the game name and the claim. |

Cuts 2–5 are deliberate-blunder creative for paid social, not for the listing:
a clip where the viewer can plainly see the mistake converts because they want
to correct it. Keep them off the store page itself. Cuts 6–8 are honest play,
so any of them can go on the store page; `08` is the one to use if the slot
should close on the game name.

### The end card

The app has no outro screen, and adding one purely to photograph would mean
shipping a screen the player can never reach. So `tools/store/outro.py`
composites the card afterwards, drawing it from the same palette
(`lib/ui/theme/tokens.dart`) and the same fonts the game and the feature
graphic use, and crossfades into it:

```bash
tools/store/outro.py gameplay/video/01_skilled_run.mp4 \
    --out gameplay/video/08_listing_40_outro.mp4 --total 40
```

`--total` is the length of the *finished* file, so a 40-second cut with a
4-second card holds ~36.6s of play. `--card-only out.png` renders just the
card for checking the layout without re-encoding anything.

`--tagline` replaces the line under the wordmark and `--kicker` adds a small
letter-spaced label above the mark:

```bash
tools/store/outro.py gameplay/video/01_skilled_run.mp4 \
    --out gameplay/video/08_listing_40_outro.mp4 --total 40 \
    --kicker "no fake ads" --tagline "That was all real gameplay."
```

### "This is the real game" — the copy angle

Tetrofall started from one of those fake mobile ads that shows a game which
does not exist in the app being advertised, so the listing has an unusually
strong claim available: the game in the ad is this one, and it is playable.

The card above is worded to be *verifiable* rather than boastful. Every frame
of every reel is `adb screenrecord` output from the shipped build — nothing is
mocked up, composited or sped up — so "that was all real gameplay" is a
statement about the footage the viewer just watched, not a promise about the
game in general.

Three limits on how far to push it:

- **Never name or show another game or company's ad.** Generic "those ads" is
  fine; disparaging a named competitor is a policy problem and an IP one.
- **"No fake ads" is a promise about your own creative,** not just the store
  page. Cuts 2–5 are honest — a real bot playing badly on purpose — but the
  claim only holds while every piece of UA creative stays actual gameplay.
- **"You've seen the ad" implies the viewer saw an ad for _this_ game.** Fair
  on paid social, where the cut *is* the ad; on the listing itself prefer
  "those ads", which references the genre rather than asserting a history.

## Google Ads images

An App campaign ad group takes up to 20 images and Google places them across
YouTube, Discover, Display and AdMob. `ads/` holds exactly twenty, built by
`tools/store/ad_images.py` from the shot list in `tools/store/ads.json`.

| Slot | Size | Have |
| --- | --- | --- |
| Landscape 1.91:1 | 1200×628 | 7 (`ads/landscape/`) |
| Square 1:1 | 1200×1200 | 6 (`ads/square/`) |
| Portrait 4:5 | 1200×1500 | 7 (`ads/portrait/`) |

Max 5120KB each. `ads/contact_sheet.png` shows all twenty at once.

Fifteen carry no text: Google sets the app name, icon and headline next to the
image itself, and a board with nothing on it reads at thumbnail size. Five
carry copy — two on the "no fake ads" angle, three challenge questions. The
challenge lines are questions ("Where does this piece go?") rather than
statistics ("only 2% can…"), which Google can flag as an unverifiable claim.

Same rule as the reels: every board is a capture from this folder or a frame
decoded out of a reel. The tool only crops, scales, blurs the ground and draws
a frame; it never paints on a board and adds no fake buttons. Images 13–16
decode from `video/`, which is gitignored — without the reels they print
`skip` and the committed PNGs stay as they are.

## Google Ads videos

The same ad group takes up to 20 videos (uploaded to YouTube, then linked).
`ads_video/` holds twenty, every one with sound, built by
`tools/store/ad_videos.py` from the cut list in `tools/store/ad_videos.json`.

| Ratio | Size | Have |
| --- | --- | --- |
| Portrait 9:16 | 1080×1920 | 10 (`ads_video/portrait/`) |
| Square 1:1 | 1080×1080 | 5 (`ads_video/square/`) |
| Landscape 16:9 | 1920×1080 | 5 (`ads_video/landscape/`) |

All 10–30s, H.264 + AAC, peak −1.5dBFS. `ads_video/contact_sheet.png` shows a
frame from each. The mp4s are gitignored; regenerate them.

Most are frustration bait — a move the viewer can plainly see is wrong: the I
laid flat over a nine-deep well, a piece one column off its slot, the slot
that clears nothing, an L upside down, a tower of I-pieces, a roof over a
hole. The rest are the payoff (the four-row shatter, chain reactions), the
mechanic explained, and the "no fake ads" angle.

The rules that keep them honest:

- **Every board is real footage.** The blunders are the shipped game, driven
  badly on purpose by the capture bot (`tools/capture/reels.dart`, reels
  08–14). The hover in `02_dont_do_it` is ordinary move/rotate input steered
  over the columns before the bot takes the piece back. Nothing is drawn on a
  board.
- **Nothing is sped up.** A held frame punches in; a slowed clip always
  carries a red REPLAY label.
- **No fake buttons, arrows or stats.** Challenge copy is a question or a
  reaction ("Would YOU have missed that?"), never "only 1% can…". Captions
  describe what is on screen, so check them against the frame when a reel is
  re-recorded — a clear that happens a frame early makes "0 ROWS" a lie.
- **Sound is the game's own**, levelled, plus stingers (buzzer, record
  scratch, riser…) synthesised by `tools/store/ad_sfx.py` — no samples, no
  music, nothing to license.

Layouts: `full` (portrait), `pillar` (square — the whole board, full height,
over a blurred copy of itself, so a piece hovering near the top stays in
frame), `crop`, `split` (BAD / GOOD side by side, two different boards,
labelled), and `panel` (landscape — the board on the right, copy on the left).

```bash
# Record the reels with audio (emulator only — see below)
tools/capture/capture.sh audio-reel gameplay/video 08_edge_hover 09_one_off …

python3 tools/store/ad_sfx.py                    # stingers
python3 tools/store/ad_videos.py                 # all twenty + contact sheet
python3 tools/store/ad_videos.py --only 04_one_column
python3 tools/store/ad_videos.py --verify        # sizes, lengths, audio present
```

### Recording with sound

`screenrecord` has no audio, and scrcpy — which does — is unusable on this
emulator: while any guest-side audio capture runs, the guest's software H.264
encoder stops after ~5 seconds, so the file has a full soundtrack under five
seconds of picture, and nothing reports an error. That held for every audio
codec, `--audio-source=playback`, and a separate audio-only session beside
`screenrecord`. `audio-reel` therefore records with the emulator console
(`adb emu screenrecord`), which encodes on the host: ~21fps with even frame
spacing, and the game's audio. Check a take's picture length per stream
(`ffprobe -show_entries stream=duration`), not the container's — the capture
script prints it.

A take that sits on the GAME OVER overlay ends early: the host recorder writes
no frames while the screen is static. That is fine for the cuts, which only
use the first second of the overlay.

## Regenerating

```bash
# Feature graphics (no emulator needed)
flutter test tools/branding/forge_test.dart --plain-name "forge feature graphic"

# Screenshots — boot the AVD you want first, then:
tools/capture/capture.sh shots gameplay/phone shatter cascade rise_pressure …

# Both tablet slots in one pass. The target argument takes comma-separated
# `outdir@serial` pairs, so each scene is built once and then installed,
# launched and photographed on every device — eight builds for both tablets
# instead of sixteen. Safe only because the harness freezes the frame before
# the screencap, so the second device shoots the identical frame.
tools/capture/capture.sh shots \
  gameplay/tablet7@emulator-5556,gameplay/tablet10@emulator-5558 \
  shatter cascade rise_pressure ghost_drop deep_well tetrofall_clear chain_x3 late_game

# Videos
tools/capture/capture.sh reel gameplay/video 02_blunder_i_well

# Caption frames, and the spec check
python3 tools/store/frame_shots.py --caption tools/store/captions.json
python3 tools/store/frame_shots.py --verify
```

The shot list, board layouts, scores and captions live in
`tools/capture/scenes.dart`; the video scripts live in `tools/capture/reels.dart`.

### Emulators

Three AVDs, all portrait, all natively the exact aspect Play wants so nothing
is ever cropped:

| AVD | Resolution | Density | Shortest width | Slot |
| --- | --- | --- | --- | --- |
| `Tetrofall_Phone` | 1080×1920 | 420 | 411dp | Phone |
| `Tetrofall_Tab7` | 1080×1920 | 280 | 617dp | 7-inch tablet |
| `Tetrofall_Tab10` | 1440×2560 | 280 | 823dp | 10-inch tablet |

```bash
~/Library/Android/sdk/emulator/emulator -avd Tetrofall_Phone -no-boot-anim
```

The Android SDK is not on `PATH` here; `capture.sh` uses absolute paths.

## How the captures avoid the three usual problems

**No ad slots, and no empty ad slot either.** The harness never calls
`AdsService.init()`, so no ad can load. That alone is not enough: the shipped
layout still *reserves* ~90pt for the banner, and an empty reserved band
photographs as dead space. The capture entrypoint mounts the game with
`GameplayScreen(immersive: true)`, which drops the reservation, drops the
board padding and floats the HUD over the board. The board is exactly 9:16
(18×32), so on a 9:16 device it then fills the frame edge to edge.

`immersive` defaults to `false` and nothing in `lib/` passes `true` — the
shipped app keeps its banner and its layout, and
`test/responsive_layout_test.dart` guards that.

**The money frames are three frames long.** The shatter and the ripple cascade
cannot be caught by hand. The harness seeds a board one move from a clear,
lets the demo bot make that move, and calls `TetrofallGame.freezeForCapture()`
a set number of milliseconds after the clear fires — stopping Flame's clock
without raising the pause overlay. `adb exec-out screencap` then has all the
time it needs.

**The full-screen dialog, and the dimming behind it.** The harness mounts
`immersiveSticky`, and the first time a device sees that, Android throws up a
system dialog — "Viewing full screen / To exit, swipe down from the top of
your screen / Got it" — across the top of the screen. Because it is a system
window, Android also dims the app behind it, so the capture comes out both
covered *and* about two stops dark. `capture.sh` now sets
`settings put secure immersive_mode_confirmations confirmed` on every target
before shooting.

This one hid for a while: `Tetrofall_Phone` had the dialog dismissed by hand
at some point, so the phone pass never showed it, and a fresh tablet AVD
produced eight covered, dimmed frames that were otherwise correct. The check
that catches it is the mean-RGB comparison against the phone frame of the
same scene — a dimmed frame lands 30–40 levels low on every channel, while a
correct tablet frame matches its phone counterpart to within 1/255.

## What makes a reel watchable

`01_skilled_run` took nine takes. None of the failures were technical — every
one produced a valid 40-second 1080×1920 H.264 file of the real game. They
were just unusable, and the reasons are worth not rediscovering.

**No seeded board.** Reel 1 was the only reel with no `layout`, so it played
from bare wood. On an 18-wide board a single row costs ~4.5 pieces, so 40
seconds of skilled play moved the score 730 points with the frame ~85% empty.
Reels need `layout` for the same reason stills do.

**The opening happened off camera.** `capture.sh` used to sleep a guessed six
seconds before `screenrecord`, and a seeded board plus a skilled bot resolves
the opening well inside that, so the take recorded the aftermath. Fixed
properly: the harness prints `TETROFALL_CAPTURE_READY` once the board is
seeded *and drawn*, and `capture.sh` blocks on that line in logcat. Cold start
here ranged from two to five seconds depending on how many emulators were up,
so no fixed sleep was ever going to be right.

**The freeze caught a stale frame.** `freezeForCapture()` stops Flame's clock,
so calling it in the same tick as `_seedBoard` froze the board as it looked
*before* the seed — an empty board under a seeded score, because the HUD is
Flutter widgets and repaints regardless. Both the freeze and the ready marker
now wait 150ms for the seeded frame to actually render.

**Takes of the same reel differ, a lot.** This is the one to know about. Net
stack height is the rise rate minus the bot's clear rate — a small difference
of two large numbers — and the bot ticks on a wall-clock `Timer` while rise is
frame-driven, so under emulator load their ratio shifts run to run. Five takes
of the identical config split bimodally:

| | mean luma | sparse frames |
| --- | --- | --- |
| takes 1, 3 | 178, 181 | 0/40 |
| takes 2, 4, 5 | 192–194 | 15–17/40 |

Roughly two takes in five come out dense. So **record several and measure**,
rather than tuning the reel against a single take — two board layouts were
tried and discarded on evidence that turned out to be one noisy sample each.
The durable fix, if this ever needs to be reproducible, is to drive the bot
off the engine's update loop instead of a wall-clock timer, so its rate and
the rise rate share one clock.

The cheap way to judge a take without watching it: sample a frame a second and
print mean luma. The board is dark blocks on light wood, so luma is an inverse
density read — a dull take sits flat above 200, and a good one stays between
165 and 190 for the whole forty seconds.

```bash
# record N takes off the already-installed APK, then measure each
ffmpeg -v error -i gameplay/video/01_skilled_run.mp4 -vf fps=1 /tmp/f_%03d.png
python3 -c "
from PIL import Image, ImageStat; import glob, statistics
v=[ImageStat.Stat(Image.open(f).convert('RGB')).mean[0] for f in sorted(glob.glob('/tmp/f_*.png'))]
print(f'mean {statistics.mean(v):.0f}  sparse {sum(1 for x in v if x>200)}/{len(v)}')"
```

### Uploading it

The Play listing's promo-video slot takes a **YouTube URL**, not a file — the
mp4 has to go to YouTube first. `gameplay/video/` is gitignored, so this file
is local only and is regenerated rather than committed.

## Two minutes is harder than forty seconds

The long cuts run into something the 40-second one does not, and it is worth
understanding before tuning either of them.

Board density over a long take is the rise rate minus the bot's clear rate,
and that has **no stable middle**. Below a threshold the bot out-clears the
floor and the board sits near-empty; above it the floor wins and the run tops
out. Reel 6 measured, at 120s:

| `riseSpeed` | mean luma | sparse | outcome |
| --- | --- | --- | --- |
| 1.4 | 198 | 37/60 | survives, near-empty for 90s |
| 1.8 | 199 | 39/60 | survives, near-empty |
| 2.0 | 171 | 0/60 | dense — but topped out at t=114 |
| 2.8 | 150 | 0/60 | dense — topped out at t=96 |

A promo cut must not end on the GAME OVER overlay, so reel 6 sits on the
dense side at 2.0 and `tools/store/trim_reel.py` cuts the take before the
overlay lands if it appears. Detection is mean luma: live play never goes
below ~140 and the overlay dims the screen to ~50, so the 100 threshold needs
no tuning. Run it over any reel — with no game-over found the file is left
untouched.

```bash
tools/store/trim_reel.py gameplay/video/06_endurance_2min.mp4 --in-place
```

On top of the threshold sits the same take-to-take variance the 40-second cut
has, and at two minutes it compounds. Three takes of reel 6 at an identical
`riseSpeed: 2.0`:

| | mean luma | sparse | outcome |
| --- | --- | --- | --- |
| take 1 | 187 | 7/60 | survived 120s — shipped |
| take 2 | 194 | 23/60 | survived, thinner |
| take 3 | 164 | 0/18 | dense, but died at t=36 |

So record two or three and measure. A take that dies *late* is fine — trimmed,
it yields a dense ~110s cut, which beats a take that survives by being empty.

Reel 7 is subject to the same thing, despite holding mean 184 with no top-out
on its first ever take — a later recapture of the identical config died at
t=86, and three more takes of it then survived at mean 185–188. Do not read one
good take as a stable config for either long reel. Always record a few:

```bash
# after `capture.sh reel …` has built and installed the APK once, extra takes
# cost only the recording — relaunch, wait for the marker, screenrecord again
```
