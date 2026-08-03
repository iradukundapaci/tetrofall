import '../config/board_config.dart';
import 'cell.dart';
import 'events.dart';

class Grid {
  Grid({
    this.cols = BoardConfig.cols,
    this.visibleRows = BoardConfig.rows,
    this.spawnRows = BoardConfig.spawnRows,
  }) : _cells = List.generate(
         visibleRows + spawnRows,
         (_) => List<Cell?>.filled(cols, null),
       );

  final int cols;
  final int visibleRows;
  final int spawnRows;

  final List<List<Cell?>> _cells;

  int get minRow => -spawnRows;
  int get maxRow => visibleRows - 1;

  bool inBounds(int row, int col) =>
      col >= 0 && col < cols && row >= minRow && row <= maxRow;

  Cell? at(int row, int col) {
    if (!inBounds(row, col)) return null;
    return _cells[row + spawnRows][col];
  }

  void set(int row, int col, Cell? cell) {
    assert(inBounds(row, col), 'set out of bounds: ($row,$col)');
    _cells[row + spawnRows][col] = cell;
  }

  bool isOccupied(int row, int col) => at(row, col) != null;

  bool isRowFull(int row) {
    for (var c = 0; c < cols; c++) {
      if (at(row, c) == null) return false;
    }
    return true;
  }

  bool rowHasAnyBlock(int row) {
    for (var c = 0; c < cols; c++) {
      if (at(row, c) != null) return true;
    }
    return false;
  }

  void clearAll() {
    for (var r = minRow; r <= maxRow; r++) {
      for (var c = 0; c < cols; c++) {
        set(r, c, null);
      }
    }
  }

  /// Empties the bottom [count] visible rows in place — used by the
  /// Watch-Ad-To-Continue flow (game.md §1.9). No shifting: the stack
  /// above stays exactly where it is, it just gains breathing room below.
  /// Returns the cells that were cleared, for the caller to animate.
  List<ClearedCell> clearBottomRows(int count) {
    final firstRow = (maxRow - count + 1).clamp(0, maxRow);
    final captured = <ClearedCell>[];
    for (var r = firstRow; r <= maxRow; r++) {
      for (var c = 0; c < cols; c++) {
        final cell = at(r, c);
        if (cell != null) {
          captured.add(ClearedCell(row: r, col: c, type: cell.type));
        }
        set(r, c, null);
      }
    }
    return captured;
  }
}
