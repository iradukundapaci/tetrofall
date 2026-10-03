# Ads slim-down — drop banner, app-open and rewarded-interstitial

Keep **interstitial** and **rewarded** only. Reclaim the banner strip for the
board. Recover the lost revenue from the two formats that remain, without the
player feeling more advertised to.

Baseline: `main` @ `e507900`, app version `1.1.3+11`, Android + iOS live.

---

## 1. The hole, exactly

From the AdMob report (`Screenshot 2026-10-03 at 11.07.47.png`):

| Ad unit | Format | eCPM | Earnings | Impressions | Fate |
|---|---|---:|---:|---:|---|
| Playareabanner | Banner | $0.63 | $1.26 | 2,015 | **drop** |
| tetrofallInterstitial | Interstitial | $4.08 | $0.75 | 185 | keep |
| tetrofallrewarded | Rewarded | $4.06 | $0.25 | 61 | keep |
| tetrofallappopen | App open | $1.41 | $0.14 | 101 | **drop** |
| Tetrofall rewarded | Rewarded interstitial | — | $0.00 | 0 | **drop** |
| **Total** | | **$1.02** | **$2.41** | **2,362** | |

- Surviving revenue: **$1.00** (41.5% of $2.41) from **246** impressions.
- Hole to close: **$1.40**.
- Blended eCPM of what survives: **$4.07**.
- So closing the hole purely with more full-screen impressions needs
  **+344 impressions**, i.e. 246 → **590 (2.4×)**. Pulling that from frequency
  alone would be very noticeable. It has to come from four different places.

**The banner was 85% of impressions and 52% of revenue at $0.63.** Once it is
gone the account's blended eCPM jumps from $1.02 to ~$4. That is a reporting
artefact, not income — judge this change on **ARPDAU**, never on eCPM.

### The one number to look up first

2,015 banner impressions ≈ one per auto-refresh period of board time. Check the
banner unit's refresh setting in the AdMob console before deleting it:

| Banner refresh | Board time in the window | Current interstitial cadence |
|---|---|---|
| 60 s | ~33.6 h | 1 per **10.9 min** of play |
| 30 s | ~16.8 h | 1 per **5.4 min** of play |

The code already permits one interstitial per **2 runs or 180 s of play**
(`AdsService._interstitialRunCap`, `_interstitialPlaySecondsCap`). Either way
the shipped cadence is **under-delivering** — at 60 s refresh, by about 3×.
That gap is lever D and it costs the player nothing, because the permission to
show those ads is already shipped.

---

## 2. Where the $1.40 comes back

Four levers, ordered by cost-to-the-player (cheapest first).

### Lever A — price, not frequency (invisible) · +$0.20–0.30

Nothing the player can see. Pure eCPM on the two surviving formats.

- `android/app/build.gradle.kts` currently carries **Unity Ads** and **Liftoff
  Monetize** adapters only; the file's own comment says AppLovin is held back
  pending account approval, and Meta / InMobi were dropped. Re-check all three —
  three extra bidders on interstitial + rewarded is the standard 15–30% eCPM
  lift, and it applies to every impression the other levers create.
- Move the Unity and Liftoff ad sources from waterfall to **bidding** in the
  mediation groups, if they are not already.
- Delete the banner and app-open **mediation groups** once the units go (§5),
  so no group is left optimising for a format that no longer requests.
- Open Ad Inspector on a device once after the change to confirm every adapter
  still answers (`MobileAds.instance.openAdInspector`).

### Lever B — relocate the app-open moment (near-invisible) · +$0.15–0.25

App-open earned $0.14 across 101 impressions at $1.41. The *moment* is worth
keeping; the *format* is the worst-paid one in the account.

Replace it with an **owed break**: when the app returns from background, don't
show anything — arm the interstitial cadence so the **next natural break**
(game over → Play Again, or quit → Home) shows an interstitial instead.

- Same number of interruptions as app-open does today, because the arming
  reuses app-open's own caps: ≥30 s backgrounded, ≥15 min since the last owed
  break, tutorial finished, not a click-out to an ad.
- Each one is worth **$4.08 instead of $1.41** — 2.9×.
- It is *less* intrusive: nothing fires on launch or resume, which is also what
  keeps it inside AdMob's interstitial policy (never on app open).
- At 70% conversion (some sessions end without reaching a break):
  ~70 impressions ≈ **$0.29**, against $0.14 today.

### Lever C — rewarded supply (opt-in, zero annoyance) · +$0.32–0.44

The biggest single gap. 61 rewarded impressions against 185 interstitials is
backwards: rewarded pays the same ($4.06 vs $4.08) and the player **asks** for
it. With interstitials firing every ~2 runs, the window held roughly 370 game
overs — a **~16% take rate** on the continue offer.

Three fixes, no new game systems required:

