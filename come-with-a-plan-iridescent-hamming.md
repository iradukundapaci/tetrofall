# Coin Economy — Ad-Only Monetization

## Context

Tetrofall should be fully playable without anyone ever spending real money. All
monetization runs through **rewarded video**, converted into one soft currency
(**Coins**). Coins buy everything: booster charges, re-spins, continues, themes,
loot chests, and timed ad-free play. Every existing "watch an ad for one more
re-spin / one more refill" prompt is deleted — those moments spend Coins, and an
empty wallet sends the player to the earn screen instead of to a paywall.

The surprise from exploration: **this economy already exists as HTML mockups,
priced for IAP.** `screens/shop.html` sells coin packs ($0.99–$7.99), a $4.99
Starter Pack, Remove Ads at $2.99, and coin-priced boosters (Hammer 80, Drill
100, Lightning 150). `screens/themes.html` has nine themes at 300–800 coins.
`daily-reward.html` grants coins and `Bomb x1`. None of it exists in Dart —
`settings_screen.dart:25-29` and `phase11_monetization_plan.md:7` record the coin
economy as a deliberate MVP cut, not an oversight.

So this is largely a **rebase from dollars to ad-views**, plus deleting the
dollar paths. What ships today is a mature AdMob layer (UMP consent,
personalisation switch, connectivity-aware retry, GA4 consent mode, four units)
with rewarded-continue live and the two booster placements still on a 1.8 s mock.

### Decisions taken

| Question | Decision |
| --- | --- |
| Real-money purchases | Ads-only at launch; keep the wallet and pricing shaped so optional coin packs can be added later |
| Timed ad-free scope | Suppresses interstitials **and** app-open ads; game-clock metered, plus a fixed debit each time an app-open ad is skipped |
| Earn pace | **1 ad = 50 Coins**, keeping the mock prices as-is |
| Themes | Build 3 now (plumbing already supports more) |

---

## 1. The conversion rate

**1 rewarded ad = 50 Coins.** Every price is designed as a multiple of that, so
the design question is never "how many coins?" but "how many ads is this worth?"

This deliberately pays far above an ad's cash value. At the mock's own rate (500
coins = $0.99) a coin is worth ~$0.002, and a rewarded view earns ~$0.005–0.015 —
so "fair value" would be ~5 coins per ad and a Hammer would cost 16 ads. Paying
50 keeps every mock price intact while making the shop reachable. The rate is the
single tuning knob for the whole economy; put it in one constant.

### Revenue reality check

| Metric | Realistic range |
| --- | --- |
| Rewarded eCPM | $5–15 (US/UK/CA), $1–3 (tier 3) |
| Interstitial eCPM | Roughly 1/3 of rewarded |
| Revenue per rewarded view | ~$0.005–0.015 |
| Rewarded views/day, engaged player | 5–20 |
| Resulting ARPDAU | ~$0.03–0.15 |

A pure-ad economy has **no whale**: the most devoted player alive can only give a
few dollars a year, because they only have so many minutes. That is an acceptable
trade for "nobody ever has to pay" — but it is a decision with a price tag. This
is why the wallet is built so coin packs can be dropped in later without
reworking prices: your goal is that nobody *has to* pay, which is compatible with
letting someone *choose* to.

---

## 2. Faucet — earning Coins

| Source | Yield | Notes |
| --- | --- | --- |
| Rewarded ad, views 1–10/day | 50 each | Full rate |
| Rewarded ad, views 11–20/day | 35 each | Soft taper |
| Rewarded ad, views 21+/day | 25 each | Soft taper |
| Streak bonus | +50 | Every 5th consecutive view in one sitting |
| Daily login streak | 50 / 100 / 200 + charges | Existing 7-day calendar mock; Day 7 = Mystery Chest |
| Daily challenges | 50 × 3 | The zero-ad floor |
| First-launch grant | 200 | So the shop is explorable before the first ad |

