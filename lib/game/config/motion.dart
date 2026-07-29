/// Every animation constant in the game lives here. Tuning happens here,
/// nowhere else. See game.md §2.4.
abstract final class Motion {
  // §2.3 Shatter clear — crack-then-burst, 1:1 with the reference footage:
  // the whole cleared row first shows crack fractures for [crackHold],
  // then bursts center-out into chunky 3D wooden shards that spray upward
  // in a V and tumble under gravity.
  static const crackHold = Duration(milliseconds: 220);
  static const shatterStep = Duration(milliseconds: 28);
  static const shatterBeat = Duration(milliseconds: 120);

  // Shard kinematics are expressed in *cells* (multiplied by cellSize at
  // spawn) so the effect scales identically on any screen — essential now
  // that a cell is only ~1/21 of the screen width.
  static const shardGravityCellsPerS2 = 42.0;
  static const shardMinUpSpeedCells = 9.0; // cells/s, upward
  static const shardMaxUpSpeedCells = 20.0;
  static const shardMaxOutwardSpeedCells = 11.0; // cells/s at the row's edge
  static const shardOutwardJitterCells = 2.5;
  static const shardMinSizeCells = 0.18; // chunky fragments, not specks
  static const shardMaxSizeCells = 0.52;
  static const particlesPerCellMin = 7;
  static const particlesPerCellMax = 10;
  static const particlePoolSize = 1600;
  static const shardMinLifetime = Duration(milliseconds: 1100);
  static const shardMaxLifetime = Duration(milliseconds: 1900);
  static const shardFadeStartFraction = 0.75; // fade over the last 25%
  static const shardMinRotationSpeed = 2.0; // rad/s — visible tumble
  static const shardMaxRotationSpeed = 7.0;

  /// Total duration of the crack-then-burst shatter sequence for a row of
  /// [cols] columns (§2.3) — the crack hold, plus the farthest cell's
  /// burst delay, plus the closing beat. `RESOLVING` waits this long
  /// before cascading; it does not wait for shard particles to finish
  /// falling (those outlive the phase).
  static double shatterSequenceSeconds(int cols) {
    final center = (cols - 1) / 2.0;
    final farthestDelay = (cols - 1 - center).abs() * shatterStep.inMilliseconds;
    return (crackHold.inMilliseconds + farthestDelay + shatterBeat.inMilliseconds) /
        1000;
  }

  // §2.2 Cascading fall
  static const gravityCellsPerS2 = 60.0;
  static const impactSquash = Duration(milliseconds: 60);

  // §1.3 Falling & locking
  static const lockDelay = Duration(milliseconds: 500);
  static const lockResetLimit = 15;
  static const softDropDivisor = 7;
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
