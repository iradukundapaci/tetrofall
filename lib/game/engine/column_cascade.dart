import 'grid.dart';
import 'gravity_resolver.dart';

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
