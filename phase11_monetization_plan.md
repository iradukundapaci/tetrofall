# Phase 11 — Monetization & Release: Detailed Plan

Expands the Phase 11 entry in `game.md` (line 1139) into a standalone plan. **This document supersedes `game.md`'s Phase 11 ad-format decisions** — the original spec called for a banner + rewarded-continue with no interstitials; the strategy below adds capped interstitials and app-open ads on top of the banner, based on general mobile-game ad-format guidance. Store assets and build signing from `game.md` Phase 11 still apply, narrowed to Android only.

**Android only.** This release targets Google Play exclusively — no iOS build, no App Store submission, no iOS-specific ad SDK setup or entitlements. Anything iOS-only (App Tracking Transparency, App Store screenshots, etc.) is out of scope for this phase.

**No IAP at MVP.** There is no purchase flow of any kind — ads run unconditionally for every player.

---

## 1. Ad format strategy

| Format | Priority | Use in Tetrofall |
|---|---|---|
| **Rewarded ads** ⭐⭐⭐⭐⭐ | Primary format | Player-initiated, opt-in. Best revenue-per-view and the only format with no downside to player satisfaction — they choose to watch. |
| **Interstitial ads** ⭐⭐⭐⭐ | Secondary format | Full-screen, shown only between sessions (never mid-run), frequency-capped. |
| **App open ads** ⭐⭐⭐ | Occasional | Shown on cold return from a long background stay. Used sparingly. |
| **Banner ads** ⭐⭐ | Included | Full-width adaptive banner, fixed slot below the board on `gameplay.html`/`pause.html`, matching `game.md`'s original placement (`lib/ui/widgets/banner_ad_slot.dart`, wired into `GameplayScreen`). |

---

## 2. Rewarded ads — placements

Tetrofall has no coin/cosmetic economy at MVP (per the Phase 9 decision: one theme), so rewarded placements are limited to what the current feature set supports:

1. **Continue once after losing** (already in `game.md`) — watch an ad, resume with the whole board cleared, score preserved (the forced clear itself isn't scored). This is the only rewarded placement at MVP.
2. **Deferred, not MVP:** double coins, daily bonus claim, temporary cosmetic/theme unlock — these all require a meta-progression system (coins, multiple themes) that doesn't exist yet. Revisit once/if that system ships. Don't build the ad hooks for these now; there's nothing behind them.

## 3. Interstitial ads — placements & caps

Shown **only on the game-over → main-menu transition**, never mid-run and never on every loss. Endless-style runs here are short (target 90–150 s per `game.md` Phase 10 metrics), so an interstitial after every death would be one every couple of minutes — too aggressive.

Cap logic (whichever threshold hits first, then reset both counters):

- Every **4 completed runs** (games that ended in a loss), OR
- After **~6 minutes** of cumulative play since the last interstitial

Never show one:
- On the very first loss of a fresh session (let the player get a feel for the game first).
- Immediately after a rewarded continue was just watched (don't double up ad exposure back-to-back).

## 4. App open ads — placements & caps

Shown when the app is foregrounded after being backgrounded for **at least 5 minutes**, and never:
- On first install / first-ever launch.
- More than once per hour, regardless of how many times the app is backgrounded/foregrounded.

This is a small, opportunistic revenue source for players who alt-tab away and back — not a format to rely on.

---

## 5. `AdsService` — architecture

Keep the same stub-until-Phase-11 file referenced in `game.md` (`lib/services/ads_service.dart`), now implemented for real:

```
AdsService
  init()                          — load SDK, run consent flow, request first ads
  loadRewardedContinue()          — pre-fetch, called as soon as a run starts
  showRewardedContinue() -> bool  — returns whether reward was granted
  notifyRunEnded()                — increments run counter, maybe shows interstitial
  notifyAppForegrounded()         — maybe shows app-open ad, per cooldown
```

- **Frequency state** (run counter, cumulative play seconds, last-interstitial timestamp, last-app-open timestamp) lives in `StorageService` alongside settings so caps survive an app restart.
- **Pre-fetching**: request the next rewarded ad and interstitial as soon as the current one is consumed/shown, not at the moment of need — avoids a spinner on the game-over screen.
- **Offline behavior**: every `show*()` call must fail silently and instantly if no ad is loaded (airplane mode, no fill). Continue-after-loss must never block on a network call — if the rewarded ad can't load, hide/disable the continue option rather than showing a broken prompt.
- Ad network SDK is not yet a dependency (`pubspec.yaml` currently has none) — add it in this phase, not before, so it isn't dead weight during earlier phases. Only the Android side needs configuring (AdMob App ID in `AndroidManifest.xml`, Android ad unit IDs) — skip any iOS setup (`Info.plist` entries, iOS ad unit IDs).

## 6. Consent & compliance

Needed before any ad SDK initializes:

- **Google UMP / consent form** (or equivalent) for GDPR/EEA users, and California/US state privacy signals if the ad network requires it.
- **Google Play Data Safety form** must declare ad-partner data collection accurately, or the listing gets rejected/pulled.
- **Privacy policy** (already listed as a Phase 11 asset in `game.md`) must describe ad-partner data sharing.

---

## 7. What you check

1. Install the **release** build (signed AAB/APK) on a real Android device, not debug.
2. Play a fresh session: no interstitial on the first loss; one appears only after the 4-run / 6-minute cap trips.
3. Lose a run, watch the rewarded continue ad: run resumes with the whole board cleared, score intact.
4. Confirm no interstitial fires immediately after a rewarded continue.
5. Background the app for 5+ minutes, foreground it: one app-open ad, not a rewarded or interstitial. Repeat within the same hour — no second app-open ad.
6. Confirm the banner loads below the board on the gameplay screen and stays put (no overlap with HUD/board) when paused; confirm it collapses cleanly with no crash if the banner fails to load.
7. Full run in airplane mode: no crashes, no hangs waiting on an ad, continue option gracefully unavailable if nothing loaded.
8. Confirm the UMP consent flow appears once, at the right time, and ad requests respect the user's choice.

---

## 8. Open questions

1. If a player declines tracking consent, do non-personalized ads still meet revenue expectations?
2. Should the free continue (no ad available) be capped to once per run, same as the ad-backed one, to avoid a workaround for infinite continues when offline?
3. Revisit rewarded-ad placements (double coins, cosmetic unlock, daily bonus) once/if a coin economy or multiple themes ship post-MVP.
