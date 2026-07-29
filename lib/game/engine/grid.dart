import '../config/board_config.dart';
import 'cell.dart';

/// The settled-block playfield. Rows run `-spawnRows .. visibleRows - 1`:
/// negative rows are the hidden spawn buffer (§1.1), never occupied by a
/// settled block — only by the active piece while it's still above row 0.
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

  /// A row is full when every column is occupied.
  bool isRowFull(int row) {
    for (var c = 0; c < cols; c++) {
      if (at(row, c) == null) return false;
    }
    return true;
  }

  /// True if any settled block occupies the given row.
  bool rowHasAnyBlock(int row) {
    for (var c = 0; c < cols; c++) {
      if (at(row, c) != null) return true;
    }
    return false;
  }

  /// Clears every cell. Used by the debug screen's fixture loader.
  void clearAll() {
    for (var r = minRow; r <= maxRow; r++) {
      for (var c = 0; c < cols; c++) {
        set(r, c, null);
      }
    }
  }
}
