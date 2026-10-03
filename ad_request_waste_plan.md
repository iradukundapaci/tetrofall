# Why 600 requests become 67 impressions

Diagnosis of the request→impression gap in the AdMob "Ads activity performance"
card, and the fix. Baseline: `main` @ `616f4ab`, after the banner/app-open
removal in `236ce4c`. Companion to `ads_slimdown_plan.md` — that document is
about getting *more* impressions; this one is about not burning requests to get
the ones we already have.

---

## 1. The funnel, exactly

| Stage | Count | Lost here |
|---|---:|---|
| Requests | 600 | |
| Matched (46.83%) | ~281 | **319** — AdMob had nothing to return |
| Impressions | 67 | **214** — we held an ad and never showed it |
| **Request → impression** | **11.2%** | |

As a rough reference, an interstitial/rewarded app with a healthy mediation
stack sits around 80–95% match and 50–80% show. Treat those as
order-of-magnitude, not targets.

**The causal order is: we over-request → the stack runs dry for this user →
match rate falls → the ladder retries harder → more requests.** It is a loop,
and the code is the thing feeding it.

### Read this before acting on the money numbers

eCPM is **€0.50**. The baseline in `ads_slimdown_plan.md` §1 was $4.08
interstitial / $4.06 rewarded — an 8× collapse. Two readings, and the console
tells you which:

- **Remnant fill.** Repeated requests for the same user exhaust the top of the
  stack; what answers the 6th request in ten minutes is the bottom of the
  waterfall. This is what the rest of this document predicts.
- **Mix.** Old 1.1.3 installs still requesting the banner would drag blended
  eCPM down — but banners show ~95%+ of what they match, so a 23.8% show rate
  says this traffic is full-screen dominated, which argues against it.

Split the report by **ad unit × app version** before concluding anything. Also:
at €0.03/day a single day is noise. Confirm over 7 days.

---

## 2. The cache — and what "wasted" actually costs

This section exists because it decides which fixes are worth making.

### What we cache

One ad per format, in memory, no deeper: `_rewardedAd` and `_interstitialAd`
(`lib/services/ads_service.dart:72-73`). The loaders no-op when the slot is
full or a load is in flight (`:397-400`, `:491-494`), so we never hold two of
anything. Each is held under a 55-minute TTL (`:64-65`, just under AdMob's
~1 hour) and dropped by `dropExpiredAds()` (`:124-136`). Nothing survives a
cold start; what persists in `StorageService` is the cadence counters, not the
ads.

### Depth-1 is correct — don't cache deeper

Load latency for a full-screen ad is ~1–5 s, so load-on-demand at game over
means a spinner or a dead button — which `ads_slimdown_plan.md` Lever C.1
already identifies as a bug in the shipped build. Preloading stays.

But caching *deeper* would make the ratio worse, not better. Impressions are
bounded by game overs × cadence caps, so a second held interstitial is just
another matched ad that expires unshown: more requests, lower show rate, no
extra revenue.

### An unshown cached ad costs two things, and money is not one of them

1. **One request** — the denominator of match rate, which is the broken number.
2. **The player's bandwidth** — a rewarded video creative is several MB,
   pre-fetched at every run start, often on cellular.

Nothing is charged, no inventory is consumed. Which means **"make sure every
cached ad gets shown" is the wrong goal.** The only ways to hit it are forcing
shows or loosening the cadence, both of which `ads_slimdown_plan.md` §3 rules
out on purpose.

The right goal is: **never fire a request whose show probability is low.** Same
problem from the other end, but it selects entirely different fixes — and it
means a 24% show rate is not automatically a failure. Rewarded is opt-in;
~84% of fetches going unused is what opt-in *means*. Fix that through take rate
(`ads_slimdown_plan.md` Lever C), not through the fetch.

---

## 3. Why we request so much — ranked

### Cause 1 — the retry ladder never terminates · the dominant one

`_AdRetry` (`:14-44`) backs off 4 s → 8 → 16 → 32 → 60, then **stays at 60 s
forever** while the app is foregrounded and the slot is empty (`_max =
Duration(seconds: 60)`, `:16`). Every no-fill reschedules itself (`:430`
rewarded, `:522` interstitial).

