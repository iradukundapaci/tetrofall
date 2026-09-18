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

  /// Watch-Ad-To-Continue: rows fill bottom-to-top, hold a beat once the
  /// board is completely full, then clear top-to-bottom — one row per
  /// step, each firing the standard per-row shatter effect.
  static const continueFillRowStep = Duration(milliseconds: 35);
  static const continueFullHold = Duration(milliseconds: 220);
  static const continueClearRowStep = Duration(milliseconds: 90);

  static const gravityCellsPerS2 = 60.0;
  static const impactSquash = Duration(milliseconds: 60);

  /// Ripple cascade: gravity releases one row per step, walking up the stack.
  /// The step interval is deliberately far shorter than a one-cell fall
  /// (~183ms), so three or four rows are in flight at once and the wave reads
  /// as continuous rather than as a queue of separate drops.
  static const rippleStepBase = Duration(milliseconds: 55);
  static const rippleStepMin = Duration(milliseconds: 14);

  /// Time the wave is allowed to take for one pass at full scale. A tall stack
  /// compresses its step interval to fit rather than running proportionally
  /// longer.
  static const rippleBudget = Duration(milliseconds: 900);

  /// Ceiling on an entire resolve, chains included. Blowing it drops the
  /// remaining work into a single [ColumnCascade] collapse — an escape hatch so
  /// a pathological board can never stall the game.
  static const resolveHardCap = Duration(milliseconds: 3500);

  /// Floor on the difficulty-derived resolve speed scale. The drop interval
  /// falls to 0.25x of its opening value by the last checkpoint; clearing that
  /// fast reads as a glitch, so the resolve stops speeding up at 0.35x.
  static const resolveMinTimeScale = 0.35;

  /// Later links in a chain shatter faster, so a four-deep chain does not cost
  /// four full shatter sequences.
  static const chainShatterFalloff = 0.35;
  static const chainShatterFloor = 0.45;

  static const lockDelay = Duration(milliseconds: 500);
  static const lockResetLimit = 15;
  static const softDropDivisor = 7;

  static const riseWarnRow = 3;
  static const riseEmergeFadeFraction = 0.30;

  // Boosters (`boosters.md` §11.2). Everything here is multiplied by the
  // engine's `resolveTimeScale`, like every other resolve animation, so
  // boosters speed up as the game does — except the reel timings, which
  // happen before the run and are never scaled.
  static const boosterReelSpin = Duration(milliseconds: 500);
  static const boosterReelStagger = Duration(milliseconds: 250);
  static const boosterRespinSpin = Duration(milliseconds: 500);
  static const boosterHammerSwing = Duration(milliseconds: 140);
  static const boosterBombFuse = Duration(milliseconds: 300);
  static const boosterBombRing = Duration(milliseconds: 40);
  static const boosterDrillCellStep = Duration(milliseconds: 30);
  static const boosterGrow = Duration(milliseconds: 180);
  static const boosterSlideRow = Duration(milliseconds: 160);
  static const boosterSlideStep = Duration(milliseconds: 45);
  static const boosterStackStep = Duration(milliseconds: 50);
  static const boosterSweep = Duration(milliseconds: 260);
  static const boosterBoltStep = Duration(milliseconds: 90);
  static const boosterQuakeShake = Duration(milliseconds: 420);
  static const boosterTiltLean = Duration(milliseconds: 150);
  static const boosterFireLayer = Duration(milliseconds: 70);
  static const boosterEffectBeat = Duration(milliseconds: 120);

  static const horizontalMoveEase = Duration(milliseconds: 60);
}
