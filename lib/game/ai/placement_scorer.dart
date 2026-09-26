import 'dart:math' as math;

import '../engine/grid.dart';
import '../engine/tetromino.dart';

/// Scores where a single piece could land. Split out of `DemoBot` so the
/// Director can ask the same question the bot answers — "how good is this
/// placement?" — without driving anything: it ranks the pieces left in the bag
/// against the board, and it measures the player's own placements against the
/// best one available.
///
/// One piece deep, like the bot: no lookahead, and blind to sticky groups and
/// cascades. That is deliberate, it keeps a call cheap enough to make on every
/// lock.
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
  /// cannot even be placed at the top.
  static int? landingRow(Grid grid, List<GridOffset> cells, int anchorCol) {
    var row = grid.minRow;
    if (collidesAt(grid, cells, row, anchorCol)) return null;
    while (!collidesAt(grid, cells, row + 1, anchorCol)) {
      row++;
    }
    return row;
  }

  /// Higher is better. With [blunder] the clear term flips, so the bot walks
  /// up to a completed row and refuses to finish it.
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
      // Refuse the clear, tolerate holes — but keep penalising height, which
      // is what makes the resulting board read as a solvable position the bot
      // is fumbling rather than as noise.
      return -cleared * 800.0 + holes * 25.0 - maxHeight * 2.0;
    }
    return cleared * 1000.0 - holes * 40.0 - maxHeight * 2.0;
  }

  /// The best and worst score any placement of [type] can get on [grid].
  /// `(-inf, -inf)` when nothing fits.
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

  /// The best score [type] can reach on [grid]; how well it "fits" the board.
  static double bestFit(Grid grid, TetrominoType type) =>
      range(grid, type).best;
}