A 10-minute session on a device that isn't getting fill:

```
4 + 8 + 16 + 32 = 60s to reach the cap, then one per 60s
→ ~13 requests per format → ~26 requests, both formats
```

Those requests cannot become impressions — impressions are bounded by game
overs and the cadence caps, not by how many ads we fetch. So ~26 requests chase
at most 1–2 shows. **Forty such sessions is 1,000 requests.** That is the shape
of the 600.

Self-reinforcing: each extra request for the same user makes the next likelier
to no-fill, which schedules another retry.

### Cause 2 — `notifyRunStarted()` walks straight past the backoff

`notifyRunStarted()` (`:303-306`, called from `gameplay_screen.dart:196` on
every run start) calls `_loadRewarded()` and `_loadInterstitial()` directly.
Their guards (`:397-400`, `:491-494`) only check *consent*, *ad in hand* and
*load in flight*. **A pending retry timer does not block them.**

So during a no-fill streak every run start fires two fresh requests on top of
the ladder already running. Runs in this game can end in 30 seconds. The
accumulated backoff is never consulted at the one moment it matters most.

### Cause 3 — the ladder is reset by things that aren't new information

`_retryNow()` (`:333-338`) calls `_rewardedRetry.reset()` /
`_interstitialRetry.reset()`, dropping the accumulated wait back to 4 s. It
fires from **every resume** (`:636`) and **every online transition**
(`_onOnlineChanged`, `:328`).

`ConnectivityService` publishes `isOnline` from a real probe and flips to false
on any probe failure (`connectivity_service.dart:67-71`), re-probing on a
5–60 s ladder. On a weak mobile signal that flaps, and each flap restarts the
ad ladder at 4 s: another 4/8/16/32 burst into a stack that just said no.

### Cause 4 — we fetch formats that cannot be shown

- **Interstitial past its caps.** Once `_interstitialsShownThisSession >= 4` or
  `interstitialsShownToday >= 8`, `_underInterstitialCap` (`:531-533`) makes
  `_showInterstitial()` return null for the rest of the session/day — but
  `_loadInterstitial()` knows nothing about the caps and keeps loading *and
  retrying*. Every one of those has zero show probability.
- **Both formats at app start.** `_startAdsIfAllowed()` (`:294-295`) loads both
  before the player has left the home screen. AdMob's own guidance is to
  request close to the show; a run start is close enough and arrives seconds
  later.
- **Interstitial when the cadence isn't near due.** At run start,
  `runsSinceLastInterstitial` is 0 or 1. When it's 0 and play-seconds are low,
  this run's end cannot make an interstitial due — the fetch is speculative two
  runs ahead.

### Cause 5 — expiry re-requests speculatively

`dropExpiredAds()` disposes the expired ad and **immediately re-requests**
(`:128`, `:134`). From the show paths (`showRewardedContinue` `:440`,
`_showInterstitial` `:539`) and from game over (`gameplay_screen.dart:271`)
that is right — something is about to want an ad.

It also runs on **resume** (`:630`). A player who opens the app and sits on the
home screen therefore generates a fresh request per format per hour that cannot
possibly show, and if that request no-fills it starts a Cause 1 ladder.

### Cause 6 — the rewarded ad is fetched far too early

Fetched at run start, the rewarded ad sits for the entire run — five minutes on
a long one — and is only consumable at the game-over screen, and only if the
player opts in. Two costs:

- **Dead fetches** on every run that ends in a quit rather than a game over,
  and on every game over where the offer is declined.
- **Age at show time.** An ad fetched 5 minutes ago is worth less than one
  fetched 20 seconds ago; some demand sources discount or drop stale fills
  outright. Part of the €0.50 may be this.

Note `maxContinuesPerRun = 2` (`game_engine.dart:167`), so the reload fired
immediately after a continue is *legitimate* — a second continue is reachable
in the same run. No change needed there.

### Cause 7 — matched ads thrown away (the show-rate half)

These explain the 214 matched-but-unshown. Per §2, most are not defects:

