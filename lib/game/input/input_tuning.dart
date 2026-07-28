/// All input gesture thresholds in one place (§1.12) so they can be tuned
/// without touching gesture code.
///
/// Distance thresholds are expressed as fractions of the board's current
/// `cellSize` (R3/R4) rather than fixed px, so gesture feel is identical on
/// a small phone and a tablet — a 26 px swipe means very different things
/// on those two screens, a 0.6-cell swipe doesn't. [fallbackCellSize] only
/// covers the brief window before the board has completed its first
/// layout pass.
abstract final class InputTuning {
  /// Delayed Auto Shift: time held after the first move before auto-repeat
  /// kicks in.
  static const dasDelay = Duration(milliseconds: 170);

  /// Auto Repeat Rate: interval between repeated moves once DAS has fired.
  static const arr = Duration(milliseconds: 50);

  /// Max finger travel, in px, for a gesture to still count as a tap.
  static const tapSlop = 16.0;

  /// Max duration for a gesture to still count as a tap.
  static const tapMaxDuration = Duration(milliseconds: 250);

  /// Cell size assumed before the board reports a real one.
  static const fallbackCellSize = 32.0;

  /// Fraction of a cell's width that triggers a one-column horizontal
  /// move.
  static const swipeColumnFraction = 0.6;

  /// Fraction of a cell's height (downward) that engages soft drop.
  static const softDropFraction = 1.25;

  /// Fraction of a cell's height (downward) that instantly triggers hard
  /// drop, regardless of speed.
  static const hardDropFraction = 4.7;

  /// Downward velocity, in px/s, that instantly triggers hard drop
  /// regardless of distance travelled so far — a fast flick down hard
  /// drops even before crossing [hardDropFraction] (§1.12: "fast/long").
  static const hardDropVelocity = 1000.0;

  static double swipeColumnThreshold(double cellSize) =>
      cellSize * swipeColumnFraction;

  static double softDropDistance(double cellSize) =>
      cellSize * softDropFraction;

  static double hardDropDistance(double cellSize) =>
      cellSize * hardDropFraction;
}
