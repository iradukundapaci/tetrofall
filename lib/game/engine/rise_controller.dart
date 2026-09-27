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

  double speedMultiplier = 1.0;

  double elapsed = 0.0;

  RiseConfig riseConfig = RiseConfig.curve;

  /// The Director's nudge to the rise interval; above 1 the floor is slower.
  double directorIntervalScale = 1.0;

  /// Asked for a [RowPlan] whenever a row is generated, i.e. for the row after
  /// the visible [pendingRow], which is never rewritten. Null means normal.
  RowPlan Function()? rowPlanner;

  late List<Cell?> pendingRow;

  List<int> _previousGapCols = const [];

  int? _meanderCenter;
  int _meanderWidth = 1;
  int _meanderWidthTarget = 1;
  int _meanderRowsLeft = 0;

  void reset({Duration initialElapsed = Duration.zero}) {
    riseProgress = 0.0;
    directorIntervalScale = 1.0;
    elapsed = initialElapsed.inMicroseconds / 1e6;
    _previousGapCols = const [];
    _meanderCenter = null;
    _meanderWidth = 1;
    _meanderWidthTarget = 1;
    _meanderRowsLeft = 0;
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
        (dt * speedMultiplier) / (riseInterval * directorIntervalScale);
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
      RowStyle.meander => _meanderGaps(gapCount),
    };

    final row = List<Cell?>.generate(
      grid.cols,
      (c) => gapCols.contains(c) ? null : Cell(BlockType.wood),
    );
    _previousGapCols = gapCols;
    return row;
  }

  /// One run of [count] neighbouring gaps, centred on [aroundCol] when given.
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
      final cols = _randomCols(count);
      final tooClose = cols.any(
        (c) => _previousGapCols.any((p) => (c - p).abs() < 2),
      );
      if (!tooClose) return cols;
    }
    return _scatteredGaps(count);
  }

  List<int> _scatteredGaps(int count) {
    for (var attempt = 0; attempt < 8; attempt++) {
      final cols = _randomCols(count);
      if (!cols.any(_previousGapCols.contains)) return cols;
    }
    return _randomCols(count);
  }

  /// One shaft, centred on [_meanderCenter], that drifts by at most one
  /// column a row and eases its width toward a target held for several rows
  /// at a time — the target ranges from 1 up to [maxWidth], so the shaft
  /// pinches down to a single-column channel and widens back out on its own.
  List<int> _meanderGaps(int maxWidth) {
    maxWidth = maxWidth.clamp(1, grid.cols - 1);
    if (_meanderRowsLeft <= 0) {
      _meanderWidthTarget = 1 + _random.nextInt(maxWidth);
      _meanderRowsLeft = 4 + _random.nextInt(8);
    } else {
      _meanderRowsLeft--;
    }
    if (_meanderWidth < _meanderWidthTarget) {
      _meanderWidth++;
    } else if (_meanderWidth > _meanderWidthTarget) {
      _meanderWidth--;
    }

    final half = _meanderWidth ~/ 2;
    final low = half;
    final high = grid.cols - 1 - (_meanderWidth - 1 - half);
    final center = _meanderCenter ?? _random.nextInt(grid.cols);
    final drift = _random.nextInt(3) - 1;
    _meanderCenter = (center + drift).clamp(low, high);

    final start = _meanderCenter! - half;
    return [for (var i = 0; i < _meanderWidth; i++) start + i];
  }

  List<int> _randomCols(int count) {
    final cols = <int>{};
    while (cols.length < count) {
      cols.add(_random.nextInt(grid.cols));
    }
    return cols.toList();
  }
}