Engaged player: ~10 ads (500) + challenges (150) + login (~100) ≈ **750 coins/day**
— a 450-coin theme inside a day, matching the chosen pace.

**Taper, not a cap.** Never block earning; that punishes your best player. The
taper also matches reality, since mediation fill rate and eCPM both degrade under
heavy same-day frequency anyway.

**Never hard-depend on fill.** Ads no-fill. Challenges and login coins must be
enough to keep progressing with zero ad views — slower, but never stuck. This is
already the house rule in `boosters.md` §4.9 Rule 4: *"Never offer what can't be
delivered."*

### Watching many ads without friction

This is the highest-leverage part of the plan — the faucet's throughput sets the
size of the whole economy.

- **A dedicated earn screen** ("Coin Vault"), reachable from the main menu, the
  shop, and every insufficient-funds moment. Loop: watch → `+50` counts up → the
  next ad is *already preloaded* and the button is armed → tap again. Never
  bounce back to a menu between views; that is what kills multi-view sessions.
- **Preload pool of 2.** Start loading the replacement on
  `onAdShowedFullScreenContent`, not on dismiss, so "Watch next" is never a
  spinner. A spinner between ads is the difference between a 6-ad session and a
  2-ad one.
- **Separate ad unit.** Add `rewardedCoins` rather than reusing
  `rewardedContinue`, so the two placements stay comparable in analytics.
- Reuse the existing `_AdRetry` backoff (`ads_service.dart:14-45`) and
  `ConnectivityService`.

---

## 3. Sinks — spending Coins

### Booster charges

Boosters are *rolled* into four slots each run (`loadout_roller.dart`), which
conflicts with a shop that sells boosters by name. Reconciled with a **charge
inventory**: the roll decides which four boosters are *available* this run and
each starts with 1 free charge; owned charges let you recharge a spent slot
mid-run. The shop and daily rewards top up that inventory — which is exactly the
"boosters filled with coins" model, and it matches `daily-reward.html` already
granting `Bomb x1`.

Priced by slot tier, which is the game's own power-and-scarcity ladder
(`boosters.md` §13 plans Small/Line common, Area uncommon, Board rare):

| Tier | Boosters | 1 charge | 3-pack (−20%) |
| --- | --- | --- | --- |
| Small | Hammer, Bomb, Patch | 80 | 190 |
| Line | Drill, Slide, Pillar | 100 | 240 |
| Area | Sweep, Lightning, Mortar | 150 | 360 |
| Board | Earthquake, Tilt, Wildfire | 220 | 530 |

Matches the mock exactly for Hammer (80), Drill (100) and Lightning (150);
normalizes Bomb 120 → 80 since it is Small tier. The six boosters with no mock
price inherit their tier's.

### Everything else

| Item | Price | Rationale |
| --- | --- | --- |
| Slot re-spin | 30 | High frequency, sub-ad price; cap 3/run as today |
| Continue after loss | 120 | Saves a whole run; stays 1/run |
| Mystery Chest | 250 | Loot box; see below |
| Theme — Marble | 300 | Mock price |
| Theme — Snow | 350 | Mock price |
| Theme — Candy | 450 | Mock price |
| Clear Skies 30 min | 150 | See §4 |
| Clear Skies 2 h | 500 | |
| Clear Skies 6 h | 1200 | |

**Per-run caps are the balance lever, not price.** Keep 2 refills, 3 re-spins and
1 continue per run. Without them, a rich player turns the board into a sandbox
and the game stops being a game. Price controls *pace*; caps control *difficulty*.

**Mystery Chest contents** — weighted roll over coins (100–400), booster charges
(1–3 of a random tier), or an unowned theme (rare). Never roll an owned theme; if
all are owned that outcome becomes coins. Pity rule: guaranteed non-coin reward
every 4th chest, so the chest never feels like a coin laundry.

---

## 4. Clear Skies (timed ad-free play)

### The hole this had to solve

