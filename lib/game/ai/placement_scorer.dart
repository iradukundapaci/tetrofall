import 'dart:math' as math;

import '../engine/grid.dart';
import '../engine/tetromino.dart';

/// Scores where a single piece could land, for the bot and the Director (which
/// ranks the bag against the board and measures the player's placements).
/// One piece deep with no lookahead or cascade awareness, so it is cheap
/// enough to call on every lock.
abstract final class PlacementScorer {
  static bool collidesAt(
    Grid grid,
    List<GridOffset> cells,
    int anchorRow,
    int anchorCol,
  ) {
    for (final c in cells) {
      final row = anchorRow + c.row;
      final col = anchorCol + c.col;
      if (!grid.inBounds(row, col)) return true;
      if (grid.isOccupied(row, col)) return true;
    }
    return false;
  }

  /// Where a piece dropped at [anchorCol] comes to rest, or null when it
  /// doesn't fit at the top.
  static int? landingRow(Grid grid, List<GridOffset> cells, int anchorCol) {
    var row = grid.minRow;
    if (collidesAt(grid, cells, row, anchorCol)) return null;
    while (!collidesAt(grid, cells, row + 1, anchorCol)) {
      row++;
    }
    return row;
  }

  /// Higher is better. With [blunder] the clear term flips.
  static double score(
    Grid grid,
    List<GridOffset> cells,
    int landingRow,
    int anchorCol, {
    required bool blunder,
  }) {
    final rows = grid.maxRow + 1;
    final occ = List.generate(
      rows,
      (r) => List.generate(grid.cols, (c) => grid.isOccupied(r, c)),
    );
    for (final cell in cells) {
      final r = landingRow + cell.row;
      final c = anchorCol + cell.col;
      if (r >= 0 && r < rows) occ[r][c] = true;
    }

    var cleared = 0;
    for (final row in occ) {
      if (row.every((occupied) => occupied)) cleared++;
    }

    var holes = 0;
    var maxHeight = 0;
    for (var c = 0; c < grid.cols; c++) {
      var seenBlock = false;
      for (var r = 0; r < rows; r++) {
        if (occ[r][c]) {
          if (!seenBlock) maxHeight = math.max(maxHeight, rows - r);
          seenBlock = true;
        } else if (seenBlock) {
          holes++;
        }
      }
    }

    if (blunder) {
      // Keep penalising height so the board reads as a position being
      // fumbled rather than noise.
      return -cleared * 800.0 + holes * 25.0 - maxHeight * 2.0;
    }
    return cleared * 1000.0 - holes * 40.0 - maxHeight * 2.0;
  }

  /// The best and worst score any placement of [type] can get; both
  /// `-inf` when nothing fits.
  static ({double best, double worst}) range(Grid grid, TetrominoType type) {
    var best = double.negativeInfinity;
    var worst = double.infinity;
    for (final rotation in RotationState.values) {
      final cells = Tetromino.cellsFor(type, rotation);
      final cols = cells.map((c) => c.col);
      final minCol = cols.reduce(math.min);
      final maxCol = cols.reduce(math.max);
      for (var col = -minCol; col <= grid.cols - 1 - maxCol; col++) {
        final landing = landingRow(grid, cells, col);
        if (landing == null) continue;
        final s = score(grid, cells, landing, col, blunder: false);
        if (s > best) best = s;
        if (s < worst) worst = s;
      }
    }
    if (best == double.negativeInfinity) {
      return (best: double.negativeInfinity, worst: double.negativeInfinity);
    }
    return (best: best, worst: worst);
  }

  /// How well [type] fits the board: the best score it can reach.
  static double bestFit(Grid grid, TetrominoType type) =>
      range(grid, type).best;
}