| Path | Code | Avoidable? |
|---|---|---|
| Rewarded held, player declines the continue (~84% of game overs) | — | **No.** Inherent to opt-in. Fix take rate (`ads_slimdown_plan.md` Lever C), not the fetch. |
| Interstitial held while cadence / `_fullScreenAdGap` / caps block it | `:541` | **No.** Player protections. Keep. |
| Ad expires at 55 min, disposed and re-requested | `:124-136` | **Partly** — see Cause 5, and don't hold a speculative ad that long (Cause 6). |
| App killed holding a matched ad | — | No. |
| `_discardCachedAds()` on a consent/personalisation change | `:376-382` | No. Correct behaviour. |

The honest read: **the show-rate half is mostly structural; the match-rate half
is ours.** Causes 1–6 are the work.

### Cause 8 — we are flying blind

`AdOutcome` has only `shown`, `rewarded`, `failed`
(`analytics_service.dart:211-218`). We log failures and shows. We log **no
request and no successful load**, so the request:impression ratio is invisible
outside the AdMob console and cannot be attributed to a build, a placement or a
code path. Every number in §1 came from a screenshot.

---

## 4. The fix

Ordered by effect per unit of risk. All of it lives in
`lib/services/ads_service.dart` unless stated.

### Fix 1 — make the ladder terminate (Cause 1)

In `_AdRetry`:

- `_max` 60 s → **5 min**.
- Add a consecutive-attempt ceiling (**4**). Past it, `schedule()` no-ops and
  the slot stays empty until a real demand event asks again.
- `reset()` clears the counter; it is already called on every successful load.

A 10-minute dry session drops from ~13 requests per format to **4**.

### Fix 2 — honour the backoff at the demand moments (Cause 2)

- Expose `_AdRetry.isPending`.
- `_loadRewarded()` / `_loadInterstitial()` gain `{bool force = false}` and
  return early when a retry is pending and `force` is false.
- `notifyRunStarted()` calls **without** `force` — a run start is a hint, not
  new information about fill.
- `_retryNow()` is the only caller that passes `force: true`, because a resume
  or a network return genuinely is new information.

### Fix 3 — don't reset on flapping (Cause 3)

Debounce `_retryNow()`: ignore a reset within 60 s of the previous one. Resume
and connectivity both route through it, so one guard covers both.

### Fix 4 — don't fetch what can't be shown (Cause 4)

- `_loadInterstitial()` returns early when `!_underInterstitialCap`. One line,
  no behaviour change beyond not requesting into a closed window. Hook
  `notifyRunStarted()` so a new session's reset re-opens it.
- Drop the `_loadRewarded()` / `_loadInterstitial()` pair from
  `_startAdsIfAllowed()` (`:294-295`). First run start picks them up.
  **Check first:** the home screen has no ad surface now that the banner is
  gone, so nothing regresses — confirm that on device.
- *Optional, measure before shipping:* gate the run-start interstitial prefetch
  on the cadence being reachable at this run's end
  (`runsSince + 1 >= _interstitialRunCap || playSeconds + 30 >= cap ||
  _breakOwed`). Roughly halves interstitial prefetches but risks arriving at a
  long run's game over empty-handed. Ship Fixes 1–5 first and see whether it is
  still needed.

### Fix 5 — stop re-requesting on expiry (Cause 5)

`dropExpiredAds({bool refill = false})`:

- Dispose as today; only call the loaders when `refill` is true.
- `refill: true` from the show paths (`:440`, `:539`) and from the game-over
  call (`gameplay_screen.dart:271`) — those are real demand.
- `refill: false` from the resume path (`:630`). `notifyRunStarted()` already
  covers the next moment that actually needs an ad.

Removes a request per format per idle hour, and the ladder it can start.

### Fix 6 — instrument it (Cause 8)

Add `requested` and `loaded` alongside `shown` in the ad reporting path (GA4
side; GameAnalytics has no clean verb for these, so leave `AdOutcome`'s GA
mapping untouched and log these as design/GA4 events). Then
`requests → loaded → shown` per format per placement is readable without the
console, and the next regression shows up in a day instead of a month.

### Fix 7 — the console half of the match rate (not code)

This is `ads_slimdown_plan.md` Lever A, still open. Fixing the request storm
raises match rate on its own, but the stack is thin:

