import 'block_fall.dart';
import 'grid.dart';

/// Gravity as a wave: a released row drops into the holes beneath it while
/// everything above stays put, and the caller walks the cursor up one row per
/// step. Landing on an uneven surface can complete a row, which is how chains
/// fall out of a plain bottom-up walk. Spawn rows (negative indices) are
/// left alone.
abstract final class RippleCascade {
  /// Largest row index at or above [fromRow] (rows count downward, so
  /// `<= fromRow`) holding a cell with empty space directly beneath it.
  static int? nextFloatingRow(Grid grid, {required int fromRow}) {
    var r = fromRow < grid.maxRow ? fromRow : grid.maxRow - 1;
    for (; r >= 0; r--) {
      for (var c = 0; c < grid.cols; c++) {
        if (grid.at(r, c) != null && grid.at(r + 1, c) == null) return r;
      }
    }
    return null;
  }

  /// Drops every floating cell in [row] to rest in its own column.
  static List<BlockFall> settleRow(Grid grid, int row) {
    if (row < 0 || row >= grid.maxRow) return const [];

    final falls = <BlockFall>[];
    for (var col = 0; col < grid.cols; col++) {
      final cell = grid.at(row, col);
      if (cell == null) continue;

      var rest = row;
      while (rest < grid.maxRow && grid.at(rest + 1, col) == null) {
        rest++;
      }
      if (rest == row) continue;

      grid.set(row, col, null);
      grid.set(rest, col, cell);
      falls.add(
        BlockFall(col: col, fromRow: row, toRow: rest, type: cell.type),
      );
    }
    return falls;
  }

  /// The board the wave converges on, in one pass. Rows at or below
  /// [floorRow] keep their overhangs, as they do during the wave.
  static List<BlockFall> settleAbove(Grid grid, {required int floorRow}) {
    final falls = <BlockFall>[];
    for (var r = floorRow - 1; r >= 0; r--) {
      falls.addAll(settleRow(grid, r));
    }
    return falls;
  }

  /// Rows at or above [fromRow] that still hold a block, i.e. how many more
  /// ripple steps remain. Used to pace the wave against its time budget.
  static int rowsRemaining(Grid grid, {required int fromRow}) {
    var count = 0;
    for (var r = fromRow < grid.maxRow ? fromRow : grid.maxRow; r >= 0; r--) {
      if (grid.rowHasAnyBlock(r)) count++;
    }
    return count;
  }
}
