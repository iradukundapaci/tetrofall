# Phase 11 — Monetization & Release: Detailed Plan

Expands the Phase 11 entry in `game.md` (line 1139) into a standalone plan. **This document supersedes `game.md`'s Phase 11 ad-format decisions** — the original spec called for a banner + rewarded-continue with no interstitials; the strategy below adds capped interstitials and app-open ads on top of the banner, based on general mobile-game ad-format guidance. Store assets and build signing from `game.md` Phase 11 still apply, narrowed to Android only.

**Android only.** This release targets Google Play exclusively — no iOS build, no App Store submission, no iOS-specific ad SDK setup or entitlements. Anything iOS-only (App Tracking Transparency, App Store screenshots, etc.) is out of scope for this phase.

**No IAP.** There is no real-money purchase of any kind. Monetization is rewarded video converted into Coins — see §0, which supersedes the rewarded placements in §2 and the banner row in §1.

---

## 0. Coin economy

Nobody ever has to pay. Rewarded video is the **only** faucet, and it pays in **Coins**; Coins are the only price. Every "watch an ad for X" prompt is gone — the continue, booster refills and loadout re-spins all cost Coins, and an empty wallet routes to the earn screen rather than putting an ad in front of the player at the moment they are trying to play. All numbers live in `lib/game/config/economy_tuning.dart`.

**Conversion: 1 rewarded view = 50 Coins.** Every price is designed as a multiple of that. It deliberately pays far above an ad's cash value (~$0.005–0.015 a view): the old shop mockup's 500 Coins = $0.99 would make fair value ~5 Coins an ad.

| Faucet | Pays |
|---|---|
| Rewarded view, 1st–10th of the day | 50 |
| 11th–20th / 21st+ | 35 / 25 — a taper, never a cap |
| Every 5th view in a row | +50 streak bonus |
| Daily challenges (3/day) | 50 each — the zero-ad floor |
| 7-day login calendar | 50 / 100 / 200 Coins, booster charges, Mystery Chest on day 7 |
| First launch | 200 |

| Sink | Coins |
|---|---|
| Booster charge — Small / Line / Area / Board | 80 / 100 / 150 / 220 (3-packs 190 / 240 / 360 / 530) |
| Loadout re-spin (after the free one) | 30, max 3 a run |
| Continue after loss | 120, once a run |
| Mystery Chest | 250 |
| Themes — Marble / Snow / Candy | 300 / 350 / 450 |
| Clear Skies 30 min / 2 h / 6 h | 150 / 500 / 1200 |

**Clear Skies** is timed ad-free play and replaces Remove Ads. It suppresses only *involuntary* ads — the game-over interstitial and the app-open ad — never rewarded video, which is the faucet: a player who could switch that off could spend their way into an economy with no income. It is metered in **game time** (it drains only while a run is in `playing`/`resolving`, never on the menu demo, the pause sheet or game over), and each suppressed app-open ad debits 60 s, because foregrounding is not game time. Prices are set above the interstitial revenue they give up (~1 interstitial per 6 min of play at ~⅓ rewarded eCPM → 1.2–1.7× margin). There is no permanent tier.

**Per-run caps stay** (1 continue, 2 refills, 3 bought re-spins). Price sets the pace; caps keep the run a game.

**Code:** `WalletService` (balance, charges, themes), `ClearSkiesService`, `DailyService`, `MysteryChest`, bundled as `Economy` and built in `main()`. The earn screen is `CoinVaultScreen`; `AdsService` keeps a pool of two rewarded ads so back-to-back views never wait on a spinner. The door is left open for optional Coin packs later without re-pricing anything.

---

## 1. Ad format strategy

| Format | Priority | Use in Tetrofall |
|---|---|---|
| **Rewarded ads** ⭐⭐⭐⭐⭐ | Primary format | Player-initiated, opt-in, and the only source of Coins (§0). Best revenue-per-view and the only format with no downside to player satisfaction — they choose to watch. |
| **Interstitial ads** ⭐⭐⭐⭐ | Secondary format | Full-screen, shown only between sessions (never mid-run), frequency-capped. |
| **App open ads** ⭐⭐⭐ | Occasional | Shown on cold return from a long background stay. Used sparingly. |
| ~~**Banner ads**~~ | Removed | The slot below the board became the booster bar (`boosters.md` §4.1). `lib/ui/widgets/banner_ad_slot.dart` still exists but nothing mounts it. |

---

## 2. Rewarded ads — placements

> **Superseded by §0.** There is now one rewarded placement, the Coin faucet (`AdPlacements.rewardedCoins`). The continue below is bought with Coins; the section is kept for the reasoning behind it.

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
- Immediately after a rewarded view was just watched (don't double up ad exposure back-to-back).
- While the player has Clear Skies balance (§0) — the counters are zeroed rather than banked, so no interstitial fires the instant it runs out.

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
  showRewardedCoins() -> bool     — the Coin faucet; a pool of 2 is kept loaded
  rewardedCoinsReady              — listenable count, drives the earn button
  notifyRunEnded()                — increments run counter, maybe shows interstitial
  notifyAppForegrounded()         — maybe shows app-open ad, per cooldown
```

- **Frequency state** (run counter, cumulative play seconds, last-interstitial timestamp, last-app-open timestamp) lives in `StorageService` alongside settings so caps survive an app restart.
- **Pre-fetching**: request the next rewarded ad and interstitial as soon as the current one is consumed/shown, not at the moment of need — avoids a spinner on the game-over screen.
- **Offline behavior**: every `show*()` call must fail silently and instantly if no ad is loaded (airplane mode, no fill). The earn button must never be drawn when no Coin ad is loaded (`rewardedCoinsReady == 0`); the continue and every other purchase are Coins, so none of them block on the network.
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
3. Lose a run and continue for 120 Coins: run resumes with the whole board cleared, score intact. With too few Coins, the continue opens the Coin Vault and the run is still there on return.
4. Confirm no interstitial fires immediately after a rewarded view.
5. Background the app for 5+ minutes, foreground it: one app-open ad, not a rewarded or interstitial. Repeat within the same hour — no second app-open ad.
6. Confirm the banner loads below the board on the gameplay screen and stays put (no overlap with HUD/board) when paused; confirm it collapses cleanly with no crash if the banner fails to load.
7. Full run in airplane mode: no crashes, no hangs waiting on an ad; the Coin Vault shows no earn button; daily challenges and the login calendar still pay.
8. Confirm the UMP consent flow appears once, at the right time, and ad requests respect the user's choice.

---

## 8. Open questions

1. If a player declines tracking consent, do non-personalized ads still meet revenue expectations?
2. ~~Cap the free continue?~~ Moot: the continue costs Coins and is once a run whatever pays for it.
3. ~~Revisit rewarded-ad placements once a coin economy ships.~~ Shipped — §0.
4. Optional Coin packs (IAP) as a shortcut for players who want one. The prices in §0 were set so they can be added without re-pricing anything.
