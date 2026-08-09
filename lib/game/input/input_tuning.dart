abstract final class InputTuning {
  static const tapSlop = 16.0;

  static const tapMaxDuration = Duration(milliseconds: 250);

  static const fallbackCellSize = 32.0;

  static const swipeColumnFraction = 0.85;

  static const softDropFraction = 1.25;

  static const hardDropFraction = 4.7;

  static const hardDropVerticalityRatio = 1.5;

  /// How much of this event's own movement must be sideways for it to count
  /// toward a column shift. Judged per event rather than against the total
  /// displacement since touch-down, so a thumb that has arced downward — or
  /// is holding a soft drop — can still steer.
  static const horizontalAxisRatio = 0.5;

  /// Column shifts fire in bursts on a fast swipe, and each haptic tick is a
  /// platform-channel round trip on the UI thread.
  static const hapticMinInterval = Duration(milliseconds: 40);

  static double swipeColumnThreshold(double cellSize) =>
      cellSize * swipeColumnFraction;

  static double softDropDistance(double cellSize) =>
      cellSize * softDropFraction;

  static double hardDropDistance(double cellSize) =>
      cellSize * hardDropFraction;
}