1. **Never show a dead button.** `GameOverOverlay` currently renders a disabled
   `'Loading Ad…'` primary button when the rewarded ad is not in hand
   (`game_over_overlay.dart:184-199`). Every one of those is a lost impression
   *and* a lost tap. Load the rewarded ad at **run start** (not only on
   dismissal) so it is nearly always ready; if it still isn't, drop the
   continue row entirely and promote `Play Again`.
2. **Lead with the reward, not the ad.** `'Watch Ad to Continue'` →
   `'Continue — keep 12,480'` with the play glyph kept as the secondary signal.
   The board-clear is a genuinely good deal; the current label sells the cost.
3. **A second placement: head start.** Opt-in before a run — watch an ad, start
   with the bottom rows pre-cleared or the rise slowed for the first 30 s. The
   engine already takes `RunConfig` / `initialElapsed`, so this is a config
   tweak plus a button on the game-over card's Play Again row and on the main
   menu. At 10% of runs that is ~37 impressions.

Realistic landing: 61 → **140–170** impressions.

> Not recommended: "double your score" rewarded. It devalues `bestScore`, which
> is the only progression in the build. The `coin-economy` branch is the proper
> home for rewarded demand — when it lands, this lever has far more room.

### Lever D — make the shipped cadence actually deliver (invisible) · +$0.15–0.25

Do **not** tighten the caps first. Fix why the existing caps under-fire:

- `_showInterstitial()` returns null when nothing is loaded; the counters stay
  due, so it only *delays* — except when the session ends while owed. Persist
  nothing new (the counters already survive cold start), but **prefetch
  earlier**: reload the interstitial at run start as well as on dismissal.
- The 60 s `_fullScreenAdGap` and the "skip right after a rewarded continue"
  rule are player protections. **Keep both.**
- Only if A–C land short: `_interstitialPlaySecondsCap` 180 → 150. Leave
  `_interstitialRunCap` at 2. This is the one lever a player could notice, so
  it goes last and behind a Remote Config flag.

### Lever E — a bigger board sells more sessions (slow, real)

No banner and a 6–18% larger board (§4) should move session length and D1.
Impressions follow session count. Don't model it; do watch it.

### Where that lands

| | Impressions | Revenue |
|---|---:|---:|
| Surviving today | 246 | $1.00 |
| + Lever A (eCPM) | — | +$0.20–0.30 |
| + Lever B (owed break) | +70 | +$0.15–0.25 |
| + Lever C (rewarded) | +80–110 | +$0.32–0.44 |
| + Lever D (cadence delivery) | +40–60 | +$0.15–0.25 |
| **Projected** | **~440–490** | **$1.82–2.19** |
| Was | 2,362 | $2.41 |

**76–91% of the old revenue**, at a materially better experience, with Lever E
closing the rest over the following weeks. Be honest with yourself about this:
a 58% revenue cut does not fully reverse in one release. If the number has to
be 100% on day one, the banner has to stay.

---

## 3. Guardrails — what "not highly noticeable" means here

Supply is going up, so the ceilings matter more than before. These are the
rules the implementation must not break:

- **Never mid-run.** Only at game over → Play Again / Home, and quit → Home.
- **Never on launch or resume.** Lever B arms a later break; it never shows.
- **One full-screen ad per 60 s**, account-wide (`_fullScreenAdGap`).
- **Never straight after a rewarded continue** (`_justWatchedRewardedContinue`).
- **Nothing before the tutorial is done** (`_storage.tutorialSeen`).
- **New: a per-session interstitial cap** (suggest 4) and a per-day cap
  (suggest 8). Cheap insurance now that three levers push in the same
  direction. Store alongside the existing counters in `StorageService`.
- Rewarded stays opt-in and skippable, always.
- Target cadence after all levers: **one interstitial per ~7–8 min of play** —
  still looser than the caps already shipped, and well inside the casual-game
  norm of one per 3–5 min.

---

## 4. The board — and why removing the banner is not enough on its own

This is the part that is not obvious, so it gets the detail.

`_GameplayBody` lays the board out as `AspectRatio(9/16)` inside `Center`
inside `Expanded` (`gameplay_screen.dart:673-700`). The board takes
`min(availableWidth, availableHeight × 0.5625)`. **Freed vertical space only
becomes a bigger board while the board is height-bound.**

Current horizontal budget: `width − 2 × ui.spaceSm` (8 pt × scale per side).
On a tall Android phone the board is *already* width-bound — so removing a
90 pt banner adds 90 pt of empty letterbox and **zero** board.

Measured against the real formulas (`ui_scale.dart`, `estimateBannerHeight`):

