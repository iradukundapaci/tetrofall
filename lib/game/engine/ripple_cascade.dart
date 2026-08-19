import 'gravity_resolver.dart';
import 'grid.dart';

/// Gravity as a wave rather than a single collapse.
///
/// [ColumnCascade] repacks every column to its final position in one step, so
/// the whole stack teleports down together. This settles the board one row at
/// a time instead: a released row drops into whatever holes are beneath it
/// while everything above it stays exactly where it was, and the caller walks
/// the cursor upward a row per animation step.
///
/// Because a released row lands on an uneven surface, its cells merge into the
/// partial rows below — and a merge can complete a row, which is what makes
/// chains fall out of a plain bottom-up walk.
///
/// Spawn rows (negative indices) are left alone, matching [ColumnCascade].
abstract final class RippleCascade {
  /// Largest row index at or above [fromRow] holding a cell with empty space
  /// directly beneath it. Null once everything from [fromRow] down is settled.
  ///
  /// Rows are indexed downward, so "at or above" means `<= fromRow`, and the
  /// search runs bottom-up to find the row gravity should release next.
  static int? nextFloatingRow(Grid grid, {required int fromRow}) {
    // The bottom row has nothing beneath it, so it can never float.
    var r = fromRow < grid.maxRow ? fromRow : grid.maxRow - 1;
    for (; r >= 0; r--) {
      for (var c = 0; c < grid.cols; c++) {
        if (grid.at(r, c) != null && grid.at(r + 1, c) == null) return r;
      }
    }
    return null;
  }

  /// Drops every floating cell in [row] to its resting position in its own
  /// column. Everything above [row] is left untouched — that is the whole
  /// point: the rows above have not been released yet.
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

  /// The board the wave converges on, in one pass — for the hard cap, where
  /// the engine gives up on animating and collapses whatever is left. Rows at
  /// or below [floorRow] keep their overhangs, exactly as they do during the
  /// wave: releasing them is not this clear's business.
  static List<BlockFall> settleAbove(Grid grid, {required int floorRow}) {
    final falls = <BlockFall>[];
    for (var r = floorRow - 1; r >= 0; r--) {
      falls.addAll(settleRow(grid, r));
    }
    return falls;
  }

  /// Rows at or above [fromRow] that still hold at least one block, i.e. how
  /// many more ripple steps the cascade could still take. Used to pace the
  /// wave against its time budget so a tall stack compresses instead of
  /// running long.
  static int rowsRemaining(Grid grid, {required int fromRow}) {
    var count = 0;
    for (var r = fromRow < grid.maxRow ? fromRow : grid.maxRow; r >= 0; r--) {
      if (grid.rowHasAnyBlock(r)) count++;
    }
    return count;
  }
}
