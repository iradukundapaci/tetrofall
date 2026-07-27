/// All input gesture thresholds in one place (§1.12) so they can be tuned
/// without touching gesture code.
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

  /// Horizontal px of drag that triggers a one-column move.
  static const swipeColumnThreshold = 26.0;

  /// Downward px (from finger-down) that engages soft drop.
  static const softDropDistance = 24.0;

  /// Downward px (from finger-down) that instantly triggers hard drop.
  static const hardDropDistance = 150.0;
}
