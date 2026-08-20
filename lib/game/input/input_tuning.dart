abstract final class InputTuning {
  static const tapSlop = 16.0;

  static const tapMaxDuration = Duration(milliseconds: 250);

  static const fallbackCellSize = 32.0;

  static const swipeColumnFraction = 0.85;

  static const softDropFraction = 1.25;

  static const hardDropFraction = 4.7;

  static const hardDropVerticalityRatio = 1.5;

  /// Downward speed, in cells per second, that separates a flick from a drag.
  ///
  /// Distance alone used to decide the hard drop, so holding a soft drop and
  /// steering the piece down the board eventually crossed
  /// [hardDropFraction] and slammed the piece home — the player never asked
  /// for that. Speed is what actually distinguishes the two gestures: a
  /// flick is a single fast stroke, a soft drop is a slow drag or an
  /// outright hold. Only a gesture that was still moving at flick speed
  /// when it engaged the soft drop may hard drop at all (see
  /// [GestureHandler] arming), so a deliberate drag can travel the whole
  /// board without escalating.
  static const flickCellsPerSecond = 10.0;

  /// Fraction of [flickSpeed] above which the stroke reads as a downward flick
  /// in progress and sideways column shifts are held. Below 1.0 so the hold
  /// covers the acceleration ramp into a flick, not only its peak.
  static const flickSuppressionFraction = 0.7;

  /// Exponential-smoothing weight kept from previous samples for the
  /// downward-speed estimate. Lower than [axisSmoothing] because the arming
  /// decision is made within a couple of events of the finger crossing
  /// [softDropFraction] and needs to reflect the current stroke, not the
  /// approach to it.
  static const velocitySmoothing = 0.5;

  /// Judged against a smoothed recent direction (see [axisSmoothing]) and a
  /// two-threshold latch (see [horizontalEnterRatio] /
  /// [horizontalExitRatio]) rather than the total displacement since
  /// touch-down, so a thumb that has arced downward — or is holding a soft
  /// drop — can still steer.
  ///
  /// Entering "sideways" needs a clearly sideways ratio; once in it, only a
  /// clear return to vertical drops back out. A single shared threshold let
  /// a short run of correlated noisy samples — real touch sensors don't
  /// jitter independently sample-to-sample — cross it, accumulate a full
  /// column shift, then the correction run cross it back the other way
  /// right after: the piece visibly jumps and snaps back. The gap between
  /// the two thresholds is the noise margin.
  static const horizontalEnterRatio = 0.65;
  static const horizontalExitRatio = 0.3;

  /// Exponential-smoothing weight kept from the previous samples when
  /// updating the rolling per-axis direction (0-1: higher keeps more
  /// history). A single pointer-move event's delta is noisy — real touch
  /// input wobbles sideways from sample to sample even during an intended
  /// straight drag — so judging the axis on one raw sample is unreliable.
  /// Smoothing over a handful of recent samples (~3 events, well under
  /// 100ms) removes that noise without meaningfully delaying a genuine
  /// direction change.
  static const axisSmoothing = 0.6;

  /// Column shifts fire in bursts on a fast swipe, and each haptic tick is a
  /// platform-channel round trip on the UI thread.
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