As originally stated, timed "No Ads" is self-contradictory: if coins come only
from ads, spending coins to remove ads spends your only income to destroy your
only income. Worse, rewarded ads are *opt-in*, so if "no ads" included them the
player could disable their own faucet and soft-lock the economy.

Scoped to **involuntary ads only** — rewarded is never suppressed:

- Interstitial on game over → menu (`ads_service.dart:577`)
- App-open ad on foreground (`ads_service.dart:683`)

Rename the store entry from "Remove Ads" to **Clear Skies**, with copy that says
so plainly: *"No interruptions while you play. Rewarded ads stay available
whenever you want Coins."* Truthful, and it keeps the faucet open.

### Pricing it so it does not lose money

It is bought with ad-derived coins, so it trades *rewarded revenue* for *skipped
interstitial revenue* and must be priced above cost. Using the shipped caps
(`_interstitialRunCap = 4`, `_interstitialPlaySecondsCap = 360`) and 90–150 s
runs, the 6-minute cap trips first → **~1 interstitial per 6 min of game time**.
At ~1/3 rewarded eCPM:

| Tier | Interstitials skipped | Revenue forgone | Price | Margin |
| --- | --- | --- | --- | --- |
| 30 min | ~5 | ~90 coins | 150 | 1.7× |
| 2 h | ~20 | ~340 coins | 500 | 1.5× |
| 6 h | ~60 | ~1010 coins | 1200 | 1.2× |

Margin narrows with tier size — that is the volume discount — but stays above 1×.
**No permanent tier**, which would end ad revenue from that player forever.

App-open ads fire on foregrounding, which is *not* game time, so suppressing them
free would be a leak. Each suppressed app-open ad **debits 60 s** of balance. At
most one per hour, so it is a few debits a session.

### Why game-clock metering is right

Wall-clock timers leak value — buy it, close the app, it expires unused — and
create anxiety. A clock that advances only while a run is live means coins buy
*runs*, not *minutes of your life*. Easier to communicate, too: "150 Coins ≈ your
next 10 runs, uninterrupted."

Three traps found in the code:

1. **The main menu runs a full game.** `main_menu_screen.dart:71` builds a real
   `TetrofallGame` as an attract-mode demo. Ticking on raw `update(dt)` would
   drain the balance while nobody is playing. Gate on an explicit flag.
2. **`update(dt)` runs during game over.** `GamePhase.ready`/`gameOver` return
   early from `engine.tick` but Flame still calls `update`. Gate on
   `engine.phase == playing || resolving`, mirroring how `tickElapsedOnly` is
   called (`game_engine.dart:328,343`).
3. **Nothing pauses the game on backgrounding.** `GameplayScreen` has no
   lifecycle hook, so a backgrounded mid-run game keeps `pausedNotifier == false`
   and would drain the balance in the player's pocket. Needs an
   `AppLifecycleListener` — an existing bug this feature forces us to fix.

Note `holdForOverlay()` (`tetrofall_game.dart:137-145`) already stops the Flame
clock without raising the pause overlay, so ad sheets and the loadout roll
correctly do not burn balance.

---

## 5. Implementation

### Phase 1 — Wallet and persistence
- `lib/services/storage_service.dart` — add keys following the existing getter
  (L33-101) / `saveX` (L103-161) style: `coin_balance`, `booster_charges`
  (comma-encoded like `booster_last_loadout`), `owned_themes`, `equipped_theme`,
  `clear_skies_seconds`, `daily_streak_day`, `daily_last_claim_epoch`,
  `daily_challenge_state`, `ad_views_today` + `ad_views_day_epoch`,
  `chest_since_bonus`, `starter_grant_given`.
- New `lib/services/wallet_service.dart` — a `ChangeNotifier` (precedent:
  `BoosterRunState`). API: `coins`, `earn(amount, source)`, `trySpend(amount,
  sku)`, `chargesOf(BoosterType)`, `grantCharge`, `consumeCharge`. Construct in
  `main.dart:21-33` beside `AdsService`; inject through `TetrofallApp`
  (`app.dart:9-14`) — the codebase uses constructor injection, no DI framework.

