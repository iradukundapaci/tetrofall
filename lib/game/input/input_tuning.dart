abstract final class InputTuning {
  static const tapSlop = 16.0;

  static const tapMaxDuration = Duration(milliseconds: 250);

  static const fallbackCellSize = 32.0;

  static const swipeColumnFraction = 0.85;

  static const softDropFraction = 1.25;

  static const hardDropFraction = 4.7;

  static const hardDropVerticalityRatio = 1.5;

  static double swipeColumnThreshold(double cellSize) =>
      cellSize * swipeColumnFraction;

  static double softDropDistance(double cellSize) =>
      cellSize * softDropFraction;

  static double hardDropDistance(double cellSize) =>
      cellSize * hardDropFraction;
}
