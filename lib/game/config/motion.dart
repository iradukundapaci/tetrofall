abstract final class Motion {
  static const crackHold = Duration(milliseconds: 380);
  static const shatterStep = Duration(milliseconds: 42);
  static const shatterBeat = Duration(milliseconds: 180);

  static const shardGravityCellsPerS2 = 60.0;
  static const shardMinUpSpeedCells = 6.0;
  static const shardMaxUpSpeedCells = 12.0;
  static const shardMaxOutwardSpeedCells = 4.0;
  static const shardOutwardJitterCells = 1.0;
  static const shardHorizontalDragPerS = 1.8;
  static const shardMinSizeCells = 0.18;
  static const shardMaxSizeCells = 0.52;

  static const particlesPerCellMin = 7;
  static const particlesPerCellMax = 10;
  static const particlesLineBonusPerExtraLine = 3;
  static const particlesPerCellCap = 18;
  static const maxParticlesPerClear = 800;
  static const particlePoolSize = 1600;
  static const shardMinLifetime = Duration(milliseconds: 1300);
  static const shardMaxLifetime = Duration(milliseconds: 2200);
  static const shardFadeStartFraction = 0.75;
  static const shardMinRotationSpeed = 2.0;
  static const shardMaxRotationSpeed = 7.0;

  static double shatterSequenceSeconds(int cols) {
    final center = (cols - 1) / 2.0;
    final farthestDelay =
        (cols - 1 - center).abs() * shatterStep.inMilliseconds;
    return (crackHold.inMilliseconds +
            farthestDelay +
            shatterBeat.inMilliseconds) /
        1000;
  }

  static const gravityCellsPerS2 = 60.0;
  static const impactSquash = Duration(milliseconds: 60);

  static const lockDelay = Duration(milliseconds: 500);
  static const lockResetLimit = 15;
  static const softDropDivisor = 7;

  static const riseWarnRow = 3;
  static const riseEmergeFadeFraction = 0.30;

  static const horizontalMoveEase = Duration(milliseconds: 60);

  static const comboBannerPopIn = Duration(milliseconds: 150);
  static const comboBannerHold = Duration(milliseconds: 500);
  static const comboBannerFadeOut = Duration(milliseconds: 300);
}
