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
}
