import 'dart:math';

import '../config/difficulty.dart';
import 'cell.dart';
import 'grid.dart';

class RiseController {
  RiseController(this.grid, {Random? random}) : _random = random ?? Random() {
    pendingRow = _generateRow();
  }

  final Grid grid;
  final Random _random;

  double riseProgress = 0.0;

  double debugSpeedMultiplier = 1.0;

  double elapsed = 0.0;

  late List<Cell?> pendingRow;

  List<int> _previousGapCols = const [];

  void reset({Duration initialElapsed = Duration.zero}) {
    riseProgress = 0.0;
    elapsed = initialElapsed.inMicroseconds / 1e6;
    _previousGapCols = const [];
    pendingRow = _generateRow();
  }

  double get riseInterval => difficultyNow.riseInterval;

  double get fillRatio => difficultyNow.fillRatio;

  DifficultyCheckpoint get difficultyNow =>
      Difficulty.at(Duration(milliseconds: (elapsed * 1000).round()));

  bool tick(double dt) {
    elapsed += dt;
    if (elapsed < Difficulty.riseGracePeriod.inMicroseconds / 1e6) return false;
    riseProgress += (dt * debugSpeedMultiplier) / riseInterval;
    if (riseProgress >= 1.0) {
      riseProgress -= 1.0;
      return true;
    }
    return false;
  }

  void tickElapsedOnly(double dt) {
    elapsed += dt;
  }

  bool wouldTopOut() => grid.rowHasAnyBlock(0);

  void commitRise() {
    for (var r = 1; r <= grid.maxRow; r++) {
      for (var c = 0; c < grid.cols; c++) {
        grid.set(r - 1, c, grid.at(r, c));
      }
    }
    for (var c = 0; c < grid.cols; c++) {
      grid.set(grid.maxRow, c, pendingRow[c]);
    }
    pendingRow = _generateRow();
  }

  List<Cell?> _generateRow() {
    final maxGaps = (grid.cols * 0.4).round().clamp(1, grid.cols - 1);
    final gapCount = (grid.cols * (1 - fillRatio)).round().clamp(1, maxGaps);
    final gapCols = elapsed < 60
        ? _adjacentGaps(gapCount)
        : _scatteredGaps(gapCount);

    final row = List<Cell?>.generate(
      grid.cols,
      (c) => gapCols.contains(c) ? null : Cell(BlockType.wood),
    );
    _previousGapCols = gapCols;
    return row;
  }

  List<int> _adjacentGaps(int count) {
    final start = _random.nextInt(grid.cols - count + 1);
    return [for (var i = 0; i < count; i++) start + i];
  }

  List<int> _scatteredGaps(int count) {
    for (var attempt = 0; attempt < 8; attempt++) {
      final cols = <int>{};
      while (cols.length < count) {
        cols.add(_random.nextInt(grid.cols));
      }
      final overlapsPrevious = cols.any(_previousGapCols.contains);
      if (!overlapsPrevious) return cols.toList();
    }
    final cols = <int>{};
    while (cols.length < count) {
      cols.add(_random.nextInt(grid.cols));
    }
    return cols.toList();
  }
}