- `android/app/build.gradle.kts:125-134` carries **Unity Ads** and **Liftoff**
  only; AppLovin was held pending account approval, Meta/InMobi dropped. Three
  more bidders is the cheapest money in either document.
- Confirm Unity/Liftoff are on **bidding**, not waterfall.
- Check for a manual eCPM **floor** on the interstitial/rewarded units — a
  floor above what this traffic clears would produce exactly this match rate,
  independent of everything above.
- `MobileAds.instance.openAdInspector` on a device: confirm every adapter
  answers, and look at what is actually filling at €0.50.

### Deferred — fetch the rewarded ad late in the run (Cause 6)

Only after Fix 6's instrumentation shows run-start rewarded fetches are still a
real share of the waste. Two versions:

- **Cheap, no engine change.** `grid.rowHasAnyBlock(row)` is already public
  (`grid.dart:45`), so `_onEngineEvent` in `gameplay_screen.dart` can watch for
  the stack reaching a warning row on an event it already receives
  (`RiseCommittedEvent` / `PieceLockedEvent`) and call a new
  `AdsService.notifyRunAtRisk()`. Move the rewarded prefetch there; leave the
  interstitial at run start.
- **Time proxy, cruder.** Prefetch rewarded at N seconds of run elapsed rather
  than at run start. No engine coupling at all, but it fires on long safe runs
  too.

The first is only slightly more work and is the one worth doing. The risk in
both is arriving at game over with nothing loaded on a fast death — which is
the dead-button bug again, so measure the near-miss rate before enabling.
Keep it behind a flag.

---

## 5. What this does and does not do

**It does not create impressions.** Impressions are bounded by game overs ×
cadence caps. Expect the 67 to stay roughly where it is on day one.

| | Now | After |
|---|---:|---:|
| Requests | 600 | **~150–200** |
| Match rate | 46.8% | up — fewer exhausted-stack requests |
| eCPM | €0.50 | up, if Cause 1 was the remnant-fill driver |
| Show rate | 23.8% | up mechanically (smaller denominator) |

More impressions is the other document's job (Levers C and D). This one stops
the waste, lifts the price of what we already show, and removes a 9:1
request-to-impression ratio — a pattern AdMob's own quality signals read as
noise and deprioritise accordingly.

---

## 6. Order

1. **Fix 6** (instrumentation) first, so the before/after is measurable at all.
2. **Fixes 1–3** together — the retry storm. One release.
3. **Fixes 4 and 5** — the speculative fetches. Same release if convenient;
   they are small and independent of each other.
4. **Fix 7** in the console, in parallel from day one, no release needed.
5. Fix 4's optional cadence gate, then the deferred late-rewarded fetch, only
   if the new instrumentation still shows waste after a week.

### Verify by hand on a device

Medium_Phone_API_36 with `--profile`, release-mode ad units so the fill path is
real:

- Airplane mode on at the home screen: `[Ads]` load-failure logs stop after 4
  attempts per format instead of repeating every 60 s.
- Toggle airplane mode off/on repeatedly: no 4/8/16/32 burst per toggle.
- Start and quit runs rapidly during a no-fill streak: no request per run start
  while a retry is pending.
- Play past four interstitials in one session: no further interstitial requests
  in the logs for the rest of the session.
- Background the app for an hour and resume: the expired ad is dropped, and no
  request follows until a run starts.
- Normal play: the continue button is still ready at game over, and the
  interstitial still fires on cadence — the fixes must not starve the two
  moments that pay.

---

## 7. Decisions for you

1. **Retry ceiling of 4 and a 5-minute cap** — or more conservative (6 / 3 min)
   for the first release?
2. **Dropping the app-start prefetch** — any surface I've missed that needs an
   ad before the first run starts?
3. **The deferred late-rewarded fetch** — worth the engine-adjacent hook, or
   leave the rewarded ad at run start and take the staleness?
4. **AppLovin / Meta / InMobi** — same question `ads_slimdown_plan.md` §9.5
   asked, and it is still the single biggest lever here. Is the account
   approval situation unchanged?
5. **The €0.50 eCPM** — want me to take this as its own question once you have
   the ad-unit × version split? It may be a floor setting rather than anything
   in this document.
