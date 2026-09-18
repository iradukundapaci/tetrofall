import '../boosters/booster_type.dart';

/// One tier of timed ad-free play ("Clear Skies").
///
/// [gameTime] is game-clock seconds, not wall-clock: the balance only drains
/// while a run is actually live, so buying this spends Coins on runs rather
/// than on minutes of the player's life.
class ClearSkiesTier {
  const ClearSkiesTier(this.gameTime, this.price);

  final Duration gameTime;
  final int price;
}

/// Every number the Coin economy can be retuned by.
///
/// Rewarded video is the only faucet — there is no IAP — so each price here is
/// designed as a multiple of [coinsPerAdFullRate]. The question a price answers
/// is never "how many Coins?" but "how many ads is this worth?".
///
/// Prices deliberately pay far above an ad's cash value. At the shop mockup's
/// own rate (500 Coins for $0.99) a Coin is worth ~$0.002 while a rewarded view
/// earns ~$0.005–0.015, so "fair value" would be ~5 Coins an ad and the
/// cheapest booster would cost 16 views. Paying 50 keeps every mocked price
/// intact while leaving the shop reachable inside a day's play.
abstract final class EconomyTuning {
  // --- Faucet -------------------------------------------------------------

  /// What one rewarded view pays for the first [fullRateViewsPerDay] views of
  /// a day. The single most load-bearing constant in the economy: changing it
  /// rescales every price's felt cost at once.
  static const coinsPerAdFullRate = 50;

  /// Views past [fullRateViewsPerDay] pay this, and views past
  /// [taperedViewsPerDay] pay [coinsPerAdFloorRate].
  ///
  /// A taper, never a cap. Blocking earning would punish the most engaged
  /// player, and it would be punishing them for something that happens anyway:
  /// mediation fill rate and eCPM both degrade under heavy same-day frequency,
  /// so the curve is roughly what the ad stack already pays.
  static const coinsPerAdTaperedRate = 35;
  static const coinsPerAdFloorRate = 25;
  static const fullRateViewsPerDay = 10;
  static const taperedViewsPerDay = 20;

  /// Paid every [streakBonusEvery] consecutive views inside one sitting. The
  /// reason to watch a sixth ad rather than stopping at five.
  static const streakBonus = 50;
  static const streakBonusEvery = 5;

  /// Granted once, on first launch, so the shop is worth opening before the
  /// player has watched anything.
  static const starterGrant = 200;

  /// The zero-ad floor. Ads must stay the dominant income or the faucet is
  /// free and nobody watches anything, so this sits well under a day's views.
  static const dailyChallengeReward = 50;
  static const dailyChallengesPerDay = 3;

  /// Seven-day login calendar (`screens/daily-reward.html`). A zero entry is a
  /// booster-charge day rather than a Coin day; day 7 is the Mystery Chest.
  static const loginStreakCoins = <int>[50, 0, 100, 0, 0, 200, 0];

  // --- Booster charges ----------------------------------------------------

  /// Price of one charge, by slot — the game's own power-and-scarcity ladder
  /// (`boosters.md` §13 plans Small/Line common, Area uncommon, Board rare).
  ///
  /// Matches `screens/shop.html` exactly for Hammer (80), Drill (100) and
  /// Lightning (150). Bomb is normalised 120 → 80 because it is Small tier;
  /// the six boosters the mockup never priced inherit their tier's.
  static int chargePrice(BoosterSlot slot) => switch (slot) {
    BoosterSlot.small => 80,
    BoosterSlot.line => 100,
    BoosterSlot.area => 150,
    BoosterSlot.board => 220,
  };

  /// Three charges at roughly a fifth off, rounded to something readable.
  static int chargeBundlePrice(BoosterSlot slot) => switch (slot) {
    BoosterSlot.small => 190,
    BoosterSlot.line => 240,
    BoosterSlot.area => 360,
    BoosterSlot.board => 530,
  };

  static const chargeBundleSize = 3;

  // --- Other sinks --------------------------------------------------------

  /// Sub-ad price: re-spinning a slot is the highest-frequency purchase in the
  /// game and has to stay an impulse, not a decision.
  static const respinPrice = 30;

  /// Saves a whole run, so it is priced like one.
  static const continuePrice = 120;

  static const mysteryChestPrice = 250;

  /// Coin payout range when a chest rolls Coins.
  static const chestCoinsMin = 100;
  static const chestCoinsMax = 400;

  /// Every Nth chest guarantees a non-Coin reward, so a chest never degrades
  /// into a coin laundry.
  static const chestPityEvery = 4;

  // --- Clear Skies --------------------------------------------------------

  /// Timed suppression of *involuntary* ads only — the game-over interstitial
  /// and the app-open ad. Rewarded video is never suppressed: it is the only
  /// faucet, and a player who could switch it off could soft-lock their own
  /// economy.
  ///
  /// Priced above what it costs. With the shipped caps (an interstitial every
  /// 4 runs or 360s of play, whichever trips first) the play-seconds cap wins
  /// at 90–150s runs, so this suppresses ~1 interstitial per 6 minutes of game
  /// time. At roughly a third of rewarded eCPM that is ~90 Coins of forgone
  /// revenue per 30 minutes against a 150 Coin price. Margin narrows on the
  /// bigger tiers — that is the volume discount — but stays above 1x.
  ///
  /// There is deliberately no permanent tier: it would end ad revenue from
  /// that player forever.
  static const clearSkiesTiers = <ClearSkiesTier>[
    ClearSkiesTier(Duration(minutes: 30), 150),
    ClearSkiesTier(Duration(hours: 2), 500),
    ClearSkiesTier(Duration(hours: 6), 1200),
  ];

  /// App-open ads fire on foregrounding, which is not game time, so
  /// suppressing them would otherwise be free. Each one skipped costs this
  /// much of the balance. Capped at one an hour by `AdsService`, so it is a
  /// few debits a session at most.
  static const clearSkiesAppOpenDebit = Duration(seconds: 60);
}