### Phase 2 — Price catalogue
- New `lib/game/config/economy_tuning.dart`, mirroring `booster_tuning.dart`'s
  `abstract final class` style: conversion rate, taper thresholds, streak bonus,
  tier prices, Clear Skies tiers, chest table, starter grant.
- `lib/game/boosters/booster_type.dart` — add a `coinPrice` getter switching on
  the existing `slot` field; no new data needed.
- `lib/game/config/booster_tuning.dart:15` — **`chargesPerBooster` 5 → 1**. This
  is a documented test override; at 5 charges a purchased charge is worthless and
  the sink collapses. Also `tokenRespinEnabled` false → **true** (L23) — the flag
  exists for exactly this.

### Phase 3 — Coin faucet
- `lib/services/ad_unit_ids.dart` — add a `rewardedCoins` unit and
  `AdPlacements.rewardedCoins`.
- `lib/services/ads_service.dart` — a 2-deep rewarded-coins pool modeled on
  `_loadRewarded` (:450) / `showRewardedContinue` (:496); reload on show, not
  dismiss. Expose `showRewardedCoins() -> bool`.
- New `lib/ui/screens/coin_vault_screen.dart` — the uninterrupted earn loop.
- Retire the mock: `booster_ad_sheet.dart:15` `mockVideoDuration` and its two
  callers (`gameplay_screen.dart:343-390`, `loadout_overlay.dart:137-162`) become
  coin spends. Keep the sheet as a coin-confirm with an "earn coins" fallback.
  Drop the hardcoded `adAvailable: true` at `gameplay_screen.dart:204,475`.

### Phase 4 — Clear Skies
- New `lib/services/clear_skies_service.dart` — remaining game-seconds behind a
  `ValueNotifier<Duration>`, plus `debitAppOpen()`.
- Tick from `tetrofall_game.dart:254` `update(dt)`, guarded on the phase
  predicate and a new `countsPlayTime` flag (false for the menu demo).
- `ads_service.dart:577` `_showInterstitial` and `:683` `_maybeShowAppOpenAd` —
  early-return while balance > 0; the app-open path debits 60 s.
- Add an `AppLifecycleListener` to `GameplayScreen` to pause on background.

### Phase 5 — Shop and surfaces
- New screens porting the mocks minus every dollar row: `shop_screen.dart`,
  `themes_screen.dart`, `daily_reward_screen.dart`.
