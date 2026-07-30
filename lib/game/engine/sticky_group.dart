import 'grid.dart';
import 'gravity_resolver.dart';

class StickyGroup implements GravityResolver {
  @override
  List<BlockFall> resolve(Grid grid) {
    final visited = <int>{};
    final falls = <BlockFall>[];
    int key(int r, int c) => r * grid.cols + c;

    for (var r = 0; r <= grid.maxRow; r++) {
      for (var c = 0; c < grid.cols; c++) {
        if (grid.at(r, c) == null || !visited.add(key(r, c))) continue;

        final component = <(int, int)>[(r, c)];
        final queue = <(int, int)>[(r, c)];
        while (queue.isNotEmpty) {
          final (cr, cc) = queue.removeLast();
          for (final (dr, dc) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
            final nr = cr + dr, nc = cc + dc;
            if (nr < 0 ||
                nr > grid.maxRow ||
                nc < 0 ||
                nc >= grid.cols ||
                grid.at(nr, nc) == null ||
                !visited.add(key(nr, nc))) {
              continue;
            }
            component.add((nr, nc));
            queue.add((nr, nc));
          }
        }

        final bottomMostRowByCol = <int, int>{};
        for (final (cr, cc) in component) {
          final current = bottomMostRowByCol[cc];
          if (current == null || cr > current) bottomMostRowByCol[cc] = cr;
        }
        var dropDistance = grid.maxRow + 1;
        for (final entry in bottomMostRowByCol.entries) {
          final cc = entry.key;
          var free = 0;
          var below = entry.value + 1;
          while (below <= grid.maxRow && grid.at(below, cc) == null) {
            free++;
            below++;
          }
          if (free < dropDistance) dropDistance = free;
        }
        if (dropDistance <= 0) continue;

        component.sort((a, b) => b.$1.compareTo(a.$1));
        for (final (cr, cc) in component) {
          final cell = grid.at(cr, cc)!;
          grid.set(cr, cc, null);
          grid.set(cr + dropDistance, cc, cell);
          falls.add(
            BlockFall(
              col: cc,
              fromRow: cr,
              toRow: cr + dropDistance,
              type: cell.type,
            ),
          );
        }
      }
    }
    return falls;
  }
}
