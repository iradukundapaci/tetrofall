/// Every number the booster system can be retuned by (`boosters.md` §11.1).
///
/// Nothing under `lib/game/boosters/` carries a literal of its own — sizes,
/// caps and windows all come from here so the test build can be retuned
/// without reopening the effect code.
abstract final class BoosterTuning {
  /// One charge per booster per run — the shipping rule from `boosters.md`
  /// §3.2, restored from the test build's 5.
  ///
  /// The Coin economy depends on this being 1. A purchased charge is only
  /// worth anything if the free one that came with the roll is scarce; at 5
  /// nobody would ever buy one and the sink collapses.
  static const chargesPerBooster = 1;

  static const freeRespinsPerRun = 1;
  static const adRespinEnabled = true;
  static const adRespinsPerRun = 3;
  static const adRefillEnabled = true;
  static const adRefillsPerRun = 2;
  static const adRefillsPerBooster = 1;

  /// Re-spins are bought with Coins now, not with a rewarded view — the ad is
  /// the faucet, never the price.
  static const tokenRespinEnabled = true;
  static const starterKitRuns = 3;

  static const aimWindow = Duration(seconds: 4);
  static const slotTapDebounce = Duration(milliseconds: 150);
  static const tipDuration = Duration(milliseconds: 2500);

  static const bombRadius = 1; // 3 x 3
  static const sweepRows = 2;
  static const lightningBolts = 4;

  /// 16 was proposed against a 10-wide board. On the shipped 18-wide one that
  /// is less than a row, so the default is 24 (§11.1).
  static const wildfireCap = 24;

  static const slideMinDragCells = 0.5;
}