- `main_menu_screen.dart` — add the icon row `screens.md` Phase 3 specifies
  (Daily Reward / Themes / Shop / Settings) and a coin pill reusing
  `lib/ui/widgets/counter_pill.dart` (whose doc comment already names "coin
  counts" as its use case). Delete the `No Ads — $2.99` button.
- `game_over_overlay.dart` — render the coins pill already mocked at
  `screens/game-over.html:161-166` but never implemented in Dart.
- **Keep an inline "earn coins" affordance on the game-over overlay.** Moving the
  continue behind coins otherwise throws away the highest-urgency conversion
  moment in the game; the player should be able to top up without losing the run.

### Phase 6 — Themes
- `lib/models/theme_definition.dart` — add 3 consts beside `classicWood` plus a
  `static const all` registry. Thread owned/equipped state through
  `tetrofall_game.dart:22`, `board_component.dart:25`, `board_frame.dart:16`,
  which currently hardcode the default. `TileCache._key` already keys on
  `theme.id`, so rendering is ready.
- Each theme needs 15 colours and one tile PNG — the dominant art cost here.

### Phase 7 — Daily rewards and challenges
- New `lib/services/daily_service.dart` — 7-day login streak (from
  `daily-reward.html`) plus 3 rotating daily challenges. Feed progress off the
  engine event bus, reusing the `RunTracker.onEvent` switch shape
  (`run_tracker.dart:86-110`).
- Keep challenge income (~150/day) below ad income, or the faucet is free and
  nobody watches anything.
- Note `RowsClearedEvent.forced` (`events.dart:57`) exists precisely so an
  economy layer does not credit the continue sweep as 32 line clears — honour it.

### Phase 8 — Docs and cleanup
- Rewrite `phase11_monetization_plan.md` (its §2.2 already defers exactly this
  work, and §1 still lists a banner that no longer exists).
- `boosters.md` §3.5 (re-spin sources), §4.9 (rewarded refill caps), §13.
- `screens.md` Phase 10; strip dollar prices from `shop.html`, `main-menu.html`.
- **Retire the `booster_ab_group` experiment** (`boosters.md` §10.2): its control
  arm keeps the banner to compare ARPDAU, which a coin economy invalidates.
- `BannerAdSlot` is fully built but referenced nowhere, while
  `phase11_monetization_plan.md:20` claims it is wired into `GameplayScreen`.
  Delete it or document it as deliberately dormant; `splash_screen.dart:78` still
  pre-measures its size.

---

## 6. Remaining risks

- **Revenue ceiling.** No whale, so ARPDAU stays ~$0.03–0.15. Mitigated by
  shaping the wallet for later coin packs.
- **Coins live in SharedPreferences** and are trivially editable on a rooted
  device. Recommend accepting it: no cash is at risk, and `best_score` already
  sits in plain prefs. Revisit only if leaderboards ship.
- **Theme art is the critical path.** If the 3 themes slip, boosters and Clear
  Skies carry the economy alone, and the long-term aspirational sink is missing.
- **Ad fatigue caps the faucet.** Fill and eCPM degrade after heavy same-day use,
  so real earnings will trail the theoretical curve. The taper is deliberately
  aligned with this.
- **iOS is unconfigured for ads** — no `SKAdNetworkItems`, no
  `NSUserTrackingUsageDescription` in `ios/Runner/Info.plist`. Fine while
  `phase11_monetization_plan.md:5` scopes the release to Android.

---

## 7. Verification

**Unit tests** (`test/`, following `ads_connectivity_test.dart`):
- Wallet: earn/spend/insufficient-funds; balance survives a reload; charge
  inventory encode/decode round-trips.
- Taper: views 1–10 pay 50, 11–20 pay 35, 21+ pay 25; resets on a new UTC day;
  streak bonus fires on the 5th consecutive view.
- Prices: every one of the 12 boosters resolves a price; 3-packs are cheaper per
  charge.
- Clear Skies: balance decrements only for `playing`/`resolving`; does not move
  during pause, `holdForOverlay`, game over, or the menu demo; app-open debits
  60 s; interstitial and app-open both suppressed while balance > 0.
- Chest: never rolls an owned theme; pity fires on the 4th.

**Widget tests:** shop renders no dollar prices; an unaffordable item routes to
the Coin Vault; the game-over coins pill shows the run's earnings.

**Device checks** (release build, real Android device):
1. Fresh install: 200 starter coins, shop browsable, no interstitial on first loss.
2. Coin Vault: watch 5 ads back to back with no spinner between them; `+50` each,
   bonus on the 5th; balance persists across a force-quit.
3. Buy a Board charge; confirm a spent Board slot recharges mid-run and the 2/run
   cap still holds.
4. Buy Clear Skies 30 min; play 3 runs — no interstitial; confirm the timer does
   not move while paused, while backgrounded, or on the main menu.
5. Let Clear Skies expire mid-session; confirm interstitials resume at the normal
   cadence.
6. Buy and equip a theme; confirm it persists across restart and all 12 booster
   glyphs recolour.
7. Airplane mode: Coin Vault shows no earn button (never an offer that cannot be
   delivered), challenges and login coins still claimable, no hangs.
8. Verify the UMP consent flow still appears once and ad requests respect it.