| Device | Banner | Board now | Banner out, padding kept | Banner out, padding → `ui.px(2)` |
|---|---:|---|---|---|
| 393×873 Android (top 40 / bottom 24) | 90 | 376 × 669 | 376 × 669 — **+0%** | 389 × 691 — **+6.8% area** |
| 393×852 iPhone 15 Pro (top 59 / bottom 34) | 90 | 358 × 636 | 376 × 669 (+10.6%) | 389 × 691 — **+18.1% area** |
| 375×667 iPhone SE (top 20 / bottom 0) | 50 | 306 × 544 | 333 × 591 (+18%) | 333 × 591 — **+18.0% area** |

So the layout change is two things, not one:

1. **Remove the banner slot** and reserve `max(viewPadding.bottom, ui.spaceXs)`
   at the bottom instead. The banner used to absorb the home-indicator inset
   via `bannerBottomInset`; without that guard the board would sit under the
   gesture bar, and the board takes drags — system swipes would eat them.
2. **Cut the horizontal board padding** from `ui.spaceSm` to `ui.px(2)`, so the
   width-bound case can actually use the screen. Without this, tall Android
   phones gain nothing. `boardWantsHeight` at `gameplay_screen.dart:596` and
   `boardPadding` at `:608` hardcode the same inset twice — derive one from the
   other while you are in there.

Leftover vertical slack on tall screens (~50 pt) stays as symmetric bands via
`Center`. That reads as deliberate framing, and the bottom band doubles as a
thumb-rest clear of the board's gesture area.

**Out of scope, flagged:** growing `BoardConfig.rows` (32) to swallow the rest
of the height is the only way to fully fill a tall screen, and it is a
difficulty change — more vertical room means more time before top-out. It
would need Director retuning and a sim sweep. Keep the 18:32 playfield for this
release.

`tools/capture/main.dart` already mounts gameplay `immersive: true`, which is a
bannerless full-bleed board — so the renderer is known to handle the wider
layout. Flame resizes via `onGameResize`; confirm on device that a mid-run
rotation or inset change doesn't desync the grid.

---

## 5. Code changes, file by file

**`lib/ui/widgets/banner_ad_slot.dart`** — delete the file.

**`lib/ui/screens/gameplay_screen.dart`**
- Drop the `BannerAdSlot` child and its import.
- Drop `bannerHeight` (`:587`) and `bannerBottomInset` (`:601`).
- `chrome` becomes `viewPadding.top + ui.hudHeight + ui.spaceXs * 2 + bottomGuard`,
  where `bottomGuard = math.max(viewPadding.bottom, ui.spaceXs)`.
- Add the bottom guard as a `SizedBox` after the `Expanded`, or as bottom
  padding on it.
- Horizontal board padding `ui.spaceSm` → `ui.px(2)`; keep the two sites in sync.

**`lib/ui/screens/splash_screen.dart`**
- Drop the `resolveBannerSize` prefetch in `_preloadAssets` (`:70-73`). Keep
  `dart:async` — `unawaited` is still used at `:90`.

**`lib/services/ads_service.dart`**
- Banner sizing out: `fallbackBannerHeight`, `estimateBannerHeight`,
  `reservedBannerHeight`, `resolveBannerSize`, `_resolveBannerSize`,
  `_bannerSize`, `_bannerSizeWidth`, `_bannerSizeFuture`.
- App-open out: `_appOpenAd`, `_appOpenLoadedAt`, `_appOpenTtl`,
  `_appOpenRetry`, `_appOpenLoadRevision`, `_loadAppOpen`,
  `_maybeShowAppOpenAd`, and the app-open branches in `dropExpiredAds`,
  `_discardCachedAds`, `_onOnlineChanged`, `_retryNow`, `_startAdsIfAllowed`,
  `setPersonalizedAds`, `dispose`.
- **Keep** `_backgroundedAt`, `notifyAdClicked`, `_adClickGrace` and the
  `leftForAd` guard — Lever B reuses all of them.
- Rename `_appOpenMinBackgroundDuration` → `_owedBreakMinBackground` (30 s) and
  `_appOpenMinInterval` → `_owedBreakMinInterval` (15 min).
- Add `_breakOwed`, set on resume under those caps, consumed in
  `notifyRunEnded` as a third `due` condition, cleared when an ad shows.
- Add the per-session / per-day interstitial caps from §3.
- Prefetch rewarded + interstitial at run start (new `notifyRunStarted()`,
  called from `_startTrackedRun`).

**`lib/services/ad_unit_ids.dart`** — drop `banner` and `appOpen`; drop
`AdPlacements.banner` and `AdPlacements.appOpen`. (Add `AdPlacements.headStart`
if Lever C.3 ships.)

**`lib/services/analytics_service.dart`** — drop `AdKind.banner`. The app-open
comment above `AdKind` becomes stale; the owed break reports as a plain
`interstitial` at the `interstitial` placement, which is correct.

