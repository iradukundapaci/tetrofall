/* Tetrofall playable ads — ported constants.
 *
 * Every value here is copied from the Dart source named beside it, so the
 * ads play by the real game's rules. If those files change, re-check here.
 * The one deliberate difference is ROWS: an ad frame is too short for the
 * real 32-row well, so the ad board is the bottom 20 rows of it.
 */
(function () {
  'use strict';

  var C = TF.C = {};

  // lib/game/config/board_config.dart (rows shortened for the ad frame)
  C.COLS = 18;
  C.ROWS = 20;
  C.SPAWN_ROWS = 2;

  // lib/ui/theme/tokens.dart, lib/models/theme_definition.dart, tools/store/outro.py
  C.COLOR = {
    woodDark: '#4A2F1C',
    woodMid: '#7A5230',
    woodLight: '#C89B6A',
    bg: '#2B1C12',
    boardBg: '#1F140C',
    gold: '#F2B632',
    goldLight: '#FFD46B',
    goldDeep: '#D9931C',
    red: '#D9432E',
    green: '#4CAF6B',
    text: '#F5EAD9',
    textMuted: '#B9A889'
  };

  // lib/game/engine/scoring.dart
  C.LINE_BASE_SCORE = { 1: 100, 2: 300, 3: 500, 4: 800 };
  C.MAX_CHAIN_STEPS = 8;

  // lib/game/config/difficulty.dart — [elapsedS, dropMs, riseIntervalS, fillRatio]
  C.CHECKPOINTS = [
    [0, 1000, 22, 0.35],
    [90, 850, 16, 0.45],
    [180, 700, 12, 0.55],
    [300, 550, 9, 0.62],
    [480, 400, 6, 0.70],
    [720, 250, 4.5, 0.75]
  ];
  C.RISE_GRACE = 12;

  // lib/game/config/motion.dart (seconds)
  C.MOTION = {
    crackHold: 0.38,
    shatterStep: 0.042,
    shatterBeat: 0.18,
    gravityCellsPerS2: 60,
    impactSquash: 0.06,
    rippleStepBase: 0.055,
    rippleStepMin: 0.014,
    rippleBudget: 0.9,
    resolveHardCap: 3.5,
    resolveMinTimeScale: 0.35,
    chainShatterFalloff: 0.35,
    chainShatterFloor: 0.45,
    lockDelay: 0.5,
    lockResetLimit: 15,
    softDropDivisor: 7,
    riseWarnRow: 3,
    shardMinUpSpeedCells: 6,
    shardMaxUpSpeedCells: 12,
    shardMaxOutwardSpeedCells: 4,
    shardMinSizeCells: 0.18,
    shardMaxSizeCells: 0.52,
    shardMinLifetime: 1.3,
    shardMaxLifetime: 2.2,
    shardFadeStartFraction: 0.75
  };

  C.shatterSequenceSeconds = function (cols) {
    var M = C.MOTION;
    var center = (cols - 1) / 2;
    return M.crackHold + Math.abs(cols - 1 - center) * M.shatterStep + M.shatterBeat;
  };

  // lib/game/input/input_tuning.dart (px are logical/CSS px)
  C.INPUT = {
    tapSlop: 16,
    tapMaxDuration: 0.25,
    swipeColumnFraction: 0.85,
    softDropFraction: 1.25,
    hardDropFraction: 4.7,
    hardDropVerticalityRatio: 1.5,
    flickCellsPerSecond: 10,
    flickSuppressionFraction: 0.7,
    velocitySmoothing: 0.5,
    horizontalEnterRatio: 0.65,
    horizontalExitRatio: 0.3,
    axisSmoothing: 0.6
  };

  // lib/game/engine/game_engine.dart inputBufferWindow
  C.INPUT_BUFFER_WINDOW = 0.25;
})();
