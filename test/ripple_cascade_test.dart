import 'package:flutter_test/flutter_test.dart';
import 'package:tetrofall/game/engine/cell.dart';
import 'package:tetrofall/game/engine/column_cascade.dart';
import 'package:tetrofall/game/engine/grid.dart';
import 'package:tetrofall/game/engine/ripple_cascade.dart';

/// Row-at-a-time gravity: one released row settles into the holes beneath it
/// while everything above stays frozen where it stands.
void main() {
  /// Paints a row from a mask string, `#` occupied and anything else empty.
  void paint(Grid grid, int row, String mask) {
    for (var c = 0; c < grid.cols; c++) {
      grid.set(row, c, mask[c] == '#' ? Cell(BlockType.wood) : null);
    }
  }

  String read(Grid grid, int row) => [
    for (var c = 0; c < grid.cols; c++) grid.at(row, c) == null ? '.' : '#',
  ].join();

  /// A narrow board keeps the masks readable.
  Grid narrow() => Grid(cols: 4, visibleRows: 6, spawnRows: 2);

  group('settleRow', () {
    test('drops a row to rest and leaves everything above untouched', () {
      final grid = narrow();
      paint(grid, 3, '#..#'); // frozen: must not move
      paint(grid, 4, '.##.'); // released
      paint(grid, 5, '....');

      final falls = RippleCascade.settleRow(grid, 4);

      expect(read(grid, 3), '#..#', reason: 'the row above stays frozen');
      expect(read(grid, 4), '....');
      expect(read(grid, 5), '.##.');
      expect(falls.length, 2);
      expect(falls.every((f) => f.fromRow == 4 && f.toRow == 5), isTrue);
    });

    test('cells in the same row land at different depths', () {
      final grid = narrow();
      paint(grid, 4, '##..');
      paint(grid, 5, '#...'); // col 0 is blocked one row higher than col 1

      RippleCascade.settleRow(grid, 4);

      expect(read(grid, 4), '#...', reason: 'col 0 rested on the floor block');
      expect(read(grid, 5), '##..');
    });

    test('a released row merges into the partial row below it', () {
      final grid = narrow();
      paint(grid, 4, '.##.');
      paint(grid, 5, '#..#');

      RippleCascade.settleRow(grid, 4);

      expect(read(grid, 5), '####', reason: 'the merge completes the row');
      expect(read(grid, 4), '....');
    });

    test('a settled row does not move and reports no falls', () {
      final grid = narrow();
      paint(grid, 4, '##..');
      paint(grid, 5, '####');

      expect(RippleCascade.settleRow(grid, 4), isEmpty);
      expect(read(grid, 4), '##..');
    });

    test('spawn rows are left alone', () {
      final grid = narrow();
      grid.set(-1, 0, Cell(BlockType.wood));

      expect(RippleCascade.settleRow(grid, -1), isEmpty);
      expect(grid.at(-1, 0), isNotNull);
    });
  });

  group('nextFloatingRow', () {
    test('finds the bottom-most row with space beneath it', () {
      final grid = narrow();
      paint(grid, 2, '#...');
      paint(grid, 4, '.#..');
      paint(grid, 5, '####');

      // Row 5 is on the floor, row 4 sits on it — row 2 is the one hanging.
      expect(RippleCascade.nextFloatingRow(grid, fromRow: 5), 2);
    });

    test('walks upward from the cursor', () {
      final grid = narrow();
      paint(grid, 1, '#...');
      paint(grid, 3, '#...');
      paint(grid, 5, '####');

      final first = RippleCascade.nextFloatingRow(grid, fromRow: grid.maxRow)!;
      expect(first, 3);
      expect(RippleCascade.nextFloatingRow(grid, fromRow: first - 1), 1);
    });

    test('returns null once the stack is settled', () {
      final grid = narrow();
      paint(grid, 4, '##..');
      paint(grid, 5, '####');

      expect(RippleCascade.nextFloatingRow(grid, fromRow: grid.maxRow), isNull);
    });
  });

  group('settleAbove', () {
    test('rows at or below the floor keep their overhangs', () {
      final grid = narrow();
      paint(grid, 2, '..#.'); // above the floor: must settle
      paint(grid, 3, '...#'); // the cleared line
      paint(grid, 4, '..#.'); // below the floor: overhangs a hole
      paint(grid, 5, '.#..');

      RippleCascade.settleAbove(grid, floorRow: 3);

      expect(read(grid, 2), '....');
      expect(read(grid, 3), '..##', reason: 'it came to rest on the overhang');
      expect(read(grid, 4), '..#.', reason: 'the overhang below is untouched');
      expect(read(grid, 5), '.#..', reason: 'nothing below the floor moves');
    });

    test('a block above the floor falls past it into a hole below', () {
      final grid = narrow();
      paint(grid, 2, '#...');
      paint(grid, 3, '...#');
      paint(grid, 4, '..#.');
      paint(grid, 5, '.#..');

      final falls = RippleCascade.settleAbove(grid, floorRow: 3);

      expect(read(grid, 2), '....');
      expect(read(grid, 5), '##..', reason: 'col 0 fell all the way to rest');
      expect(read(grid, 3), '...#', reason: 'the floor row itself is frozen');
      expect(falls.single.col, 0);
      expect(falls.single.fromRow, 2);
      expect(falls.single.toRow, 5);
    });

    test('a floor at the top of the board releases nothing', () {
      final grid = narrow();
      paint(grid, 2, '##..');
      paint(grid, 5, '..##');

      expect(RippleCascade.settleAbove(grid, floorRow: 0), isEmpty);
      expect(read(grid, 2), '##..');
    });

    test('matches the wave it stands in for', () {
      Grid seeded() {
        final grid = Grid(cols: 5, visibleRows: 8, spawnRows: 2);
        paint(grid, 1, '#..#.');
        paint(grid, 2, '.#...');
        paint(grid, 4, '##.##');
        paint(grid, 6, '..#..');
        paint(grid, 7, '#...#');
        return grid;
      }

      const floor = 5;
      final flushed = seeded();
      RippleCascade.settleAbove(flushed, floorRow: floor);

      final rippled = seeded();
      var cursor = RippleCascade.nextFloatingRow(rippled, fromRow: floor - 1);
      var guard = 0;
      while (cursor != null && guard++ < 100) {
        RippleCascade.settleRow(rippled, cursor);
        cursor = RippleCascade.nextFloatingRow(rippled, fromRow: cursor - 1);
      }

      for (var r = 0; r <= flushed.maxRow; r++) {
        expect(read(flushed, r), read(rippled, r), reason: 'row $r');
      }
    });
  });

  test('rippling bottom-up converges on the same board as ColumnCascade', () {
    Grid seeded() {
      final grid = Grid(cols: 5, visibleRows: 8, spawnRows: 2);
      paint(grid, 1, '#..#.');
      paint(grid, 2, '.#...');
      paint(grid, 4, '##.##');
      paint(grid, 6, '..#..');
      paint(grid, 7, '#...#');
      return grid;
    }

    final rippled = seeded();
    var cursor = RippleCascade.nextFloatingRow(
      rippled,
      fromRow: rippled.maxRow,
    );
    var guard = 0;
    while (cursor != null && guard++ < 100) {
      RippleCascade.settleRow(rippled, cursor);
      cursor = RippleCascade.nextFloatingRow(rippled, fromRow: cursor - 1);
    }

    final collapsed = seeded();
    ColumnCascade().resolve(collapsed);

    for (var r = 0; r <= collapsed.maxRow; r++) {
      expect(read(rippled, r), read(collapsed, r), reason: 'row $r');
    }
  });
}