**`lib/services/storage_service.dart`** — drop `_bannerAdWidthKey`,
`_bannerAdHeightKey`, `bannerAdHeightForWidth`, `saveBannerAdSize`,
`_lastAppOpenAdEpochMsKey`, `lastAppOpenAdShownAt`, `saveLastAppOpenAdShownAt`.
Add keys for the owed-break timestamp and the session/day caps. Orphaned
prefs on existing installs are harmless; no migration.

**`lib/ui/screens/game_over_overlay.dart`** — Lever C.1 and C.2.

**`lib/services/remote_flags.dart`** — see §7.

**Existing tests that stop compiling** (removal only, not new coverage):
`test/ads_connectivity_test.dart:159-168` (banner-size caching),
`test/analytics_events_test.dart:348` (`AdKind.banner`),
`test/responsive_layout_test.dart:115-134` (the immersive group's premise is
"the shipped layout keeps its banner"), and the banner wording in
`test/ads_personalization_test.dart`.

---

## 6. AdMob console — and the ordering trap

**Do not delete the ad units when you merge the code.** Players on 1.1.3 keep
requesting the banner and app-open units for weeks. A deleted unit stops
serving within about an hour and those installs just get errors — you lose the
revenue the old build was still earning, for nothing.

Order:

1. Ship the new build. Old installs keep earning from banner / app-open.
2. Watch the Play Console / App Store Connect version adoption.
3. When the pre-change versions are a negligible share of DAU (typically 3–6
   weeks), delete in the console:
   - `Playareabanner` (banner) — **both** the Android and iOS apps; the code
     carries a separate unit id per platform for every format.
   - `tetrofallappopen` (app open) — both apps.
   - `Tetrofall rewarded` (rewarded interstitial) — never implemented in code,
     0 impressions, safe to delete immediately.
4. Delete the mediation groups that targeted those units (Lever A).

Historical reporting for deleted units is retained, so the before/after
comparison survives.

No change needed to `AndroidManifest.xml` / `Info.plist` — the AdMob app id
stays. No change to `app-ads.txt`.

---

## 7. Remote Config levers

`RemoteFlags` already has the pattern (in-code default + Firebase override).
Add, so none of this needs a release to back out:

| Key | Default | What it does |
|---|---|---|
| `owed_break_enabled` | `true` | Lever B master switch |
| `owed_break_min_interval_s` | `900` | How often a return can arm a break |
| `interstitial_play_seconds_cap` | `180` | Lever D's last resort, tunable to 150 |
| `interstitials_per_session_cap` | `4` | Guardrail |
| `rewarded_head_start_enabled` | `false` | Lever C.3, dark-launch then enable |

---

## 8. Rollout order

1. **Removal + board** (§4, §5) — ship alone. This is the player-facing half
   and it is a pure improvement; let it get its own read on retention.
2. **Lever A** (console only, no release) — can run in parallel from day one.
3. **Lever D's prefetch** + guardrail caps — same release as 1 if convenient.
4. **Lever B**, flag-gated.
5. **Lever C.1 / C.2** (button behaviour), then **C.3** (head start) once the
   take-rate move is measured.
6. **Lever D's cap tightening** only if the numbers still fall short.

### What to watch (GA4 + GameAnalytics; placements are already instrumented)

- **ARPDAU** — the only honest scoreboard. Not eCPM.
- Impressions per DAU, split by format.
- Rewarded **take rate** at game over (`continue:offered` → `continue:accepted`
  → `continue:earned` are already logged in `gameplay_screen.dart`).
- Interstitial **fill rate** at the moment of a break (`AdOutcome.failed` /
  `AdFailure.noFill`) — this is what Lever D is really fixing.
- Session length and D1/D7 retention — Lever E's proof.
- Give it a full week before judging; a 58% revenue cut will look alarming on
  day one no matter what.

### Verify by hand on a device

Medium_Phone_API_36 with `--profile`, plus one short screen (SE-class) and one
tall 20:9 Android: board fills the freed space, nothing sits under the gesture
bar, the board accepts drags right to its bottom edge, no interstitial on
launch or resume, the owed break fires at the *next* game over after a 30 s
background, and the continue button is never a dead "Loading Ad…".

---

## 9. Decisions for you

1. **Accept 76–91% recovery?** If day-one parity is required, the banner has to
   stay. (§2)
2. **Head start rewarded placement** — new game surface. In or out? (Lever C.3)
3. **Continue countdown** on the game-over card ("Continue (5…)") would lift
   take rate several points but is the one Lever C item a player *would*
   notice. In or out?
4. **`BoardConfig.rows`** — leave at 32 this release, or open a separate
   difficulty experiment to fill tall screens properly? (§4)
5. **AppLovin / Meta / InMobi** — is the account approval situation in
   `android/app/build.gradle.kts:125-134` still accurate? Lever A is the
   cheapest money in this document and it is blocked on that answer.
