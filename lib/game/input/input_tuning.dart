abstract final class InputTuning {
  static const tapSlop = 16.0;

  static const tapMaxDuration = Duration(milliseconds: 250);

  static const fallbackCellSize = 32.0;

  static const swipeColumnFraction = 0.85;

  static const softDropFraction = 1.25;

  static const hardDropFraction = 4.7;

  static const hardDropVerticalityRatio = 1.5;

  /// Downward speed, in cells per second, that separates a flick from a drag.
  /// Only a gesture still moving at flick speed when it engages the soft drop
  /// may hard drop, so a deliberate drag can travel the whole board.
  static const flickCellsPerSecond = 10.0;

  /// Fraction of [flickSpeed] above which column shifts are held. Below 1.0 so
  /// the hold covers the ramp into a flick, not only its peak.
  static const flickSuppressionFraction = 0.7;

  /// Weight kept from previous samples for the downward-speed estimate. Lower
  /// than [axisSmoothing] so the arming decision reflects the current stroke.
  static const velocitySmoothing = 0.5;

  /// Sideways intent enters above [horizontalEnterRatio] and only exits below
  /// [horizontalExitRatio]; the gap is the noise margin.
  static const horizontalEnterRatio = 0.65;
  static const horizontalExitRatio = 0.3;

  /// Weight kept from previous samples for the per-axis direction (0-1;
  /// higher keeps more history).
  static const axisSmoothing = 0.6;

  /// Each haptic tick is a platform-channel round trip, and column shifts fire
  /// in bursts on a fast swipe.
  static const hapticMinInterval = Duration(milliseconds: 40);

  static double swipeColumnThreshold(double cellSize) =>
      cellSize * swipeColumnFraction;

  static double softDropDistance(double cellSize) =>
      cellSize * softDropFraction;

  static double hardDropDistance(double cellSize) =>
      cellSize * hardDropFraction;

  /// Logical pixels per second matching [flickCellsPerSecond].
  static double flickSpeed(double cellSize) => cellSize * flickCellsPerSecond;
}
