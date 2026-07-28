/// Every animation constant in the game lives here. Tuning happens here,
/// nowhere else. See game.md §2.4.
abstract final class Motion {
  // §2.3 Shatter clear
  static const shatterStep = Duration(milliseconds: 28);
  static const shatterBeat = Duration(milliseconds: 120);
  static const particleGravity = 900.0; // px/s^2
  static const particlesPerCellMin = 10;
  static const particlesPerCellMax = 14;
  static const particlePoolSize = 600;
  static const shardMinVy = -140.0; // px/s, upward-biased cone
  static const shardMaxVy = -40.0;
  static const shardMinVx = -90.0;
  static const shardMaxVx = 90.0;
  static const shardMinLifetime = Duration(milliseconds: 600);
  static const shardMaxLifetime = Duration(milliseconds: 900);
  static const shardFadeStartFraction = 0.6; // fade over the last 40%
  static const shardMinRotationSpeed = 1.0; // rad/s
  static const shardMaxRotationSpeed = 3.0;
  static const shardMinSize = 3.0; // px
  static const shardMaxSize = 6.0;

  /// Total duration of the center-out shatter sequence for a row of
  /// [cols] columns (§2.3) — the farthest cell's delay plus the closing
  /// beat. `RESOLVING` waits this long before cascading; it does not wait
  /// for shard particles to finish falling (those outlive the phase).
  static double shatterSequenceSeconds(int cols) {
    final center = (cols - 1) / 2.0;
    final farthestDelay = (cols - 1 - center).abs() * shatterStep.inMilliseconds;
    return (farthestDelay + shatterBeat.inMilliseconds) / 1000;
  }

  // §2.2 Cascading fall
  static const gravityCellsPerS2 = 60.0;
  static const impactSquash = Duration(milliseconds: 60);

  // §1.3 Falling & locking
  static const lockDelay = Duration(milliseconds: 500);
  static const lockResetLimit = 15;
  static const softDropDivisor = 20;
  static const hardDropPointsPerRow = 2;
  static const softDropPointsPerRow = 1;

  // §2.1 Rising rows
  static const riseWarnRow = 3;
  static const riseEmergeFadeFraction = 0.30;

  // §1.12 Controls
  static const horizontalMoveEase = Duration(milliseconds: 60);

  // §1.7 Combo banner (GOOD!/AWESOME!/INCREDIBLE!/UNBELIEVABLE!)
  static const comboBannerPopIn = Duration(milliseconds: 150);
  static const comboBannerHold = Duration(milliseconds: 500);
  static const comboBannerFadeOut = Duration(milliseconds: 300);
}
