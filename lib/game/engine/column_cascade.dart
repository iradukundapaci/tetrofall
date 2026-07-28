import 'grid.dart';
import 'gravity_resolver.dart';

/// Default resolver (§1.6): each column repacks independently, bottom-up.
/// A block only falls as far as the next block *in its own column* — the
/// "middle row" rule that makes Tetrofall's cascade different from
/// Tetris's uniform row-shift. Produces more clears and chains, and reads
/// more clearly in motion, than [StickyGroup].
class ColumnCascade implements GravityResolver {
  @override
  List<BlockFall> resolve(Grid grid) {
    final falls = <BlockFall>[];
    for (var col = 0; col < grid.cols; col++) {
      final survivorRows = <int>[
        for (var r = 0; r <= grid.maxRow; r++)
          if (grid.at(r, col) != null) r,
      ];

      var write = grid.maxRow;
      for (final row in survivorRows.reversed) {
        if (row != write) {
          final cell = grid.at(row, col)!;
          grid.set(write, col, cell);
          grid.set(row, col, null);
          falls.add(
            BlockFall(col: col, fromRow: row, toRow: write, type: cell.type),
          );
        }
        write--;
      }
    }
    return falls;
  }
}
