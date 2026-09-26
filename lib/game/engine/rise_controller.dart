import 'dart:math';

import '../config/difficulty.dart';
import '../config/run_config.dart';
import 'cell.dart';
import 'grid.dart';
import 'row_plan.dart';

class RiseController {
  RiseController(this.grid, {Random? random}) : _random = random ?? Random() {
    pendingRow = _generateRow();
  }

  final Grid grid;
  final Random _random;

  double riseProgress = 0.0;

  double debugSpeedMultiplier = 1.0;

  double elapsed = 0.0;

  /// The run's own shape of the rise, set by `GameEngine` from `RunConfig`.
  RiseConfig riseConfig = RiseConfig.curve;

  /// The Director's nudge to the rise interval; above 1 the floor is slower.
  /// Composes with [debugSpeedMultiplier] rather than replacing it.
  double directorIntervalScale = 1.0;

  /// Asked for a [RowPlan] each time a row is generated. Null means every row
  /// follows today's rules. Called for the row *after* the one that is showing:
  /// the visible [pendingRow] is never rewritten.
  RowPlan Function()? rowPlanner;

  late List<Cell?> pendingRow;

  List<int> _previousGapCols = const [];

  void reset({Duration initialElapsed = Duration.zero}) {
    riseProgress = 0.0;
    directorIntervalScale = 1.0;
    elapsed = initialElapsed.inMicroseconds / 1e6;
    _previousGapCols = const [];
    pendingRow = _generateRow();
  }

  double get riseInterval =>
      difficultyNow.riseInterval * riseConfig.scaleAt(elapsed);

  double get fillRatio => difficultyNow.fillRatio;

  DifficultyCheckpoint get difficultyNow =>
      Difficulty.at(Duration(milliseconds: (elapsed * 1000).round()));

  bool tick(double dt) {
    elapsed += dt;
    if (elapsed < Difficulty.riseGracePeriod.inMicroseconds / 1e6) return false;
    riseProgress +=
        (dt * debugSpeedMultiplier) / (riseInterval * directorIntervalScale);
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
    final plan = rowPlanner?.call() ?? RowPlan.normal;
    final maxGaps = (grid.cols * 0.4).round().clamp(1, grid.cols - 1);
    final gapCount = (grid.cols * (1 - fillRatio)).round().clamp(1, maxGaps);
    final gapCols = switch (plan.style) {
      RowStyle.normal =>
        elapsed < 60 ? _adjacentGaps(gapCount) : _scatteredGaps(gapCount),
      RowStyle.gift => [plan.wellColumn ?? _random.nextInt(grid.cols)],
      RowStyle.friendly => _adjacentGaps(gapCount, aroundCol: plan.wellColumn),
      RowStyle.tough => _spreadGaps(gapCount),
    };

    final row = List<Cell?>.generate(
      grid.cols,
      (c) => gapCols.contains(c) ? null : Cell(BlockType.wood),
    );
    _previousGapCols = gapCols;
    return row;
  }

  /// One run of [count] neighbouring gaps. With [aroundCol] the run is
  /// centred on it, so the gaps line up with the well the player is keeping
  /// open; the draw is only spent when there is nothing to line up with.
  List<int> _adjacentGaps(int count, {int? aroundCol}) {
    final start = aroundCol == null
        ? _random.nextInt(grid.cols - count + 1)
        : (aroundCol - count ~/ 2).clamp(0, grid.cols - count);
    return [for (var i = 0; i < count; i++) start + i];
  }

  /// Scattered gaps kept at least two columns clear of the previous row's, so
  /// nothing stacks into a tidy shaft.
  List<int> _spreadGaps(int count) {
    for (var attempt = 0; attempt < 8; attempt++) {
      final cols = <int>{};
      while (cols.length < count) {
        cols.add(_random.nextInt(grid.cols));
      }
      final tooClose = cols.any(
        (c) => _previousGapCols.any((p) => (c - p).abs() < 2),
      );
      if (!tooClose) return cols.toList();
    }
    return _scatteredGaps(count);
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
