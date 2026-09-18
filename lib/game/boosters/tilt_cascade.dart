import '../engine/grid.dart';
import 'block_path.dart';

/// The board leans, and every block runs downhill (`boosters.md` §5.11).
///
/// Down always beats sideways, so a block passing over a hole drops into it
/// instead of sliding past. Rows are walked bottom-up and, within a row, from
/// the tilt side inward, so the cells nearest the low edge get out of the way
/// of the ones behind them.
abstract final class TiltCascade {
  /// [dir] is -1 for left, +1 for right. [solid] holds the active piece's
  /// cells, which block movement without being grid cells (§4.5 rule 1).
  static List<BlockPath> run(Grid grid, int dir, Set<(int, int)> solid) {
    final paths = <BlockPath>[];
    // Where each block started, so several passes over the same block still
    // read as one journey to the animator.
    final origin = <(int, int), (int, int)>{};

    var moved = true;
    // Each pass moves at least one block strictly lower or further to the
    // tilt side, so the loop terminates; the guard is belt and braces.
    for (
      var guard = 0;
      moved && guard <= grid.cols + grid.visibleRows;
      guard++
    ) {
      moved = false;
      for (var r = grid.maxRow; r >= 0; r--) {
        for (final c in _orderTowards(dir, grid.cols)) {
          final cell = grid.at(r, c);
          if (cell == null) continue;

          final path = <(int, int)>[(r, c)];
          var cr = r;
          var cc = c;
          while (true) {
            if (_isFree(grid, solid, cr + 1, cc)) {
              cr++;
            } else if (_isFree(grid, solid, cr, cc + dir)) {
              cc += dir;
            } else {
              break;
            }
            path.add((cr, cc));
          }
          if (path.length == 1) continue;

          grid.move((r, c), (cr, cc));
          final from = origin.remove((r, c)) ?? (r, c);
          origin[(cr, cc)] = from;
          paths.add(BlockPath(path, cell.type));
          moved = true;
        }
      }
    }
    return _merge(paths);
  }

  /// Columns ordered from the tilt side inward.
  static Iterable<int> _orderTowards(int dir, int cols) sync* {
    if (dir > 0) {
      for (var c = cols - 1; c >= 0; c--) {
        yield c;
      }
    } else {
      for (var c = 0; c < cols; c++) {
        yield c;
      }
    }
  }

  static bool _isFree(Grid grid, Set<(int, int)> solid, int row, int col) {
    if (row < 0 || row > grid.maxRow || col < 0 || col >= grid.cols) {
      return false;
    }
    if (grid.at(row, col) != null) return false;
    return !solid.contains((row, col));
  }

  /// Stitches the per-pass segments of one block back into a single path.
  /// A block that moves on pass 1 and again on pass 2 must animate as one
  /// continuous slide, not as two hops with a stop between them.
  static List<BlockPath> _merge(List<BlockPath> paths) {
    final byStart = <(int, int), int>{};
    final merged = <BlockPath>[];
    for (final p in paths) {
      final joinAt = byStart.remove(p.cells.first);
      if (joinAt == null) {
        byStart[p.cells.last] = merged.length;
        merged.add(p);
        continue;
      }
      final head = merged[joinAt];
      final joined = BlockPath([...head.cells, ...p.cells.skip(1)], p.type);
      merged[joinAt] = joined;
      byStart[joined.cells.last] = joinAt;
    }
    return merged;
  }
}
